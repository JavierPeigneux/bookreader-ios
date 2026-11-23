import XCTest

final class ReaderUITests: XCTestCase {
    @MainActor
    func testFirstRunTutorial() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let next = app.buttons["tutorial.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertEqual(next.label, "Empezar")
        next.tap()
        app.buttons["tutorial.back"].tap()
        for step in 1...7 {
            XCTAssertTrue(app.staticTexts["\(step) / 7"].exists)
            next.tap()
        }
        XCTAssertFalse(next.exists)
        XCTAssertTrue(app.buttons["folder.new"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["1 / 7"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRenameBookAndFindByNewName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--store-screenshots", "--disable-animations", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "La biblioteca del faro")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        app.buttons["Renombrar libro"].tap()
        let name = app.textFields["book.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "La biblioteca del faro".count) + "Tema 7 - Literatura")
        app.buttons["book.save"].tap()
        let renamed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tema 7 - Literatura")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        let search = librarySearch(in: app)
        search.tap(); search.typeText("Tema 7")
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        XCTAssertTrue(app.staticTexts["Tema 7 - Literatura"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchArtworkAndLocalizedCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--launch-preview", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.images["launch.artwork"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Folisona"].exists)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            var previousFrame = CGRect.zero
            var stableSamples = 0
            let settled = NSPredicate { _, _ in
                let frame = app.frame
                let artwork = app.images["launch.artwork"]
                let title = app.staticTexts["Folisona"].firstMatch
                guard XCUIDevice.shared.orientation == orientation, artwork.exists, frame.intersects(artwork.frame), title.exists, frame.contains(title.frame) else { stableSamples = 0; return false }
                stableSamples = frame == previousFrame ? stableSamples + 1 : 0
                previousFrame = frame
                return stableSamples >= 3
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: app)], timeout: 15), .completed)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = orientation == .portrait ? "Inicio vertical" : "Inicio horizontal"
            screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        for (language, locale, cancel) in [("es", "es_ES", "Cancelar"), ("en", "en_US", "Cancel")] {
            app.launchArguments = ["--store-screenshots", "--disable-animations", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.buttons["folder.new"].waitForExistence(timeout: 15))
            app.buttons["folder.new"].tap()
            XCTAssertTrue(app.buttons[cancel].waitForExistence(timeout: 5))
            app.buttons[cancel].tap()
            XCTAssertTrue(app.buttons["folder.new"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testDraggingDocumentsCreatesFolder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--store-screenshots", "--disable-animations", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "La biblioteca del faro")).firstMatch
        let second = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cuaderno de días tranquilos")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        // Keep the drop point clear of the scrolling edge while holding the book.
        if !second.isHittable || second.frame.midY > app.frame.height * 0.75 {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(first.isHittable && second.isHittable)
        let cover = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "book.cover.", "La biblioteca del faro")).firstMatch
        XCTAssertTrue(cover.isHittable)
        cover.press(forDuration: 0.7, thenDragTo: second, withVelocity: .slow, thenHoldForDuration: 0.3)
        let name = app.textFields["folder.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Lecturas")
        app.buttons["folder.save"].tap()
        let folder = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lecturas")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        if !second.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Carpeta de lecturas"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testFolderCreationMoveRenameAndSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--store-screenshots", "--disable-animations", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.buttons["folder.new"].waitForExistence(timeout: 15))
        app.buttons["folder.new"].tap()
        let name = app.textFields["folder.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Oposiciones")
        app.buttons["folder.save"].tap()
        let folder = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oposiciones")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "La biblioteca del faro")).firstMatch
        book.press(forDuration: 1)
        app.buttons["Mover a carpeta"].tap()
        app.buttons["Oposiciones"].tap()
        folder.tap()
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Senderos del bosque")).firstMatch.exists)
        app.buttons["Biblioteca"].tap()
        folder.press(forDuration: 1)
        app.buttons["Renombrar carpeta"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11) + "Temario")
        app.buttons["folder.save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Temario")).firstMatch.waitForExistence(timeout: 5))
        // Root search must also find documents stored inside folders.
        let search = librarySearch(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("faro")
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Busqueda en carpetas"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    private func librarySearch(in app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.isHittable {
            let searchButton = app.buttons["Buscar"]
            if searchButton.isHittable { searchButton.tap() }
            else { app.scrollViews.firstMatch.swipeDown() }
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    @MainActor
    private func waitForLayout(_ app: XCUIApplication) {
        // Duo can retain its panel coordinate axes across rotations. Verify stable,
        // visible controls rather than imposing a width/height ratio on the device.
        var previousFrame = CGRect.zero
        var previousButtonFrame = CGRect.zero
        var stableSamples = 0
        let settled = NSPredicate { _, _ in
            let frame = app.frame
            let button = app.buttons["Escuchar"]
            guard button.exists, button.isHittable, frame.contains(button.frame) else {
                stableSamples = 0
                return false
            }
            stableSamples = frame == previousFrame && button.frame == previousButtonFrame ? stableSamples + 1 : 0
            previousFrame = frame
            previousButtonFrame = button.frame
            return stableSamples >= 2
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }

    @MainActor
    func testLibraryAndSpanishReader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        if app.buttons["tutorial.skip"].exists { app.buttons["tutorial.skip"].tap() }
        XCTAssertTrue(app.navigationBars["Folisona"].waitForExistence(timeout: 15))
        let library = XCTAttachment(screenshot: app.screenshot())
        library.name = "Biblioteca"
        library.lifetime = .keepAlways
        add(library)
        let sample = app.buttons["Probar con un texto en castellano"]
        if sample.exists {
            sample.tap()
        } else {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bienvenida")).firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Escuchar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bienvenida"].firstMatch.exists)
        let reader = XCTAttachment(screenshot: app.screenshot())
        reader.name = "Lector-castellano"
        reader.lifetime = .keepAlways
        add(reader)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(app)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Lector-apaisado"
        landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait
        waitForLayout(app)
        app.terminate()
        app.launch()
        if app.buttons["tutorial.skip"].exists { app.buttons["tutorial.skip"].tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bienvenida")).firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor
    func testEnglishLocalization() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["tutorial.skip"].exists { app.buttons["tutorial.skip"].tap() }
        XCTAssertTrue(app.buttons["Import document"].waitForExistence(timeout: 15))
        let sample = app.buttons["Try a Spanish sample"]
        if sample.exists {
            sample.tap()
        } else {
            let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bienvenida")).firstMatch
            XCTAssertTrue(book.waitForExistence(timeout: 10))
            XCTAssertTrue(book.label.contains("1 section"), book.label)
            book.tap()
        }
        app.buttons["reader.history"].tap()
        XCTAssertTrue(app.switches["Show listening times"].exists || app.buttons["Show listening times"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Times will appear once you listen to the book."].exists)
        app.buttons["Show listening times"].tap()
        app.buttons["reader.chapters"].tap()
        XCTAssertTrue(app.navigationBars["Chapter playlist"].waitForExistence(timeout: 5))
        app.buttons["chapter.0"].tap()
        let play = app.buttons["Listen"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bienvenida"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Section 1 of 1"].exists)
        XCTAssertTrue(app.buttons["Next section"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "English reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(app.progressIndicators.count, 0)
        app.buttons["reader.prepare"].tap()
        app.buttons["Download voices"].tap()
        XCTAssertTrue(app.buttons["reader.voice.openSettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Accessibility → Read & Speak → Voices"].exists)

    }

    @MainActor
    func testMissingVoicesOffersSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--store-screenshots", "--no-system-voices", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The Lighthouse Library")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        app.buttons["chapter.0"].tap()
        let download = app.buttons["reader.voice.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reader.playback"].exists)
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "No voices"
        empty.lifetime = .keepAlways
        add(empty)
        download.tap()
        let open = app.buttons["reader.voice.openSettings"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let instructions = XCTAttachment(screenshot: app.screenshot())
        instructions.name = "Download voice instructions"
        instructions.lifetime = .keepAlways
        add(instructions)
        open.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in settings.state == .runningForeground }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed)
        app.activate()
        app.buttons["Done"].tap()
        XCTAssertTrue(download.waitForExistence(timeout: 5))
    }

    @MainActor
    private func captureStoreScreenshots(language: String) throws {
        guard ProcessInfo.processInfo.environment["FOLISONA_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Only run via scripts/screenshots.sh")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--store-screenshots", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "es" ? "es_ES" : "en_US"]
        app.launch()
        if app.buttons["tutorial.skip"].exists { app.buttons["tutorial.skip"].tap() }
        let title = language == "es" ? "La biblioteca del faro" : "The Lighthouse Library"
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        func capture(_ name: String) {
            // Include system chrome and allow navigation/sheet animations to settle.
            let settled = expectation(description: "Screenshot layout settled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
            wait(for: [settled], timeout: 3)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Store-\(language)-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        capture("01-library")
        book.tap()
        let chapter = app.buttons["chapter.0"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        capture("02-chapters")
        chapter.tap()
        XCTAssertTrue(app.buttons["reader.chapters"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.swipeDown()
        capture("03-reader")
        app.terminate()
    }

    @MainActor func testStoreSpanish() throws { try captureStoreScreenshots(language: "es") }
    @MainActor func testStoreEnglish() throws { try captureStoreScreenshots(language: "en") }

}
