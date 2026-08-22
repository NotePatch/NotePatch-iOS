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
        XCTAssertTrue(app.staticTexts["CPU pipeline diagram"].exists)
        app.buttons["documentMoreActions.remark-doc"].tap()
        XCTAssertTrue(app.buttons["editDocumentRemark.remark-doc"].waitForExistence(timeout: 2))
        app.buttons["editDocumentRemark.remark-doc"].tap()
        XCTAssertTrue(app.textFields["documentRemarkField"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["documentRemarkField"].value as? String, "CPU pipeline diagram")
        app.buttons["cancelDocumentRemarkButton"].tap()
        keepScreenshot(app, name: "audit-documents")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["tab.notes"].tap()
        let subsectionPicker = app.scrollViews["notesSubsectionPicker"]
        XCTAssertTrue(subsectionPicker.waitForExistence(timeout: 3))
        for identifier in [
            "notesSubsection.notes", "notesSubsection.search", "notesSubsection.homework",
            "notesSubsection.flashcards", "notesSubsection.units"
        ] {
            assertMinimumHitSize(app.buttons[identifier], width: 44, height: 44)
        }
        keepScreenshot(app, name: "audit-notes")

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

        app.buttons["notesSubsection.units"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["learningContentScroll"].waitForExistence(timeout: 3))
        keepScreenshot(app, name: "audit-units")

        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.textViews["openClawComposerTextView"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["chatHistoryButton"])
        XCTAssertTrue(app.staticTexts["openClawTab"].exists)
        XCTAssertFalse(app.buttons["copyConversationButton"].exists)
        XCTAssertFalse(app.staticTexts["Saved conversation"].exists)
        XCTAssertFalse(app.staticTexts["已保存的对话"].exists)
        XCTAssertFalse(app.staticTexts["首条消息后自动保存"].exists)
        assertMinimumHitSize(app.buttons["openClawAttachmentButton"])
        assertMinimumHitSize(app.buttons["openClawSendButton"])
        keepScreenshot(app, name: "audit-ai-chat")

        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.buttons["profileEditButton"].waitForExistence(timeout: 3))
        assertMinimumHitSize(app.buttons["profileEditButton"])
        keepScreenshot(app, name: "audit-profile-top")
        let autoImageRemarkToggle = app.switches["autoImageRemarkToggle"]
        for _ in 0..<5 where !autoImageRemarkToggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(autoImageRemarkToggle.exists)
        let signOut = app.buttons["profileSignOut"]
        for _ in 0..<8 where signOut.frame.maxY > navigation.frame.minY - 20 {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.isHittable)
        XCTAssertLessThanOrEqual(signOut.frame.maxY, navigation.frame.minY - 20)
        keepScreenshot(app, name: "audit-profile-bottom")
    }

    @MainActor
    func testOfflineAIOnboardingCompletesSevenStepsWithoutNetwork() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestAIOnboardingRequired"])
        app.launch()

        let onboarding = app.descendants(matching: .any)["aiOnboardingScreen"]
        XCTAssertTrue(onboarding.waitForExistence(timeout: 5))
        let continueButton = app.buttons["aiOnboardingContinueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        for _ in 0..<6 {
            XCTAssertTrue(continueButton.isEnabled)
            continueButton.tap()
        }
        let completeButton = app.buttons["aiOnboardingCompleteButton"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        XCTAssertTrue(completeButton.isEnabled)
        completeButton.tap()

        XCTAssertTrue(onboarding.waitForNonExistence(timeout: 3))
        app.buttons["tab.ai"].tap()
        XCTAssertTrue(app.textViews["openClawComposerTextView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["chatServerGreeting"].exists)
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
        let remarkButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'queuedUploadRemarkButton.'")
        ).firstMatch
        XCTAssertTrue(remarkButton.waitForExistence(timeout: 3))
        remarkButton.tap()
        let remarkField = app.textFields["documentRemarkField"]
        XCTAssertTrue(remarkField.waitForExistence(timeout: 3))
        remarkField.tap()
        remarkField.typeText("Chapter diagram")
        app.buttons["saveDocumentRemarkButton"].tap()
        XCTAssertTrue(remarkField.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Chapter diagram"].exists)
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
        let feedbackToggle = app.switches["globalFeedbackToggle"]
        XCTAssertTrue(feedbackToggle.waitForExistence(timeout: 3))
        keepScreenshot(app, name: "feedback-after-tab-dismiss")
        feedbackToggle.tap()
        XCTAssertEqual(feedbackToggle.value as? String, "0")
    }

    @MainActor
    func testUploadErrorUsesRootFeedbackLayerAndBusyUsesTopBar() throws {
        let uploadApp = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackUploadError"])
        uploadApp.launch()
        assertBecomesHittable(uploadApp.buttons["closeUploadScreenButton"])
        let toast = uploadApp.descendants(matching: .any)["globalFeedbackToast"]
        let toastText = uploadApp.staticTexts["Upload failed"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3) || toastText.waitForExistence(timeout: 3))
        uploadApp.terminate()

        let busyApp = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackBusy"])
        busyApp.launch()
        let activityBar = busyApp.descendants(matching: .any)["globalActivityBar"]
        XCTAssertTrue(activityBar.waitForExistence(timeout: 3))
        XCTAssertFalse(busyApp.descendants(matching: .any)["globalFeedbackToast"].exists)
        XCTAssertGreaterThanOrEqual(activityBar.frame.height, 2)
        XCTAssertLessThanOrEqual(activityBar.frame.height, 4)
        let statusBar = busyApp.statusBars.firstMatch
        if statusBar.exists {
            XCTAssertGreaterThanOrEqual(activityBar.frame.minY, statusBar.frame.maxY - 1)
            XCTAssertLessThanOrEqual(activityBar.frame.minY, statusBar.frame.maxY + 4)
        }
    }

    @MainActor
    func testBusyTopBarRespectsSafeArea() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFeedbackBusy"])
        app.launch()
        let activityBar = app.descendants(matching: .any)["globalActivityBar"]
        XCTAssertTrue(activityBar.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(activityBar.frame.height, 2)
        XCTAssertLessThanOrEqual(activityBar.frame.height, 4)
        XCTAssertGreaterThanOrEqual(activityBar.frame.minY, app.frame.minY)
        XCTAssertLessThan(activityBar.frame.maxY, app.frame.midY)
        let initialMinY = activityBar.frame.minY

        for tab in ["tab.notes", "tab.ai", "tab.me", "tab.home"] {
            app.buttons[tab].tap()
            XCTAssertTrue(activityBar.exists)
            XCTAssertEqual(activityBar.frame.minY, initialMinY, accuracy: 1)
        }

        app.buttons["uploadFAB"].tap()
        XCTAssertTrue(app.buttons["closeUploadScreenButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(activityBar.exists)
        XCTAssertEqual(activityBar.frame.minY, initialMinY, accuracy: 1)
        app.buttons["closeUploadScreenButton"].tap()

        let statusBar = app.statusBars.firstMatch
        if statusBar.exists {
            XCTAssertGreaterThanOrEqual(activityBar.frame.minY, statusBar.frame.maxY - 1)
            XCTAssertLessThanOrEqual(activityBar.frame.minY, statusBar.frame.maxY + 4)
        }
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
        let minimumSafeTop: CGFloat = app.frame.height <= 700 ? 20 : 50
        XCTAssertGreaterThanOrEqual(header.frame.minY, minimumSafeTop)
        let newConversation = app.buttons["chatNewConversationButton"]
        XCTAssertTrue(newConversation.exists)
        XCTAssertGreaterThanOrEqual(newConversation.frame.minY, minimumSafeTop)
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
    func testOfflineAIHeaderAndProfileEditingSurfaces() throws {
        let app = makeApp([
            "-NotePatchUITestWorkbench", "-NotePatchUITestLongChat", "-NotePatchUITestLongToast",
            "-NotePatchUITestConversations", "-NotePatchUITestLongConversationTitle"
        ])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        let initialTitle = app.staticTexts["openClawTab"]
        XCTAssertTrue(initialTitle.waitForExistence(timeout: 3))
        assertInsideScreen(initialTitle, app: app)
        XCTAssertFalse(app.buttons["copyConversationButton"].exists)
        XCTAssertFalse(app.staticTexts["Saved conversation"].exists)
        XCTAssertFalse(app.staticTexts["已保存的对话"].exists)
        XCTAssertTrue(app.buttons["openClawAttachmentButton"].exists)

        app.buttons["chatHistoryButton"].tap()
        let conversation = app.buttons["chatConversationRow.ui-conv-1"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 3))
        conversation.tap()
        let title = app.staticTexts["数学作业讲解与本周错题复习计划详细讨论"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        assertInsideScreen(title, app: app)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.buttons["chatHistoryButton"].frame.minX - 4)
        XCTAssertFalse(app.staticTexts["Saved conversation"].exists)
        XCTAssertFalse(app.staticTexts["已保存的对话"].exists)
        XCTAssertFalse(app.buttons["copyConversationButton"].exists)

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
    func testOpenClawBubbleLongPressSeparatesActionsFromTextSelection() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        let messages = app.scrollViews["openClawMessages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))

        let assistantBubble = app.descendants(matching: .any)["chatMessageBubble.ui-chat-1"]
        XCTAssertTrue(assistantBubble.waitForExistence(timeout: 3))
        assistantBubble.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["复制消息"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["选择文本"].exists)
        XCTAssertFalse(app.buttons["修改消息"].exists)
        keepScreenshot(app, name: "chat-assistant-whole-bubble-context-menu")
        app.tap()

        let userBubble = app.descendants(matching: .any)["chatMessageBubble.ui-chat-0"]
        XCTAssertTrue(userBubble.waitForExistence(timeout: 3))
        XCTAssertTrue(userBubble.isHittable)
        userBubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["复制消息"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["修改消息"].exists)
        XCTAssertTrue(app.buttons["选择文本"].exists)
        keepScreenshot(app, name: "chat-user-whole-bubble-context-menu")
        app.buttons["选择文本"].tap()
        XCTAssertTrue(app.otherElements["chatTextSelectionScreen"].waitForExistence(timeout: 3))
        let userSelection = app.textViews["chatSelectableFullScreenText"]
        XCTAssertTrue(userSelection.waitForExistence(timeout: 3))
        XCTAssertEqual(userSelection.value as? String, "Test prompt 0")
        userSelection.press(forDuration: 1.1)
        let nativeCopy = app.menuItems.matching(
            NSPredicate(format: "label IN %@", ["拷贝", "复制", "Copy"])
        ).firstMatch
        XCTAssertTrue(nativeCopy.waitForExistence(timeout: 2))
        keepScreenshot(app, name: "chat-user-full-screen-text-selection")
        app.tap()
        app.buttons["chatTextSelectionDoneButton"].tap()

        userBubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.1)
        let editAction = app.buttons["修改消息"]
        XCTAssertTrue(editAction.waitForExistence(timeout: 2))
        editAction.tap()
        let inlineEditor = app.textViews["openClawComposerTextView"]
        XCTAssertTrue(inlineEditor.waitForExistence(timeout: 3))
        XCTAssertEqual(inlineEditor.value as? String, "Test prompt 0")
        XCTAssertTrue(app.buttons["chatRevisionCancelButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chatMessageBubble.ui-chat-0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["chatMessageBubble.ui-chat-1"].exists)
        app.buttons["chatRevisionCancelButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatMessageBubble.ui-chat-1"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["chatRevisionCancelButton"].exists)

        XCTAssertFalse(app.buttons["chatCopyMessageButton.ui-chat-0"].exists)
        XCTAssertFalse(app.buttons["chatEditMessageButton.ui-chat-0"].exists)
        keepScreenshot(app, name: "chat-bubble-long-press-actions")
    }

    @MainActor
    func testOpenClawBubblesGrowFromTheirScreenEdgeUntilMaximumWidth() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestBubbleSizing"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()
        let messages = app.scrollViews["openClawMessages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))

        let shortUser = app.descendants(matching: .any)["chatMessageBubble.ui-sizing-user-short"]
        let shortAssistant = app.descendants(matching: .any)["chatMessageBubble.ui-sizing-assistant-short"]
        XCTAssertTrue(shortUser.waitForExistence(timeout: 3))
        XCTAssertTrue(shortAssistant.waitForExistence(timeout: 3))
        XCTAssertLessThan(shortUser.frame.width, 120)
        XCTAssertLessThan(shortAssistant.frame.width, 220)
        XCTAssertLessThanOrEqual(app.frame.maxX - shortUser.frame.maxX, 24)
        XCTAssertLessThanOrEqual(shortAssistant.frame.minX - app.frame.minX, 24)

        let longUser = app.descendants(matching: .any)["chatMessageBubble.ui-sizing-user-long"]
        let longAssistant = app.descendants(matching: .any)["chatMessageBubble.ui-sizing-assistant-long"]
        for _ in 0..<4 where !longUser.exists || !longAssistant.exists {
            messages.swipeUp()
        }
        XCTAssertTrue(longUser.waitForExistence(timeout: 3))
        XCTAssertTrue(longAssistant.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(longUser.frame.width, shortUser.frame.width + 120)
        XCTAssertGreaterThan(longAssistant.frame.width, shortAssistant.frame.width + 80)
        XCTAssertLessThanOrEqual(longUser.frame.width, 320.5)
        XCTAssertLessThanOrEqual(longAssistant.frame.width, 320.5)
        XCTAssertLessThanOrEqual(app.frame.maxX - longUser.frame.maxX, 24)
        XCTAssertLessThanOrEqual(longAssistant.frame.minX - app.frame.minX, 24)
        XCTAssertGreaterThan(app.staticTexts["Hi"].frame.minX, shortUser.frame.minX)
        keepScreenshot(app, name: "chat-bubble-content-sizing")
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
        let decreaseFontSize = app.buttons["studyNoteEditorFontSizeDecrease"]
        let fontSizeMenu = app.buttons["studyNoteEditorFontSizeMenu"]
        let increaseFontSize = app.buttons["studyNoteEditorFontSizeIncrease"]
        let boldButton = app.buttons["studyNoteEditorBold"]
        let italicButton = app.buttons["studyNoteEditorItalic"]
        XCTAssertTrue(decreaseFontSize.waitForExistence(timeout: 3))
        XCTAssertTrue(fontSizeMenu.exists)
        XCTAssertTrue(increaseFontSize.exists)
        XCTAssertTrue(boldButton.exists)
        XCTAssertTrue(italicButton.exists)
        assertMinimumHitSize(decreaseFontSize)
        assertMinimumHitSize(fontSizeMenu)
        assertMinimumHitSize(increaseFontSize)
        assertMinimumHitSize(boldButton)
        assertMinimumHitSize(italicButton)
        let previousFontSizeLabel = fontSizeMenu.label
        XCTAssertTrue(increaseFontSize.isEnabled)
        increaseFontSize.tap()
        XCTAssertNotEqual(fontSizeMenu.label, previousFontSizeLabel)
        boldButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["studyNoteEditorHTML"].exists)
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

        let unitPicker = app.buttons["flashcardLearningUnitPicker"]
        XCTAssertTrue(unitPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(unitPicker.isHittable)
        unitPicker.tap()
        XCTAssertTrue(app.buttons["Linear Equations"].waitForExistence(timeout: 2))
        app.buttons["Fractions & Ratios"].tap()

        let deckPicker = app.buttons["flashcardDeckPicker"]
        XCTAssertTrue(deckPicker.waitForExistence(timeout: 2))
        XCTAssertTrue(deckPicker.isHittable)
        deckPicker.tap()
        XCTAssertTrue(app.buttons["第 1 版牌组"].waitForExistence(timeout: 2))
        app.buttons["第 1 版牌组"].tap()

        let card = app.buttons["flashcardCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        let reviewHint = app.descendants(matching: .any)["flashcardReviewHint"]
        XCTAssertTrue(reviewHint.waitForExistence(timeout: 3))
        XCTAssertTrue(reviewHint.label.contains("近 30 天错了 3 次"))
        XCTAssertTrue(app.staticTexts["What does a ratio compare?"].exists)
        XCTAssertFalse(app.staticTexts["What does a **ratio** compare?"].exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["The relationship between two quantities."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["The relationship between **two quantities**."].exists)
        let learningScroll = app.scrollViews["learningContentScroll"]
        let nextButton = app.buttons["flashcardNextButton"]
        learningScroll.swipeUp()
        XCTAssertTrue(nextButton.isHittable)
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["How do you solve a proportion?"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOfflineHomeworkShowsLatestResultAndExpandableHistory() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notesSubsectionPicker"].waitForExistence(timeout: 3))
        app.buttons["notesSubsection.homework"].tap()

        let learningScroll = app.scrollViews["learningContentScroll"]
        let latestResult = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "92 / 100")
        ).element(boundBy: 0)
        for _ in 0..<5 where !latestResult.exists {
            learningScroll.swipeUp()
        }
        XCTAssertTrue(latestResult.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["92 / 100"].exists)
        XCTAssertTrue(app.staticTexts["正式评分"].exists)

        let history = app.descendants(matching: .any)["gradingHistoryDisclosure"]
        XCTAssertTrue(history.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["gradingHistoryResult.grading-result-1"].exists)
        for _ in 0..<6 where !history.isHittable {
            learningScroll.swipeUp()
        }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let priorResult = app.descendants(matching: .any)["gradingHistoryResult.grading-result-1"]
        for _ in 0..<3 where !priorResult.exists {
            learningScroll.swipeUp()
        }
        XCTAssertTrue(priorResult.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["诊断性评分"].exists)
        keepScreenshot(app, name: "homework-grading-results")
    }

    @MainActor
    func testHomeworkScrollPositionSurvivesTaskProgressUpdates() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestHomeworkTaskUpdates"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.notes"].tap()
        app.buttons["notesSubsection.homework"].tap()

        let learningScroll = app.scrollViews["learningContentScroll"]
        let gradeButton = app.buttons["gradeHomeworkButton"]
        for _ in 0..<6 where !gradeButton.exists || !gradeButton.isHittable {
            learningScroll.swipeUp()
        }
        XCTAssertTrue(gradeButton.waitForExistence(timeout: 3))
        let originalY = gradeButton.frame.minY
        Thread.sleep(forTimeInterval: 2.4)
        XCTAssertEqual(gradeButton.frame.minY, originalY, accuracy: 3)
        for _ in 0..<5 where !app.staticTexts["作业评分"].isHittable {
            learningScroll.swipeDown()
        }
        XCTAssertTrue(app.staticTexts["作业评分"].isHittable)
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
    func testUploadOptionsRemainCompleteOnSmallScreen() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["uploadFAB"].tap()
        assertBecomesHittable(app.buttons["closeUploadScreenButton"])

        let kinds = [
            "homework", "corrected_homework", "courseware", "note",
            "exam", "answer_key", "rubric", "other"
        ]
        for kind in kinds {
            let button = app.buttons["uploadKind.\(kind)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing upload kind: \(kind)")
            XCTAssertTrue(button.isHittable, "Upload kind is clipped: \(kind)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 48)
        }
        XCTAssertEqual(app.buttons["uploadKind.corrected_homework"].label, "已批改作业")

        for identifier in ["uploadSource.camera", "uploadSource.photos", "uploadSource.file"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }

        let filename = app.staticTexts["queuedUploadFilename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(filename.frame.width, 120)
        keepScreenshot(app, name: "upload-options-small-screen")

        let disclosure = app.buttons["uploadLearningInfoDisclosure"]
        if disclosure.exists {
            disclosure.tap()
        } else {
            app.staticTexts["学习信息"].tap()
        }
        let gradeLabel = app.staticTexts["年级"]
        let topicLabel = app.staticTexts["主题"]
        for _ in 0..<5 where !gradeLabel.isHittable || !topicLabel.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(gradeLabel.exists)
        XCTAssertTrue(topicLabel.exists)
        keepScreenshot(app, name: "upload-learning-fields-small-screen")
    }

    @MainActor
    func testExtendedLearningFileRequiresConversionConfirmation() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestExtendedLearningConflict"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["uploadFAB"].tap()
        let uploadButton = app.buttons["uploadSelectedQueueButton"]
        XCTAssertTrue(uploadButton.waitForExistence(timeout: 3))
        for _ in 0..<5 where !uploadButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(uploadButton.isHittable)
        uploadButton.tap()

        XCTAssertTrue(app.alerts["文件格式不适用于学习处理"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["改为其他并上传"].exists)
        app.buttons["取消"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["workbook.xlsx"].exists)
    }

    @MainActor
    func testLongestUploadKindFitsInAllSupportedLanguages() throws {
        let expectations = [
            ("simplifiedChinese", "已批改作业"),
            ("traditionalChinese", "已批改作業"),
            ("english", "Graded Work")
        ]

        for (language, expectedLabel) in expectations {
            let app = makeApp(["-NotePatchUITestWorkbench"], language: language)
            app.launch()
            XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
            app.buttons["uploadFAB"].tap()
            assertBecomesHittable(app.buttons["closeUploadScreenButton"])

            let correctedHomework = app.buttons["uploadKind.corrected_homework"]
            XCTAssertTrue(correctedHomework.waitForExistence(timeout: 3))
            XCTAssertEqual(correctedHomework.label, expectedLabel)
            XCTAssertGreaterThanOrEqual(correctedHomework.frame.height, 48)
            XCTAssertTrue(correctedHomework.isHittable)
            keepScreenshot(app, name: "upload-options-\(language)")
            app.terminate()
        }
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
    func testOpenClawScrollToBottomButtonTracksBottomAnchor() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestLongChat"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        let messages = app.scrollViews["openClawMessages"]
        let scrollToBottom = app.buttons["chatScrollToBottomButton"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToBottom.waitForExistence(timeout: 3))

        scrollToBottom.tap()
        let hiddenAtBottom = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: scrollToBottom
        )
        wait(for: [hiddenAtBottom], timeout: 3)

        let dragStart = messages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let dragEnd = messages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        XCTAssertTrue(scrollToBottom.waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenClawUsesFullMarkdownRenderer() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestFullMarkdown"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        let messages = app.scrollViews["openClawMessages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Full Markdown"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Completed task"].exists)
        XCTAssertTrue(app.staticTexts["Alice"].exists)
        XCTAssertTrue(app.staticTexts["98"].exists)
        XCTAssertTrue(app.staticTexts["let value = 42\nprint(value)"].exists)
        let copyCode = app.buttons["markdownCodeCopyButton"]
        for _ in 0..<14 where !copyCode.exists || !copyCode.isHittable {
            messages.swipeUp()
        }
        XCTAssertTrue(copyCode.waitForExistence(timeout: 3))
        XCTAssertTrue(copyCode.isHittable)
        copyCode.tap()
        XCTAssertTrue(app.buttons["markdownCodeCopyButton"].label.contains("已复制"))
        let markdownBubble = app.descendants(matching: .any)["chatMessageBubble.ui-full-markdown"]
        XCTAssertTrue(markdownBubble.waitForExistence(timeout: 3))
        markdownBubble.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["选择文本"].waitForExistence(timeout: 2))
        app.buttons["选择文本"].tap()
        let selectionView = app.textViews["chatSelectableFullScreenText"]
        XCTAssertTrue(selectionView.waitForExistence(timeout: 3))
        XCTAssertTrue((selectionView.value as? String)?.contains("Final heading") == true)
        app.buttons["chatTextSelectionDoneButton"].tap()
        keepScreenshot(app, name: "full-markdown-renderer")
    }

    @MainActor
    func testOpenClawReasoningIsOptionalAndSeparatedFromAnswer() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestReasoningStates"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        let messages = app.scrollViews["openClawMessages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["包含思考摘要的最终回答。"].waitForExistence(timeout: 3))
        let reasoningDisclosure = app.descendants(matching: .any)["chatReasoningDisclosure.ui-reasoning-present"]
        XCTAssertTrue(reasoningDisclosure.exists)
        XCTAssertFalse(app.descendants(matching: .any)["chatReasoningDisclosure.ui-reasoning-absent"].exists)
        XCTAssertFalse(app.staticTexts["回答完成"].exists)
        reasoningDisclosure.tap()
        let reasoningText = app.staticTexts["先确认问题，再组织最终答案。"]
        XCTAssertTrue(reasoningText.waitForExistence(timeout: 2))
        reasoningText.press(forDuration: 1.1)
        XCTAssertFalse(app.buttons["修改消息"].exists)
        app.tap()

        for _ in 0..<3 where !app.staticTexts["模型未提供摘要时的最终回答。"].exists {
            messages.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["模型未提供摘要时的最终回答。"].waitForExistence(timeout: 3))
        let unavailableDisclosure = app.descendants(matching: .any)["chatReasoningDisclosure.ui-reasoning-unavailable"]
        XCTAssertTrue(unavailableDisclosure.exists)
        unavailableDisclosure.tap()
        XCTAssertTrue(app.staticTexts["该模型本次没有提供思考摘要。"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testChatPDFAttachmentUsesRemarkAndOpensQuickLook() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestChatPDFAttachment"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["tab.ai"].tap()

        XCTAssertTrue(app.staticTexts["NFC 芯片研究资料"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["NFC_.pdf"].exists)
        let attachment = app.buttons["chatAttachmentPreview.ui-pdf"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 3))
        keepScreenshot(app, name: "chat-pdf-remark-bubble")
        attachment.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLookPreview"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "chat-pdf-remark-preview")
    }

    @MainActor
    func testCompactUploadLayoutKeepsQueueActionsVisible() throws {
        let app = makeApp(["-NotePatchUITestWorkbench", "-NotePatchUITestPendingImage"])
        app.launch()
        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        app.buttons["uploadFAB"].tap()
        let uploadTitle = app.descendants(matching: .any)["uploadScreen"]
        XCTAssertTrue(uploadTitle.waitForExistence(timeout: 3))
        assertInsideScreen(uploadTitle, app: app)
        assertInsideScreen(app.buttons["closeUploadScreenButton"], app: app)

        let homework = app.buttons["uploadKind.homework"]
        let corrected = app.buttons["uploadKind.corrected_homework"]
        let courseware = app.buttons["uploadKind.courseware"]
        XCTAssertTrue(homework.exists && corrected.exists && courseware.exists)
        XCTAssertEqual(homework.frame.minY, corrected.frame.minY, accuracy: 1)
        XCTAssertEqual(homework.frame.minY, courseware.frame.minY, accuracy: 1)

        for identifier in ["uploadSource.camera", "uploadSource.photos", "uploadSource.file"] {
            assertInsideScreen(app.buttons[identifier], app: app)
        }
        for identifier in ["queuedUploadPreviewButton", "queuedUploadRemoveButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            assertInsideScreen(button, app: app)
            assertMinimumHitSize(button)
        }
        let remarkButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'queuedUploadRemarkButton.'")
        ).firstMatch
        XCTAssertTrue(remarkButton.waitForExistence(timeout: 3))
        assertInsideScreen(remarkButton, app: app)
        assertMinimumHitSize(remarkButton)
        keepScreenshot(app, name: "compact-upload-layout")
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
    func testLatestLearningWorkflowNoteSetAndGapControlsAreReachable() throws {
        let app = makeApp(["-NotePatchUITestWorkbench"])
        app.launch()

        XCTAssertTrue(app.otherElements["workbenchTabs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeActiveWorkflow"].waitForExistence(timeout: 3))
        app.buttons["homeActiveWorkflow"].tap()
        XCTAssertTrue(app.staticTexts["学习工作流"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["uploadFAB"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["uploadScreen"].waitForExistence(timeout: 3))
        app.buttons["uploadKind.note"].tap()
        let continuousToggle = app.switches["continuousNoteToggle"]
        XCTAssertTrue(continuousToggle.waitForExistence(timeout: 3))
        continuousToggle.tap()
        XCTAssertTrue(app.textFields["continuousNoteTitleField"].waitForExistence(timeout: 3))
        app.buttons["closeUploadScreenButton"].tap()

        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.buttons["noteGapsButton.unit-1"].waitForExistence(timeout: 3))
        app.buttons["noteGapsButton.unit-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteGapRow.gap-pending"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()

        app.buttons["tab.me"].tap()
        let preferencePicker = app.descendants(matching: .any)["noteContentPreferencePicker"]
        for _ in 0..<6 where !preferencePicker.isHittable { app.swipeUp() }
        XCTAssertTrue(preferencePicker.exists)
        XCTAssertTrue(app.descendants(matching: .any)["saveNotePreferencesButton"].exists)
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
