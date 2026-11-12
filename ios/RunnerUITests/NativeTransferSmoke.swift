import XCTest

final class NativeTransferSmoke: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let label = NSPredicate(format: "label CONTAINS[c] %@", text)
        let button = app.buttons.matching(label).firstMatch
        return button.exists ? button : app.staticTexts.matching(label).firstMatch
    }

    private func tap(_ text: String, in app: XCUIApplication) {
        var item = element(text, in: app)
        if !item.waitForExistence(timeout: 3) || !item.isHittable {
            app.swipeUp()
            item = element(text, in: app)
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing \(text)")
        XCTAssertTrue(item.isHittable, "Cannot tap \(text)")
        item.tap()
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEntrySheetBackAndSecondarySwipe() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(element("Overview", in: app).waitForExistence(timeout: 10))

        tap("Settings", in: app)
        XCTAssertTrue(element("Export backup", in: app).waitForExistence(timeout: 5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.42))
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.42))
        edge.press(forDuration: 0.05, thenDragTo: destination)
        XCTAssertTrue(element("Overview", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("Export backup", in: app).exists)

        tap("Add entry", in: app)
        let heading = element("Choose exercise", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(heading.frame.minY, app.frame.height * 0.10)
        capture("Choose exercise sheet")

        // The demo provides an existing exercise. A fresh install still checks
        // the sheet and dismissal above and below without creating any records.
        if element("Push-ups", in: app).exists {
            tap("Push-ups", in: app)
            XCTAssertTrue(element("Save 1 set", in: app).waitForExistence(timeout: 5))
            capture("Enter sets sheet")
            tap("Back", in: app)
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            tap("Continue to sets", in: app)
            XCTAssertTrue(element("Save 1 set", in: app).waitForExistence(timeout: 5))
        }
        tap("Cancel entry", in: app)
        XCTAssertTrue(element("Overview", in: app).waitForExistence(timeout: 5))
    }

    func testNativeShareAndPickerCancelAndResume() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(element("Overview", in: app).waitForExistence(timeout: 10))
        capture("Overview after cold launch")

        tap("Settings", in: app)
        tap("Export backup", in: app)
        let shareAction = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Save to Files")
        ).firstMatch
        XCTAssertTrue(shareAction.waitForExistence(timeout: 12), "The native share sheet did not open")
        capture("Native JSON share sheet")
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
        if close.exists && close.isHittable {
            close.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(element("Export backup", in: app).waitForExistence(timeout: 6))
        XCTAssertFalse(shareAction.exists)

        tap("Import backup", in: app)
        tap("Open JSON file", in: app)
        let navigation = app.navigationBars.matching(
            NSPredicate(format: "identifier IN %@ OR label IN %@",
                ["Recents", "Browse"], ["Recents", "Browse"])
        ).firstMatch
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close", "Done"])).firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 8) || cancel.waitForExistence(timeout: 4),
                      "The native document picker did not open")
        capture("Native JSON picker")
        XCTAssertTrue(cancel.exists && cancel.isHittable, "The native picker has no reachable close control")
        cancel.tap()
        XCTAssertTrue(element("Open JSON file", in: app).waitForExistence(timeout: 6))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(element("Open JSON file", in: app).waitForExistence(timeout: 8),
                      "The app lost the current screen when it resumed")
    }
}
