import Foundation
import AVFoundation

@main struct AppleSpeechCheck {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/apple-speech-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = AppleSpeechService()
        for (voice, text, name) in [
            (ReaderVoice.spanish, "¡Buenos días! El niño lee un libro en castellano. Mañana iremos a la biblioteca de Valencia.", "es"),
            (ReaderVoice.english, "Good morning! The child is reading a book. Tomorrow we will visit the library together.", "en")
        ] {
            let url = directory.appendingPathComponent(name + ".wav")
            _ = try await service.generate(text: Array(repeating: text, count: 8).joined(separator: " "), voice: voice, destination: url)
            let file = try AVAudioFile(forReading: url)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let samples = buffer.floatChannelData![0]
            let energy = (0..<Int(buffer.frameLength)).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) }
            let rms = sqrt(energy / Double(buffer.frameLength))
            guard rms > 0.0001 else { throw ReaderError.message("Silent audio") }
            print("AUDIO_OK", name, voice.rawValue, "seconds", Double(file.length)/file.processingFormat.sampleRate, "RMS", rms)
        }
        let cancelled = directory.appendingPathComponent("cancelled.wav")
        try? FileManager.default.removeItem(at: cancelled)
        let task = Task { try await service.generate(text: String(repeating: "Un libro para leer en voz alta. ", count: 1000), voice: .spanish, destination: cancelled) }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        let next = directory.appendingPathComponent("next.wav")
        _ = try await service.generate(text: "La siguiente lectura funciona después de cancelar.", voice: .spanish, destination: next)
        do { _ = try await task.value; throw ReaderError.message("Cancellation ignored") }
        catch is CancellationError { }
        guard !FileManager.default.fileExists(atPath: cancelled.path),
              try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains(where: { $0.contains("partial") }) else {
            throw ReaderError.message("Cancelled request left an audio file")
        }
        print("CANCELLATION_AND_RESTART_OK")
    }
}
