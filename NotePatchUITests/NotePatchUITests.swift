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
    func testUITestEmailLogsIntoOfflineWorkbenchWithoutPassword() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestNoSession")
        app.launch()

        let email = app.textFields["emailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("uitest")
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
        XCTAssertTrue(app.staticTexts["UI 离线测试模式"].exists)
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["OpenClaw"].exists)
        XCTAssertTrue(app.tabBars.buttons["学习"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["learningTab"].waitForExistence(timeout: 3))
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
    func testOpenClawEditorAcceptsMultilineInput() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["OpenClaw"].tap()

        let editor = app.textViews["问 OpenClaw"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("第一行\n第二行")
        XCTAssertTrue(app.buttons["发送"].isEnabled)
    }

    @MainActor
    func testLearningSearchAndGradingWorkflowIsAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["学习"].tap()

        let segments = app.segmentedControls.firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: 3))
        segments.buttons["检索"].tap()
        let query = app.textFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("一次函数")
        XCTAssertTrue(app.buttons["knowledgeSearchButton"].isEnabled)

        segments.buttons["评分"].tap()
        XCTAssertTrue(app.staticTexts["作业评分"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["gradeHomeworkButton"].exists)
        app.buttons["创建作业"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeworkCreateSheet"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
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
