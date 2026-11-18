import SwiftUI
import Observation

/// MVVC: Models + Views + ViewModels + Coordinator. Services own IO and speech synthesis.
@MainActor @Observable
final class AppCoordinator {
    let library: LibraryViewModel
    private let speech = AppleSpeechService()
    var selection: UUID?
    var reader: ReaderViewModel?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--store-screenshots") {
            // Isolated fictional library. Never alters the user's imported books.
            let root = URL.cachesDirectory.appendingPathComponent("FolisonaScreenshotLibrary")
            let store = LibraryStore(root: root)
            try? FileManager.default.removeItem(at: root)
            let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
            let titles = english ? ["The Lighthouse Library", "A Notebook of Quiet Days", "Paths Through the Forest"]
                                 : ["La biblioteca del faro", "Cuaderno de días tranquilos", "Senderos del bosque"]
            let headings = english ? ["The letter", "Beyond the harbour", "The keeper of stories", "A light in the window"]
                                   : ["La carta", "Más allá del puerto", "La guardiana de historias", "Una luz en la ventana"]
            let paragraphs = english ? [
                "The letter arrived on a Tuesday, folded between the pages of a book nobody remembered lending. Clara recognised the handwriting before she read her name.",
                "Outside, the sea was quiet. She put the book in her bag and took the path towards the lighthouse, following the scent of salt and the sound of gulls.",
                "At the end of the path stood a wooden door. Behind it, shelves reached the ceiling. Every book held a journey, and every journey began with someone willing to listen."
            ] : [
                "La carta llegó un martes, doblada entre las páginas de un libro que nadie recordaba haber prestado. Clara reconoció la letra antes de leer su nombre.",
                "Fuera, el mar estaba en calma. Guardó el libro en su bolsa y tomó el sendero hacia el faro, siguiendo el olor a sal y el sonido de las gaviotas.",
                "Al final del camino había una puerta de madera. Detrás, las estanterías llegaban hasta el techo. Cada libro guardaba un viaje, y cada viaje empezaba con alguien dispuesto a escuchar."
            ]
            for (index, title) in titles.enumerated() {
                let blocks = headings.enumerated().flatMap { chapter, heading in
                    paragraphs.enumerated().map { offset, text in
                        ReadingBlock(id: chapter * paragraphs.count + offset, heading: heading,
                                     text: text, chapterID: chapter)
                    }
                }
                var book = Book(title: title, format: ["EPUB", "PDF", "MD"][index], blocks: blocks)
                book.importedAt = Date(timeIntervalSince1970: 1_800_000_000 - Double(index))
                // Fictional listening history for store screenshots, isolated and DEBUG-only.
                let session = UUID()
                let bedtime = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23, minute: 14))!
                for block in 0..<3 {
                    book.recordListening(block: block, sessionID: session,
                                         at: bedtime.addingTimeInterval(Double(block * 60)))
                }
                try? store.save(book)
            }
            library = LibraryViewModel(store: store)
            UserDefaults.standard.set(true, forKey: "reader.showListeningTimes")
            return
        }
        #endif
        library = LibraryViewModel()
    }

    func open(_ book: Book) {
        reader?.close()
        reader = ReaderViewModel(book: book, service: speech) { [weak self] in self?.library.update($0) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--store-screenshots"),
           Locale.preferredLanguages.first?.hasPrefix("en") == true {
            reader?.voice = .english
        }
        #endif
        selection = book.id
    }
    func importDocument(_ url: URL, folder: UUID? = nil) async {
        if let book = await library.importDocument(url) {
            if let folder { library.move(book.id, to: folder) }
            open(book)
        }
    }
    func delete(_ book: Book) {
        if reader?.book.id == book.id { reader?.close(); reader = nil; selection = nil }
        library.delete(book)
    }
    func handleMemoryWarning() {
        reader?.cancelGeneration()
    }
    func returnedToLibrary() { reader?.close(); reader = nil }
}
