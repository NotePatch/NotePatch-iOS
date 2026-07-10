import XCTest

final class NotePatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAuthScreenLaunchesWithoutStoredSession() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestNoSession")
        app.launch()

        XCTAssertTrue(app.staticTexts["NotePatch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["apiAddressField"].exists)
        XCTAssertTrue(app.textFields["emailField"].exists)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertTrue(app.buttons["loginButton"].exists)
    }

    @MainActor
    func testWorkbenchTabsUsePersonalWorkspaceLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["任务"].exists)
        XCTAssertTrue(app.tabBars.buttons["OpenClaw"].exists)
        XCTAssertTrue(app.tabBars.buttons["学习"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        app.tabBars.buttons["学习"].tap()
        XCTAssertTrue(app.otherElements["learningTab"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["family"].exists)
        XCTAssertFalse(app.staticTexts["class"].exists)
        XCTAssertFalse(app.staticTexts["school"].exists)
    }

    @MainActor
    func testPendingImagePreviewCanBeCancelled() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()

        XCTAssertTrue(app.otherElements["uploadPreviewScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["uploadPreviewFilename"].exists)
        XCTAssertTrue(app.buttons["confirmPendingUploadButton"].exists)

        let cancelButton = app.buttons["cancelPendingUploadButton"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["uploadPreviewScreen"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("-NotePatchUITestNoSession")
            app.launch()
        }
    }
}
