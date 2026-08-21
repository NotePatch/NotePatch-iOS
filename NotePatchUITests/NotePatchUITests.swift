import XCTest

final class NotePatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func makeApp(
        _ arguments: [String] = [],
        language: String = "simplifiedChinese"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-NotePatchUITestLanguage", language])
        app.launchArguments.append("-NotePatchUITestResetGlobalFeedback")
        app.launchArguments.append(contentsOf: arguments)
        return app
    }

    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func assertInsideScreen(
        _ element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, "Missing element", file: file, line: line)
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX - 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, app.frame.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX + 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, app.frame.maxY + 1, file: file, line: line)
    }

    private func assertMinimumHitSize(
        _ element: XCUIElement,
        width: CGFloat = 44,
        height: CGFloat = 44,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, "Missing interactive element", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, width - 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, height - 0.5, file: file, line: line)
    }

    private func assertBecomesHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hittable = expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: element
        )
        wait(for: [hittable], timeout: timeout)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func dismissKeyboardForAudit(_ app: XCUIApplication, editor: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }

        let startY = max(0.1, (editor.frame.minY - 80) / app.frame.height)
        let belowTextFieldY = min(0.95, (editor.frame.maxY + 28) / app.frame.height)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: belowTextFieldY)
                )
            )

        let dismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: keyboard
        )
        wait(for: [dismissed], timeout: 3)
    }

    @discardableResult
    private func assertAppearsQuickly(
        _ element: XCUIElement,
        timeout: TimeInterval = 1.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> TimeInterval {
        let startedAt = Date()
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        let elapsed = Date().timeIntervalSince(startedAt)
        XCTAssertLessThan(elapsed, timeout, file: file, line: line)
        return elapsed
    }

    @MainActor
    func testVisualAuditCorePages() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        let navigation = app.otherElements["workbenchTabs"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        assertInsideScreen(navigation, app: app)
        assertMinimumHitSize(app.buttons["uploadFAB"])
        keepScreenshot(app, name: "audit-home-top")

        app.buttons["homeMetricDocuments"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["documentsList"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-documents")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["tab.notes"].tap()
        let subsectionPicker = app.scrollViews["notesSubsectionPicker"]
        XCTAssertTrue(subsectionPicker.waitForExistence(timeout: 3))
        for identifier in [
            "notesSubsection.notes", "notesSubsection.units", "notesSubsection.search",
            "notesSubsection.homework", "notesSubsection.flashcards"
        ] {
            assertMinimumHitSize(app.buttons[identifier], width: 44, height: 44)
        }
        keepScreenshot(app, name: "audit-notes")

        app.buttons["notesSubsection.units"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["learningUnitsSection"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-units")

        app.buttons["notesSubsection.search"].tap()
        XCTAssertTrue(app.textFields["knowledgeQueryField"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-search")

        app.buttons["notesSubsection.homework"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeworkGradingSection"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-homework")

        app.buttons["notesSubsection.flashcards"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["flashcardsSection"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["flashcardCard"])
        let flashcardSubtitle = app.staticTexts["按复习优先级巩固知识点"]
        let flashcardUnitPicker = app.descendants(matching: .any)["flashcardLearningUnitPicker"]
        XCTAssertTrue(flashcardSubtitle.exists)
        XCTAssertTrue(flashcardUnitPicker.exists)
        XCTAssertLessThanOrEqual(flashcardSubtitle.frame.maxY, flashcardUnitPicker.frame.minY - 4)
        keepScreenshot(app, name: "audit-flashcards")

        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.textViews["openClawComposerTextView"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["chatHistoryButton"])
        assertMinimumHitSize(app.buttons["copyConversationButton"])
        assertMinimumHitSize(app.buttons["openClawAttachmentButton"])
        assertMinimumHitSize(app.buttons["openClawSendButton"])
        keepScreenshot(app, name: "audit-ai-chat")

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["profileEditButton"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["profileEditButton"])
        keepScreenshot(app, name: "audit-profile-top")
        let signOut = app.buttons["profileSignOut"]
        for _ in 0..<8 where signOut.frame.maxY > navigation.frame.minY - 20 {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, navigation.frame.minY - 20)
        keepScreenshot(app, name: "audit-profile-bottom")
    }

    @MainActor
    func testVisualAuditInteractiveLayers() throws {
        let app = makeApp([
            "-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage",
            "-NotePatchUITestConversations", "-NotePatchUITestPurgeFailure"
        ])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))

        app.buttons["homeActiveTask"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["taskScreen"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-task")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["uploadFAB"].tap()
        assertBecomesHittable(app.buttons["closeUploadScreenButton"])
        XCTAssertTrue(app.buttons["uploadQueueThumbnail"].waitForExistence(timeout: 3))
        let previewButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '预览 '")).firstMatch
        let removeButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '移除 '")).firstMatch
        assertMinimumHitSize(previewButton)
        assertMinimumHitSize(removeButton)
        keepScreenshot(app, name: "audit-upload-queue")
        app.buttons["uploadQueueThumbnail"].tap()
        XCTAssertTrue(app.buttons["imagePreviewCloseButton"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-local-image-preview")
        app.buttons["imagePreviewCloseButton"].tap()
        app.buttons["closeUploadScreenButton"].tap()

        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
        app.buttons["chatHistoryButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatConversationDrawer"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["chatNewConversationButton"])
        keepScreenshot(app, name: "audit-conversation-drawer")
        app.descendants(matching: .any)["chatConversationBackdrop"].tap()
        sleep(1)
        keepScreenshot(app, name: "audit-conversation-drawer-closed")

        let navigation = app.otherElements["workbenchTabs"]
        let navigationFrame = navigation.frame
        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.exists)
        XCTAssertTrue(editor.isEnabled)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(navigation.frame.minY, navigationFrame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(editor.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        keepScreenshot(app, name: "audit-ai-keyboard")
        dismissKeyboardForAudit(app, editor: editor)

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["profileEditButton"].waitForExistence(timeout: 3))
        app.buttons["profileEditButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profileEditSheet"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-profile-editor")
        app.buttons["取消"].tap()

        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.buttons["studyNoteRow-note-1"].waitForExistence(timeout: 3))
        app.buttons["studyNoteRow-note-1"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(app, name: "audit-note-reader")
        app.buttons["editStudyNoteButton"].tap()
        XCTAssertTrue(app.textFields["studyNoteEditorTitle"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-note-editor")
        app.buttons["取消"].tap()
    }

    @MainActor
    func testOfflinePrimaryInteractionsRemainResponsive() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))

        let destinations: [(String, XCUIElement)] = [
            ("tab.notes", app.scrollViews["notesSubsectionPicker"]),
            ("tab.ai", app.textViews["openClawComposerTextView"]),
            ("tab.me", app.buttons["profileEditButton"]),
            ("tab.home", app.descendants(matching: .any)["homeDashboard"])
        ]
        for _ in 0..<2 {
            for (tab, destination) in destinations {
                app.buttons[tab].tap()
                assertAppearsQuickly(destination)
            }
        }

        app.buttons["uploadFAB"].tap()
        assertAppearsQuickly(app.buttons["closeUploadScreenButton"])
        app.buttons["closeUploadScreenButton"].tap()
        XCTAssertFalse(app.buttons["closeUploadScreenButton"].isHittable)

        app.buttons["tab.ai"].tap()
        assertAppearsQuickly(app.buttons["chatHistoryButton"])
        app.buttons["chatHistoryButton"].tap()
        assertAppearsQuickly(app.descendants(matching: .any)["chatConversationDrawer"])
        app.descendants(matching: .any)["chatConversationBackdrop"].tap()
        assertAppearsQuickly(app.textViews["openClawComposerTextView"])
    }

    @MainActor
    func testUploadPreviewCloseDoesNotBlockTabSwitch() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))

        app.buttons["uploadFAB"].tap()
        assertBecomesHittable(app.buttons["closeUploadScreenButton"])
        app.buttons["uploadQueueThumbnail"].tap()
        XCTAssertTrue(app.buttons["imagePreviewCloseButton"].waitForExistence(timeout: 3))
        app.buttons["imagePreviewCloseButton"].tap()
        XCTAssertFalse(app.buttons["imagePreviewCloseButton"].exists)
        app.buttons["closeUploadScreenButton"].tap()
        XCTAssertFalse(app.buttons["closeUploadScreenButton"].isHittable)

        let uploadButton = app.buttons["uploadFAB"]
        XCTAssertTrue(uploadButton.isHittable)
        uploadButton.tap()
        assertBecomesHittable(app.buttons["closeUploadScreenButton"])
        app.buttons["closeUploadScreenButton"].tap()
        XCTAssertFalse(app.buttons["closeUploadScreenButton"].isHittable)

        let aiTab = app.buttons["tab.ai"]
        XCTAssertTrue(aiTab.isHittable)
        aiTab.tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFailedTaskPageDoesNotBlockTabSwitch() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPurgeFailure"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))

        app.buttons["homeActiveTask"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["taskScreen"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testScrolledContentDoesNotStealBottomNavigationTaps() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))

        app.swipeUp()
        let aiTab = app.buttons["tab.ai"]
        XCTAssertTrue(aiTab.isHittable)
        aiTab.tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testGlobalFeedbackPinsDismissesWithoutSwallowingTapAndCanBeDisabled() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackSuccess"])
        app.launch()

        let toast = app.descendants(matching: .any)["globalFeedbackToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["globalStatusDismissButton"].exists)
        toast.tap()
        sleep(6)
        XCTAssertTrue(toast.exists)

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.switches["globalFeedbackToggle"].waitForExistence(timeout: 3))
        XCTAssertFalse(toast.exists)
        app.switches["globalFeedbackToggle"].tap()
        XCTAssertEqual(app.switches["globalFeedbackToggle"].value as? String, "0")
    }

    @MainActor
    func testUploadErrorUsesRootFeedbackLayerAndBusyUsesTopBar() throws {
        let uploadApp = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackUploadError"])
        uploadApp.launch()
        assertBecomesHittable(uploadApp.buttons["closeUploadScreenButton"])
        XCTAssertTrue(uploadApp.descendants(matching: .any)["globalFeedbackToast"].waitForExistence(timeout: 3))
        uploadApp.terminate()

        let busyApp = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackBusy"])
        busyApp.launch()
        XCTAssertTrue(busyApp.descendants(matching: .any)["globalActivityBar"].waitForExistence(timeout: 3))
        XCTAssertFalse(busyApp.descendants(matching: .any)["globalFeedbackToast"].exists)
    }

    @MainActor
    func testConversationDrawerHeaderStaysBelowFullScreenSafeArea() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestConversations"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
        app.buttons["chatHistoryButton"].tap()

        let header = app.staticTexts["chatConversationDrawerHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(header.frame.minY, 50)
        let newConversation = app.buttons["chatNewConversationButton"]
        XCTAssertTrue(newConversation.exists)
        XCTAssertGreaterThanOrEqual(newConversation.frame.minY, 50)
        XCTAssertLessThanOrEqual(newConversation.frame.maxY, app.frame.maxY)
    }

    @MainActor
    func testConversationDrawerCloseRestoresComposerInteraction() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestConversations"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.buttons["chatHistoryButton"].waitForExistence(timeout: 3))
        app.buttons["chatHistoryButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatConversationDrawer"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["chatConversationBackdrop"].tap()
        sleep(1)

        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.exists)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
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
        assertBecomesHittable(app.buttons["closeUploadScreenButton"])
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

            let closeButton = app.buttons["closeUploadScreenButton"]
            assertBecomesHittable(closeButton, file: #filePath, line: #line)
            closeButton.tap()
            XCTAssertFalse(closeButton.isHittable, "Upload screen did not close on \(tabIdentifier)")
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
    func testOpenClawMessagesScrollToComposerBoundaryWithKeyboard() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat", "-NotePatchUITestKeyboardBoundary"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        let editor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let messages = app.scrollViews["openClawMessages"]
        XCTAssertTrue(messages.exists)
        XCTAssertLessThanOrEqual(messages.frame.maxY, editor.frame.minY + 1)
        let startY = min(messages.frame.maxY - 36, editor.frame.minY - 36) / app.frame.height
        let endY = max(messages.frame.minY + 36, messages.frame.midY - 80) / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            )
        XCTAssertLessThanOrEqual(messages.frame.maxY, editor.frame.minY + 1)
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
