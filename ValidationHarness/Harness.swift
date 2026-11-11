import Foundation
import AVFoundation
import MLX

/// Development-only host check using the exact same service and bundled resources as iOS.
@main
struct Harness {
    static func main() async {
        do {
            let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/bookreader-castellano.wav")
            let matrix = MLXArray(Array(0..<12)).reshaped(3, 4)
            let selected = take(matrix, MLXArray(2), axis: 1, stream: .gpu).asArray(Int32.self)
            guard selected == [2, 6, 10] else { throw ReaderError.message("Scalar gather regression failed") }
            print("METAL_SCALAR_GATHER_OK")
            let arguments = Array(CommandLine.arguments.dropFirst())
            let text = arguments.count > 1 ? try String(contentsOfFile: arguments[1], encoding: .utf8)
                : "¡Buenos días! El niño lee un libro en castellano. Mañana iremos a la biblioteca de Valencia."
            let repeats = arguments.count > 2 ? max(1, Int(arguments[2]) ?? 1) : 1
            let service = KokoroService()
            for iteration in 0..<repeats {
                let start = Date()
                let url = try await service.generate(text: text, voice: .dora, destination: destination)
                let audio = try AVAudioFile(forReading: url)
                print("AUDIO_OK iteration=\(iteration) path=\(url.path) duration=\(Double(audio.length) / audio.processingFormat.sampleRate) generation=\(Date().timeIntervalSince(start)) sampleRate=\(audio.processingFormat.sampleRate)")
                print("MLX_MEMORY active=\(Memory.activeMemory) cache=\(Memory.cacheMemory) peak=\(Memory.peakMemory)")
            }
            await service.releaseResources()
            print("MLX_RELEASED active=\(Memory.activeMemory) cache=\(Memory.cacheMemory)")
        } catch {
            print("AUDIO_FAILED \(error)")
            exit(1)
        }
    }
}
