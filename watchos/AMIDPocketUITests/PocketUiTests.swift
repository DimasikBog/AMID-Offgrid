import XCTest

final class PocketUiTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<28 {
            // XCTest can scroll a realized native Button into view when tapping.
            // Waiting for isHittable here can oscillate between snapped List pages.
            if element.exists { return }
            // Small drags avoid skipping lazily-created rows on a 40/42 mm watch.
            let above = element.exists && element.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.38 : 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.62 : 0.48))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: XCUIGestureVelocity(rawValue: 60), thenHoldForDuration: 0.6)
        }
        capture(app, "unreachable-row")
        print(app.debugDescription)
        XCTAssertTrue(element.exists, "Element cannot be reached")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChecklistPersistsAcrossProcessRestartAndAllCardsOpen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let check = app.descendants(matching: .any).matching(identifier: "check-water").firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 30))
        reveal(check, in: app)
        let before = String(describing: check.value)
        check.tap()
        let changedValue = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in String(describing: check.value) != before },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changedValue], timeout: 10), .completed,
                       "Checklist toggle must change before persistence is checked")
        let changed = String(describing: check.value)
        XCTAssertNotEqual(before, changed)
        capture(app, "01-checklist")
        app.terminate()
        app.launch()
        XCTAssertTrue(check.waitForExistence(timeout: 30))
        XCTAssertEqual(String(describing: check.value), changed)

        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cards", withExtension: "json"))
        let pack = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cards = try XCTUnwrap(pack["cards"] as? [[String: String]])
        XCTAssertEqual(cards.count, 6)
        for card in cards {
            app.terminate()
            app.launch()
            let id = try XCTUnwrap(card["id"])
            // Match the actionable Button, not the parent Cell with the same label.
            let link = app.buttons["card-\(id)"]
            reveal(link, in: app)
            link.tap()
            let body = app.staticTexts["card-body"]
            XCTAssertTrue(body.waitForExistence(timeout: 15))
            XCTAssertEqual(body.label, card["body"])
            capture(app, "card-\(id)")
        }
        print("AMID_WATCH_EMULATOR_PASS: six cards, checklist, process restart")
    }
}
