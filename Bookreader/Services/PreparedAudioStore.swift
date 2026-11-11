import Foundation

struct AudioPreparation: Codable, Equatable {
    let voice: ReaderVoice
    let lowerBound: Int
    let upperBound: Int
    var range: Range<Int> { lowerBound..<upperBound }
}

struct PreparedAudioStore {
    let root: URL
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("PreparedAudio")) { self.root = root }
    func directory(_ book: UUID) -> URL { root.appendingPathComponent(book.uuidString) }
    func destination(book: UUID, voice: ReaderVoice, index: Int) -> URL {
        directory(book).appendingPathComponent(voice.rawValue).appendingPathComponent("\(index).wav")
    }
    func playbackURL(book: UUID, voice: ReaderVoice, index: Int) -> URL {
        let saved = destination(book: book, voice: voice, index: index)
        if FileManager.default.fileExists(atPath: saved.path) { return saved }
        return URL.cachesDirectory.appendingPathComponent(book.uuidString).appendingPathComponent(voice.rawValue).appendingPathComponent("\(index).wav")
    }
    func available(book: UUID, voice: ReaderVoice) -> Set<Int> {
        let folders = [directory(book).appendingPathComponent(voice.rawValue), URL.cachesDirectory.appendingPathComponent(book.uuidString).appendingPathComponent(voice.rawValue)]
        return Set(folders.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { $0.pathExtension == "wav" }.compactMap { Int($0.deletingPathExtension().lastPathComponent) })
    }
    func save(_ preparation: AudioPreparation, book: UUID) throws {
        var folder = directory(book)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try JSONEncoder().encode(preparation).write(to: folder.appendingPathComponent("preparation.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func pending(book: UUID) -> AudioPreparation? {
        guard let data = try? Data(contentsOf: directory(book).appendingPathComponent("preparation.json")) else { return nil }
        return try? JSONDecoder().decode(AudioPreparation.self, from: data)
    }
    func complete(book: UUID) throws {
        let url = directory(book).appendingPathComponent("preparation.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func remove(book: UUID) throws {
        if FileManager.default.fileExists(atPath: directory(book).path) { try FileManager.default.removeItem(at: directory(book)) }
    }
}

/// Counts cached work in the bar, but excludes it when measuring generation speed.
struct PreparationProgress {
    var total = 0
    var initiallyCached = 0
    var completed = 0
    var partial = 0.0
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, (Double(completed) + partial) / Double(total)))
    }
    func remainingSeconds(elapsed: TimeInterval) -> TimeInterval? {
        let produced = Double(completed - initiallyCached) + partial
        let remaining = max(0, Double(total - completed) - partial)
        guard remaining > 0 else { return 0 }
        guard elapsed >= 1, produced >= 0.1 else { return nil }
        return elapsed / produced * remaining
    }
}
