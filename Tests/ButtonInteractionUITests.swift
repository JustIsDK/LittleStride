import XCTest

final class ButtonInteractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 100 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    func testEmptyAreaOpensManualEntry() {
        app.buttons["拍照"].firstMatch.tap()
        let manual = app.buttons["不用 AI，手动录入题目"]
        reveal(manual)
        XCTAssertGreaterThan(manual.frame.width, app.frame.width * 0.75)
        manual.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["录入题目"].waitForExistence(timeout: 3))
        let save = app.buttons["保存题目"]
        reveal(save)
        XCTAssertFalse(save.isEnabled)
    }

    func testAISettingsEmptyAreaTriggersValidation() {
        app.buttons["拍照"].firstMatch.tap()
        let settings = app.buttons["AI 配置与连接检查"]
        reveal(settings)
        settings.tap()
        let save = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "保存连接配置")).firstMatch
        reveal(save)
        XCTAssertGreaterThan(save.frame.width, app.frame.width * 0.75)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "AI settings before press"; before.lifetime = .keepAlways; add(before)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 2)
        XCTAssertTrue(app.alerts["需要处理"].waitForExistence(timeout: 3))
        app.alerts["需要处理"].buttons["知道了"].tap()
    }
}
