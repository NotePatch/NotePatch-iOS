import XCTest

final class NotePatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func makeApp(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestLanguage", "simplifiedChinese"])
        app.launchArguments.append(contentsOf: arguments)
        return app
    }

    @MainActor
    func testAuthScreenLaunchesWithoutStoredSession() throws {
        let app = makeApp(["-NotePatchUITestNoSession"])
        app.launch()

        XCTAssertTrue(app.staticTexts["NotePatch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["apiAddressField"].exists)
        XCTAssertTrue(app.textFields["emailField"].exists)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertTrue(app.buttons["loginButton"].exists)
    }

    @MainActor
    func testUITestEmailLogsIntoOfflineWorkbenchWithoutPassword() throws {
        let app = makeApp(["-NotePatchUITestNoSession"])
        app.launch()

        let email = app.textFields["emailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("uitest")
        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["笔记"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI"].exists)
        XCTAssertTrue(app.tabBars.buttons["我的"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["globalStatusBanner"].exists)
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
    }

    @MainActor
    func testWorkbenchTabsUsePersonalWorkspaceLanguage() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["文档"].exists)
        XCTAssertTrue(app.tabBars.buttons["笔记"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI"].exists)
        XCTAssertTrue(app.tabBars.buttons["我的"].exists)
        app.tabBars.buttons["文档"].tap()
        let documentSections = app.segmentedControls["documentsSectionPicker"]
        XCTAssertTrue(documentSections.waitForExistence(timeout: 3))
        XCTAssertTrue(documentSections.buttons["文档"].exists)
        XCTAssertTrue(documentSections.buttons["任务"].exists)
        documentSections.buttons["任务"].tap()
        XCTAssertTrue(app.staticTexts["当前任务"].waitForExistence(timeout: 3))
        app.tabBars.buttons["笔记"].tap()
        let notesSections = app.segmentedControls["notesSectionPicker"]
        XCTAssertTrue(notesSections.waitForExistence(timeout: 3))
        notesSections.buttons["复习"].tap()
        XCTAssertTrue(app.segmentedControls["reviewSectionPicker"].waitForExistence(timeout: 3))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profileTab"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
        XCTAssertFalse(app.staticTexts["family"].exists)
        XCTAssertFalse(app.staticTexts["class"].exists)
        XCTAssertFalse(app.staticTexts["school"].exists)
    }

    @MainActor
    func testOfflineStudyNoteCanBeReadInsideTheApp() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["笔记"].tap()
        let noteTitle = app.staticTexts["Fractions & Ratios Notes"]
        XCTAssertTrue(noteTitle.waitForExistence(timeout: 3))
        noteTitle.tap()
        XCTAssertTrue(app.staticTexts["Key Concepts"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["editStudyNoteButton"].exists)
        app.buttons["editStudyNoteButton"].tap()
        XCTAssertTrue(app.textFields["studyNoteEditorTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["studyNoteEditorMarkdown"].exists)
        XCTAssertTrue(app.textFields["studyNoteEditorSummary"].exists)
        app.buttons["取消"].tap()
    }

    @MainActor
    func testFailedDocumentPurgeShowsRetryAction() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPurgeFailure"])
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
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
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
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["AI"].tap()

        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let attachmentButton = app.buttons["openClawAttachmentButton"]
        XCTAssertTrue(attachmentButton.exists)
        editor.tap()
        XCTAssertGreaterThan(attachmentButton.frame.minY, editor.frame.minY + 20)
        let fixedWidth = editor.frame.width
        let singleLineHeight = editor.frame.height
        let automaticWrappingText = String(repeating: "自动换行测试", count: 10)
        editor.typeText(automaticWrappingText)
        let wrappedLineExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in editor.frame.height > singleLineHeight + 1 },
            object: nil
        )
        wait(for: [wrappedLineExpectation], timeout: 2)
        XCTAssertEqual(editor.frame.width, fixedWidth, accuracy: 1)
        editor.typeText("\n第二行")
        XCTAssertEqual(editor.value as? String, automaticWrappingText + "\n第二行")
        let sendButton = app.buttons["openClawSendButton"]
        XCTAssertTrue(sendButton.isEnabled)
        XCTAssertLessThanOrEqual(sendButton.frame.maxX, app.frame.maxX - 12)
    }

    @MainActor
    func testOpenClawAttachmentMenuShowsPhotoAndFileOptions() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["AI"].tap()

        let attachmentButton = app.buttons["openClawAttachmentButton"]
        XCTAssertTrue(attachmentButton.waitForExistence(timeout: 3))
        attachmentButton.tap()
        XCTAssertTrue(app.buttons["选择照片"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["选择文件"].exists)
    }

    @MainActor
    func testOpenClawKeyboardStaysVisibleAndDismissesAfterCrossingComposer() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["AI"].tap()

        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        editor.typeText("a")
        XCTAssertTrue(keyboard.exists)
        XCTAssertFalse(app.buttons["收起键盘"].exists)

        let startY = max(0.1, (editor.frame.minY - 80) / app.frame.height)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: max(0.05, startY - 0.12))
                )
            )
        XCTAssertTrue(keyboard.exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.buttons["openClawSendButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            )

        let keyboardDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: keyboard
        )
        wait(for: [keyboardDismissed], timeout: 3)
    }

    @MainActor
    func testLearningSearchAndGradingWorkflowIsAvailable() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.tabBars.buttons["笔记"].tap()
        let notesSections = app.segmentedControls["notesSectionPicker"]
        XCTAssertTrue(notesSections.waitForExistence(timeout: 3))
        notesSections.buttons["复习"].tap()

        let segments = app.segmentedControls["reviewSectionPicker"]
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
            let app = makeApp()
            app.launchArguments.append("-NotePatchUITestNoSession")
            app.launch()
        }
    }
}
