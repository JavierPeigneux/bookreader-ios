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

struct LibraryFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}

struct LibraryOrganization: Codable {
    var folders: [LibraryFolder] = []
    var membership: [String: UUID] = [:]
}

extension LibraryStore {
    private var organizationURL: URL { root.appendingPathComponent("Organization/folders.json") }
    func loadOrganization() throws -> LibraryOrganization {
        guard FileManager.default.fileExists(atPath: organizationURL.path) else { return LibraryOrganization() }
        return try JSONDecoder().decode(LibraryOrganization.self, from: Data(contentsOf: organizationURL))
    }
    func saveOrganization(_ organization: LibraryOrganization) throws {
        try FileManager.default.createDirectory(at: organizationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(organization).write(to: organizationURL, options: .atomic)
    }
}
