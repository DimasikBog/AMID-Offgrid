import XCTest

final class PocketUiTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element cannot be reached")
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
            let link = app.descendants(matching: .any).matching(identifier: "card-\(id)").firstMatch
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
