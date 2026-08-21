import XCTest

final class NotePatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func makeApp(
        _ arguments: [String] = [],
        language: String = "simplifiedChinese"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestLanguage", language])
        app.launchArguments.append(contentsOf: arguments)
        return app
    }

    @MainActor
    func testSupportedLanguagesRenderConsistentTabLabels() throws {
        let expectations = [
            ("simplifiedChinese", ["主页", "笔记", "AI", "我的"]),
            ("traditionalChinese", ["首頁", "筆記", "AI", "我的"]),
            ("english", ["Home", "Notes", "AI", "Me"])
        ]
        let identifiers = ["tab.home", "tab.notes", "tab.ai", "tab.me"]

        for (language, labels) in expectations {
            let app = makeApp(["-NotePatchUITestWorkbench"], language: language)
            app.launch()
            XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
            for (identifier, label) in zip(identifiers, labels) {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.exists)
                XCTAssertEqual(button.label, label)
            }
            app.terminate()
        }
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
        XCTAssertTrue(app.buttons["tab.home"].exists)
        XCTAssertTrue(app.buttons["tab.notes"].exists)
        XCTAssertTrue(app.buttons["tab.ai"].exists)
        XCTAssertTrue(app.buttons["tab.me"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeDashboard"].exists)
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.staticTexts["My Workspace"].exists)
    }

    @MainActor
    func testWorkbenchTabsUsePersonalWorkspaceLanguage() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.home"].exists)
        XCTAssertTrue(app.buttons["tab.notes"].exists)
        XCTAssertTrue(app.buttons["tab.ai"].exists)
        XCTAssertTrue(app.buttons["tab.me"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeSummary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeRecentDocuments"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeRecentNotes"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["homeReviewShortcuts"].exists)
        XCTAssertTrue(app.buttons["homeMetricDocuments"].exists)
        XCTAssertTrue(app.buttons["homeMetricLearningUnits"].exists)
        XCTAssertTrue(app.buttons["homeMetricHomeworks"].exists)

        app.buttons["homeMetricDocuments"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["documentsList"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["homeMetricLearningUnits"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["learningUnitsSection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["notesSubsectionPicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["闪卡"].exists)

        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeDashboard"].waitForExistence(timeout: 3))
        app.buttons["homeMetricHomeworks"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeworkGradingSection"].waitForExistence(timeout: 3))

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.staticTexts["My Workspace"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["family"].exists)
        XCTAssertFalse(app.staticTexts["class"].exists)
        XCTAssertFalse(app.staticTexts["school"].exists)
    }

    @MainActor
    func testOfflineAIModelCatalogAndAssistantModelLabel() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["aiModelPicker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["aiModelStaleWarning"].exists)

        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatModelLabel"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOfflineAICopyAndProfileEditingSurfaces() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        let copyConversation = app.buttons["copyConversationButton"]
        XCTAssertTrue(copyConversation.waitForExistence(timeout: 3))
        XCTAssertTrue(copyConversation.isEnabled)
        copyConversation.tap()
        XCTAssertTrue(app.staticTexts["整段对话已复制。"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["openClawAttachmentButton"].exists)

        app.buttons["tab.me"].tap()
        let editProfile = app.buttons["profileEditButton"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profileAvatarButton"].exists)
        editProfile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profileEditSheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["profileNameField"].exists)
        XCTAssertTrue(app.textFields["profileEmailField"].exists)
    }

    @MainActor
    func testOfflineStudyNoteCanBeReadInsideTheApp() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        let noteRow = app.buttons["studyNoteRow-note-1"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: 3))
        noteRow.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        let editButton = app.buttons["editStudyNoteButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        editButton.tap()
        XCTAssertTrue(app.textFields["studyNoteEditorTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["studyNoteEditorHTML"].exists)
        XCTAssertTrue(app.textFields["studyNoteEditorSummary"].exists)
        app.buttons["取消"].tap()
    }

    @MainActor
    func testOfflineFlashcardCanSwitchAndFlip() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notesSubsectionPicker"].waitForExistence(timeout: 3))
        app.buttons["notesSubsection.flashcards"].tap()

        let card = app.buttons["flashcardCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["What does a ratio compare?"].exists)
        XCTAssertFalse(app.staticTexts["What does a **ratio** compare?"].exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["The relationship between two quantities."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["The relationship between **two quantities**."].exists)
        app.buttons["下一张"].tap()
        XCTAssertTrue(app.staticTexts["How do you solve a proportion?"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOfflineLearningUnitMergeConfirmation() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        app.buttons["notesSubsection.units"].tap()
        let mergeButton = app.buttons["mergeLearningUnitsButton"]
        XCTAssertTrue(mergeButton.waitForExistence(timeout: 3))
        mergeButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["learningUnitMergeSheet"].waitForExistence(timeout: 3))
        let source = app.buttons["mergeSource-unit-2"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.tap()
        let continueButton = app.buttons["mergeContinueButton"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.firstMatch.buttons["合并"].exists)
    }

    @MainActor
    func testFailedDocumentPurgeShowsRetryAction() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPurgeFailure"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeActiveTask"].waitForExistence(timeout: 3))
        app.buttons["homeActiveTask"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["taskScreen"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.staticTexts["文档清理"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["失败"].exists)
        XCTAssertTrue(app.buttons["retryDocumentPurgeButton"].exists)
    }

    @MainActor
    func testPendingImageAppearsInUploadQueueAndCanBeRemoved() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.home"].tap()
        app.buttons["uploadFAB"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["uploadScreen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["待上传"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["uploadQueueThumbnail"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["uploadSelectedQueueButton"].exists)
        let removeButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '移除 '")).firstMatch
        XCTAssertTrue(removeButton.exists)
        removeButton.tap()
        let thumbnailRemoved = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons["uploadQueueThumbnail"]
        )
        wait(for: [thumbnailRemoved], timeout: 3)
    }

    @MainActor
    func testUploadFABOpensFromEveryWorkbenchTab() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        for tabIdentifier in ["tab.home", "tab.notes", "tab.ai", "tab.me"] {
            app.buttons[tabIdentifier].tap()

            let uploadButton = app.buttons["uploadFAB"]
            XCTAssertTrue(uploadButton.waitForExistence(timeout: 2), "Missing upload button on \(tabIdentifier)")
            XCTAssertTrue(uploadButton.isHittable, "Upload button is not hittable on \(tabIdentifier)")
            uploadButton.tap()

            let closeButton = app.buttons["uploadScreen"]
            XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Upload screen did not open from \(tabIdentifier)")
            closeButton.tap()
            XCTAssertFalse(closeButton.exists, "Upload screen did not close on \(tabIdentifier)")
        }
    }

    @MainActor
    func testOpenClawEditorAcceptsMultilineInput() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

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
        app.buttons["tab.ai"].tap()

        let attachmentButton = app.buttons["openClawAttachmentButton"]
        XCTAssertTrue(attachmentButton.waitForExistence(timeout: 3))
        attachmentButton.tap()
        XCTAssertTrue(app.buttons["选择照片"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["选择文件"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chatSaveToWorkspaceToggle"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOpenClawKeyboardStaysVisibleAndDismissesAfterCrossingComposer() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        let bottomNavigation = app.otherElements["workbenchTabs"]
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 3))
        let bottomNavigationFrameBeforeKeyboard = bottomNavigation.frame
        XCTAssertLessThanOrEqual(app.frame.maxY - bottomNavigationFrameBeforeKeyboard.maxY, 36)

        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertEqual(bottomNavigation.frame.minY, bottomNavigationFrameBeforeKeyboard.minY, accuracy: 1)
        XCTAssertEqual(bottomNavigation.frame.maxY, bottomNavigationFrameBeforeKeyboard.maxY, accuracy: 1)
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 1)
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

        let belowTextFieldY = min(0.95, (editor.frame.maxY + 28) / app.frame.height)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: belowTextFieldY)
                )
            )

        let keyboardDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: keyboard
        )
        wait(for: [keyboardDismissed], timeout: 3)
        XCTAssertEqual(bottomNavigation.frame.minY, bottomNavigationFrameBeforeKeyboard.minY, accuracy: 1)
        XCTAssertEqual(bottomNavigation.frame.maxY, bottomNavigationFrameBeforeKeyboard.maxY, accuracy: 1)
    }

    @MainActor
    func testLastProfileActionScrollsAboveFloatingNavigation() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.me"].tap()
        let signOut = app.buttons["profileSignOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 3))
        let navigation = app.otherElements["workbenchTabs"]
        for _ in 0..<6 where signOut.frame.maxY > navigation.frame.minY - 20 {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, navigation.frame.minY - 20)
    }

    @MainActor
    func testLearningSearchAndGradingWorkflowIsAvailable() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notesSubsectionPicker"].waitForExistence(timeout: 3))
        app.buttons["notesSubsection.search"].tap()
        let query = app.textFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("一次函数")
        XCTAssertTrue(app.buttons["knowledgeSearchButton"].isEnabled)

        app.buttons["notesSubsection.homework"].tap()
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
