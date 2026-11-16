import Foundation
import AVFoundation

enum SynthesisPhase: Sendable { case loading, synthesizing, saving, segment(completed: Int, total: Int) }

protocol SpeechGenerating: Sendable {
    func generate(text: String, voice: ReaderVoice, destination: URL,
                  progress: @escaping @Sendable (SynthesisPhase) -> Void) async throws -> URL
}

/// Uses installed system voices. Requests lease stable engines and own temporary
/// files, so a cancelled reader cannot stop or overwrite a newer request.
@MainActor
final class AppleSpeechService: SpeechGenerating {
    // Stable delegates and engines outlive buffer callbacks. A cancelled engine
    // is unavailable until Apple acknowledges termination; it is never recycled early.
    private var engines: [SpeechEngine] = []
    private func acquireEngine() async throws -> SpeechEngine {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try Task.checkCancellation()
            if let engine = engines.first(where: { $0.isAvailable }) { engine.leased = true; return engine }
            if engines.count < 2 {
                let engine = SpeechEngine()
                engine.leased = true
                engines.append(engine)
                return engine
            }
            // A cancelled short utterance may still be delivering its final
            // callbacks. Yield to them instead of destroying the audio unit.
            try await Task.sleep(for: .milliseconds(20))
        } while Date() < deadline
        throw ReaderError.message(String(localized: "error.speech.busy"))
    }
    nonisolated static let segmentCharacterLimit = 500
    nonisolated static func segments(_ text: String) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        while !remaining.isEmpty {
            var end = remaining.index(remaining.startIndex, offsetBy: min(segmentCharacterLimit, remaining.count))
            if end < remaining.endIndex {
                let prefix = remaining[..<end]
                if let boundary = prefix.lastIndex(where: { ".!?;\n".contains($0) }),
                   prefix.distance(from: prefix.startIndex, to: boundary) >= segmentCharacterLimit / 3 {
                    end = remaining.index(after: boundary)
                } else if let space = prefix.lastIndex(where: { $0.isWhitespace }) {
                    end = remaining.index(after: space)
                }
            }
            let segment = remaining[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty { result.append(segment) }
            remaining = String(remaining[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    func generate(text: String, voice: ReaderVoice, destination: URL,
                  progress: @escaping @Sendable (SynthesisPhase) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        progress(.loading)
        guard let systemVoice = voice.systemVoice else {
            throw ReaderError.message(String(localized: "error.speech.voice_missing"))
        }
        let segments = Self.segments(text)
        guard !segments.isEmpty else { throw ReaderError.message(String(localized: "error.document.empty")) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).partial.wav")
        let engine = try await acquireEngine()
        defer { engine.leased = false }
        let writer = SpeechAudioWriter(url: temporary)
        defer { writer.close(); try? FileManager.default.removeItem(at: temporary) }
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            progress(.synthesizing)
            try await engine.run(text: segment, voice: systemVoice, writer: writer)
            progress(.segment(completed: index + 1, total: segments.count))
        }
        try Task.checkCancellation()
        progress(.saving)
        try writer.finish()
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return destination
    }
}

/// AVFoundation delivers buffers on its own queue. Consume them synchronously;
/// never send the mutable PCM buffers across an actor boundary.
private final class SpeechAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var closed = false
    private var frames: Int64 = 0
    private var hasSignal = false
    private var failure: Error?
    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            guard buffer.frameLength > 0 else { return }
            guard let channels = buffer.floatChannelData else {
                throw ReaderError.message(String(localized: "error.audio.prepare"))
            }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.format.isInterleaved
                        ? channels[0][frame * buffer.stride + channel]
                        : channels[channel][frame]
                    guard sample.isFinite else { throw ReaderError.message(String(localized: "error.speech.invalid_audio")) }
                    if abs(sample) > 0.0001 { hasSignal = true }
                }
            }
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                       commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            }
            guard file?.processingFormat == buffer.format else {
                throw ReaderError.message(String(localized: "error.audio.prepare"))
            }
            try file?.write(from: buffer)
            frames += Int64(buffer.frameLength)
        }
    }
    func finish() throws {
        try lock.withLock {
            file = nil
            closed = true
            if let failure { throw failure }
            guard frames > 0, hasSignal else { throw ReaderError.message(String(localized: "error.speech.invalid_audio")) }
        }
    }
    func fail(_ error: Error) { lock.withLock { failure = error; closed = true; file = nil } }
    func close() { lock.withLock { closed = true; file = nil } }
}

/// An empty PCM buffer ends the buffer stream, NOT the synthesizer's lifecycle.
/// Wait for both the buffer terminator and didFinish before reusing this engine.
@MainActor
private final class SpeechEngine: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var leased = false
    var isAvailable: Bool { !leased && utterance == nil }
    private var utterance: AVSpeechUtterance?
    private var writer: SpeechAudioWriter?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var ticket = UUID()
    private var buffersEnded = false
    private var synthesisEnded = false
    // Keep callbacks' owner alive even if its caller cancels/releases the service.
    // Cleared only by Apple's terminal delegate event, never by a guessed delay.
    private var callbackLifetime: SpeechEngine?

    override init() {
        super.init()
        synthesizer.delegate = self
    }
    func run(text: String, voice: AVSpeechSynthesisVoice, writer: SpeechAudioWriter) async throws {
        let requestID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                precondition(self.utterance == nil)
                self.ticket = requestID
                self.continuation = continuation
                self.writer = writer
                self.buffersEnded = false
                self.synthesisEnded = false
                self.callbackLifetime = self
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                self.utterance = utterance
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.abort(ReaderError.message(String(localized: "error.speech.timeout")), ticket: requestID)
                }
                synthesizer.write(utterance) { [weak self] buffer in
                    do {
                        guard let pcm = buffer as? AVAudioPCMBuffer else {
                            throw ReaderError.message(String(localized: "error.audio.prepare"))
                        }
                        if pcm.frameLength == 0 {
                            Task { @MainActor in self?.buffersDidEnd(ticket: requestID) }
                        } else {
                            try writer.append(pcm)
                        }
                    } catch {
                        writer.fail(error)
                        Task { @MainActor in self?.abort(error, ticket: requestID) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.abort(CancellationError(), ticket: requestID) }
        }
    }
    private func buffersDidEnd(ticket: UUID) {
        guard self.ticket == ticket, utterance != nil else { return }
        buffersEnded = true
        finishIfReady()
    }
    private func finishIfReady() {
        guard synthesisEnded && buffersEnded else { return }
        let pending = continuation
        continuation = nil
        releaseCallbacks()
        pending?.resume()
    }
    private func abort(_ error: Error, ticket: UUID) {
        guard self.ticket == ticket, let pending = continuation else { return }
        continuation = nil
        timeout?.cancel()
        timeout = nil
        writer?.close()
        // Return cancellation/error promptly. Keep the engine, delegate and
        // utterance alive and unavailable until didCancel/didFinish arrives.
        pending.resume(throwing: error)
        if synthesisEnded && buffersEnded { releaseCallbacks() }
        // Do not tear down Apple's render pipeline while a buffer callback is
        // in flight. The current bounded utterance drains silently; its output
        // is discarded and no further segments are enqueued after cancellation.
    }
    private func releaseCallbacks() {
        timeout?.cancel()
        timeout = nil
        writer = nil
        utterance = nil
        callbackLifetime = nil
    }
    private func didFinish(_ identifier: ObjectIdentifier) {
        guard let utterance, ObjectIdentifier(utterance) == identifier else { return }
        synthesisEnded = true
        finishIfReady()
    }
    private func didCancel(_ identifier: ObjectIdentifier) {
        guard let utterance, ObjectIdentifier(utterance) == identifier else { return }
        let pending = continuation
        continuation = nil
        writer?.close()
        releaseCallbacks()
        pending?.resume(throwing: CancellationError())
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didFinish(identifier) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didCancel(identifier) }
    }
}
