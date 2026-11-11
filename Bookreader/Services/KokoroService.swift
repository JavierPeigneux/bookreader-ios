import Foundation
import AVFoundation
import OSLog
#if !targetEnvironment(simulator)
import KokoroSwift
import MLX
import MLXUtilsLibrary
#endif

enum SynthesisPhase: Sendable { case loading, synthesizing, saving, segment(completed: Int, total: Int) }

protocol SpeechGenerating: Sendable {
    func generate(text: String, voice: ReaderVoice, destination: URL,
                  progress: @escaping @Sendable (SynthesisPhase) -> Void) async throws -> URL
}

/// All model access is serialized; MLX arrays never leave this actor.
actor KokoroService: SpeechGenerating {
    nonisolated static func setGPUAllowed(_ allowed: Bool) {
        #if !targetEnvironment(simulator)
        GPU.setSubmissionAllowed(allowed)
        #endif
    }

    /// This is an inference bound, independent of persisted reading blocks.
    static let inferenceCharacterLimit = 96
    static func inferenceSegments(_ text: String) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        while !remaining.isEmpty {
            var end = remaining.index(remaining.startIndex, offsetBy: min(inferenceCharacterLimit, remaining.count))
            if end < remaining.endIndex {
                let prefix = remaining[..<end]
                if let boundary = prefix.lastIndex(where: { ".!?;\n".contains($0) }),
                   prefix.distance(from: prefix.startIndex, to: boundary) >= inferenceCharacterLimit / 3 {
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

    func releaseResources() {
        #if !targetEnvironment(simulator)
        spanish = nil
        english = nil
        voices.removeAll()
        Memory.clearCache()
        #endif
    }

    #if !targetEnvironment(simulator)
    private let logger = Logger(subsystem: "com.javierpeigneux.Bookreader", category: "SynthesisMemory")
    private var spanish: KokoroTTS?
    private var english: KokoroTTS?
    private var voices: [String: MLXArray] = [:]
    #endif

    func generate(text: String, voice: ReaderVoice, destination: URL, progress: @escaping @Sendable (SynthesisPhase) -> Void = { _ in }) throws -> URL {
        try Task.checkCancellation()
        #if targetEnvironment(simulator)
        throw ReaderError.message(String(localized: "error.kokoro.simulator"))
        #else
        // MLX's desktop defaults can retain several GB of reusable buffers.
        // The allocation limit schedules pending work; it is NOT a hard process cap.
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.memoryLimit = 1024 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }
        progress(.loading)
        guard let model = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors"),
              let voiceURL = Bundle.main.url(forResource: "voices", withExtension: "npz") else {
            throw ReaderError.message(String(localized: "error.kokoro.resources_missing"))
        }
        if voices.isEmpty {
            voices = NpyzReader.read(fileFromPath: voiceURL) ?? [:]
        }
        guard let embedding = voices[voice.rawValue + ".npy"] else {
            throw ReaderError.message(String.localizedStringWithFormat(String(localized: "error.kokoro.voice_missing"), voice.title))
        }
        // Keep a single model resident when switching language.
        let engine: KokoroTTS
        if voice.isSpanish {
            if english != nil { english = nil; Memory.clearCache() }
            if spanish == nil { spanish = KokoroTTS(modelPath: model, g2p: .eSpeakNG) }
            engine = spanish!
        } else {
            if spanish != nil { spanish = nil; Memory.clearCache() }
            if english == nil { english = KokoroTTS(modelPath: model, g2p: .misaki) }
            engine = english!
        }
        let segments = Self.inferenceSegments(text)
        guard !segments.isEmpty else { throw ReaderError.message(String(localized: "error.document.empty")) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingPathExtension().appendingPathExtension("partial.wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Append each small inference directly to disk instead of retaining the
        // full block's waveform and all intermediate graphs in memory.
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            for (index, segment) in segments.enumerated() {
                try Task.checkCancellation()
                try autoreleasepool {
                    progress(.synthesizing)
                    let (samples, _) = try engine.generateAudio(voice: embedding, language: voice.isSpanish ? .es : .enUS, text: segment)
                    try Task.checkCancellation()
                    guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }), samples.contains(where: { abs($0) > 0.0001 }) else {
                        throw ReaderError.message(String(localized: "error.kokoro.invalid_audio"))
                    }
                    progress(.saving)
                    guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                          let channel = buffer.floatChannelData?[0] else {
                        throw ReaderError.message(String(localized: "error.audio.prepare"))
                    }
                    buffer.frameLength = buffer.frameCapacity
                    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
                    try file.write(from: buffer)
                }
                progress(.segment(completed: index + 1, total: segments.count))
                Memory.clearCache()
                logger.info("segment=\(index + 1)/\(segments.count) active=\(Memory.activeMemory) cache=\(Memory.cacheMemory) peak=\(Memory.peakMemory)")
            }
        }
        try Task.checkCancellation()
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
        #endif
    }
}

/// Expiration can run off-main: revoke the native gate before dispatching UI work.
final class GPUExecutionPolicy: @unchecked Sendable {
    static let shared = GPUExecutionPolicy { allowed in KokoroService.setGPUAllowed(allowed) }
    private let lock = NSLock()
    private var active = false
    private var pending = Set<UUID>()
    private var grants = Set<UUID>()
    private let setAllowed: @Sendable (Bool) -> Void

    init(setAllowed: @escaping @Sendable (Bool) -> Void) {
        self.setAllowed = setAllowed
        setAllowed(false)
    }
    func setActive(_ value: Bool) {
        lock.withLock { active = value; update() }
    }
    func register(_ id: UUID) {
        lock.withLock { _ = pending.insert(id) }
    }
    @discardableResult func grant(_ id: UUID) -> Bool {
        lock.withLock {
            guard pending.contains(id) else { return false }
            grants.insert(id)
            update()
            return true
        }
    }
    func revoke(_ id: UUID) {
        lock.withLock { pending.remove(id); grants.remove(id); update() }
    }
    private func update() { setAllowed(active || !grants.isEmpty) }
}
