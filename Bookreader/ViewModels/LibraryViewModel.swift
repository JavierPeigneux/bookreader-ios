import Foundation
import Observation

@MainActor @Observable
final class LibraryViewModel {
    private(set) var books: [Book] = []
    var isImporting = false
    var error: String?
    let store: LibraryStore
    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        do { books = try store.load() } catch { self.error = error.localizedDescription }
    }
    func importDocument(_ url: URL) async -> Book? {
        guard !isImporting else { return nil }
        isImporting = true
        defer { isImporting = false }
        do {
            let book = try await Task.detached(priority: .userInitiated) { try DocumentImporter().read(url) }.value
            try store.save(book)
            books.insert(book, at: 0)
            return book
        } catch { self.error = error.localizedDescription; return nil }
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
