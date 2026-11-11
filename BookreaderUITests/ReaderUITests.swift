import XCTest

final class ReaderUITests: XCTestCase {
    @MainActor
    private func waitForLayout(_ app: XCUIApplication) {
        // Duo can retain its panel coordinate axes across rotations. Verify stable,
        // visible controls rather than imposing a width/height ratio on the device.
        var previousFrame = CGRect.zero
        var previousButtonFrame = CGRect.zero
        var stableSamples = 0
        let settled = NSPredicate { _, _ in
            let frame = app.frame
            let button = app.buttons["Preparar y escuchar"]
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
        XCTAssertTrue(app.navigationBars["Bookreader"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.buttons["Preparar y escuchar"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bienvenida")).firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor
    func testEnglishLocalization() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
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
        let play = app.buttons["Prepare and listen"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bienvenida"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Section 1 of 1"].exists)
        XCTAssertTrue(app.buttons["Next section"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "English reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // The simulator error exercises localization outside SwiftUI views.
        play.tap()
        XCTAssertTrue(app.alerts["Audio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts["Kokoro requires a physical iPhone or iPad. You can test the library and read documents in the simulator."].exists)
        app.alerts.buttons["OK"].tap()
    }

}
