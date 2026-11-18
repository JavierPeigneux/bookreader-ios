import Foundation
import Observation
import CryptoKit

@MainActor @Observable
final class LibraryViewModel {
    private(set) var books: [Book] = []
    private(set) var organization = LibraryOrganization()
    var duplicateBook: Book?
    var isImporting = false
    var error: String?
    let store: LibraryStore
    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        do { books = try store.load(); organization = try store.loadOrganization() } catch { self.error = error.localizedDescription }
    }
    func importDocument(_ url: URL) async -> Book? {
        guard !isImporting else { return nil }
        duplicateBook = nil
        isImporting = true
        defer { isImporting = false }
        do {
            let book = try await Task.detached(priority: .userInitiated) { try DocumentImporter().read(url) }.value
            let candidates = books
            let duplicateID = await Task.detached(priority: .userInitiated) {
                let fingerprint = Self.fingerprint(book)
                return candidates.first(where: { Self.fingerprint($0) == fingerprint })?.id
            }.value
            if let existing = books.first(where: { $0.id == duplicateID }) {
                duplicateBook = existing
                return nil
            }
            try store.save(book)
            books.insert(book, at: 0)
            return book
        } catch { self.error = error.localizedDescription; return nil }
    }

    // Compare extracted content, not filenames: renamed copies are duplicates,
    // while different documents sharing a filename remain importable.
    nonisolated static func fingerprint(_ book: Book) -> String {
        let text = book.blocks.map(\.text).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var folders: [LibraryFolder] { organization.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    func folderID(for book: Book) -> UUID? { organization.membership[book.id.uuidString] }
    func visibleBooks(folder: UUID?, query: String) -> [Book] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return books.filter { book in
            let inScope = query.isEmpty ? folderID(for: book) == folder : folder == nil || folderID(for: book) == folder
            return inScope && (query.isEmpty || book.title.localizedStandardContains(query)
                || book.blocks.contains { $0.text.localizedStandardContains(query) })
        }
    }
    private func persist(_ next: LibraryOrganization) -> Bool {
        do { try store.saveOrganization(next); organization = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult
    func createFolder(name: String, books ids: [UUID] = []) -> LibraryFolder? {
        guard let name = validName(name), ids.allSatisfy({ id in books.contains { $0.id == id } }) else { return nil }
        let folder = LibraryFolder(name: name)
        var next = organization
        next.folders.append(folder)
        for id in ids { next.membership[id.uuidString] = folder.id }
        return persist(next) ? folder : nil
    }
    @discardableResult
    func renameFolder(_ folder: LibraryFolder, name: String) -> Bool {
        guard let name = validName(name, excluding: folder.id),
              let index = organization.folders.firstIndex(where: { $0.id == folder.id }) else { return false }
        var next = organization
        next.folders[index].name = name
        return persist(next)
    }
    private func validName(_ name: String, excluding: UUID? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = String(localized: "library.folder.name_required"); return nil }
        guard !folders.contains(where: { $0.id != excluding && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            error = String(localized: "library.folder.exists"); return nil
        }
        return name
    }
    @discardableResult
    func move(_ id: UUID, to folder: UUID?) -> Bool {
        guard books.contains(where: { $0.id == id }), folder == nil || folders.contains(where: { $0.id == folder }) else { return false }
        var next = organization
        next.membership[id.uuidString] = folder
        return persist(next)
    }
    func removeFolder(_ folder: LibraryFolder) {
        var next = organization
        next.folders.removeAll { $0.id == folder.id }
        next.membership = next.membership.filter { $0.value != folder.id }
        _ = persist(next) // Documents and their audio remain in the library.
    }

    func update(_ book: Book) {
        do {
            try store.save(book)
            if let index = books.firstIndex(where: { $0.id == book.id }) { books[index] = book }
        } catch { self.error = error.localizedDescription }
    }
    func delete(_ book: Book) {
        do { try store.remove(book); books.removeAll { $0.id == book.id } }
        catch { self.error = error.localizedDescription }
    }
}
