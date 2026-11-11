import XCTest
import PDFKit
import SwiftSoup
import UIKit
import AVFoundation
@testable import Bookreader

final class DocumentImporterTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func write(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    func testListeningHistoryPersistsAndKeepsPreviousSessions() throws {
        var book = Book(title: "Horas", format: "TXT", blocks: [ReadingBlock(id: 0, heading: "Texto", text: "Hola")])
        // Simulate a library written before listening history existed.
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        legacy.removeValue(forKey: "listeningSessions")
        book = try JSONDecoder().decode(Book.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(book.listeningSessions)
        let first = UUID(), second = UUID()
        let night = Date(timeIntervalSince1970: 1_800_000_000)
        book.recordListening(block: 0, sessionID: first, at: night)
        book.recordListening(block: 0, sessionID: first, at: night.addingTimeInterval(60))
        XCTAssertEqual(book.lastListenedAt(block: 0), night, "Resuming must preserve the original start")
        book.recordListening(block: 0, sessionID: second, at: night.addingTimeInterval(86_400))
        let restored = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(restored.lastListenedAt(block: 0), night.addingTimeInterval(86_400))
        XCTAssertEqual(restored.lastListenedAt(block: 0, sessionID: first), night)
        XCTAssertNil(restored.lastListenedAt(block: 1))
        for offset in 0..<40 { book.recordListening(block: 0, sessionID: UUID(), at: night.addingTimeInterval(Double(offset))) }
        XCTAssertEqual(book.listeningSessions?.count, 30)
    }

    @MainActor
    func testGPULifecycleClosesSynchronouslyAndRejectsExpiredGrant() {
        let state = TestGPUState()
        let policy = GPUExecutionPolicy { state.set($0) }
        let center = NotificationCenter()
        let lifecycle = GPUApplicationLifecycle(policy: policy, center: center)
        withExtendedLifetime(lifecycle) {
            XCTAssertFalse(state.allowed)
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertTrue(state.allowed)
            center.post(name: UIApplication.willResignActiveNotification, object: nil)
            XCTAssertFalse(state.allowed, "Must close before notification delivery returns")
            let expired = UUID()
            policy.register(expired)
            policy.revoke(expired)
            XCTAssertFalse(policy.grant(expired), "A late task callback must not resurrect expired permission")
            XCTAssertFalse(state.allowed)
            let granted = UUID()
            policy.register(granted)
            XCTAssertTrue(policy.grant(granted))
            XCTAssertTrue(state.allowed)
            center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertTrue(state.allowed, "A real grant allows background submission")
            policy.revoke(granted)
            XCTAssertFalse(state.allowed)
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertTrue(state.allowed)
        }
    }

    func testPreparationProgressExcludesCachedWorkFromEstimate() {
        var progress = PreparationProgress(total: 10, initiallyCached: 8, completed: 8)
        XCTAssertEqual(progress.fraction, 0.8)
        XCTAssertNil(progress.remainingSeconds(elapsed: 20), "Cached audio gives no speed measurement")
        progress.partial = 0.5
        XCTAssertEqual(progress.fraction, 0.85)
        XCTAssertEqual(progress.remainingSeconds(elapsed: 10), 30)
        progress.completed = 9
        progress.partial = 0
        XCTAssertEqual(progress.remainingSeconds(elapsed: 20), 20)
        progress.completed = 10
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remainingSeconds(elapsed: 30), 0)
    }

    func testTXTAccentsAndMarkdown() throws {
        let txt = try DocumentImporter().read(write("cuento.txt", Data("¡Buenos días! El pingüino tomó café en España.".utf8)))
        XCTAssertEqual(txt.blocks.first?.text, "¡Buenos días! El pingüino tomó café en España.")
        let md = try DocumentImporter().read(write("cuento.md", Data("# Capítulo uno\n\nUn **libro** con [enlace](https://example.com).".utf8)))
        let text = md.blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("Capítulo uno"))
        XCTAssertTrue(text.contains("Un libro con enlace."))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("**"))
    }
    func testPDFTextAndScannedRejection() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("Lectura en castellano: corazón y montaña." as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
        let book = try DocumentImporter().read(write("texto.pdf", data))
        XCTAssertTrue(book.blocks[0].text.contains("corazón"))
        let blank = renderer.pdfData { $0.beginPage() }
        XCTAssertThrowsError(try DocumentImporter().read(write("escaneado.pdf", blank)))
    }
    func testEPUBSpineOrderAndHTMLEntities() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ordered", withExtension: "epub"))
        let book = try DocumentImporter().read(url)
        XCTAssertEqual(book.blocks.count, 2)
        XCTAssertTrue(book.blocks[0].text.contains("Primero & castellano"))
        XCTAssertTrue(book.blocks[1].text.contains("Segundo capítulo"))
        XCTAssertFalse(book.blocks.map(\.text).joined().contains("NO LEER"))
    }
    func testChapterIdentityAndLegacyLibrary() throws {
        let blocks = [ReadingBlock(id: 0, heading: "Mismo título", text: "Uno", chapterID: 0),
                      ReadingBlock(id: 1, heading: "Mismo título", text: "Dos", chapterID: 1)]
        let book = Book(title: "Libro", format: "EPUB", blocks: blocks)
        XCTAssertEqual(book.chapters.map(\.range), [0..<1, 1..<2])
        let legacy = Data(#"{"id":0,"heading":"Antes","text":"Contenido"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ReadingBlock.self, from: legacy).chapterID)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ordered", withExtension: "epub"))
        let imported = try DocumentImporter().read(url)
        XCTAssertEqual(imported.chapters.count, 2)
        XCTAssertEqual(imported.blocks.map(\.chapterID), [0, 1])
    }

    func testMultipleEPUBChaptersInOneFilePreserveInlineText() throws {
        let document = try SwiftSoup.parse("<body><h1>Primero</h1><p>Un <em>niño</em> lee.</p><h2>Subsección</h2><p>Más texto.</p><h1>Segundo</h1><p>Final.</p></body>")
        let sections = try DocumentImporter.epubSections(document, fallback: "Libro")
        XCTAssertEqual(sections.map { $0.0 }, ["Primero", "Segundo"])
        XCTAssertTrue(sections[0].1.contains("Un niño lee."))
        XCTAssertTrue(sections[0].1.contains("Subsección"))
        XCTAssertFalse(sections[0].1.contains("Final."))
        XCTAssertTrue(sections[1].1.contains("Final."))
    }

    func testPDFPlaylistUsesOutlineOrPages() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let data = renderer.pdfData { context in
            for index in 0..<4 {
                context.beginPage()
                ("Contenido página \(index + 1)" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
        let withoutIndex = try DocumentImporter().read(write("pages.pdf", data))
        XCTAssertEqual(withoutIndex.chapters.count, 4)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "chapters", withExtension: "pdf"))
        let withIndex = try DocumentImporter().read(fixture)
        XCTAssertEqual(withIndex.chapters.map(\.title), ["Capítulo 1", "Capítulo 2"])
        let first = withIndex.blocks[withIndex.chapters[0].range].map(\.text).joined()
        let second = withIndex.blocks[withIndex.chapters[1].range].map(\.text).joined()
        XCTAssertTrue(first.contains("pagina 1") && first.contains("pagina 2"))
        XCTAssertTrue(second.contains("pagina 3") && second.contains("pagina 4"))
    }

    @MainActor
    func testPlaybackStartsBeforeLookAheadFinishesAndSelectionCancels() async throws {
        let service = TestSpeechGenerator()
        let book = Book(title: "Cola", format: "EPUB", blocks: [
            ReadingBlock(id: 0, heading: "Uno", text: "Primero", chapterID: 0),
            ReadingBlock(id: 1, heading: "Dos", text: "Segundo", chapterID: 1),
            ReadingBlock(id: 2, heading: "Tres", text: "Tercero", chapterID: 2)])
        let model = ReaderViewModel(book: book, service: service, save: { _ in })
        defer {
            model.close()
            try? FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent(book.id.uuidString))
            try? PreparedAudioStore().remove(book: book.id)
        }
        model.prepareAndPlay()
        let deadline = Date().addingTimeInterval(5)
        while (!model.isPlaying || !model.isGenerating) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(model.isPlaying, "Must play the first block while the second is still generating")
        XCTAssertTrue(model.isGenerating)
        XCTAssertNotNil(model.book.lastListenedAt(block: 0))
        XCTAssertNil(model.book.lastListenedAt(block: 1), "Generation is not listening")
        XCTAssertEqual(model.cachedBlocks, [0])
        while await service.requests.count < 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let requests = await service.requests
        XCTAssertEqual(requests, ["Primero", "Segundo"], "Must not generate the entire book")
        model.select(2)
        model.resumeFromHistory(0)
        XCTAssertEqual(model.positionBeforeHistoryJump, 2)
        model.returnFromHistory()
        XCTAssertEqual(model.book.position, 2)
        XCTAssertNil(model.positionBeforeHistoryJump)
        model.select(2)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.book.position, 2)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.isPlaying, "Cancelled work must not restart playback")
    }

    @MainActor
    func testPlaylistAdvancesAcrossChaptersInOrder() async throws {
        let service = TestSpeechGenerator(delayAfterFirst: .zero, frameCount: 4_800)
        let book = Book(title: "Autoavance", format: "EPUB", blocks: (0..<3).map {
            ReadingBlock(id: $0, heading: "Capítulo \($0)", text: "Texto \($0)", chapterID: $0)
        })
        let model = ReaderViewModel(book: book, service: service, save: { _ in })
        defer {
            model.close()
            try? FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent(book.id.uuidString))
            try? PreparedAudioStore().remove(book: book.id)
        }
        model.prepareAndPlay()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if model.book.position == 2 && !model.isPlaying && !model.isGenerating { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(model.book.position, 2)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.cachedBlocks, [0, 1, 2])
        let requests = await service.requests
        XCTAssertEqual(requests, ["Texto 0", "Texto 1", "Texto 2"])
    }

    @MainActor
    func testClosingDuringActivationDoesNotRestartOldReader() async throws {
        let service = TestSpeechGenerator(delayAfterFirst: .zero)
        let first = Book(title: "Anterior", format: "TXT", blocks: [ReadingBlock(id: 0, heading: "Texto", text: "Uno")])
        let second = Book(title: "Nuevo", format: "TXT", blocks: [ReadingBlock(id: 0, heading: "Texto", text: "Dos")])
        for book in [first, second] {
            let url = URL.cachesDirectory.appendingPathComponent(book.id.uuidString).appendingPathComponent(ReaderVoice.dora.rawValue).appendingPathComponent("0.wav")
            _ = try await service.generate(text: book.title, voice: .dora, destination: url, progress: { _ in })
        }
        let oldReader = ReaderViewModel(book: first, service: service, save: { _ in })
        let newReader = ReaderViewModel(book: second, service: service, save: { _ in })
        defer {
            oldReader.close()
            newReader.close()
            for book in [first, second] {
                try? FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent(book.id.uuidString))
            try? PreparedAudioStore().remove(book: book.id)
            }
        }
        oldReader.prepareAndPlay()
        oldReader.close() // Cancel before the asynchronous activation returns.
        newReader.prepareAndPlay()
        let deadline = Date().addingTimeInterval(5)
        while !newReader.isPlaying && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(oldReader.isPlaying)
        XCTAssertTrue(newReader.isPlaying)
        XCTAssertNil(newReader.error)
        newReader.pause()
        XCTAssertFalse(newReader.isPlaying)
        newReader.prepareAndPlay()
        while !newReader.isPlaying && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(newReader.isPlaying, "Resume must await session activation too")
    }

    func testInferenceSegmentsBoundExistingLongBlocksWithoutLosingText() {
        let text = Array(repeating: "El niño encontró un libro. ¡Qué alegría! Mañana leeremos más.", count: 20).joined(separator: " ")
        let segments = KokoroService.inferenceSegments(text)
        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty && $0.count <= KokoroService.inferenceCharacterLimit })
        XCTAssertEqual(segments.joined(separator: " "), text)
        let unbroken = String(repeating: "á", count: 350)
        XCTAssertEqual(KokoroService.inferenceSegments(unbroken).joined(), unbroken)
        XCTAssertTrue(KokoroService.inferenceSegments(unbroken).allSatisfy { $0.count <= KokoroService.inferenceCharacterLimit })
        XCTAssertTrue(KokoroService.inferenceSegments(" \n ").isEmpty)
    }

    @MainActor
    func testOfflineChapterPreparationPersistsWithoutChangingPosition() async throws {
        let store = PreparedAudioStore(root: directory.appendingPathComponent("audio"))
        let service = TestSpeechGenerator(delayAfterFirst: .zero, frameCount: 480)
        let book = Book(title: "Capítulos", format: "EPUB", blocks: (0..<3).map {
            ReadingBlock(id: $0, heading: "Capítulo \($0)", text: "Texto \($0)", chapterID: $0)
        })
        let model = ReaderViewModel(book: book, service: service, audioStore: store, save: { _ in })
        defer { model.close() }
        model.prepareChapter(book.chapters[1])
        let deadline = Date().addingTimeInterval(5)
        while model.isGenerating && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.book.position, 0)
        XCTAssertEqual(model.cachedBlocks, [1])
        XCTAssertNil(model.book.listeningSessions, "Offline preparation must not create listening tags")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.destination(book: book.id, voice: .dora, index: 1).path))
        XCTAssertNil(store.pending(book: book.id))
        let restored = ReaderViewModel(book: book, service: service, audioStore: store, save: { _ in })
        XCTAssertEqual(restored.cachedBlocks, [1])
        restored.close()
    }

    @MainActor
    func testBackgroundGrantAndExpirationPreserveResumablePreparation() async throws {
        let store = PreparedAudioStore(root: directory.appendingPathComponent("audio"))
        let service = TestSpeechGenerator(delayAfterFirst: .seconds(30), frameCount: 480)
        let permission = TestBackgroundLease(granted: true)
        var active = true
        let book = Book(title: "Fondo", format: "TXT", blocks: (0..<3).map {
            ReadingBlock(id: $0, heading: "Texto", text: "Texto \($0)")
        })
        let model = ReaderViewModel(book: book, service: service, audioStore: store,
            isAppActive: { active }, makeLease: { permission }, save: { _ in })
        model.prepareBook()
        let deadline = Date().addingTimeInterval(5)
        while await service.requests.count < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        active = false
        model.willResignActive()
        XCTAssertTrue(model.isGenerating, "GPU grant allows the current job to continue")
        XCTAssertTrue(model.backgroundGenerationAllowed)
        permission.expire()
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(store.pending(book: book.id)?.range, 0..<3)
        XCTAssertTrue(store.available(book: book.id, voice: .dora).contains(0))
        model.close()
        active = true
        let resumedService = TestSpeechGenerator(delayAfterFirst: .zero, frameCount: 480)
        let resumed = ReaderViewModel(book: book, service: resumedService, audioStore: store,
            isAppActive: { active }, save: { _ in })
        defer { resumed.close() }
        resumed.resumePreparation()
        while resumed.isGenerating && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        let requests = await resumedService.requests
        XCTAssertEqual(requests, ["Texto 1", "Texto 2"], "Resume must skip durable audio")
        XCTAssertEqual(resumed.cachedBlocks, [0, 1, 2])
        XCTAssertNil(store.pending(book: book.id))
    }

    @MainActor
    func testUnsupportedBackgroundStopsGenerationButPauseDoesNot() async throws {
        let store = PreparedAudioStore(root: directory.appendingPathComponent("audio"))
        var active = true
        let service = TestSpeechGenerator()
        let permission = TestBackgroundLease(granted: false)
        let book = Book(title: "Sin GPU de fondo", format: "TXT", blocks: [
            ReadingBlock(id: 0, heading: "Texto", text: "Uno"), ReadingBlock(id: 1, heading: "Texto", text: "Dos")])
        let model = ReaderViewModel(book: book, service: service, audioStore: store,
            isAppActive: { active }, makeLease: { permission }, save: { _ in })
        defer { model.close() }
        model.prepareAndPlay()
        let deadline = Date().addingTimeInterval(5)
        while !model.isPlaying && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        model.pause()
        XCTAssertTrue(model.isGenerating, "Pausing listening must not cancel preparation")
        model.prepareAndPlay()
        while !model.isPlaying && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        active = false
        model.willResignActive()
        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.isPlaying, "Saved audio must continue without a GPU grant")
        XCTAssertNotNil(store.pending(book: book.id))
    }

    @MainActor
    func testOfflinePreparationPromotesLegacyCache() async throws {
        let store = PreparedAudioStore(root: directory.appendingPathComponent("audio"))
        let book = Book(title: "Anterior", format: "TXT", blocks: [ReadingBlock(id: 0, heading: "Texto", text: "Uno")])
        let legacy = URL.cachesDirectory.appendingPathComponent(book.id.uuidString).appendingPathComponent(ReaderVoice.dora.rawValue).appendingPathComponent("0.wav")
        let service = TestSpeechGenerator()
        _ = try await service.generate(text: "Uno", voice: .dora, destination: legacy, progress: { _ in })
        defer { try? FileManager.default.removeItem(at: legacy.deletingLastPathComponent().deletingLastPathComponent()) }
        let model = ReaderViewModel(book: book, service: service, audioStore: store, save: { _ in })
        defer { model.close() }
        model.prepareBook()
        let deadline = Date().addingTimeInterval(5)
        while model.isGenerating && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertNil(model.error)
        let durable = store.destination(book: book.id, voice: .dora, index: 0)
        XCTAssertEqual(try Data(contentsOf: durable), try Data(contentsOf: legacy))
        XCTAssertNil(store.pending(book: book.id))
        let requests = await service.requests
        XCTAssertEqual(requests, ["Uno"], "Migration should not regenerate existing audio")
    }

    func testEPUBRejectsDRM() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "drm", withExtension: "epub"))
        XCTAssertThrowsError(try DocumentImporter().read(url))
    }
    func testChunksPreserveWordsAndBoundSize() {
        let text = Array(repeating: "El niño encontró un libro. ¡Qué alegría!", count: 100).joined(separator: " ")
        let chunks = DocumentImporter.split(text)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 350 })
        XCTAssertEqual(chunks.joined(separator: " "), text)
    }
    func testInvalidUTF8AndUnsupportedFiles() throws {
        XCTAssertThrowsError(try DocumentImporter().read(write("bad.txt", Data([0xff, 0xfe, 0xfd]))))
        XCTAssertThrowsError(try DocumentImporter().read(write("bad.zip", Data())))
    }
    func testPersistenceRoundTripAndDelete() throws {
        let store = LibraryStore(root: directory.appendingPathComponent("library"))
        var book = Book(title: "Prueba", format: "TXT", blocks: [ReadingBlock(id: 0, heading: "Uno", text: "Hola"), ReadingBlock(id: 1, heading: "Dos", text: "Adiós")])
        book.position = 1
        try store.save(book)
        XCTAssertEqual(try store.load(), [book])
        try store.remove(book)
        XCTAssertTrue(try store.load().isEmpty)
    }
    func testRealKokoroSpanishOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX requiere dispositivo físico; la síntesis no se simula.")
        #else
        let url = directory.appendingPathComponent("castellano.wav")
        let result = try await KokoroService().generate(text: "¡Buenos días! El niño lee un libro en castellano. Mañana iremos a la biblioteca de Valencia.", voice: .dora, destination: url)
        let file = try AVAudioFile(forReading: result)
        XCTAssertEqual(file.processingFormat.sampleRate, 24_000)
        XCTAssertGreaterThan(file.length, 24_000)
        let attachment = XCTAttachment(contentsOfFile: result)
        attachment.name = "Kokoro-Dora-castellano.wav"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }
}

/// Unit-test audio only: this verifies queue behavior, not Kokoro synthesis.
private actor TestSpeechGenerator: SpeechGenerating {
    private(set) var requests: [String] = []
    private let delayAfterFirst: Duration
    private let frameCount: AVAudioFrameCount
    init(delayAfterFirst: Duration = .seconds(30), frameCount: AVAudioFrameCount = 96_000) {
        self.delayAfterFirst = delayAfterFirst
        self.frameCount = frameCount
    }
    func generate(text: String, voice: ReaderVoice, destination: URL,
                  progress: @escaping @Sendable (SynthesisPhase) -> Void) async throws -> URL {
        requests.append(text)
        if requests.count > 1 { try await Task.sleep(for: delayAfterFirst) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 0.1)) * 0.01 }
        let file = try AVAudioFile(forWriting: destination, settings: format.settings)
        try file.write(from: buffer)
        return destination
    }
}

@MainActor
private final class TestBackgroundLease: BackgroundGenerationManaging {
    var canRunInBackground: Bool
    private var onExpiration: (@MainActor () -> Void)?
    init(granted: Bool) { canRunInBackground = granted }
    func request(title: String, onChange: @escaping @MainActor () -> Void, onExpiration: @escaping @MainActor () -> Void) {
        self.onExpiration = onExpiration
        onChange()
    }
    func report(completed: Int, total: Int) {}
    func finish(success: Bool) { canRunInBackground = false }
    func expire() { canRunInBackground = false; onExpiration?() }
}

private final class TestGPUState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var allowed: Bool { lock.withLock { value } }
    func set(_ value: Bool) { lock.withLock { self.value = value } }
}
