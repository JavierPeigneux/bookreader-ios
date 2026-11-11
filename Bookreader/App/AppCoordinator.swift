import SwiftUI
import Observation

/// MVVC: Models + Views + ViewModels + Coordinator. Services own IO and inference.
@MainActor @Observable
final class AppCoordinator {
    let library = LibraryViewModel()
    private let kokoro = KokoroService()
    var selection: UUID?
    var reader: ReaderViewModel?
    func open(_ book: Book) {
        reader?.close()
        reader = ReaderViewModel(book: book, service: kokoro) { [weak self] in self?.library.update($0) }
        selection = book.id
    }
    func importDocument(_ url: URL) async {
        if let book = await library.importDocument(url) { open(book) }
    }
    func delete(_ book: Book) {
        if reader?.book.id == book.id { reader?.close(); reader = nil; selection = nil }
        library.delete(book)
    }
    func handleMemoryWarning() {
        reader?.cancelGeneration()
        Task { await kokoro.releaseResources() }
    }
    func returnedToLibrary() { reader?.close(); reader = nil }
}
