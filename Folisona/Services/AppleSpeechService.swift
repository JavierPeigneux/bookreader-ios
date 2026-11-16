import Foundation
import AVFoundation

enum SynthesisPhase: Sendable { case loading, synthesizing, saving, segment(completed: Int, total: Int) }

protocol SpeechGenerating: Sendable {
    func generate(text: String, voice: ReaderVoice, destination: URL,
                  progress: @escaping @Sendable (SynthesisPhase) -> Void) async throws -> URL
}

/// Uses installed system voices. Each request owns its synthesizer and temporary
/// file, so a cancelled reader cannot stop or overwrite a newer request.
@MainActor
final class AppleSpeechService: SpeechGenerating {
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
        let writer = SpeechAudioWriter(url: temporary)
        defer { writer.close(); try? FileManager.default.removeItem(at: temporary) }
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            progress(.synthesizing)
            let request = SpeechUtteranceWriter(writer: writer)
            try await request.run(text: segment, voice: systemVoice)
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

@MainActor
private final class SpeechUtteranceWriter: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let writer: SpeechAudioWriter
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    init(writer: SpeechAudioWriter) {
        self.writer = writer
        super.init()
        synthesizer.delegate = self
    }
    func run(text: String, voice: AVSpeechSynthesisVoice) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    self?.complete(.failure(ReaderError.message(String(localized: "error.speech.timeout"))))
                }
                let writer = self.writer
                synthesizer.write(utterance) { [weak self] buffer in
                    do {
                        guard let pcm = buffer as? AVAudioPCMBuffer else {
                            throw ReaderError.message(String(localized: "error.audio.prepare"))
                        }
                        if pcm.frameLength == 0 {
                            Task { @MainActor in self?.complete(.success(())) }
                        } else {
                            try writer.append(pcm)
                        }
                    } catch {
                        writer.fail(error)
                        Task { @MainActor in self?.complete(.failure(error)) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(.failure(CancellationError())) }
        }
    }
    private func complete(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        if case .failure = result {
            writer.close()
            synthesizer.stopSpeaking(at: .immediate)
        }
        continuation.resume(with: result)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.complete(.failure(CancellationError())) }
    }
}
