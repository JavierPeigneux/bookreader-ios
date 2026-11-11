import Foundation

struct LibraryStore {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? URL.documentsDirectory.appendingPathComponent("Library", isDirectory: true)
    }
    func load() throws -> [Book] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(Book.self, from: Data(contentsOf: $0)) }
            .sorted { $0.importedAt > $1.importedAt }
    }
    func save(_ book: Book) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(book).write(to: root.appendingPathComponent(book.id.uuidString + ".json"), options: .atomic)
    }
    func remove(_ book: Book) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(book.id.uuidString + ".json"))
        try PreparedAudioStore().remove(book: book.id)
        let audio = URL.cachesDirectory.appendingPathComponent(book.id.uuidString)
        if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
    }
}
