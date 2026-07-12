import XCTest

final class NotePatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
        XCTAssertTrue(app.staticTexts["UI 离线测试模式"].exists)
        XCTAssertTrue(app.tabBars.buttons["笔记"].exists)
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI"].exists)
        XCTAssertTrue(app.tabBars.buttons["复习"].exists)
    }

    @MainActor
    func testWorkbenchTabsUsePersonalWorkspaceLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
        XCTAssertTrue(app.tabBars.buttons["笔记"].exists)
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI"].exists)
        XCTAssertTrue(app.tabBars.buttons["复习"].exists)
        app.tabBars.buttons["文档"].tap()
        let documentSections = app.segmentedControls.firstMatch
        XCTAssertTrue(documentSections.waitForExistence(timeout: 3))
        XCTAssertTrue(documentSections.buttons["文档"].exists)
        XCTAssertTrue(documentSections.buttons["任务"].exists)
        documentSections.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["当前任务"].waitForExistence(timeout: 3))
        app.tabBars.buttons["复习"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["learningTab"].waitForExistence(timeout: 3))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsTab"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["family"].exists)
        XCTAssertFalse(app.staticTexts["class"].exists)
        XCTAssertFalse(app.staticTexts["school"].exists)
    }

    @MainActor
    func testOfflineStudyNoteCanBeReadInsideTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["笔记"].tap()
        let noteTitle = app.staticTexts["分数与比例笔记"]
        XCTAssertTrue(noteTitle.waitForExistence(timeout: 3))
        noteTitle.tap()
        XCTAssertTrue(app.staticTexts["核心概念"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["editStudyNoteButton"].exists)
        app.buttons["editStudyNoteButton"].tap()
        XCTAssertTrue(app.textFields["studyNoteEditorTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["studyNoteEditorMarkdown"].exists)
        XCTAssertTrue(app.textFields["studyNoteEditorSummary"].exists)
        app.buttons["取消"].tap()
    }

    @MainActor
    func testFailedDocumentPurgeShowsRetryAction() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestWorkbench", "-NotePatchUITestPurgeFailure"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["文档"].tap()
        app.segmentedControls.firstMatch.buttons["任务"].tap()

        XCTAssertTrue(app.staticTexts["文档清理"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["失败"].exists)
        XCTAssertTrue(app.buttons["retryDocumentPurgeButton"].exists)
    }

    @MainActor
    func testPendingImageAppearsInUploadQueueAndCanBeRemoved() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["文档"].tap()
        app.buttons["showUploadPageButton"].tap()
        XCTAssertTrue(app.staticTexts["待上传"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["uploadQueueThumbnail"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["uploadSelectedQueueButton"].exists)
        let removeButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '移除 '")).firstMatch
        XCTAssertTrue(removeButton.exists)
        removeButton.tap()
        XCTAssertTrue(app.staticTexts["暂无待上传文件"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenClawEditorAcceptsMultilineInput() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["AI"].tap()

        let editor = app.textViews["问 OpenClaw"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let newConversationButton = app.buttons["新建对话"]
        let collapsedButtonY = newConversationButton.frame.minY
        editor.tap()
        XCTAssertGreaterThan(newConversationButton.frame.minY, collapsedButtonY)
        editor.typeText("第一行\n第二行")
        XCTAssertTrue(app.buttons["发送"].isEnabled)
    }

    @MainActor
    func testOpenClawKeyboardStaysVisibleAfterTyping() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["AI"].tap()

        let editor = app.textViews["问 OpenClaw"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        editor.typeText("a")
        XCTAssertTrue(keyboard.exists)
        XCTAssertFalse(app.buttons["收起键盘"].exists)
    }

    @MainActor
    func testLearningSearchAndGradingWorkflowIsAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-NotePatchUITestWorkbench")
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["复习"].tap()

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
