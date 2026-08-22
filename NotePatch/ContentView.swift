import PhotosUI
import QuickLook
import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers
import UIKit

private let workbenchContentBottomPadding: CGFloat = 24

private struct WorkbenchBottomObstructionKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var workbenchBottomObstruction: CGFloat {
        get { self[WorkbenchBottomObstructionKey.self] }
        set { self[WorkbenchBottomObstructionKey.self] = newValue }
    }
}

private struct WorkbenchBottomBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

private struct WorkbenchContentBottomPaddingModifier: ViewModifier {
    @Environment(\.workbenchBottomObstruction) private var obstruction

    func body(content: Content) -> some View {
        content.padding(.bottom, workbenchContentBottomPadding + obstruction)
    }
}

private extension View {
    func workbenchContentBottomPadding() -> some View {
        modifier(WorkbenchContentBottomPaddingModifier())
    }
}

struct ContentView: View {
    @StateObject private var model = NotePatchViewModel()
    @StateObject private var feedbackPresentation: AppFeedbackPresentationState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isFeedbackUITest = arguments.contains {
            $0.hasPrefix("-NotePatchUITestFeedback")
        }
        let isUploadErrorUITest = arguments.contains("-NotePatchUITestFeedbackUploadError")
        let usesLongUITestToast = arguments.contains("-NotePatchUITestLongToast")
        let dismissNanoseconds: UInt64
        if isUploadErrorUITest {
            dismissNanoseconds = 15_000_000_000
        } else if isFeedbackUITest {
            dismissNanoseconds = 8_000_000_000
        } else {
            dismissNanoseconds = usesLongUITestToast ? 5_000_000_000 : 2_000_000_000
        }
        _feedbackPresentation = StateObject(
            wrappedValue: AppFeedbackPresentationState(
                autoDismissNanoseconds: dismissNanoseconds
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AuthenticationGate(
                    model: model,
                    session: model.session
                )
                .equatable()

                AppFeedbackOverlay(
                    model: model,
                    profileState: model.userProfileState,
                    navigationState: model.workbenchNavigationState,
                    presentation: feedbackPresentation,
                    containerSize: geometry.size,
                    safeAreaInsets: geometry.safeAreaInsets
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .zIndex(100)
            }
            .coordinateSpace(name: AppFeedbackCoordinateSpace.name)
        }
        .task {
            await model.restoreIfNeeded()
            await model.installFeedbackUITestFixtureIfNeeded()
        }
        .onAppear {
            model.handleScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { newPhase in
            model.handleScenePhase(newPhase)
        }
        .sheet(item: $model.downloadedPreview) { preview in
            switch preview.previewKind(
                canQuickLookPreview: QLPreviewController.canPreview(preview.url as NSURL)
            ) {
            case .image:
                ImagePreview(url: preview.url)
            case .quickLook:
                QuickLookPreview(url: preview.url)
                    .accessibilityIdentifier("quickLookPreview")
            case .unsupported:
                UnsupportedFilePreview(preview: preview)
            }
        }
    }

}

private struct AuthenticationGate: View, Equatable {
    let model: NotePatchViewModel
    let session: SavedSession?

    @ViewBuilder
    var body: some View {
        if session == nil {
            AuthScreen(model: model)
        } else {
            WorkbenchScreen(
                model: model,
                navigationState: model.workbenchNavigationState,
                aiExperienceState: model.aiExperienceState
            )
        }
    }

    static func == (lhs: AuthenticationGate, rhs: AuthenticationGate) -> Bool {
        lhs.model === rhs.model && lhs.session == rhs.session
    }
}

// MARK: - Auth Screen

private struct AuthScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var appear = false

    var body: some View {
        ZStack {
            NPColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: NPSpacing.section) {
                    // Hero section
                    VStack(spacing: NPSpacing.item) {
                        NotePatchLogoImage(height: 78)
                            .scaleEffect(appear ? 1 : 0.80)
                            .opacity(appear ? 1 : 0)

                        VStack(spacing: NPSpacing.small) {
                            Text("NotePatch")
                                .npTitle()
                            Text(localized("auth.tagline"))
                                .npCaption()
                                .lineSpacing(2)
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)
                    }
                    .padding(.top, NPSpacing.xl)

                    // Form card
                    VStack(spacing: NPSpacing.item) {
                        VStack(spacing: 10) {
                            AuthField(title: "auth.api_address", systemImage: "network") {
                                TextField(localized("auth.api_placeholder"), text: $model.apiBaseURLText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .accessibilityIdentifier("apiAddressField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "auth.email", systemImage: "envelope") {
                                TextField(localized("auth.email_placeholder"), text: $model.emailText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.username)
                                    .accessibilityIdentifier("emailField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "auth.password", systemImage: "lock") {
                                SecureField(localized("auth.password_placeholder"), text: $model.passwordText)
                                    .textContentType(.password)
                                    .accessibilityIdentifier("passwordField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "auth.full_name", systemImage: "person") {
                                TextField(localized("auth.full_name_placeholder"), text: $model.fullNameText)
                                    .textContentType(.name)
                            }
                        }
                        .modifier(NPCardModifier())
                    }

                    // Login button
                    Button {
                        model.authenticate(register: false)
                    } label: {
                        HStack {
                            Spacer()
                            if model.isBusy {
                                ProgressView()
                                    .tint(NPColors.surface)
                            } else {
                                Label(localized("auth.sign_in"), systemImage: "arrow.right")
                                    .font(.body.weight(.semibold))
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("loginButton")

                    // Secondary buttons
                    HStack(spacing: NPSpacing.medium) {
                        Button {
                            model.authenticate(register: true)
                        } label: {
                            Label(localized("auth.create_account"), systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                        .disabled(model.isBusy)

                        Button {
                            model.checkAPIConnection()
                        } label: {
                            Label(localized("auth.test_connection"), systemImage: "wave.3.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                        .disabled(model.isBusy)
                    }

                    if !model.isGlobalFeedbackEnabled {
                        AuthInlineFeedback(
                            statusMessage: model.statusMessage,
                            errorMessage: model.errorMessage
                        )
                    }
                }
                .frame(maxWidth: 520)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.xxxl)
            }
        }
        .disabled(model.isBusy)
        .onAppear {
            withAnimation(.npCardEntry) { appear = true }
        }
    }
}

private struct AuthField<Field: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: NPSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NPColors.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized(title))
                    .npCaption()
                    .foregroundStyle(NPColors.textSecondary)
                field
                    .npBody()
            }
        }
        .frame(minHeight: 48)
    }
}

// MARK: - Workbench Screen

private struct WorkbenchScreen: View {
    let model: NotePatchViewModel
    @ObservedObject var navigationState: WorkbenchNavigationState
    @ObservedObject var aiExperienceState: AIExperienceState
    @State private var isUploadLayerMounted = false

    var body: some View {
        GeometryReader { geometry in
            workbenchLayout(
                containerHeight: geometry.size.height,
                topSafeAreaInset: geometry.safeAreaInsets.top,
                bottomSafeAreaInset: geometry.safeAreaInsets.bottom
            )
        }
        .modifier(WorkbenchKeyboardSafeAreaModifier(
            keepsBottomBarFixed: navigationState.selectedTab == .openClaw
        ))
        .fullScreenCover(isPresented: Binding(
            get: { aiExperienceState.isOnboardingPresented },
            set: { aiExperienceState.isOnboardingPresented = $0 }
        )) {
            AIOnboardingScreen(model: model, state: aiExperienceState)
                .interactiveDismissDisabled(true)
        }
    }

    private func workbenchLayout(
        containerHeight: CGFloat,
        topSafeAreaInset: CGFloat,
        bottomSafeAreaInset: CGFloat
    ) -> some View {
        let bottomObstruction = workbenchBottomObstruction(
            containerHeight: containerHeight,
            bottomBarFrame: navigationState.bottomBarFrame,
            isVisible: !navigationState.isBottomBarHiddenForKeyboard
        )

        return ZStack(alignment: .bottom) {
            selectedContent
                .environment(\.workbenchBottomObstruction, bottomObstruction)
                .background(NPColors.background, ignoresSafeAreaEdges: .all)
                .allowsHitTesting(!navigationState.isUploadPresented)

            KeyboardAwareWorkbenchBottomBar(
                selection: $navigationState.selectedTab,
                isKeyboardVisible: $navigationState.isBottomBarHiddenForKeyboard
            ) {
                navigationState.isUploadPresented = true
            } onSelection: { _ in
                model.dismissGlobalFeedback()
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(
                .bottom,
                workbenchBottomBarAdditionalPadding(safeAreaBottom: bottomSafeAreaInset)
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WorkbenchBottomBarFramePreferenceKey.self,
                        value: proxy.frame(in: .named("workbench"))
                    )
                }
            }
            .allowsHitTesting(!navigationState.isUploadPresented)
            .zIndex(10)

            if isUploadLayerMounted {
                UploadScreen(model: model, isPresented: $navigationState.isUploadPresented)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NPColors.background.ignoresSafeArea())
                    .opacity(navigationState.isUploadPresented ? 1 : 0)
                    .allowsHitTesting(navigationState.isUploadPresented)
                    .accessibilityHidden(!navigationState.isUploadPresented)
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "workbench")
        .onPreferenceChange(WorkbenchBottomBarFramePreferenceKey.self) { frame in
            guard !frame.isNull, frame != navigationState.bottomBarFrame else { return }
            navigationState.bottomBarFrame = frame
        }
        .onChange(of: navigationState.selectedTab) { newTab in
            AppFeedbackDismissalCenter.shared.dismiss()
            NotificationCenter.default.post(name: .notePatchDismissGlobalFeedback, object: nil)
            model.dismissGlobalFeedback()
            if newTab != .openClaw {
                dismissActiveKeyboard()
            }
            model.ensureContentForSelectedTabLoaded()
        }
        .onAppear {
            isUploadLayerMounted = navigationState.isUploadPresented
            model.ensureContentForSelectedTabLoaded()
        }
        .onChange(of: navigationState.isUploadPresented) { isPresented in
            if isPresented {
                isUploadLayerMounted = true
            } else {
                DispatchQueue.main.async {
                    guard !navigationState.isUploadPresented else { return }
                    isUploadLayerMounted = false
                }
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch navigationState.selectedTab {
        case .home:
            HomeTab(model: model, state: model.homeDashboardState)
        case .notes:
            NotesTab(model: model)
        case .openClaw:
            OpenClawChatTab(
                model: model,
                chatState: model.openClawState,
                composerState: model.openClawComposerState,
                aiExperienceState: model.aiExperienceState
            )
        case .profile:
            ProfileTab(model: model, profileState: model.userProfileState)
        }
    }

}

private struct KeyboardAwareWorkbenchBottomBar: View {
    @Binding var selection: WorkbenchTab
    @Binding var isKeyboardVisible: Bool
    let uploadAction: () -> Void
    let onSelection: (WorkbenchTab) -> Void

    var body: some View {
        WorkbenchBottomGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                WorkbenchBottomNavigation(selection: $selection, onSelection: onSelection)
                UploadActionButton(action: uploadAction)
            }
        }
        .opacity(isKeyboardVisible ? 0 : 1)
        .allowsHitTesting(!isKeyboardVisible)
        .accessibilityHidden(isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            updateKeyboardVisibility(from: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: selection) { newSelection in
            if newSelection != .openClaw {
                isKeyboardVisible = false
            }
        }
    }

    private func updateKeyboardVisibility(from notification: Notification) {
        guard selection == .openClaw,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            isKeyboardVisible = false
            return
        }
        isKeyboardVisible = frame.height > 0
    }
}

private struct WorkbenchKeyboardSafeAreaModifier: ViewModifier {
    let keepsBottomBarFixed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if keepsBottomBarFixed {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}

private struct WorkbenchBottomGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            WorkbenchBottomGlassGroup26(spacing: spacing, content: content)
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private struct WorkbenchBottomGlassGroup26<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

private struct WorkbenchBottomNavigation: View {
    @Binding var selection: WorkbenchTab
    let onSelection: (WorkbenchTab) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            navigationItems
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .nativeNavigationCapsuleChrome()
        } else {
            navigationItems
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(NPColors.surfaceHighlight.opacity(0.04))
                }
                .navigationCapsuleChrome()
        }
    }

    private var navigationItems: some View {
        HStack(spacing: 0) {
            ForEach(WorkbenchTab.allCases) { tab in
                Button {
                    AppFeedbackDismissalCenter.shared.dismiss()
                    NotificationCenter.default.post(name: .notePatchDismissGlobalFeedback, object: nil)
                    onSelection(tab)
                    withAnimation(.npInteractive) {
                        selection = tab
                    }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .notePatchDismissGlobalFeedback, object: nil)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? NPColors.brandDark : NPColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbenchTabs")
    }

}

private extension WorkbenchTab {
    var accessibilityIdentifier: String {
        switch self {
        case .home: return "tab.home"
        case .notes: return "tab.notes"
        case .openClaw: return "tab.ai"
        case .profile: return "tab.me"
        }
    }
}

// MARK: - Upload Action Button

private struct UploadActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            uploadLabel
        }
        .buttonStyle(UploadActionButtonStyle())
        .contentShape(Circle())
        .frame(width: 58, height: 58)
        .zIndex(1)
        .accessibilityLabel(localized("upload.title"))
        .accessibilityIdentifier("uploadFAB")
    }

    @ViewBuilder
    private var uploadLabel: some View {
        if #available(iOS 26.0, *) {
            uploadIcon
                .glassEffect(.regular.interactive(), in: Circle())
                .nativeNavigationCircleChrome()
        } else {
            uploadIcon
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(NPColors.surfaceHighlight.opacity(0.04))
                }
                .navigationCircleChrome()
        }
    }

    private var uploadIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 19, weight: .medium, design: .rounded))
            .foregroundStyle(NPColors.brand)
            .frame(width: 58, height: 58)
    }
}

private struct UploadActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private extension View {
    func nativeNavigationCapsuleChrome() -> some View {
        overlay {
            Capsule(style: .continuous)
                .stroke(NPColors.surfaceHighlight, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.03), radius: 32, x: 0, y: 8)
    }

    func nativeNavigationCircleChrome() -> some View {
        overlay {
            Circle()
                .stroke(NPColors.surfaceHighlight, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.03), radius: 32, x: 0, y: 8)
    }

    func navigationCapsuleChrome() -> some View {
        overlay {
            Capsule(style: .continuous)
                .fill(navigationTopHighlight)
                .allowsHitTesting(false)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(NPColors.surfaceHighlight, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.02), radius: 32, x: 0, y: 8)
    }

    func navigationCircleChrome() -> some View {
        overlay {
            Circle()
                .fill(navigationTopHighlight)
                .allowsHitTesting(false)
        }
        .overlay {
            Circle()
                .stroke(NPColors.surfaceHighlight, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.02), radius: 32, x: 0, y: 8)
    }

    private var navigationTopHighlight: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: NPColors.surfaceHighlight.opacity(0.65), location: 0),
                .init(color: NPColors.surfaceHighlight.opacity(0.08), location: 0.35),
                .init(color: .clear, location: 0.5),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Home Tab

private struct HomeTab: View {
    let model: NotePatchViewModel
    @ObservedObject var state: HomeDashboardState
    @State private var readerItem: StudyNoteListItem?

    var body: some View {
        NavigationView {
            ZStack {
                homeContent
                destinationLinks
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $readerItem) { _ in
            NavigationView {
                StudyNoteReader(model: model)
                    .onDisappear { model.closeStudyNoteReader() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(localized("common.done")) { readerItem = nil }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        .accessibilityIdentifier("homeDashboard")
    }

    private var homeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                CompactPageHeader(
                    title: localized("home.title"),
                    subtitle: currentWorkspaceName
                )

                summary

                if let task = state.activeTask, shouldPrioritizeTask(task) {
                    activeTask(task)
                } else if let workflow = state.activeWorkflow {
                    activeWorkflow(workflow)
                } else if let task = state.activeTask {
                    activeTask(task)
                }

                recentDocuments
                recentNotes
                reviewShortcuts
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .workbenchContentBottomPadding()
        }
        .refreshable {
            await refreshHomeContent()
        }
        .background(NPColors.background)
    }

    private func refreshHomeContent() async {
        model.refreshHomeDashboard()
        await Task.yield()
        while !Task.isCancelled,
              model.isBusy || state.isLoadingSupplementaryContent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            HomeMetric(
                value: String(state.documentCount),
                label: localized("home.metric.documents"),
                accessibilityIdentifier: "homeMetricDocuments"
            ) {
                model.selectedHomeDestination = .documents
            }
            Divider().frame(height: 34)
            HomeMetric(
                value: String(state.learningUnitCount),
                label: localized("home.metric.units"),
                accessibilityIdentifier: "homeMetricLearningUnits"
            ) {
                openReview(.units)
            }
            Divider().frame(height: 34)
            HomeMetric(
                value: String(state.homeworkCount),
                label: localized("home.metric.homeworks"),
                accessibilityIdentifier: "homeMetricHomeworks"
            ) {
                openReview(.homework)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeSummary")
    }

    private func activeTask(_ task: TaskItem) -> some View {
        Button {
            model.selectedHomeDestination = .tasks
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(localized("home.active_task"), systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(task.progress.clamped(to: 0...100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NPColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.textTertiary)
                }
                ProgressView(value: Double(task.progress.clamped(to: 0...100)), total: 100)
                    .tint(NPColors.brand)
            }
            .foregroundStyle(NPColors.textPrimary)
            .padding(12)
            .modifier(NPListItemModifier())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeActiveTask")
    }

    private func activeWorkflow(_ workflow: WorkflowRun) -> some View {
        Button {
            model.selectedHomeDestination = .tasks
            model.selectWorkflow(workflow.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(localized("workflow.recent"), systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(workflow.progress.clamped(to: 0...100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NPColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.textTertiary)
                }
                ProgressView(value: Double(workflow.progress.clamped(to: 0...100)), total: 100)
                    .tint(NPColors.brand)
                Text(workflowStatusLabel(workflow.status)).npCaption()
            }
            .foregroundStyle(NPColors.textPrimary)
            .padding(12)
            .modifier(NPListItemModifier())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeActiveWorkflow")
    }

    private func shouldPrioritizeTask(_ task: TaskItem) -> Bool {
        model.canRetryDocumentPurge
            || ["failed", "cancelled"].contains(task.status)
            || task.cancelRequestedAt != nil
    }

    private var recentDocuments: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(
                title: localized("home.recent_documents"),
                actionTitle: localized("common.view_all"),
                sectionAccessibilityIdentifier: "homeRecentDocuments",
                accessibilityIdentifier: "homeViewAllDocuments"
            ) {
                model.selectedHomeDestination = .documents
            }
            if state.recentDocuments.isEmpty {
                HomeInlineEmptyState(systemImage: "doc", text: localized("home.no_documents"))
            } else {
                ForEach(state.recentDocuments) { document in
                    Button {
                        if model.canDownloadDocument(document) {
                            model.downloadAndPreview(document)
                        } else {
                            model.selectedHomeDestination = .documents
                        }
                    } label: {
                        HomeDocumentRow(
                            document: document,
                            thumbnailCacheKey: model.documentThumbnailIdentifier(for: document),
                            loadThumbnail: {
                                await model.generateDocumentThumbnail(for: document, maxPixelSize: 144)
                            }
                        )
                        .equatable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeDocument-\(document.id)")
                }
            }
        }
    }

    private var recentNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(
                title: localized("home.recent_notes"),
                actionTitle: localized("common.view_all"),
                sectionAccessibilityIdentifier: "homeRecentNotes",
                accessibilityIdentifier: "homeViewAllNotes"
            ) {
                model.selectedTab = .notes
                model.selectedLearningSection = .notes
            }
            if state.isLoadingSupplementaryContent && state.recentNotes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(localized("home.loading_learning"))
                        .npCaption()
                }
                .frame(minHeight: 44)
            } else if let error = state.supplementaryError, state.recentNotes.isEmpty {
                Button(action: model.refreshHomeDashboard) {
                    Label(localizedFormat("home.learning_failed", error), systemImage: "arrow.clockwise")
                        .npCaption()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NPColors.destructive)
            } else if state.recentNotes.isEmpty {
                HomeInlineEmptyState(systemImage: "note.text", text: localized("home.no_notes"))
            } else {
                ForEach(state.recentNotes) { item in
                    Button {
                        model.openStudyNote(item)
                        readerItem = item
                    } label: {
                        HomeNoteRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeNote-\(item.id)")
                }
            }
        }
    }

    private var reviewShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("home.review"))
                .font(.headline)
                .accessibilityIdentifier("homeReviewShortcuts")
            HStack(spacing: 12) {
                HomeShortcut(
                    title: localized("review.section.units"),
                    systemImage: "square.stack.3d.up",
                    accessibilityIdentifier: "homeReviewUnits"
                ) {
                    openReview(.units)
                }
                HomeShortcut(
                    title: localized("review.section.flashcards"),
                    systemImage: "rectangle.on.rectangle.angled",
                    accessibilityIdentifier: "homeReviewFlashcards"
                ) {
                    openReview(.flashcards)
                }
            }
        }
    }

    private var destinationLinks: some View {
        Group {
            NavigationLink(
                destination: DocumentsTab(model: model),
                isActive: destinationBinding(.documents)
            ) { EmptyView() }
            NavigationLink(
                destination: TaskTab(model: model),
                isActive: destinationBinding(.tasks)
            ) { EmptyView() }
        }
        .hidden()
    }

    private var currentWorkspaceName: String {
        model.workspaces.first(where: { $0.id == model.selectedWorkspaceId })?.name
            ?? localized("workspace.personal")
    }

    private func destinationBinding(_ destination: HomeDestination) -> Binding<Bool> {
        Binding(
            get: { state.destination == destination },
            set: { isActive in
                if !isActive, state.destination == destination {
                    state.destination = nil
                }
            }
        )
    }

    private func openReview(_ section: LearningSection) {
        model.selectedLearningSection = section
        model.selectedTab = .notes
        model.ensureContentForSelectedTabLoaded()
    }
}

private struct CompactPageHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NPColors.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NPColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            CompactPageLogo()
        }
        .frame(minHeight: 56)
    }
}

private struct CompactPageLogo: View {
    var body: some View {
        NotePatchLogoImage(height: 48)
            .frame(width: 116, height: 72, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

private struct HomeMetric: View {
    let value: String
    let label: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NPColors.textPrimary)
                HStack(spacing: 3) {
                    Text(label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.caption)
                .foregroundStyle(NPColors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(NPMetricButtonStyle())
        .accessibilityLabel("\(label), \(value)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct NPMetricButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(NPColors.brandLight.opacity(configuration.isPressed ? 0.65 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.npInteractive, value: configuration.isPressed)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    let actionTitle: String
    let sectionAccessibilityIdentifier: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier(sectionAccessibilityIdentifier)
            Spacer()
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NPColors.brandDark)
                .frame(minHeight: 44)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct HomeDocumentRow: View, Equatable {
    let document: LearningDocumentItem
    let thumbnailCacheKey: String
    let loadThumbnail: () async -> UIImage?

    var body: some View {
        HStack(spacing: 12) {
            DocumentThumbnailView(
                document: document,
                cacheKey: thumbnailCacheKey,
                size: CGSize(width: 48, height: 48),
                load: loadThumbnail
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(document.displayRemark)
                    .font(.body.weight(.medium))
                    .foregroundStyle(NPColors.textPrimary)
                    .lineLimit(2)
                Text(documentMetadataSummary(document))
                    .font(.caption)
                    .foregroundStyle(NPColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            NPStatusChip(text: primaryDocumentStatus(document), variant: primaryDocumentStatusVariant(document))
        }
        .padding(12)
        .modifier(NPListItemModifier())
    }

    static func == (lhs: HomeDocumentRow, rhs: HomeDocumentRow) -> Bool {
        lhs.document == rhs.document && lhs.thumbnailCacheKey == rhs.thumbnailCacheKey
    }
}

private struct HomeNoteRow: View {
    let item: StudyNoteListItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(NPColors.brandDark)
                .frame(width: 40, height: 44)
                .background(NPColors.brandLight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.note.title.isEmpty ? localized("notes.default_title") : item.note.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(NPColors.textPrimary)
                    .lineLimit(2)
                Text(localizedFormat("home.note_metadata", item.learningUnit.title, String(item.note.versionNo)))
                    .font(.caption)
                    .foregroundStyle(NPColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NPColors.textTertiary)
        }
        .padding(12)
        .modifier(NPListItemModifier())
    }
}

private struct HomeShortcut: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(NPColors.brandDark)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NPColors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NPColors.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .modifier(NPListItemModifier())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct HomeInlineEmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(NPColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 12)
            .modifier(NPListItemModifier())
    }
}

// MARK: - Notes Tab

private struct NotesTab: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var readerItem: StudyNoteListItem?

    var body: some View {
        VStack(spacing: 0) {
            CompactPageHeader(
                title: localized("notes.title"),
                subtitle: nil
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            notesSubmenu

            Group {
                if model.selectedLearningSection == .notes {
                    notesOverview
                } else {
                    LearningTab(model: model) { item in
                        model.openStudyNote(item)
                        readerItem = item
                    }
                }
            }
            .refreshable {
                await refreshNotesContent()
            }
        }
        .sheet(item: $readerItem) { _ in
            NavigationView {
                StudyNoteReader(model: model)
                    .onDisappear { model.closeStudyNoteReader() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(localized("common.done")) {
                                readerItem = nil
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $model.isNoteGapPresented) {
            NoteGapsSheet(model: model)
        }
        .background(NPColors.background)
        .task {
            await NoteWebViewRuntime.shared.prewarmAfterInterfaceSettles()
        }
        .onChange(of: model.selectedLearningSection) { _ in
            model.ensureContentForSelectedTabLoaded()
        }
    }

    private var notesSubmenu: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LearningSection.allCases) { section in
                    Button {
                        model.selectedLearningSection = section
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(model.selectedLearningSection == section ? .semibold : .regular))
                            .foregroundStyle(model.selectedLearningSection == section ? NPColors.surfaceCard : NPColors.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(model.selectedLearningSection == section ? NPColors.brand : NPColors.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                    .animation(.npInteractive, value: model.selectedLearningSection)
                    .accessibilityAddTraits(model.selectedLearningSection == section ? .isSelected : [])
                    .accessibilityIdentifier("notesSubsection.\(section.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityIdentifier("notesSubsectionPicker")
    }

    private func refreshNotesContent() async {
        if model.selectedLearningSection == .notes {
            model.loadNotesOverview(allowOfflineNetwork: true)
        } else {
            model.loadLearningDashboard(allowOfflineNetwork: true)
        }
        await Task.yield()
        while !Task.isCancelled,
              model.isNotesLoading || model.isLearningLoading || model.isHomeworkLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private var notesOverview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.isNotesLoading && model.studyNoteGroups.isEmpty {
                    ProgressView(localized("notes.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if model.studyNoteGroups.isEmpty {
                    NPEmptyState(
                        systemImage: "note.text",
                        title: localized("notes.empty.title"),
                        message: localized("notes.empty.message")
                    )
                    .padding(.top, 56)
                } else {
                    ForEach(model.studyNoteGroups) { group in
                        VStack(alignment: .leading, spacing: NPSpacing.small) {
                            Text(group.learningUnit.title)
                                .npSubheading()
                            HStack(spacing: 6) {
                                Image(systemName: noteStateIcon(group.generationState))
                                Text(noteStateTitle(group.generationState))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(group.generationState == .generating ? NPColors.brand : NPColors.textSecondary)
                            let details = [group.learningUnit.subject, group.learningUnit.gradeLevel, group.learningUnit.topic]
                                .compactMap { $0?.isEmpty == false ? $0 : nil }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · "))
                                    .npCaption()
                            }
                            Button {
                                model.presentNoteGaps(for: group.learningUnit.id)
                            } label: {
                                Label(localized("note_gap.open"), systemImage: "lightbulb.max")
                            }
                            .buttonStyle(NPSecondaryButtonStyle())
                            .accessibilityIdentifier("noteGapsButton.\(group.learningUnit.id)")
                            if group.notes.isEmpty {
                                Text(noteStateMessage(group.generationState))
                                    .npCaption()
                                    .padding(.vertical, NPSpacing.small)
                            }
                            ForEach(group.notes) { item in
                                Button {
                                    model.openStudyNote(item)
                                    readerItem = item
                                } label: {
                                    HStack(spacing: NPSpacing.medium) {
                                        Image(systemName: "note.text")
                                            .npHeading()
                                            .foregroundStyle(NPColors.brand)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.note.title.isEmpty ? localized("notes.default_title") : item.note.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(NPColors.textPrimary)
                                                .lineLimit(2)
                                            Text(localizedFormat("note.version", String(item.note.versionNo)))
                                                .npCaption()
                                            Text(item.note.revisionOriginLabel)
                                                .npCaption()
                                            if let completionSummary = studyNoteCompletionSummary(item.note) {
                                                Text(completionSummary)
                                                    .npCaption()
                                                    .foregroundStyle(NPColors.brandDark)
                                                    .lineLimit(2)
                                            }
                                            if let summary = item.note.editSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                                                Text(summary)
                                                    .npCaption()
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: NPSpacing.small)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(NPColors.textSecondary.opacity(0.5))
                                    }
                                    .padding(12)
                                    .modifier(NPListItemModifier())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("studyNoteRow-\(item.note.id)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .workbenchContentBottomPadding()
        }
    }

    private func noteStateIcon(_ state: StudyNoteGenerationState) -> String {
        switch state {
        case .noKnowledge: return "tray"
        case .generating: return "hourglass"
        case .ready: return "checkmark.circle"
        case .unavailable: return "exclamationmark.circle"
        }
    }

    private func noteStateTitle(_ state: StudyNoteGenerationState) -> String {
        localized("note.generation.\(state.rawValue).title")
    }

    private func noteStateMessage(_ state: StudyNoteGenerationState) -> String {
        localized("note.generation.\(state.rawValue).message")
    }
}

// MARK: - Study Note Reader

private struct StudyNoteReader: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        Group {
            if let item = model.selectedStudyNoteItem {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.note.title.isEmpty ? localized("notes.default_title") : item.note.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(NPColors.textPrimary)
                        Text("\(item.learningUnit.title) · \(localizedFormat("note.version", String(item.note.versionNo)))")
                            .npBody()
                            .foregroundStyle(NPColors.textSecondary)
                        Text(item.note.revisionOriginLabel)
                            .npCaption()
                        Text("\(noteContentEditLevelLabel(item.note.contentEditLevel)) · \(noteLayoutEditLevelLabel(item.note.layoutEditLevel))")
                            .npCaption()
                        if let completionSummary = studyNoteCompletionSummary(item.note) {
                            Text(completionSummary)
                                .npCaption()
                                .foregroundStyle(NPColors.brandDark)
                        }
                        if let strategy = item.note.completionStrategy?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !strategy.isEmpty {
                            Text(localizedFormat("note.completion.strategy", strategy))
                                .npCaption()
                        }
                        if let revision = item.note.completionEvidenceRevision {
                            Text(localizedFormat("note.completion.evidence_revision", String(revision)))
                                .npCaption()
                        }
                        if let summary = item.note.editSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                            Text(summary)
                                .npCaption()
                        }
                    }
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.top, NPSpacing.item)
                    .padding(.bottom, NPSpacing.small)

                    Divider().overlay(NPColors.divider)

                    if model.isStudyNoteLoading {
                        ProgressView(localized("note.reader.loading"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let renderedURL = model.studyNoteRenderedURL {
                        SafeRenderedHTMLNoteView(
                            url: renderedURL,
                            onAuthorizationExpired: model.handleRenderedStudyNoteExpired,
                            onFailure: model.handleRenderedStudyNoteFailure
                        )
                        .accessibilityIdentifier("studyNoteRenderedHTMLReader")
                    } else if let html = model.studyNoteHTML {
                        SafeHTMLNoteView(html: html)
                            .accessibilityIdentifier("studyNoteHTMLReader")
                    } else if let error = model.studyNoteReaderError {
                        VStack(spacing: 14) {
                            NPEmptyState(
                                systemImage: "exclamationmark.triangle",
                                title: localized("note.reader.open_failed"),
                                message: error
                            )
                            Button(localized("common.retry")) {
                                model.openStudyNote(item)
                            }
                            .buttonStyle(NPSecondaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(NPSpacing.outer)
                    }
                }
                .accessibilityIdentifier("studyNoteReader")
                .navigationTitle(localized("note.reader.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if model.canEditSelectedStudyNote {
                            Button {
                                model.beginStudyNoteEditing()
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .disabled(model.isStudyNoteSaving)
                            .accessibilityLabel(localized("common.edit"))
                            .accessibilityIdentifier("editStudyNoteButton")
                        }
                        Menu {
                            Button {
                                model.presentNoteGaps(for: item.learningUnit.id)
                            } label: {
                                Label(localized("note_gap.open"), systemImage: "lightbulb.max")
                            }
                            Button {
                                model.loadStudyNoteCorrections()
                            } label: {
                                Label(localized("note.corrections"), systemImage: "checkmark.message")
                            }
                            if model.canEditSelectedStudyNote {
                                Button {
                                    model.beginStudyNoteEditing()
                                } label: {
                                    Label(localized("common.edit"), systemImage: "pencil")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(model.isStudyNoteSaving)
                        .accessibilityIdentifier("studyNoteMoreButton")
                    }
                }
            } else {
                NPEmptyState(
                    systemImage: "note.text",
                    title: localized("note.reader.closed.title"),
                    message: localized("note.reader.closed.message")
                )
                .padding(.horizontal, NPSpacing.outer)
                .accessibilityIdentifier("studyNoteReader")
            }
        }
        .sheet(isPresented: $model.isStudyNoteEditorPresented) {
            NavigationView {
                StudyNoteEditor(model: model)
                    .onDisappear { model.cancelStudyNoteEditing() }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $model.isNoteGapPresented) {
            NoteGapsSheet(model: model)
        }
        .sheet(isPresented: $model.isNoteCorrectionsPresented) {
            StudyNoteCorrectionsSheet(model: model)
        }
    }
}

private struct NoteGapsSheet: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var editorCommand: HTMLNoteCommand?
    @State private var editorCommandToken = 0
    @State private var selectedFontSize = HTMLNoteFontSize.defaultSize
    @State private var editorSnapshotRequestToken = 0
    @State private var isEditorSnapshotPending = false
    @State private var editorSnapshotError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
                    if model.isNoteGapLoading && model.noteGaps.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if let detail = model.selectedNoteGapDetail {
                        gapDetail(detail)
                    } else if model.noteGaps.isEmpty {
                        NPEmptyState(
                            systemImage: "lightbulb",
                            title: localized("note_gap.empty.title"),
                            message: localized("note_gap.empty.message")
                        )
                    } else {
                        ForEach(model.noteGaps) { gap in
                            Button {
                                if gap.status == "no_base_note" {
                                    model.toggleNoBaseGap(gap.id)
                                } else {
                                    model.selectNoteGap(gap)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: NPSpacing.small) {
                                    Image(systemName: gap.status == "no_base_note"
                                          ? (model.selectedNoBaseGapIds.contains(gap.id) ? "checkmark.circle.fill" : "circle")
                                          : "lightbulb.max")
                                        .foregroundStyle(NPColors.brand)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(gap.knowledgePointId).font(.body.weight(.medium)).lineLimit(2)
                                        Text(noteGapStatusLabel(gap.status)).npCaption()
                                        Text(localizedFormat("note_gap.coverage", String(format: "%.2f", gap.coverageScore)))
                                            .npCaption()
                                    }
                                    Spacer()
                                    if gap.status != "no_base_note" { Image(systemName: "chevron.right") }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(NPCardModifier())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("noteGapRow.\(gap.id)")
                        }
                        if !model.selectedNoBaseGapIds.isEmpty {
                            Button {
                                model.createNoteFromSelectedGaps()
                            } label: {
                                Label(
                                    localizedFormat("note_gap.create_note_count", String(model.selectedNoBaseGapIds.count)),
                                    systemImage: "note.text.badge.plus"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NPPrimaryButtonStyle())
                            .disabled(model.isNoteGapLoading)
                            .accessibilityIdentifier("createNoteFromGapsButton")
                        }
                    }
                }
                .padding(NPSpacing.outer)
            }
            .navigationTitle(localized("note_gap.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.selectedNoteGapDetail != nil {
                        Button(localized("common.back")) { model.selectedNoteGapDetail = nil }
                    } else {
                        Button(localized("common.done")) { model.isNoteGapPresented = false }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isNoteGapLoading { ProgressView() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func gapDetail(_ detail: NoteGapDetail) -> some View {
        VStack(alignment: .leading, spacing: NPSpacing.item) {
            NPSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.suggestion.knowledgePointId).npHeading()
                    NPStatusChip(text: noteGapStatusLabel(detail.suggestion.status), variant: noteGapStatusVariant(detail.suggestion.status))
                    Text(localizedFormat("note_gap.insert_position", localized("note_gap.position.\(model.noteGapInsertPosition)")))
                        .npCaption()
                    if detail.suggestion.targetAnchor != nil, model.studyNoteRenderedURL != nil {
                        Button {
                            model.jumpToSelectedGapAnchor()
                        } label: {
                            Label(localized("note_gap.show_location"), systemImage: "scope")
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                    }
                }
            }

            if !detail.suggestion.sourceRefs.isEmpty {
                Text(localized("note_gap.sources")).npSubheading()
                ForEach(Array(detail.suggestion.sourceRefs.enumerated()), id: \.offset) { _, reference in
                    HStack(alignment: .top, spacing: 8) {
                        Button { model.toggleGapSourceReference(reference) } label: {
                            Image(systemName: model.selectedGapSourceRefs.contains(reference) ? "checkmark.circle.fill" : "circle")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reference.excerpt.isEmpty ? localized("note_gap.source_no_excerpt") : reference.excerpt)
                                .npBody().lineLimit(4)
                            if let page = reference.pageIndex {
                                Text(localizedFormat("note_gap.page", String(page + 1))).npCaption()
                            }
                        }
                        Spacer(minLength: 4)
                        if reference.documentId != nil {
                            Button { model.previewGapSource(reference) } label: {
                                Image(systemName: "eye").frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(localized("common.preview"))
                        }
                    }
                    .modifier(NPCardModifier())
                }
            }

            if detail.suggestion.status == "pending" {
                LabeledField(title: "note_gap.instruction") {
                    TextEditor(text: $model.noteGapInstruction).frame(minHeight: 90)
                }
                Button(localized("note_gap.create_draft")) { model.createSelectedNoteGapDraft() }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isNoteGapLoading || model.selectedGapSourceRefs.isEmpty)
            }

            if !detail.drafts.isEmpty || detail.suggestion.status == "draft" {
                Text(localized("note_gap.draft")).npSubheading()
                if !model.noteGapDraftHTML.isEmpty {
                    DisclosureGroup(localized("common.preview")) {
                        SafeHTMLNoteView(html: model.noteGapDraftHTML)
                            .frame(minHeight: 240)
                            .padding(.top, 8)
                    }
                }
                gapEditorToolbar
                RichHTMLNoteEditor(
                    html: $model.noteGapDraftHTML,
                    selectedFontSize: $selectedFontSize,
                    command: editorCommand,
                    commandToken: editorCommandToken,
                    snapshotRequestToken: editorSnapshotRequestToken
                ) { html in
                    guard isEditorSnapshotPending, model.isNoteGapPresented else { return }
                    isEditorSnapshotPending = false
                    guard let html else {
                        editorSnapshotError = localized("note.editor.sync_failed")
                        return
                    }
                    editorSnapshotError = nil
                    model.noteGapDraftHTML = html
                    model.saveSelectedNoteGapDraft()
                }
                    .frame(minHeight: 300)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
                    .accessibilityIdentifier("noteGapDraftEditor")
                if let editorSnapshotError {
                    Text(editorSnapshotError)
                        .npCaption()
                        .foregroundStyle(NPColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker(localized("note_gap.position"), selection: $model.noteGapInsertPosition) {
                    ForEach(["before", "after", "inside"], id: \.self) { value in
                        Text(localized("note_gap.position.\(value)")).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    editorSnapshotError = nil
                    isEditorSnapshotPending = true
                    editorSnapshotRequestToken += 1
                } label: {
                    if isEditorSnapshotPending {
                        ProgressView()
                    } else {
                        Text(localized("common.save"))
                    }
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(isEditorSnapshotPending || model.isNoteGapLoading)
                LabeledField(title: "note_gap.feedback") {
                    TextEditor(text: $model.noteGapFeedback).frame(minHeight: 72)
                }
                Button(localized("note_gap.regenerate")) { model.regenerateSelectedNoteGapDraft() }
                    .buttonStyle(NPSecondaryButtonStyle())
                HStack {
                    Button(role: .destructive) { model.rejectSelectedNoteGap() } label: {
                        Text(localized("note_gap.reject")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    Button { model.acceptSelectedNoteGap() } label: {
                        Text(localized("note_gap.accept")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                }
            }

            if ["accepted", "rejected", "stale"].contains(detail.suggestion.status) {
                Text(localized("note_gap.read_only")).npCaption()
            }
        }
    }

    private var gapEditorToolbar: some View {
        RichTextEditorToolbar(
            selectedFontSize: $selectedFontSize,
            accessibilityPrefix: "noteGapEditor"
        ) { command in
            editorCommand = command
            editorCommandToken += 1
        }
    }
}

private struct StudyNoteCorrectionsSheet: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
                    if model.isStudyNoteCorrectionsLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if model.studyNoteCorrections.isEmpty {
                        NPEmptyState(
                            systemImage: "checkmark.message",
                            title: localized("note.corrections.empty.title"),
                            message: localized("note.corrections.empty.message")
                        )
                    } else {
                        ForEach(model.studyNoteCorrections) { correction in
                            NPSection {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(correction.correctionType).npSubheading()
                                    Text(localized("note.corrections.original")).npCaption()
                                    Text(correction.originalText).npBody()
                                    Text(localized("note.corrections.corrected")).npCaption()
                                    Text(correction.correctedText).npBody().foregroundStyle(NPColors.brandDark)
                                    if let reason = correction.reason { Text(reason).npCaption() }
                                    if let confidence = correction.confidence {
                                        Text(localizedFormat("note.corrections.confidence", String(format: "%.2f", confidence))).npCaption()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(NPSpacing.outer)
            }
            .navigationTitle(localized("note.corrections"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.done")) { model.isNoteCorrectionsPresented = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Study Note Editor

private struct StudyNoteEditor: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var editorCommand: HTMLNoteCommand?
    @State private var editorCommandToken = 0
    @State private var selectedFontSize = HTMLNoteFontSize.defaultSize
    @State private var editorSnapshotRequestToken = 0
    @State private var isEditorSnapshotPending = false
    @State private var editorSnapshotError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(title: localized("note.editor.title_field")) {
                    TextField(localized("note.editor.title_placeholder"), text: $model.studyNoteDraftTitle)
                        .accessibilityIdentifier("studyNoteEditorTitle")
                }

                richTextToolbar
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, NPSpacing.small)

            if model.isStudyNoteEditorLoading {
                ProgressView(localized("note.editor.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RichHTMLNoteEditor(
                    html: $model.studyNoteDraftHTML,
                    selectedFontSize: $selectedFontSize,
                    command: editorCommand,
                    commandToken: editorCommandToken,
                    snapshotRequestToken: editorSnapshotRequestToken
                ) { html in
                    guard isEditorSnapshotPending, model.isStudyNoteEditorPresented else { return }
                    isEditorSnapshotPending = false
                    guard let html else {
                        editorSnapshotError = localized("note.editor.sync_failed")
                        return
                    }
                    editorSnapshotError = nil
                    model.studyNoteDraftHTML = html
                    model.saveStudyNoteRevision()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NPColors.background)
                .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous)
                        .stroke(NPColors.border, lineWidth: 1)
                )
                .padding(.horizontal, NPSpacing.outer)
                .padding(.vertical, NPSpacing.small)
                .accessibilityIdentifier("studyNoteEditorHTML")
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledField(title: localized("note.editor.summary_field")) {
                    TextField(localized("note.editor.summary_placeholder"), text: $model.studyNoteDraftSummary)
                        .accessibilityIdentifier("studyNoteEditorSummary")
                }
                Text(localized("note.editor.summary_optional"))
                    .npCaption()
                Text("\(model.studyNoteDraftHTML.count) / 2,000,000")
                    .npCaption()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let error = editorSnapshotError ?? model.studyNoteEditorError {
                    Text(error)
                        .npBody()
                        .foregroundStyle(NPColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(NPColors.destructive.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                }
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.bottom, NPSpacing.small)
        }
        .navigationTitle(localized("note.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("common.cancel")) {
                    model.cancelStudyNoteEditing()
                }
                .disabled(model.isStudyNoteSaving || isEditorSnapshotPending)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    editorSnapshotError = nil
                    isEditorSnapshotPending = true
                    editorSnapshotRequestToken += 1
                } label: {
                    if model.isStudyNoteSaving || isEditorSnapshotPending {
                        ProgressView()
                    } else {
                        Text(localized("common.save"))
                    }
                }
                .disabled(model.isStudyNoteSaving || isEditorSnapshotPending || model.isStudyNoteEditorLoading)
                .accessibilityIdentifier("saveStudyNoteButton")
            }
        }
        .alert(localized("note.editor.conflict.title"), isPresented: $model.isStudyNoteConflictPending) {
            Button(localized("common.cancel"), role: .cancel) {
                model.isStudyNoteConflictPending = false
            }
            Button(localized("note.editor.conflict.continue")) {
                model.confirmStudyNoteConflictAndSave()
            }
        } message: {
            Text(localized("note.editor.conflict.message"))
        }
    }

    private var richTextToolbar: some View {
        RichTextEditorToolbar(
            selectedFontSize: $selectedFontSize,
            accessibilityPrefix: "studyNoteEditor"
        ) { command in
            editorCommand = command
            editorCommandToken += 1
        }
    }
}

private struct RichTextEditorToolbar: View {
    @Binding var selectedFontSize: Int
    let accessibilityPrefix: String
    let perform: (HTMLNoteCommand) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                commandButton(.undo, systemImage: "arrow.uturn.backward", label: "note.editor.undo", identifier: "undo")
                commandButton(.redo, systemImage: "arrow.uturn.forward", label: "note.editor.redo", identifier: "redo")
                Divider().frame(height: 24)
                fontSizeControls
                Divider().frame(height: 24)
                commandButton(.bold, systemImage: "bold", label: "note.editor.bold", identifier: "bold")
                commandButton(.italic, systemImage: "italic", label: "note.editor.italic", identifier: "italic")
                commandButton(.heading2, systemImage: "textformat.size", label: "note.editor.heading", identifier: "heading")
                commandButton(.unorderedList, systemImage: "list.bullet", label: "note.editor.bullet_list", identifier: "unorderedList")
                commandButton(.orderedList, systemImage: "list.number", label: "note.editor.numbered_list", identifier: "orderedList")
            }
        }
        .frame(height: 44)
    }

    private var fontSizeControls: some View {
        HStack(spacing: 0) {
            Button {
                guard let size = HTMLNoteFontSize.smaller(than: selectedFontSize) else { return }
                selectedFontSize = size
                perform(.fontSize(size))
            } label: {
                Text(localized("note.editor.font_size.decrease.short"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .disabled(HTMLNoteFontSize.smaller(than: selectedFontSize) == nil)
            .accessibilityLabel(localized("note.editor.font_size.decrease"))
            .accessibilityIdentifier("\(accessibilityPrefix)FontSizeDecrease")

            Menu {
                ForEach(HTMLNoteFontSize.presets, id: \.self) { size in
                    Button {
                        selectedFontSize = size
                        perform(.fontSize(size))
                    } label: {
                        if selectedFontSize == size {
                            Label(String(size), systemImage: "checkmark")
                        } else {
                            Text(String(size))
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(String(selectedFontSize))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .frame(minWidth: 58, minHeight: 44)
                .contentShape(Rectangle())
            }
            .frame(minWidth: 58, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(localizedFormat("note.editor.font_size.current", String(selectedFontSize)))
            .accessibilityIdentifier("\(accessibilityPrefix)FontSizeMenu")

            Button {
                guard let size = HTMLNoteFontSize.larger(than: selectedFontSize) else { return }
                selectedFontSize = size
                perform(.fontSize(size))
            } label: {
                Text(localized("note.editor.font_size.increase.short"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .disabled(HTMLNoteFontSize.larger(than: selectedFontSize) == nil)
            .accessibilityLabel(localized("note.editor.font_size.increase"))
            .accessibilityIdentifier("\(accessibilityPrefix)FontSizeIncrease")
        }
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous)
                .stroke(NPColors.border.opacity(0.7), lineWidth: 1)
        )
    }

    private func commandButton(
        _ command: HTMLNoteCommand,
        systemImage: String,
        label: String,
        identifier: String
    ) -> some View {
        Button {
            perform(command)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous))
        .accessibilityLabel(localized(label))
        .accessibilityIdentifier("\(accessibilityPrefix)\(identifier.prefix(1).uppercased())\(identifier.dropFirst())")
    }
}

// MARK: - Documents Tab

private struct DocumentsTab: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var filtersExpanded = false
    @State private var remarkDocument: LearningDocumentItem?
    @State private var remarkDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            documentList
        }
        .background(NPColors.background)
        .navigationTitle(localized("documents.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .sheet(item: $remarkDocument) { document in
            RemarkEditorSheet(
                title: localized("image_remark.edit.title"),
                text: $remarkDraft,
                originalFilename: document.originalFilename,
                allowsEmpty: false,
                isSaving: model.documentRemarkUpdatingId == document.id,
                onCancel: { remarkDocument = nil },
                onSave: {
                    model.updateDocumentRemark(document, remark: remarkDraft) {
                        remarkDocument = nil
                    }
                },
                onRestoreFilename: {
                    remarkDraft = document.originalFilename
                    model.updateDocumentRemark(document, remark: document.originalFilename) {
                        remarkDocument = nil
                    }
                }
            )
        }
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Filter
                HStack {
                    Button {
                        withAnimation(.npInteractive) { filtersExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 12, weight: .medium))
                            Text(activeFilterSummary(status: model.statusFilter, documentKind: model.documentKindFilter, fileType: model.fileTypeFilter))
                                .lineLimit(1)
                            Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NPColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(NPColors.surface)
                        .clipShape(Capsule())
                        .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("documentsList")
                    Spacer()
                }

                if filtersExpanded {
                    NPSection {
                        FilterPanel(model: model)
                    }
                }

                if model.documents.isEmpty {
                    NPEmptyState(
                        systemImage: "doc",
                        title: localized("documents.empty.title"),
                        message: localized("documents.empty.message")
                    )
                } else {
                    ForEach(model.documents) { document in
                        DocumentRow(
                            document: document,
                            artifacts: model.selectedArtifactDocumentId == document.id ? model.selectedArtifacts : [],
                            ocrArtifacts: model.selectedOcrDocumentId == document.id ? model.selectedOcrArtifacts : [],
                            isBusy: model.isBusy,
                            isPreviewLoading: model.isDocumentPreviewLoading(document.id),
                            canProcess: model.canProcessDocument(document),
                            canDownload: model.canDownloadDocument(document),
                            thumbnailCacheKey: model.documentThumbnailIdentifier(for: document),
                            loadThumbnail: {
                                await model.generateDocumentThumbnail(for: document, maxPixelSize: 176)
                            },
                            onDownload: { model.downloadAndPreview(document) },
                            onProcess: { model.startProcessing(document) },
                            onDelete: { model.deleteDocument(document) },
                            onWorkflow: { model.openWorkflow(for: document) },
                            onArtifacts: { model.loadArtifacts(for: document) },
                            onOCR: { model.loadOcrArtifacts(for: document) },
                            onEditRemark: {
                                remarkDraft = document.displayRemark
                                remarkDocument = document
                            },
                            onArtifactDownload: { model.downloadAndPreview($0) },
                            onOcrDownload: { model.downloadAndPreview($0) }
                        )
                        .equatable()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .workbenchContentBottomPadding()
        }
    }

}

// MARK: - Upload Screen (FAB entry point)

private struct UploadScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(localized("upload.title"))
                    .font(.headline)
                    .accessibilityIdentifier("uploadScreen")

                HStack {
                    Button(localized("common.close")) {
                        model.cancelLearningUploadFormatConversion()
                        isPresented = false
                    }
                    .accessibilityIdentifier("closeUploadScreenButton")

                    Spacer()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, NPSpacing.outer)
            .background(.ultraThinMaterial)

            Divider()

            UploadDocumentScreen(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NPColors.background)
    }
}

// MARK: - Upload Document Screen

private struct UploadDocumentScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var isShowingFileImporter = false
    @State private var queuedPreview: DownloadedPreview?
    @State private var isQueuedPreviewLayerMounted = false
    @State private var pickerUserId: String?
    @State private var pickerWorkspaceId: String?
    @State private var remarkQueueItem: QueuedUploadItem?
    @State private var remarkDraft = ""
    @State private var compactLayout = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: compactLayout ? 12 : NPSpacing.section) {
                    NPSection {
                        UploadPanel(
                            model: model,
                            compactLayout: compactLayout,
                            onCameraUpload: { isShowingCamera = true },
                            onGalleryUpload: {
                                capturePickerContext()
                                isShowingPhotoLibrary = true
                            },
                            onFileUpload: {
                                capturePickerContext()
                                isShowingFileImporter = true
                            }
                        )
                    }

                    NPSection {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(localized("upload.queue.pending"), systemImage: "tray.and.arrow.up")
                                    .npSubheading()
                                Spacer()
                                Text(localizedFormat("upload.items_count", String(model.queuedUploadItems.count)))
                                    .npCaption()
                            }

                            if model.queuedUploadItems.isEmpty {
                                NPEmptyState(
                                    systemImage: "tray",
                                    title: localized("upload.queue.empty.title"),
                                    message: localized("upload.queue.empty.message")
                                )
                            } else {
                                LazyVStack(spacing: 10) {
                                    ForEach(Array(model.queuedUploadItems.enumerated()), id: \.element.id) { index, item in
                                        QueuedUploadRow(
                                            item: item,
                                            isBusy: model.isBusy,
                                            pageNumber: model.isContinuousNoteUploadEnabled || model.activeNoteSet != nil ? index + 1 : nil,
                                            onToggle: { model.toggleQueuedUpload(item.id) },
                                            onPreview: {
                                                isQueuedPreviewLayerMounted = true
                                                queuedPreview = DownloadedPreview(
                                                    url: item.file.url,
                                                    mimeType: item.file.mimeType,
                                                    filename: item.file.filename,
                                                    fileSize: item.file.fileSize
                                                )
                                            },
                                            onRemove: { model.removeQueuedUpload(item.id) },
                                            onEditRemark: {
                                                remarkDraft = item.remark ?? ""
                                                remarkQueueItem = item
                                            },
                                            onMoveUp: { model.moveContinuousNotePage(item.id, direction: -1) },
                                            onMoveDown: { model.moveContinuousNotePage(item.id, direction: 1) }
                                        )
                                    }
                                }

                                Button {
                                    model.uploadSelectedQueuedFiles()
                                } label: {
                                    Label(localizedFormat("upload.selected_count", String(model.queuedUploadItems.filter(\.isSelected).count)), systemImage: "arrow.up.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(NPPrimaryButtonStyle())
                                .disabled(model.isBusy || !model.queuedUploadItems.contains(where: \.isSelected))
                                .accessibilityIdentifier("uploadSelectedQueueButton")
                            }
                        }
                    }
                }
                .padding(.horizontal, compactLayout ? 16 : NPSpacing.outer)
                .padding(.top, compactLayout ? 8 : 14)
                .padding(.bottom, compactLayout ? 16 : NPSpacing.section)
            }
            .allowsHitTesting(queuedPreview == nil)

            if isQueuedPreviewLayerMounted {
                UploadQueuedPreviewOverlay(preview: queuedPreview) {
                    self.queuedPreview = nil
                    DispatchQueue.main.async {
                        guard self.queuedPreview == nil else { return }
                        self.isQueuedPreviewLayerMounted = false
                    }
                }
                .opacity(queuedPreview == nil ? 0 : 1)
                .allowsHitTesting(queuedPreview != nil)
                .accessibilityHidden(queuedPreview == nil)
                .zIndex(10)
            }
        }
        .background(NPColors.background.ignoresSafeArea())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateCompactLayout(for: proxy.size) }
                    .onChange(of: proxy.size) { updateCompactLayout(for: $0) }
            }
        )
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.uploadPickedFiles(
                    from: urls,
                    expectedUserId: pickerUserId,
                    expectedWorkspaceId: pickerWorkspaceId
                )
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                model.uploadCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingPhotoLibrary) {
            PhotoLibraryPicker(cacheDirectory: model.uploadCacheDirectory) { result in
                isShowingPhotoLibrary = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    model.stageImportedUploadFiles(
                        files,
                        expectedUserId: pickerUserId,
                        expectedWorkspaceId: pickerWorkspaceId
                    )
                case .failure(let error):
                    if model.isCurrentImportContext(userId: pickerUserId, workspaceId: pickerWorkspaceId) {
                        model.presentError(error)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $remarkQueueItem) { item in
            RemarkEditorSheet(
                title: localized("image_remark.upload.title"),
                text: $remarkDraft,
                originalFilename: nil,
                allowsEmpty: true,
                isSaving: false,
                onCancel: { remarkQueueItem = nil },
                onSave: {
                    if model.updateQueuedUploadRemark(item.id, remark: remarkDraft) {
                        remarkQueueItem = nil
                    }
                },
                onRestoreFilename: nil
            )
        }
        .alert(
            localized("upload.format_conflict.title"),
            isPresented: $model.isLearningUploadFormatConfirmationPresented
        ) {
            Button(localized("common.cancel"), role: .cancel) {
                model.cancelLearningUploadFormatConversion()
            }
            Button(localized("upload.format_conflict.convert")) {
                model.confirmLearningUploadFormatConversion()
            }
        } message: {
            Text(localizedFormat(
                "upload.format_conflict.message",
                String(model.pendingLearningFormatConversionCount)
            ))
        }
    }

    private func capturePickerContext() {
        pickerUserId = model.session?.userId
        pickerWorkspaceId = model.selectedWorkspaceId
    }

    private func updateCompactLayout(for size: CGSize) {
        let shouldCompact = size.height <= 700 || size.width <= 350
        if compactLayout != shouldCompact {
            compactLayout = shouldCompact
        }
    }
}

private struct UploadQueuedPreviewOverlay: View {
    let preview: DownloadedPreview?
    let onClose: () -> Void

    @ViewBuilder
    var body: some View {
        if let preview {
            switch preview.previewKind(
                canQuickLookPreview: QLPreviewController.canPreview(preview.url as NSURL)
        ) {
        case .image:
            QueuedImagePreview(url: preview.url, onClose: onClose)
            case .quickLook:
                ZStack(alignment: .topTrailing) {
                    QuickLookPreview(url: preview.url)
                        .accessibilityIdentifier("quickLookPreview")
                        .ignoresSafeArea()
                    previewCloseButton
                }
                .background(NPColors.background.ignoresSafeArea())
            case .unsupported:
                UnsupportedFilePreview(preview: preview, onClose: onClose)
            }
        } else {
            Color.clear
        }
    }

    private var previewCloseButton: some View {
        Button(action: onClose) {
            Label(localized("common.close"), systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title)
                .foregroundStyle(NPColors.textPrimary)
                .padding(18)
        }
        .accessibilityIdentifier("imagePreviewCloseButton")
    }
}

private struct QueuedImagePreview: View {
    let url: URL
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnificationGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if scale > 1 {
                                scale = 1
                                baseScale = 1
                                offset = .zero
                                baseOffset = .zero
                            } else {
                                scale = 2.5
                                baseScale = 2.5
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            }

            Button(action: onClose) {
                Label(localized("common.close"), systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(Color.white)
                    .padding(18)
            }
            .accessibilityIdentifier("imagePreviewCloseButton")
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                downsampleUploadImage(at: url, maxPixelSize: 4096)
            }.value
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(5, max(1, baseScale * value))
            }
            .onEnded { _ in
                baseScale = scale
                if scale == 1 {
                    offset = .zero
                    baseOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }
}

private struct QueuedUploadRow: View {
    let item: QueuedUploadItem
    let isBusy: Bool
    let pageNumber: Int?
    let onToggle: () -> Void
    let onPreview: () -> Void
    let onRemove: () -> Void
    let onEditRemark: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                ZStack {
                    Color.clear
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .npHeading()
                        .foregroundStyle(item.isSelected ? NPColors.brand : NPColors.textSecondary)
                }
                .frame(width: 44, height: 44)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(localizedFormat(
                item.isSelected ? "accessibility.deselect_file" : "accessibility.select_file",
                item.file.filename
            ))

            UploadThumbnailView(file: item.file, onPreview: onPreview)
                .disabled(isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.file.filename)
                    .font(.body.weight(.medium))
                    .foregroundStyle(NPColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("queuedUploadFilename")
                Text("\(documentKindLabel(item.documentKind)) · \(formatBytes(item.file.fileSize))")
                    .npCaption()
                if let pageNumber {
                    Text(localizedFormat("note_set.page_number", String(pageNumber)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.brand)
                }
                queueStateView
                if let remark = item.remark, !remark.isEmpty {
                    Label(remark, systemImage: "text.bubble")
                        .npCaption()
                        .foregroundStyle(NPColors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if pageNumber != nil {
                        Button(action: onMoveUp) {
                            Image(systemName: "arrow.up").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .accessibilityLabel(localized("note_set.move_up"))
                        Button(action: onMoveDown) {
                            Image(systemName: "arrow.down").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .accessibilityLabel(localized("note_set.move_down"))
                    }
                    if item.file.isImage {
                        Button(action: onEditRemark) {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy || item.remoteState != nil)
                        .accessibilityLabel(localized("image_remark.edit.action"))
                        .accessibilityIdentifier("queuedUploadRemarkButton.\(item.id.uuidString)")
                    }
                    Button(action: onPreview) {
                        Image(systemName: "eye")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel(localizedFormat("accessibility.preview_file", item.file.filename))
                    .accessibilityIdentifier("queuedUploadPreviewButton")

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel(localizedFormat("accessibility.remove_file", item.file.filename))
                    .accessibilityIdentifier("queuedUploadRemoveButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(NPSpacing.small)
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                .stroke(NPColors.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var queueStateView: some View {
        switch item.state {
        case .pending:
            EmptyView()
        case .uploading:
            Label(localized("upload.queue.uploading"), systemImage: "arrow.up.circle")
                .npCaption()
                .foregroundStyle(NPColors.brand)
        case .uploaded:
            Label(localized("upload.queue.uploaded"), systemImage: "checkmark.circle.fill")
                .npCaption()
                .foregroundStyle(NPColors.successText)
        case .failed(let message):
            Text(message.resolved())
                .npCaption()
                .foregroundStyle(NPColors.destructive)
                .lineLimit(2)
        }
    }
}

private struct UploadPanel: View {
    @ObservedObject var model: NotePatchViewModel
    let compactLayout: Bool
    let onCameraUpload: () -> Void
    let onGalleryUpload: () -> Void
    let onFileUpload: () -> Void
    @State private var isLearningInfoExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 10 : 12) {
            SectionLabel(localized("upload.document_type"))

            ChoiceGrid(minimum: compactLayout ? 88 : 108) {
                ForEach(["homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric", "other"], id: \.self) { kind in
                    UploadKindButton(
                        title: documentKindLabel(kind),
                        selected: model.uploadDocumentKind == kind,
                        enabled: !model.isBusy
                    ) {
                        model.uploadDocumentKind = kind
                    }
                    .accessibilityIdentifier("uploadKind.\(kind)")
                }
            }

            HStack(spacing: NPSpacing.small) {
                UploadSourceButton(title: "upload.source.camera", systemImage: "camera.fill", accessibilityIdentifier: "uploadSource.camera", emphasized: true, compactLayout: compactLayout, enabled: !model.isBusy && UIImagePickerController.isSourceTypeAvailable(.camera), action: onCameraUpload)
                UploadSourceButton(title: "upload.source.photos", systemImage: "photo.on.rectangle", accessibilityIdentifier: "uploadSource.photos", emphasized: false, compactLayout: compactLayout, enabled: !model.isBusy, action: onGalleryUpload)
                UploadSourceButton(title: "upload.source.file", systemImage: "folder", accessibilityIdentifier: "uploadSource.file", emphasized: false, compactLayout: compactLayout, enabled: !model.isBusy, action: onFileUpload)
            }

            if let progress = model.uploadProgressPercent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.uploadProgressLabel)
                        Spacer()
                        Text("\(progress)%")
                            .monospacedDigit()
                    }
                    .npCaption()
                    ProgressView(value: Double(progress), total: 100)
                }
                .padding(.top, 2)
            }

            DisclosureGroup(localized("upload.learning_info"), isExpanded: $isLearningInfoExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(localized("upload.learning_unit"), selection: $model.uploadLearningUnitId) {
                        Text(localized("upload.learning_unit_auto")).tag("")
                        ForEach(model.learningUnits) { unit in
                            Text(unit.title).tag(unit.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("uploadLearningUnitPicker")
                    if model.uploadLearningUnitId.isEmpty {
                        LabeledField(title: "upload.unit_title") {
                            TextField(localized("upload.unit_title_placeholder"), text: $model.uploadLearningUnitTitle)
                                .accessibilityIdentifier("uploadLearningUnitTitleField")
                        }
                    }
                    LabeledField(title: "upload.subject") {
                        TextField(localized("upload.subject_placeholder"), text: $model.uploadSubject)
                            .accessibilityIdentifier("uploadSubjectField")
                    }
                    VStack(spacing: 10) {
                        LabeledField(title: "upload.grade") {
                            TextField(localized("upload.grade_placeholder"), text: $model.uploadGradeLevel)
                                .accessibilityIdentifier("uploadGradeField")
                        }
                        LabeledField(title: "upload.topic") {
                            TextField(localized("upload.topic_placeholder"), text: $model.uploadTopic)
                                .accessibilityIdentifier("uploadTopicField")
                        }
                    }
                }
                .padding(.top, NPSpacing.small)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(NPColors.textPrimary)
            .accessibilityIdentifier("uploadLearningInfoDisclosure")

            if model.uploadDocumentKind == "note" {
                Divider()
                Toggle(localized("note_set.toggle"), isOn: $model.isContinuousNoteUploadEnabled)
                    .disabled(model.isBusy || model.activeNoteSet != nil)
                    .accessibilityIdentifier("continuousNoteToggle")
                Text(localized("note_set.help")).npCaption()

                if model.isContinuousNoteUploadEnabled || model.activeNoteSet != nil {
                    LabeledField(title: "note_set.title") {
                        TextField(localized("note_set.title_placeholder"), text: $model.continuousNoteTitle)
                            .disabled(model.activeNoteSet != nil)
                            .accessibilityIdentifier("continuousNoteTitleField")
                    }
                    if let noteSet = model.activeNoteSet {
                        Label(
                            localizedFormat("note_set.locked", String(noteSet.expectedPageCount)),
                            systemImage: "lock.fill"
                        )
                        .npCaption()
                    }
                }

                Toggle(localized("note.strategy.override"), isOn: $model.uploadUsesCustomNoteStrategy)
                    .disabled(model.isBusy || model.activeNoteSet != nil)
                    .accessibilityIdentifier("uploadNoteStrategyOverride")
                if model.uploadUsesCustomNoteStrategy {
                    Picker(localized("note.preferences.content"), selection: $model.uploadNoteContentEditLevel) {
                        ForEach(NoteContentEditLevel.supportedValues) { level in
                            Text(noteContentEditLevelLabel(level)).tag(level)
                        }
                        if !NoteContentEditLevel.supportedValues.contains(model.uploadNoteContentEditLevel) {
                            Text(model.uploadNoteContentEditLevel.rawValue).tag(model.uploadNoteContentEditLevel)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("uploadNoteContentStrategy")
                    Picker(localized("note.preferences.layout"), selection: $model.uploadNoteLayoutEditLevel) {
                        ForEach(NoteLayoutEditLevel.supportedValues) { level in
                            Text(noteLayoutEditLevelLabel(level)).tag(level)
                        }
                        if !NoteLayoutEditLevel.supportedValues.contains(model.uploadNoteLayoutEditLevel) {
                            Text(model.uploadNoteLayoutEditLevel.rawValue).tag(model.uploadNoteLayoutEditLevel)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("uploadNoteLayoutStrategy")
                }
            }
        }
        .onChange(of: model.uploadDocumentKind) { kind in
            if kind != "note", model.activeNoteSet == nil {
                model.isContinuousNoteUploadEnabled = false
                model.uploadUsesCustomNoteStrategy = false
            }
        }
    }
}

private struct UploadKindButton: View {
    let title: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NPColors.brandDark)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 8)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(selected ? NPColors.brandLight.opacity(0.6) : NPColors.interactive)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(selected ? NPColors.brand : NPColors.border, lineWidth: selected ? 1 : 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct UploadSourceButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let emphasized: Bool
    let compactLayout: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            UploadSourceLabel(title: title, systemImage: systemImage, compactLayout: compactLayout)
        }
        .buttonStyle(UploadSourceButtonStyle(emphasized: emphasized))
        .disabled(!enabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct UploadSourceLabel: View {
    let title: String
    let systemImage: String
    let compactLayout: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: compactLayout ? 17 : 19, weight: .medium))
            Text(localized(title))
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: compactLayout ? 56 : 64)
    }
}

private struct UploadSourceButtonStyle: ButtonStyle {
    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(emphasized ? .white : NPColors.brandDark)
            .background(
                RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous)
                    .fill(emphasized ? NPColors.brand : NPColors.brandLight)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.npInteractive, value: configuration.isPressed)
    }
}

private struct FilterPanel: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterChoices(
                label: "filter.status",
                values: ["", "created", "uploading", "scanning", "uploaded", "processing", "ready", "failed"],
                selected: model.statusFilter,
                enabled: !model.isBusy,
                onChange: model.setStatusFilter
            )
            FilterChoices(
                label: "filter.type",
                values: ["", "homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric", "other"],
                selected: model.documentKindFilter,
                enabled: !model.isBusy,
                onChange: model.setDocumentKindFilter
            )
            FilterChoices(
                label: "filter.file",
                values: ["", "image", "pdf", "docx", "pptx", "audio", "video", "other"],
                selected: model.fileTypeFilter,
                enabled: !model.isBusy,
                onChange: model.setFileTypeFilter
            )
        }
    }
}

private struct FilterChoices: View {
    let label: String
    let values: [String]
    let selected: String
    let enabled: Bool
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(label)
            ChoiceGrid(minimum: 72) {
                ForEach(values, id: \.self) { value in
                    ChoiceButton(text: filterChoiceLabel(value), selected: selected == value, enabled: enabled) {
                        onChange(value)
                    }
                }
            }
        }
    }
}

private struct DocumentRow: View, Equatable {
    let document: LearningDocumentItem
    let artifacts: [DocumentArtifactItem]
    let ocrArtifacts: [OcrArtifactItem]
    let isBusy: Bool
    let isPreviewLoading: Bool
    let canProcess: Bool
    let canDownload: Bool
    let thumbnailCacheKey: String
    let loadThumbnail: () async -> UIImage?
    let onDownload: () -> Void
    let onProcess: () -> Void
    let onDelete: () -> Void
    let onWorkflow: () -> Void
    let onArtifacts: () -> Void
    let onOCR: () -> Void
    let onEditRemark: () -> Void
    let onArtifactDownload: (DocumentArtifactItem) -> Void
    let onOcrDownload: (OcrArtifactItem) -> Void
    @State private var detailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDownload) {
                HStack(alignment: .top, spacing: 8) {
                    DocumentThumbnailView(
                        document: document,
                        cacheKey: thumbnailCacheKey,
                        size: CGSize(width: 52, height: 58),
                        load: loadThumbnail
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.displayRemark)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(NPColors.textPrimary)
                            .lineLimit(2)
                        Text("\(documentKindLabel(document.documentKind)) · \(fileTypeLabel(document.fileType)) · \(formatBytes(document.fileSize))")
                            .font(.caption)
                            .foregroundStyle(NPColors.textSecondary)
                            .lineLimit(1)
                        Text(compactDateTime(document.createdAt))
                            .font(.caption)
                            .foregroundStyle(NPColors.textTertiary)
                            .lineLimit(1)
                        if document.isImageRemarkActive {
                            Label(localized("image_remark.status.processing"), systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(NPColors.brand)
                        } else if document.imageRemarkStatus == "failed" {
                            Label(localized("image_remark.status.failed"), systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(NPColors.warning)
                        }
                    }
                    Spacer(minLength: 8)
                    if isPreviewLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 24, minHeight: 24)
                    } else {
                        NPStatusChip(text: primaryDocumentStatus(document), variant: primaryDocumentStatusVariant(document))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canDownload || isPreviewLoading)
            .accessibilityLabel(localizedFormat("accessibility.preview_file", document.displayRemark))
            .accessibilityIdentifier("documentPreviewArea-\(document.id)")

            HStack(spacing: 8) {
                Button(action: onProcess) {
                    Label(processTitle, systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPDocumentPrimaryButtonStyle())
                .disabled(isBusy || isPreviewLoading || !canProcess)

                Button(action: onDownload) {
                    if isPreviewLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "eye")
                    }
                }
                .buttonStyle(NPDocumentIconButtonStyle())
                .disabled(!canDownload || isPreviewLoading)
                .accessibilityLabel(localized("common.preview"))

                Menu {
                    if document.latestWorkflowRunId != nil {
                        Button(action: onWorkflow) {
                            Label(localized("workflow.view_progress"), systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    Button(action: onOCR) {
                        Label(localized("document.ocr_results"), systemImage: "text.viewfinder")
                    }
                    .disabled(isBusy || document.status != "ready" || !canDownload)
                    Button(action: onArtifacts) {
                        Label(localized("document.artifacts"), systemImage: "tray.full")
                    }
                    .disabled(isBusy || !canDownload)
                    Button(action: onEditRemark) {
                        Label(localized("image_remark.edit.action"), systemImage: "pencil")
                    }
                    .disabled(isBusy)
                    .accessibilityIdentifier("editDocumentRemark.\(document.id)")
                    Button {
                        detailsExpanded.toggle()
                    } label: {
                        Label(
                            localized(detailsExpanded ? "common.hide_details" : "common.view_details"),
                            systemImage: "info.circle"
                        )
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label(localized("document.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(NPDocumentIconButtonStyle())
                .disabled(isBusy || isPreviewLoading)
                .accessibilityLabel(localized("common.more_actions"))
                .accessibilityIdentifier("documentMoreActions.\(document.id)")
            }

            if detailsExpanded {
                Divider()
                DetailText(localizedFormat("image_remark.detail.original_filename", document.originalFilename))
                if let title = document.title, !title.isEmpty, title != document.originalFilename {
                    DetailText(localizedFormat("image_remark.detail.title", title))
                }
                DetailText(localizedFormat("image_remark.detail.source", imageRemarkSourceLabel(document.remarkSource)))
                if let status = document.imageRemarkStatus, !status.isEmpty {
                    DetailText(localizedFormat("image_remark.detail.status", imageRemarkStatusLabel(status)))
                }
                DetailText(localizedFormat("document.detail.mime", document.mimeType ?? localized("common.unknown")))
                if let sha256 = document.sha256 {
                    DetailText(localizedFormat("document.detail.sha256", sha256))
                }
                DetailText(localizedFormat("document.detail.updated", document.updatedAt))
            }

            if !artifacts.isEmpty {
                Divider()
                SectionLabel(localized("document.artifacts"))
                ForEach(artifacts) { artifact in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        DetailText(
                            [artifactTypeLabel(artifact.artifactType), artifact.mimeType, formatBytes(artifact.fileSize)]
                                .compactMap { $0 }.joined(separator: " · ")
                        )
                        Spacer(minLength: 0)
                        IconButton(systemImage: "arrow.down.circle", accessibilityLabel: localized("document.download_artifact"), enabled: !isBusy) {
                            onArtifactDownload(artifact)
                        }
                    }
                }
            }

            if !ocrArtifacts.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(localized("document.ocr_results"))
                    ForEach(ocrArtifacts) { artifact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            DetailText(
                                [artifactTypeLabel(artifact.artifactType), artifact.mimeType, formatBytes(artifact.fileSize), compactDateTime(artifact.createdAt)]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                            Spacer(minLength: 0)
                            IconButton(systemImage: "arrow.down.circle", accessibilityLabel: localized("document.download_ocr"), enabled: !isBusy && artifact.downloadURL?.isEmpty == false) {
                                onOcrDownload(artifact)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .modifier(NPListItemModifier())
    }

    static func == (lhs: DocumentRow, rhs: DocumentRow) -> Bool {
        lhs.document == rhs.document
            && lhs.artifacts == rhs.artifacts
            && lhs.ocrArtifacts == rhs.ocrArtifacts
            && lhs.isBusy == rhs.isBusy
            && lhs.isPreviewLoading == rhs.isPreviewLoading
            && lhs.canProcess == rhs.canProcess
            && lhs.canDownload == rhs.canDownload
            && lhs.thumbnailCacheKey == rhs.thumbnailCacheKey
    }

    private var processTitle: String {
        localized(document.status == "ready" || document.status == "failed" ? "document.reprocess" : "document.process")
    }

}

private struct RemarkEditorSheet: View {
    let title: String
    @Binding var text: String
    let originalFilename: String?
    let allowsEmpty: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let onRestoreFilename: (() -> Void)?

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(localized("image_remark.placeholder"), text: $text)
                        .disabled(isSaving)
                        .accessibilityIdentifier("documentRemarkField")
                    Text("\(text.count) / 255")
                        .npCaption()
                        .foregroundStyle(text.count > 255 ? NPColors.destructive : NPColors.textSecondary)
                } footer: {
                    Text(localized(allowsEmpty ? "image_remark.upload.help" : "image_remark.edit.help"))
                }

                if let originalFilename, onRestoreFilename != nil {
                    Section {
                        Button(localized("image_remark.restore_filename")) {
                            onRestoreFilename?()
                        }
                        .disabled(isSaving || originalFilename.isEmpty)
                        .accessibilityIdentifier("restoreDocumentFilenameButton")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.cancel"), action: onCancel)
                        .disabled(isSaving)
                        .accessibilityIdentifier("cancelDocumentRemarkButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave()
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text(localized("common.save")) }
                    }
                    .disabled(isSaving || text.count > 255 || (!allowsEmpty && trimmedText.isEmpty))
                    .accessibilityIdentifier("saveDocumentRemarkButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(isSaving)
    }
}

private struct TaskTab: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: NPSpacing.item) {
                WorkflowPanel(model: model, state: model.learningWorkflowState)
                if model.activeTask != nil || model.activeWorkflowDetail == nil {
                    TaskPanel(
                        activeTask: model.activeTask,
                        events: model.taskEvents,
                        canRetryDocumentPurge: model.canRetryDocumentPurge,
                        onRetryDocumentPurge: model.retryDocumentPurge
                    )
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .workbenchContentBottomPadding()
        }
        .onAppear { model.loadWorkflows() }
        .refreshable { model.loadWorkflows(force: true) }
        .background(NPColors.background)
        .navigationTitle(localized("workflow.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
}

private struct WorkflowPanel: View {
    @ObservedObject var model: NotePatchViewModel
    @ObservedObject var state: LearningWorkflowState
    @State private var stagesExpanded = true
    @State private var eventsExpanded = false

    var body: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.item) {
                HStack {
                    Label(localized("workflow.recent"), systemImage: "point.3.connected.trianglepath.dotted")
                        .npSubheading()
                        .accessibilityIdentifier("workflowScreen")
                    Spacer()
                    if state.isLoading { ProgressView() }
                }

                if !state.workflows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NPSpacing.small) {
                            ForEach(state.workflows.prefix(20)) { workflow in
                                Button { model.selectWorkflow(workflow.id) } label: {
                                    workflowChip(workflow)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("workflowRow.\(workflow.id)")
                            }
                        }
                    }
                }

                if let detail = state.activeDetail {
                    workflowSummary(detail.workflow)

                    DisclosureGroup(localized("workflow.stages"), isExpanded: $stagesExpanded) {
                        LazyVStack(spacing: NPSpacing.small) {
                            ForEach(detail.tasks) { item in
                                HStack(alignment: .top, spacing: NPSpacing.small) {
                                    Image(systemName: workflowTaskIcon(item.task.status))
                                        .foregroundStyle(workflowTaskColor(item.task.status))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workflowStageLabel(item.stage))
                                            .font(.body.weight(.medium))
                                        Text("\(localized("workflow.phase")): \(workflowStageLabel(item.phase))")
                                            .npCaption()
                                        if item.required {
                                            Text(localized("workflow.required"))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(NPColors.brand)
                                        }
                                    }
                                    Spacer()
                                    Text("\(item.task.progress.clamped(to: 0...100))%")
                                        .font(.caption.monospacedDigit())
                                }
                                .padding(10)
                                .background(NPColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
                                .accessibilityIdentifier("workflowStage.\(item.id)")
                            }
                        }
                        .padding(.top, 8)
                    }

                    if !state.events.isEmpty {
                        DisclosureGroup(localized("workflow.events"), isExpanded: $eventsExpanded) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(eventsExpanded ? state.events : Array(state.events.suffix(4))) { event in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(event.level == "error" ? NPColors.destructive : NPColors.textTertiary)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 6)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.message).npCaption()
                                            if let stage = event.stage {
                                                Text(workflowStageLabel(stage))
                                                    .font(.caption2)
                                                    .foregroundStyle(NPColors.textTertiary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                } else if state.workflows.isEmpty && !state.isLoading {
                    NPEmptyState(
                        systemImage: "checkmark.circle",
                        title: localized("workflow.empty.title"),
                        message: localized("workflow.empty.message")
                    )
                }
            }
        }
    }

    private func workflowSummary(_ workflow: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NPStatusChip(text: workflowStatusLabel(workflow.status), variant: workflowStatusVariant(workflow.status))
                Spacer()
                Text("\(workflow.progress.clamped(to: 0...100))%")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(workflow.progress.clamped(to: 0...100)), total: 100)
            HStack(spacing: NPSpacing.item) {
                workflowStatusColumn("workflow.core", workflow.coreStatus)
                workflowStatusColumn("workflow.enrichment", workflow.enrichmentStatus)
            }
            if let stage = workflow.currentStage {
                Label(workflowStageLabel(stage), systemImage: "arrow.right.circle")
                    .npCaption()
            }
            if workflow.status == "waiting", let waitingUntil = workflow.waitingUntil {
                Label(localizedFormat("workflow.waiting_until", compactDateTime(waitingUntil)), systemImage: "clock")
                    .npCaption()
            }
            if let error = workflow.errorMessage, !error.isEmpty {
                Text(error)
                    .npBody()
                    .foregroundStyle(workflow.status == "partially_succeeded" ? NPColors.warning : NPColors.destructive)
            }
        }
    }

    private func workflowChip(_ workflow: WorkflowRun) -> some View {
        let stage = workflow.currentStage ?? workflow.triggerType
        let isSelected = state.activeDetail?.workflow.id == workflow.id
        return VStack(alignment: .leading, spacing: 4) {
            Text(workflowStageLabel(stage))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(workflowStatusLabel(workflow.status))
                .font(.caption2)
                .foregroundStyle(NPColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? NPColors.brand.opacity(0.14) : NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
    }

    private func workflowStatusColumn(_ title: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(title)).font(.caption2).foregroundStyle(NPColors.textTertiary)
            Text(workflowStatusLabel(status)).font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskPanel: View {
    let activeTask: TaskItem?
    let events: [TaskEventItem]
    let canRetryDocumentPurge: Bool
    let onRetryDocumentPurge: () -> Void
    @State private var resultExpanded = false
    @State private var eventsExpanded = false

    var body: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(localized("task.active"), systemImage: "clock.arrow.circlepath")
                        .npSubheading()
                        .foregroundStyle(NPColors.textPrimary)
                        .accessibilityIdentifier("taskScreen")
                    Spacer()
                    if let activeTask {
                        NPStatusChip(text: taskStatusLabel(activeTask), variant: taskStatusChipVariant(activeTask))
                    }
                }

                if let activeTask {
                    VStack(alignment: .leading, spacing: NPSpacing.small) {
                        HStack {
                            Text(taskTypeLabel(activeTask.taskType))
                                .font(.body.weight(.medium))
                                .foregroundStyle(NPColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(activeTask.progress.clamped(to: 0...100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(NPColors.textSecondary)
                        }
                        ProgressView(value: Double(activeTask.progress.clamped(to: 0...100)), total: 100)
                    }
                    HStack(spacing: NPSpacing.item) {
                        if let startedAt = activeTask.startedAt {
                            TaskTime(label: localized("task.started"), value: compactDateTime(startedAt))
                        }
                        if let finishedAt = activeTask.finishedAt {
                            TaskTime(label: localized("task.completed"), value: compactDateTime(finishedAt))
                        }
                        if let cancelRequestedAt = activeTask.cancelRequestedAt {
                            TaskTime(label: localized("task.cancel_requested"), value: compactDateTime(cancelRequestedAt))
                        }
                    }
                    if let taskMessage = terminalMessage(for: activeTask) {
                        let isCancelled = activeTask.status == "cancelled"
                        let msgColor: Color = isCancelled ? NPColors.warning : NPColors.destructive
                        Label(taskMessage, systemImage: "exclamationmark.triangle.fill")
                            .npBody()
                            .foregroundStyle(msgColor)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(msgColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                    }
                    if let resultText = activeTask.resultText {
                        DisclosureGroup(localized("task.result"), isExpanded: $resultExpanded) {
                            DetailText(resultText, lineLimit: nil)
                                .padding(.top, 6)
                        }
                        .font(.body.weight(.medium))
                    }
                    if canRetryDocumentPurge {
                        Button(action: onRetryDocumentPurge) {
                            Label(localized("task.retry_cleanup"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPPrimaryButtonStyle())
                        .accessibilityIdentifier("retryDocumentPurgeButton")
                    }
                } else {
                    NPEmptyState(
                        systemImage: "checkmark.circle",
                        title: localized("task.empty.title"),
                        message: localized("task.empty.message")
                    )
                }

                if !events.isEmpty {
                    Divider().background(NPColors.interactive.opacity(0.4))
                    HStack {
                        SectionLabel(localized("task.event_log"))
                        Spacer()
                        Button(eventsExpanded ? localized("common.collapse") : localized("common.view_all")) {
                            eventsExpanded.toggle()
                        }
                        .npCaption()
                    }

                    ForEach(visibleEvents) { event in
                        HStack(alignment: .top, spacing: NPSpacing.small) {
                            Circle()
                                .fill(event.level == "error" ? NPColors.destructive : NPColors.textSecondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.progress.map { "\($0)% · " } ?? "")\(event.message)")
                                    .npCaption()
                                    .foregroundStyle(event.level == "error" ? NPColors.destructive : NPColors.textPrimary)
                                    .lineLimit(eventsExpanded ? 3 : 1)
                                if eventsExpanded, let dataText = event.dataText {
                                    DetailText(dataText, lineLimit: 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleEvents: [TaskEventItem] {
        if eventsExpanded {
            return events
        }
        let recent = Array(events.suffix(4))
        if let latestError = events.last(where: { $0.level == "error" }),
           !recent.contains(latestError) {
            return [latestError] + recent.suffix(3)
        }
        return recent
    }

    private func terminalMessage(for task: TaskItem) -> String? {
        if task.status == "cancelled" {
            return events.last(where: { $0.eventType.contains("cancel") })?.message
                ?? events.last(where: { $0.level == "error" })?.message
                ?? events.last?.message
                ?? task.errorMessage
                ?? localized("task.cancelled_fallback")
        }
        return task.errorMessage
    }
}

private struct TaskTime: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .npCaption()
                .foregroundStyle(NPColors.textSecondary)
            Text(value)
                .npCaption()
                .foregroundStyle(NPColors.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - OpenClaw Chat Tab

private struct InlineChatMessageRevisionContext {
    let message: OpenClawChatMessage
    let conversationId: String?
    let originalMessages: [OpenClawChatMessage]
    let originalComposerText: String
    let originalComposerHeight: CGFloat
    let originalAttachments: [LocalUploadFile]
    let originalSaveAttachmentsToWorkspace: Bool
}

private struct OpenClawChatTab: View {
    let model: NotePatchViewModel
    @ObservedObject var chatState: OpenClawViewState
    @ObservedObject var composerState: OpenClawComposerState
    @ObservedObject var aiExperienceState: AIExperienceState
    @Environment(\.workbenchBottomObstruction) private var bottomObstruction
    @State private var renamingConversation: ChatConversation?
    @State private var textSelectionMessage: OpenClawChatMessage?
    @State private var titleDraft = ""
    @State private var inlineRevision: InlineChatMessageRevisionContext?
    @State private var isConversationDrawerOpen = false
    @State private var isComposerFocused = false
    @State private var isShowingAIPhotoLibrary = false
    @State private var isShowingAIFileImporter = false
    @State private var attachmentPickerUserId: String?
    @State private var attachmentPickerWorkspaceId: String?
    @State private var keyboardFrame: CGRect = .null
    @State private var isChatAtBottom = true

    private let chatBottomAnchorID = "openClawChatBottomAnchor"

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                let keyboardOffset = keyboardAvoidanceOffset(
                    contentFrame: geometry.frame(in: .global),
                    keyboardFrame: keyboardFrame
                )
                let isKeyboardPresented = keyboardOffset > 0

                VStack(spacing: 0) {
                // ——— Conversation header (fixed) ———
                HStack(spacing: 8) {
                    Text(chatState.selectedConversation?.title ?? localized("chat.new_conversation"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NPColors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        .accessibilityIdentifier("openClawTab")
                    Button {
                        cancelInlineRevision()
                        dismissComposer()
                        withAnimation(.npInteractive) {
                            isConversationDrawerOpen = true
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(NPColors.interactive.opacity(0.4))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(NPColors.textSecondary)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(chatState.isHistoryLoading || chatState.isConversationMutating)
                    .accessibilityLabel(localized("chat.drawer.open_accessibility"))
                    .accessibilityIdentifier("chatHistoryButton")
                    CompactPageLogo()
                }
                .padding(.horizontal, 16)
                .padding(.top, max(6, min(12, geometry.safeAreaInsets.top / 5)))
                .padding(.bottom, 2)

                Rectangle()
                    .fill(NPColors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                    .accessibilityHidden(true)

                // ——— Brand Hero ———
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(spacing: 0) {
                            ChatScrollPanObserver(
                                onPan: { value in
                                    dismissKeyboardIfNeeded(
                                        startLocation: value.startLocation,
                                        location: value.location,
                                        translation: value.translation,
                                        scrollBottomY: value.scrollBottomY
                                    )
                                },
                                onBottomChange: { atBottom in
                                    guard isChatAtBottom != atBottom else { return }
                                    isChatAtBottom = atBottom
                                }
                            )
                            .frame(height: 0)

                            // ——— Welcome card ———
                            if chatState.messages.isEmpty {
                                NPSection {
                                    VStack(spacing: NPSpacing.small) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 28, weight: .light))
                                            .foregroundStyle(NPColors.brand)
                                            .padding(.bottom, NPSpacing.xs)
                                        Text(aiExperienceState.greeting?.assistantName ?? localized("chat.ai_name"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(NPColors.textPrimary)
                                        if let greeting = aiExperienceState.greeting {
                                            LightweightMarkdownText(
                                                markdown: greeting.message,
                                                color: NPColors.textSecondary,
                                                horizontalAlignment: .center,
                                                textAlignment: .center
                                            )
                                        } else if aiExperienceState.isGreetingLoading {
                                            ProgressView()
                                        } else {
                                            Button(localized("common.retry")) {
                                                model.loadChatHistory(force: true)
                                            }
                                            .buttonStyle(NPSecondaryButtonStyle())
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, NPSpacing.xs)
                                }
                                .padding(.horizontal, NPSpacing.outer)
                                .accessibilityIdentifier("chatServerGreeting")
                            }

                            // ——— Messages ———
                            LazyVStack(spacing: NPSpacing.medium) {
                                ForEach(chatState.messages) { message in
                                    OpenClawMessageBubble(
                                        message: message,
                                        onCopy: { model.copyOpenClawMessage(message) },
                                        onSelectText: { textSelectionMessage = message },
                                        onPreviewAttachment: model.previewOpenClawAttachment,
                                        onEdit: canEdit(message) ? {
                                            beginInlineRevision(message)
                                        } : nil
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding(.horizontal, NPSpacing.outer)
                            .padding(.vertical, 14)

                            Color.clear
                                .frame(height: 1)
                                .id(chatBottomAnchorID)
                        }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    if value.translation.height > 6 {
                                        isChatAtBottom = false
                                    }
                                    if UIDevice.current.userInterfaceIdiom == .pad,
                                       isComposerFocused,
                                       value.translation.height > 12 {
                                        dismissComposer()
                                    }
                                }
                        )
                        .accessibilityIdentifier("openClawMessages")

                        if !chatState.messages.isEmpty, !isChatAtBottom {
                            Button {
                                withAnimation(.easeOut(duration: 0.24)) {
                                    proxy.scrollTo(chatBottomAnchorID, anchor: .bottom)
                                    isChatAtBottom = true
                                }
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NPColors.brandDark)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle().stroke(NPColors.border, lineWidth: 1)
                                    }
                                    .shadow(
                                        color: NPShadow.small.color,
                                        radius: NPShadow.small.radius,
                                        y: NPShadow.small.y
                                    )
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .padding(.bottom, NPSpacing.small)
                            .accessibilityLabel(localized("chat.scroll_to_bottom"))
                            .accessibilityIdentifier("chatScrollToBottomButton")
                        }
                    }
                }
                // ——— Composer bar ———
                VStack(spacing: 0) {
                    composer
                        .padding(.horizontal, NPSpacing.outer)
                        .padding(.vertical, 10)
                }
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: NPColors.background.opacity(0), location: 0),
                            .init(color: NPColors.background, location: 0.25),
                            .init(color: NPColors.background, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(isKeyboardPresented ? 0 : 1)
                }
                .padding(.bottom, isKeyboardPresented ? NPSpacing.small : bottomObstruction)
            }
            .padding(.bottom, keyboardOffset)
            .animation(.easeOut(duration: 0.22), value: keyboardOffset)
            }

            conversationDrawer
                .offset(x: isConversationDrawerOpen ? 0 : -420)
                .opacity(isConversationDrawerOpen ? 1 : 0)
                .allowsHitTesting(isConversationDrawerOpen)
                .accessibilityHidden(!isConversationDrawerOpen)
                .animation(.npInteractive, value: isConversationDrawerOpen)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            updateKeyboardFrame(from: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
            updateKeyboardFrame(from: $0, forceHidden: true)
        }
        .onDisappear {
            keyboardFrame = .null
            endInlineRevision(restoreMessages: true)
            dismissComposer()
        }
        .simultaneousGesture(drawerOpenGesture)
        .fileImporter(
            isPresented: $isShowingAIFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addAIFileAttachments(urls)
            } else if case .failure(let error) = result {
                if model.isCurrentImportContext(
                    userId: attachmentPickerUserId,
                    workspaceId: attachmentPickerWorkspaceId
                ) {
                    model.presentError(error)
                }
            }
        }
        .sheet(isPresented: $isShowingAIPhotoLibrary) {
            PhotoLibraryPicker(cacheDirectory: aiAttachmentCacheDirectory) { result in
                isShowingAIPhotoLibrary = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    model.stageOpenClawDraftAttachments(
                        files,
                        expectedUserId: attachmentPickerUserId,
                        expectedWorkspaceId: attachmentPickerWorkspaceId
                    )
                case .failure(let error):
                    if model.isCurrentImportContext(
                        userId: attachmentPickerUserId,
                        workspaceId: attachmentPickerWorkspaceId
                    ) {
                        model.presentError(error)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $textSelectionMessage) { message in
            ChatMessageTextSelectionScreen(message: message) {
                textSelectionMessage = nil
            }
        }
        .alert(
            localized("chat.rename_title"),
            isPresented: Binding(
                get: { renamingConversation != nil },
                set: { if !$0 { renamingConversation = nil } }
            )
        ) {
            TextField(localized("chat.title_placeholder"), text: $titleDraft)
            Button(localized("common.cancel"), role: .cancel) {}
            Button(localized("common.save")) {
                if let conversation = renamingConversation {
                    model.renameConversation(conversation.id, to: titleDraft)
                }
            }
            .disabled(
                chatState.isConversationMutating ||
                titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).count > 160
            )
        }
        .background(NPColors.background)
    }

    private func updateKeyboardFrame(from notification: Notification, forceHidden: Bool = false) {
        let frame = forceHidden
            ? CGRect.null
            : (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        guard keyboardFrame != frame else { return }
        keyboardFrame = frame
    }

    private func dismissComposer() {
        isComposerFocused = false
        dismissActiveKeyboard()
    }

    private func canEdit(_ message: OpenClawChatMessage) -> Bool {
        message.role == .user
            && message.id != "system"
            && !message.id.hasPrefix("local-")
            && !chatState.isSending
            && !chatState.isMessageRevising
            && inlineRevision == nil
    }

    private func beginInlineRevision(_ message: OpenClawChatMessage) {
        guard inlineRevision == nil,
              !chatState.isSending,
              !chatState.isMessageRevising,
              let index = chatState.messages.firstIndex(where: { $0.id == message.id }) else { return }
        inlineRevision = InlineChatMessageRevisionContext(
            message: message,
            conversationId: chatState.selectedConversationId,
            originalMessages: chatState.messages,
            originalComposerText: composerState.text,
            originalComposerHeight: composerState.measuredTextHeight,
            originalAttachments: composerState.attachments,
            originalSaveAttachmentsToWorkspace: composerState.saveAttachmentsToWorkspace
        )
        withAnimation(.npInteractive) {
            chatState.messages = Array(chatState.messages.prefix(index + 1))
        }
        composerState.text = message.content
        composerState.measuredTextHeight = 44
        composerState.attachments = []
        isComposerFocused = true
    }

    private func cancelInlineRevision() {
        guard !chatState.isMessageRevising else { return }
        endInlineRevision(restoreMessages: true)
        dismissComposer()
    }

    private func endInlineRevision(restoreMessages: Bool) {
        guard let revision = inlineRevision else { return }
        if restoreMessages,
           chatState.selectedConversationId == revision.conversationId {
            withAnimation(.npInteractive) {
                chatState.messages = revision.originalMessages
            }
        }
        composerState.text = revision.originalComposerText
        composerState.measuredTextHeight = revision.originalComposerHeight
        composerState.attachments = revision.originalAttachments
        composerState.saveAttachmentsToWorkspace = revision.originalSaveAttachmentsToWorkspace
        inlineRevision = nil
    }

    private func submitInlineRevision() {
        guard let revision = inlineRevision,
              !chatState.isMessageRevising else { return }
        dismissComposer()
        model.reviseOpenClawMessage(revision.message, prompt: composerState.text) {
            endInlineRevision(restoreMessages: false)
        }
    }

    // MARK: - Conversation Drawer

    private func closeConversationDrawer() {
        withAnimation(.npInteractive) {
            isConversationDrawerOpen = false
        }
    }

    private var drawerOpenGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard !isConversationDrawerOpen,
                      value.startLocation.x <= 20,
                      value.translation.width > 40,
                      value.translation.width > abs(value.translation.height) * 1.5 else { return }
                cancelInlineRevision()
                dismissComposer()
                withAnimation(.npInteractive) {
                    isConversationDrawerOpen = true
                }
            }
    }

    private var conversationDrawer: some View {
        GeometryReader { proxy in
            let drawerWidth = min(320, proxy.size.width * 0.82)
            let windowInsets = currentAppWindowSafeAreaInsets()
            let topSafeAreaInset = resolvedTopSafeAreaInset(
                reportedSafeAreaTop: proxy.safeAreaInsets.top,
                windowSafeAreaTop: windowInsets.top,
                statusBarHeight: currentAppStatusBarHeight()
            )
            let bottomSafeAreaInset = max(proxy.safeAreaInsets.bottom, windowInsets.bottom)
            ZStack(alignment: .leading) {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: drawerWidth)
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("chatConversationBackdrop")
                        .onTapGesture {
                            closeConversationDrawer()
                        }
                    }
                    .ignoresSafeArea()

                conversationDrawerPanel(
                    topSafeAreaInset: topSafeAreaInset,
                    bottomSafeAreaInset: bottomSafeAreaInset
                )
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 16)
                            .onEnded { value in
                                guard value.translation.width < -48,
                                      abs(value.translation.width) > abs(value.translation.height) else { return }
                                closeConversationDrawer()
                            }
                    )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatConversationDrawer")
    }

    private func conversationDrawerPanel(
        topSafeAreaInset: CGFloat,
        bottomSafeAreaInset: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(localized("chat.drawer.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NPColors.textPrimary)
                    .accessibilityIdentifier("chatConversationDrawerHeader")
                Spacer()
                Button {
                    closeConversationDrawer()
                    model.startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NPColors.brandDark)
                        .frame(width: 44, height: 44)
                        .background(NPColors.interactive.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("chat.new_conversation"))
                .accessibilityIdentifier("chatNewConversationButton")
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, topSafeAreaInset + 19)
            .padding(.bottom, 10)

            if chatState.conversations.isEmpty {
                Text(localized("chat.drawer.empty"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(NPSpacing.outer)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chatState.conversations) { conversation in
                            conversationDrawerRow(conversation)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, bottomSafeAreaInset + 16)
                }
            }
        }
        .background { conversationDrawerBackground.ignoresSafeArea() }
        .shadow(color: .black.opacity(0.12), radius: 24, x: 8, y: 0)
    }

    @ViewBuilder
    private var conversationDrawerBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private func conversationDrawerRow(_ conversation: ChatConversation) -> some View {
        let isSelected = conversation.id == chatState.selectedConversationId
        return Button {
            closeConversationDrawer()
            model.selectConversation(conversation.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? NPColors.brandDark : NPColors.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(NPColors.textPrimary)
                        .lineLimit(1)
                    let timestamp = conversationTimestamp(conversation)
                    if !timestamp.isEmpty {
                        Text(timestamp)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(NPColors.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? NPColors.brand.opacity(0.14) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                titleDraft = conversation.title
                renamingConversation = conversation
            } label: {
                Label(localized("chat.rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.deleteConversation(conversation.id)
            } label: {
                Label(localized("chat.delete_conversation"), systemImage: "trash")
            }
        }
        .accessibilityIdentifier("chatConversationRow.\(conversation.id)")
    }

    private func conversationTimestamp(_ conversation: ChatConversation) -> String {
        let raw = conversation.lastMessageAt ?? conversation.createdAt
        guard !raw.isEmpty else { return "" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func dismissKeyboardIfNeeded(
        startLocation: CGPoint,
        location: CGPoint,
        translation: CGSize,
        scrollBottomY: CGFloat
    ) {
        let composerControlsHeight: CGFloat = 56
        let composerBoundary = scrollBottomY + max(12, min(44, composerState.measuredTextHeight))
        let keyboardBoundary = keyboardFrame.isNull
            ? composerBoundary
            : keyboardFrame.minY - composerControlsHeight
        let dismissalBoundary = min(composerBoundary, keyboardBoundary)
        guard isComposerFocused,
              translation.height > 12,
              translation.height > abs(translation.width),
              startLocation.y < scrollBottomY,
              location.y >= dismissalBoundary else {
            return
        }
        dismissComposer()
    }

    private var isComposerExpanded: Bool {
        isComposerFocused || !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        let expanded = isComposerExpanded
        let composerHeight = expanded ? max(92, composerState.measuredTextHeight + 62) : 44

        return VStack(spacing: NPSpacing.small) {
            if !composerState.attachments.isEmpty {
                aiAttachmentStrip
            }

            GeometryReader { geometry in
                let textHorizontalInset = expanded ? NPSpacing.small : 54
                let textViewWidth = max(0, geometry.size.width)

                ZStack(alignment: .topLeading) {
                    Text(localized("chat.composer_placeholder"))
                        .foregroundStyle(NPColors.textSecondary)
                        .padding(.leading, expanded ? NPSpacing.outer : 54)
                        .padding(.trailing, expanded ? NPSpacing.outer : 54)
                        .padding(.top, expanded ? 19 : 11)
                        .opacity(composerState.text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)

                    AdaptiveComposerTextView(
                        text: $composerState.text,
                        isFocused: Binding(
                            get: { isComposerFocused },
                            set: { isComposerFocused = $0 }
                        ),
                        height: $composerState.measuredTextHeight,
                        availableWidth: textViewWidth,
                        horizontalInset: textHorizontalInset,
                        maximumLines: expanded ? 7 : 1
                    )
                    .frame(
                        width: textViewWidth,
                        height: expanded ? composerState.measuredTextHeight : 44
                    )
                    .padding(.top, expanded ? NPSpacing.small : 0)
                    .padding(.bottom, expanded ? 46 : 0)
                    .disabled(chatState.isSending || chatState.isMessageRevising)

                    HStack(spacing: 10) {
                        if inlineRevision == nil {
                            composerAttachmentButton
                        }
                        Spacer(minLength: 0)
                        if inlineRevision != nil {
                            composerRevisionCancelButton
                        }
                        composerSendButton
                    }
                    .padding(.horizontal, expanded ? NPSpacing.small : 0)
                    .frame(height: 38)
                    .padding(.bottom, expanded ? NPSpacing.small : 0)
                    .frame(maxHeight: .infinity, alignment: expanded ? .bottom : .center)
                }
                .frame(
                    width: geometry.size.width,
                    height: composerHeight,
                    alignment: .topLeading
                )
                .modifier(AIComposerInputSurface(isActive: expanded))
            }
            .frame(height: composerHeight)
        }
    }

    private struct AIComposerInputSurface: ViewModifier {
        let isActive: Bool

        func body(content: Content) -> some View {
            content
                .background {
                    AIComposerSurfaceBackground()
                        .overlay {
                            RoundedRectangle(cornerRadius: NPRadius.sheet, style: .continuous)
                                .stroke(NPColors.surfaceHighlight, lineWidth: 0.5)
                        }
                        .modifier(NPCardShadow())
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
    }

    private struct AIComposerSurfaceBackground: View {
        @ViewBuilder
        var body: some View {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: NPRadius.sheet, style: .continuous)
                )
            } else {
                RoundedRectangle(cornerRadius: NPRadius.sheet, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
    }

    private var composerAttachmentButton: some View {
        Menu {
            Button {
                dismissComposer()
                captureAttachmentPickerContext()
                isShowingAIPhotoLibrary = true
            } label: {
                Label(localized("chat.choose_photo"), systemImage: "photo.on.rectangle")
            }
            Button {
                dismissComposer()
                captureAttachmentPickerContext()
                isShowingAIFileImporter = true
            } label: {
                Label(localized("chat.choose_file"), systemImage: "folder")
            }
            Divider()
            Toggle(isOn: $composerState.saveAttachmentsToWorkspace) {
                Label(localized("chat.save_to_workspace"), systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("chatSaveToWorkspaceToggle")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .foregroundStyle(NPColors.textSecondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(localized("chat.add_attachment"))
        .accessibilityIdentifier("openClawAttachmentButton")
        .disabled(chatState.isSending)
    }

    private var composerRevisionCancelButton: some View {
        Button {
            cancelInlineRevision()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(NPColors.textPrimary)
        .background {
            Circle()
                .fill(NPColors.textSecondary.opacity(0.14))
        }
        .clipShape(Circle())
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .disabled(chatState.isMessageRevising)
        .accessibilityLabel(localized("common.cancel"))
        .accessibilityIdentifier("chatRevisionCancelButton")
    }

    private var aiAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NPSpacing.small) {
                ForEach(composerState.attachments) { file in
                    AIComposerAttachmentChip(file: file) {
                        removeAIDraftAttachment(file)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 46)
    }

    private func addAIFileAttachments(_ urls: [URL]) {
        let cacheDirectory = aiAttachmentCacheDirectory
        let expectedUserId = attachmentPickerUserId
        let expectedWorkspaceId = attachmentPickerWorkspaceId
        Task {
            let outcomes = await FileImportService.shared.importFiles(
                urls,
                fallbackPrefix: "ai-attachment",
                cacheDirectory: cacheDirectory
            )
            let didStage = model.stageOpenClawDraftAttachments(
                outcomes.compactMap(\.file),
                expectedUserId: expectedUserId,
                expectedWorkspaceId: expectedWorkspaceId
            )
            if didStage, let message = outcomes.compactMap(\.errorDisplayText).first {
                model.presentError(message)
            }
        }
    }

    private func removeAIDraftAttachment(_ file: LocalUploadFile) {
        model.removeOpenClawDraftAttachment(file)
    }

    private func captureAttachmentPickerContext() {
        attachmentPickerUserId = model.session?.userId
        attachmentPickerWorkspaceId = model.selectedWorkspaceId
    }

    private var aiAttachmentCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private var composerSendButton: some View {
        let hasPrompt = !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isInlineRevision = inlineRevision != nil
        let canSend = !chatState.isSending
            && !chatState.isMessageRevising
            && (isInlineRevision ? hasPrompt : (hasPrompt || !composerState.attachments.isEmpty))
        let hasActiveGeneration = chatState.messages.contains {
            $0.role == .assistant && $0.status == .sending && $0.taskId != nil
        }
        let shouldShowStop = !hasPrompt && chatState.isSending && hasActiveGeneration
        let isStopping = chatState.cancellingTaskId != nil

        if shouldShowStop {
            return AnyView(
                Button {
                    model.stopOpenClawChat()
                } label: {
                    Group {
                        if isStopping {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: NPColors.surface))
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NPColors.surface)
                .background {
                    Circle()
                        .fill(NPColors.destructive)
                }
                .clipShape(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .disabled(isStopping)
                .accessibilityLabel(localized("chat.stop_generation"))
                .accessibilityIdentifier("openClawStopButton")
            )
        }

        return AnyView(
            Button {
                if isInlineRevision {
                    submitInlineRevision()
                } else {
                    dismissComposer()
                    _ = model.startOpenClawChat(
                        prompt: composerState.text,
                        attachments: composerState.attachments
                    )
                }
            } label: {
                Group {
                    if chatState.isMessageRevising {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: NPColors.surface))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? NPColors.surface : NPColors.textSecondary)
            .background {
                Circle()
                    .fill(canSend ? NPColors.brand : NPColors.textSecondary.opacity(0.18))
            }
            .clipShape(Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .disabled(!canSend)
            .accessibilityLabel(localized(isInlineRevision ? "chat.revision.action" : "chat.send"))
            .accessibilityIdentifier("openClawSendButton")
        )
    }
}

private struct AIComposerAttachmentChip: View {
    let file: LocalUploadFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            attachmentIcon

            Text(file.filename)
                .npCaption()
                .lineLimit(1)
                .frame(maxWidth: 128, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NPColors.textSecondary)
            .accessibilityLabel(localizedFormat("accessibility.remove_file", file.filename))
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 44)
        .background(NPColors.surface)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(NPColors.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        UploadThumbnailImage(
            file: file,
            size: CGSize(width: 30, height: 30),
            cornerRadius: 6
        )
    }
}

private func dismissActiveKeyboard() {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .endEditing(true)
}

// MARK: - Learning Tab

private struct LearningTab: View {
    @ObservedObject var model: NotePatchViewModel
    let onOpenNote: (StudyNoteListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch model.selectedLearningSection {
                    case .notes:
                        EmptyView()
                    case .units:
                        LearningUnitsSection(model: model, onOpenNote: onOpenNote)
                    case .search:
                        KnowledgeSearchSection(model: model)
                    case .homework:
                        HomeworkGradingSection(model: model)
                    case .flashcards:
                        FlashcardsSection(model: model)
                    }
                }
                .padding(.horizontal, 16)
                .workbenchContentBottomPadding()
            }
            .background {
                if model.selectedLearningSection == .homework {
                    HomeworkScrollPositionPreserver(identity: model.selectedHomeworkId)
                }
            }
            .accessibilityIdentifier("learningContentScroll")
        }
        .onChange(of: model.selectedLearningSection) { section in
            if section == .flashcards {
                model.ensureFlashcardsLoaded()
            }
        }
        .sheet(isPresented: $model.isStudyNoteGenerationPresented) {
            StudyNoteGenerationSheet(model: model)
        }
    }
}

private struct HomeworkScrollPositionPreserver: UIViewRepresentable {
    let identity: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(identity: identity)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.prepareForLayoutUpdate(identity: identity, from: uiView)
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attachIfNeeded(from: self)
        }
    }

    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var identity: String?
        private var savedOffset = CGPoint.zero
        private var layoutGeneration = 0
        private var isProtectingLayout = false

        init(identity: String?) {
            self.identity = identity
        }

        deinit {
            observation?.invalidate()
        }

        func attachIfNeeded(from view: UIView) {
            guard scrollView == nil, let scrollView = enclosingScrollView(from: view) else { return }
            self.scrollView = scrollView
            savedOffset = scrollView.contentOffset
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, change in
                guard let self, let scrollView, let offset = change.newValue else { return }
                if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
                    self.isProtectingLayout = false
                    self.savedOffset = offset
                } else if !self.isProtectingLayout {
                    self.savedOffset = offset
                }
            }
        }

        func prepareForLayoutUpdate(identity newIdentity: String?, from view: UIView) {
            attachIfNeeded(from: view)
            guard let scrollView else { return }
            if identity != newIdentity {
                identity = newIdentity
                savedOffset = scrollView.contentOffset
                isProtectingLayout = false
                return
            }
            guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
                savedOffset = scrollView.contentOffset
                return
            }
            let target = savedOffset
            layoutGeneration &+= 1
            let generation = layoutGeneration
            isProtectingLayout = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView, self.layoutGeneration == generation else { return }
                defer { self.isProtectingLayout = false }
                guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
                    self.savedOffset = scrollView.contentOffset
                    return
                }
                let minimumY = -scrollView.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                )
                let restoredY = min(max(target.y, minimumY), maximumY)
                if scrollView.contentOffset.y < restoredY - 1 {
                    scrollView.setContentOffset(
                        CGPoint(x: scrollView.contentOffset.x, y: restoredY),
                        animated: false
                    )
                }
                self.savedOffset = CGPoint(x: scrollView.contentOffset.x, y: restoredY)
            }
        }

        private func enclosingScrollView(from view: UIView) -> UIScrollView? {
            var candidate = view.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                candidate = current.superview
            }
            return nil
        }
    }
}

private struct LearningUnitsSection: View {
    @ObservedObject var model: NotePatchViewModel
    let onOpenNote: (StudyNoteListItem) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            LearningSectionHeader(title: localized("review.units.title"), subtitle: localized("review.units.subtitle"), isLoading: model.isLearningLoading) {
                model.loadLearningUnits(allowOfflineNetwork: true)
            }
            HStack(spacing: NPSpacing.small) {
                Button {
                    model.beginLearningUnitMerge()
                } label: {
                    Label(localized("merge.action"), systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(!model.canBeginLearningUnitMerge)
                .accessibilityIdentifier("mergeLearningUnitsButton")

                if model.activeTask?.taskType == "merge_learning_units" {
                    Button(localized("merge.view_task")) {
                        model.viewLearningUnitMergeTask()
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                }
                Spacer()
            }
            if model.isLearningLoading && model.learningUnits.isEmpty {
                ProgressView(localized("review.units.loading"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if model.learningUnits.isEmpty {
                LearningEmptyState()
            } else {
                ForEach(model.learningUnits) { unit in
                    Button { model.selectLearningUnit(unit.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(unit.title).npSubheading().lineLimit(2)
                                Spacer()
                                if unit.id == model.selectedLearningUnitId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(NPColors.brand)
                                }
                            }
                            let details = [unit.subject, unit.gradeLevel, unit.topic].compactMap { $0?.isEmpty == false ? $0 : nil }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · ")).npCaption()
                            }
                            if let mergeStatus = model.displayedMergeStatus(for: unit), !mergeStatus.isEmpty {
                                NPStatusChip(text: mergeStatusLabel(mergeStatus), variant: statusChipVariant(mergeStatus))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(NPCardModifier())
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.selectedLearningUnitId != nil {
                Button {
                    if let unitId = model.selectedLearningUnitId {
                        model.presentNoteGaps(for: unitId)
                    }
                } label: {
                    Label(localized("note_gap.open"), systemImage: "lightbulb.max")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .accessibilityIdentifier("selectedUnitNoteGapsButton")

                Button {
                    if let unitId = model.selectedLearningUnitId {
                        model.presentStudyNoteGeneration(for: unitId)
                    }
                } label: {
                    Label(
                        localized(model.studyNotes.isEmpty ? "note.generate" : "note.regenerate"),
                        systemImage: "wand.and.stars"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .accessibilityIdentifier("generateStudyNoteButton")

                Text(localized("notes.default_title")).npSubheading().padding(.top, 6)
                if model.studyNotes.isEmpty {
                    Text(localized("notes.unit.empty"))
                        .npBody()
                        .foregroundStyle(NPColors.textSecondary)
                } else {
                    ForEach(model.studyNotes) { note in
                        HStack(spacing: NPSpacing.medium) {
                            Image(systemName: "note.text").foregroundStyle(NPColors.brand)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title.isEmpty ? localized("notes.default_title") : note.title)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                                Text(localizedFormat("note.version", String(note.versionNo))).npCaption()
                            }
                            Spacer()
                            Button {
                                guard let unit = model.learningUnits.first(where: { $0.id == model.selectedLearningUnitId }) else {
                                    return
                                }
                                onOpenNote(StudyNoteListItem(learningUnit: unit, note: note))
                            } label: {
                                Image(systemName: "eye")
                            }
                                .buttonStyle(NPSecondaryButtonStyle())
                                .accessibilityLabel(localized("note.preview"))
                        }
                        .modifier(NPCardModifier())
                    }
                }
            }
        }
        .accessibilityIdentifier("learningUnitsSection")
        .sheet(isPresented: $model.isLearningUnitMergePresented) {
            LearningUnitMergeSheet(model: model)
        }
    }
}

private struct StudyNoteGenerationSheet: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localized("note.generation.strategy"))) {
                    Toggle(localized("note.strategy.override"), isOn: $model.studyNoteGenerationUsesOverride)
                    if model.studyNoteGenerationUsesOverride {
                        Picker(localized("note.preferences.content"), selection: $model.studyNoteGenerationContentLevel) {
                            ForEach(NoteContentEditLevel.supportedValues) { level in
                                Text(noteContentEditLevelLabel(level)).tag(level)
                            }
                            if !NoteContentEditLevel.supportedValues.contains(model.studyNoteGenerationContentLevel) {
                                Text(model.studyNoteGenerationContentLevel.rawValue).tag(model.studyNoteGenerationContentLevel)
                            }
                        }
                        Picker(localized("note.preferences.layout"), selection: $model.studyNoteGenerationLayoutLevel) {
                            ForEach(NoteLayoutEditLevel.supportedValues) { level in
                                Text(noteLayoutEditLevelLabel(level)).tag(level)
                            }
                            if !NoteLayoutEditLevel.supportedValues.contains(model.studyNoteGenerationLayoutLevel) {
                                Text(model.studyNoteGenerationLayoutLevel.rawValue).tag(model.studyNoteGenerationLayoutLevel)
                            }
                        }
                    }
                }
                Section {
                    Toggle(localized("note.generation.force"), isOn: $model.studyNoteGenerationForceReprocess)
                    Text(localized("note.generation.force_help")).npCaption()
                }
            }
            .navigationTitle(localized("note.generation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.cancel")) { model.isStudyNoteGenerationPresented = false }
                        .disabled(model.isStudyNoteGenerating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("note.generate")) { model.generateStudyNote() }
                        .disabled(model.isStudyNoteGenerating)
                        .accessibilityIdentifier("confirmGenerateStudyNoteButton")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct LearningUnitMergeSheet: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: NPSpacing.item) {
                    Text(localized("merge.help"))
                        .npBody()
                        .foregroundStyle(NPColors.textSecondary)

                    NPSection {
                        VStack(alignment: .leading, spacing: NPSpacing.small) {
                            SectionLabel(localized("merge.target"))
                            Picker(localized("merge.target"), selection: Binding(
                                get: { model.mergeTargetLearningUnitId },
                                set: { model.setLearningUnitMergeTarget($0) }
                            )) {
                                ForEach(model.learningUnits.filter { $0.mergedIntoId == nil }) { unit in
                                    Text(unit.title).tag(unit.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Text(localizedFormat("merge.sources_count", String(model.mergeSourceLearningUnitIds.count)))
                        .npSubheading()
                    ForEach(model.learningUnits.filter { $0.id != model.mergeTargetLearningUnitId && $0.mergedIntoId == nil }) { unit in
                        Button {
                            model.toggleLearningUnitMergeSource(unit.id)
                        } label: {
                            HStack(spacing: NPSpacing.medium) {
                                Image(systemName: model.mergeSourceLearningUnitIds.contains(unit.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.mergeSourceLearningUnitIds.contains(unit.id) ? NPColors.brand : NPColors.textSecondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(unit.title).npSubheading()
                                    let details = [unit.subject, unit.gradeLevel, unit.topic].compactMap { value -> String? in
                                        guard let value else { return nil }
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        return trimmed.isEmpty ? nil : trimmed
                                    }
                                    if !details.isEmpty { Text(details.joined(separator: " · ")).npCaption() }
                                }
                                Spacer()
                            }
                            .modifier(NPCardModifier())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mergeSource-\(unit.id)")
                    }
                }
                .padding(NPSpacing.outer)
            }
            .navigationTitle(localized("merge.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.cancel")) { model.isLearningUnitMergePresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("merge.continue")) { model.requestLearningUnitMergeConfirmation() }
                        .disabled(model.mergeSourceLearningUnitIds.isEmpty || model.isLearningUnitMerging)
                        .accessibilityIdentifier("mergeContinueButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("learningUnitMergeSheet")
        .alert(localized("merge.confirm.title"), isPresented: $model.isLearningUnitMergeConfirmationPresented) {
            Button(localized("common.cancel"), role: .cancel) {}
            Button(localized("merge.confirm.action"), role: .destructive) {
                model.confirmLearningUnitMerge()
            }
        } message: {
            Text(localized("merge.confirm.message"))
        }
    }
}

private struct FlashcardsSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            LearningSectionHeader(
                title: localized("flashcards.title"),
                subtitle: localized("flashcards.subtitle"),
                isLoading: model.isFlashcardsLoading
            ) {
                model.ensureFlashcardsLoaded(force: true)
            }

            if model.learningUnits.isEmpty {
                NPEmptyState(
                    systemImage: "rectangle.stack",
                    title: localized("flashcards.no_units.title"),
                    message: localized("flashcards.no_units.message")
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: NPSpacing.medium)],
                    spacing: NPSpacing.small
                ) {
                    Menu {
                        ForEach(model.learningUnits) { unit in
                            Button {
                                model.selectFlashcardLearningUnit(unit.id)
                            } label: {
                                if unit.id == model.selectedFlashcardLearningUnitId {
                                    Label(unit.title, systemImage: "checkmark")
                                } else {
                                    Text(unit.title)
                                }
                            }
                        }
                    } label: {
                        flashcardPickerLabel(
                            title: localized("flashcards.learning_unit"),
                            value: model.learningUnits.first(where: { $0.id == model.selectedFlashcardLearningUnitId })?.title
                                ?? localized("flashcards.learning_unit")
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("flashcardLearningUnitPicker")

                    Menu {
                        if model.flashcardDecks.isEmpty {
                            Text(localized("flashcards.empty.title"))
                        } else {
                            ForEach(model.flashcardDecks) { deck in
                                Button {
                                    model.selectFlashcardDeck(deck.id)
                                } label: {
                                    let title = localizedFormat("flashcards.deck_version", String(deck.versionNo))
                                    if deck.id == model.selectedFlashcardDeckId {
                                        Label(title, systemImage: "checkmark")
                                    } else {
                                        Text(title)
                                    }
                                }
                            }
                        }
                    } label: {
                        flashcardPickerLabel(
                            title: localized("flashcards.deck"),
                            value: selectedFlashcardDeckLabel
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .disabled(model.flashcardDecks.isEmpty)
                    .accessibilityIdentifier("flashcardDeckPicker")
                }

                if model.isFlashcardsLoading && model.flashcardDeckDetail == nil {
                    ProgressView(localized("flashcards.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if let error = model.flashcardError {
                    VStack(spacing: NPSpacing.small) {
                        NPEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: localized("flashcards.load_failed"),
                            message: error
                        )
                        Button(localized("common.retry")) {
                            model.ensureFlashcardsLoaded(force: true)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                } else if let card = model.currentFlashcard,
                          let detail = model.flashcardDeckDetail {
                    flashcard(card, detail: detail)
                    priorityDetails(card)
                } else {
                    NPEmptyState(
                        systemImage: "rectangle.stack",
                        title: localized("flashcards.empty.title"),
                        message: localized("flashcards.empty.message")
                    )
                }
            }
        }
        .accessibilityIdentifier("flashcardsSection")
    }

    private func flashcard(_ card: Flashcard, detail: FlashcardDeckDetail) -> some View {
        VStack(spacing: NPSpacing.item) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    model.flipCurrentFlashcard()
                }
            } label: {
                VStack(spacing: 14) {
                    Text(model.isFlashcardShowingBack ? localized("flashcards.back") : localized("flashcards.front"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.brand)
                    LightweightMarkdownText(
                        markdown: model.isFlashcardShowingBack ? card.back : card.front,
                        color: NPColors.textPrimary,
                        horizontalAlignment: .center,
                        textAlignment: .center,
                        paragraphFont: .title3.weight(.medium)
                    )
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localized("flashcards.tap_to_flip"))
                        .npCaption()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(NPSpacing.card)
                .modifier(NPCardModifier())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flashcardCard")

            if let reviewHint = card.reviewHint {
                flashcardReviewHint(reviewHint)
            }

            HStack(spacing: NPSpacing.item) {
                Button { model.showPreviousFlashcard() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.flashcardIndex == 0)
                .accessibilityLabel(localized("flashcards.previous"))
                .accessibilityIdentifier("flashcardPreviousButton")

                Spacer()
                Text(localizedFormat(
                    "flashcards.progress",
                    String(model.flashcardIndex + 1),
                    String(detail.cards.count)
                ))
                .npCaption()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                Spacer()

                Button { model.showNextFlashcard() } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.flashcardIndex + 1 >= detail.cards.count)
                .accessibilityLabel(localized("flashcards.next"))
                .accessibilityIdentifier("flashcardNextButton")
            }
        }
    }

    private func flashcardReviewHint(_ hint: FlashcardReviewHint) -> some View {
        let appearance = flashcardHintAppearance(hint.primary.tone)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: appearance.icon)
                    .foregroundStyle(appearance.color)
                    .frame(width: 24, height: 24)
                Text(flashcardHintText(hint.primary))
                    .npBody()
                    .foregroundStyle(NPColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if !hint.badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(hint.badges.prefix(3).enumerated()), id: \.offset) { _, badge in
                            let badgeAppearance = flashcardHintAppearance(badge.tone)
                            Label(flashcardHintText(badge), systemImage: badgeAppearance.icon)
                                .font(.caption)
                                .foregroundStyle(badgeAppearance.color)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background(badgeAppearance.color.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(NPSpacing.medium)
        .background(NPColors.brandLight.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous)
                .stroke(appearance.color.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("flashcardReviewHint")
    }

    private func flashcardHintAppearance(_ tone: String) -> (icon: String, color: Color) {
        switch tone {
        case "positive": return ("checkmark.circle.fill", NPColors.successText)
        case "warning": return ("exclamationmark.circle.fill", NPColors.warning)
        default: return ("lightbulb.fill", NPColors.brand)
        }
    }

    private var selectedFlashcardDeckLabel: String {
        guard let selectedId = model.selectedFlashcardDeckId,
              let deck = model.flashcardDecks.first(where: { $0.id == selectedId }) else {
            return localized("flashcards.deck")
        }
        return localizedFormat("flashcards.deck_version", String(deck.versionNo))
    }

    private func flashcardPickerLabel(title: String, value: String) -> some View {
        HStack(spacing: NPSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(NPColors.textTertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NPColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: NPSpacing.xs)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NPColors.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, NPSpacing.medium)
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
        .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
    }

    private func priorityDetails(_ card: Flashcard) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.priorityFactors.keys.sorted(), id: \.self) { key in
                    if let value = card.priorityFactors[key] {
                        HStack(alignment: .firstTextBaseline) {
                            Text(priorityFactorLabel(key))
                                .foregroundStyle(NPColors.textSecondary)
                            Spacer(minLength: 12)
                            Text(value.displayString)
                                .foregroundStyle(NPColors.textPrimary)
                        }
                        .npBody()
                    }
                }
                if let difficulty = card.difficulty?.trimmingCharacters(in: .whitespacesAndNewlines), !difficulty.isEmpty {
                    HStack {
                        Text(localized("flashcards.difficulty"))
                            .foregroundStyle(NPColors.textSecondary)
                        Spacer()
                        Text(difficulty)
                    }
                    .npBody()
                }
            }
            .padding(.top, 10)
        } label: {
            Text(localizedFormat("flashcards.priority", String(format: "%.4f", card.priorityScore)))
                .font(.body.weight(.medium))
                .foregroundStyle(NPColors.textPrimary)
        }
        .modifier(NPCardModifier())
    }

    private func priorityFactorLabel(_ key: String) -> String {
        switch key {
        case "base": return localized("flashcards.factor.base")
        case "error_pressure": return localized("flashcards.factor.error_pressure")
        case "success_pressure": return localized("flashcards.factor.success_pressure")
        case "recent_correct_streak": return localized("flashcards.factor.correct_streak")
        default: return key
        }
    }
}

private struct LearningSectionHeader: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    let onRefresh: () -> Void
    @Environment(\.sizeCategory) private var sizeCategory

    @ViewBuilder
    var body: some View {
        if sizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(localized(title)).npHeading()
                    Spacer(minLength: 12)
                    refreshButton
                }
                Text(localized(subtitle))
                    .npCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(title)).npHeading()
                    Text(localized(subtitle)).npCaption()
                }
                Spacer()
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
            .buttonStyle(NPToolbarIconButtonStyle())
            .disabled(isLoading)
            .accessibilityLabel(localizedFormat("accessibility.refresh_named", localized(title)))
    }
}

private struct KnowledgeSearchSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("knowledge.title")).npHeading()
                Text(localized("knowledge.subtitle")).npCaption()
            }

            NPSection {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(title: "knowledge.query") {
                        TextField(localized("knowledge.query_placeholder"), text: $model.knowledgeQuery)
                            .accessibilityIdentifier("knowledgeQueryField")
                    }
                    Picker(localized("knowledge.learning_unit"), selection: $model.knowledgeLearningUnitId) {
                        Text(localized("knowledge.all_units")).tag("")
                        ForEach(model.learningUnits) { unit in Text(unit.title).tag(unit.id) }
                    }
                    .pickerStyle(.menu)
                    LabeledField(title: "knowledge.subject_optional") {
                        TextField(localized("knowledge.subject_placeholder"), text: $model.knowledgeSubject)
                    }
                    Stepper(
                        localizedFormat("knowledge.limit", String(model.knowledgeLimit)),
                        value: $model.knowledgeLimit,
                        in: 1...20
                    )
                    Button { model.searchKnowledge() } label: {
                        Label(localized("knowledge.search"), systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isKnowledgeSearching || model.knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("knowledgeSearchButton")
                }
            }

            if model.isKnowledgeSearching {
                ProgressView(localized("knowledge.searching")).frame(maxWidth: .infinity).padding(.vertical, NPSpacing.large)
            } else if model.hasSearchedKnowledge && model.knowledgeResults.isEmpty {
                NPEmptyState(systemImage: "magnifyingglass", title: localized("knowledge.empty.title"), message: localized("knowledge.empty.message"))
            } else if !model.knowledgeResults.isEmpty {
                HStack {
                    Text(localized("knowledge.results")).npSubheading()
                    Spacer()
                    Text(localizedFormat("knowledge.results_count", String(model.knowledgeResults.count))).npCaption()
                }
                ForEach(model.knowledgeResults) { item in
                    NPSection {
                        VStack(alignment: .leading, spacing: NPSpacing.small) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(documentDisplayName(item.documentId) ?? item.metadataTitle ?? item.sourceType ?? localized("knowledge.snippet"))
                                    .npSubheading()
                                    .foregroundStyle(NPColors.textPrimary)
                                    .lineLimit(2)
                                Spacer()
                                Text(String(format: "%.4f", item.score))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(NPColors.textSecondary)
                            }
                            Text(item.content).npBody().textSelection(.enabled).foregroundStyle(NPColors.textPrimary)
                            let details = [
                                item.subject,
                                item.gradeLevel,
                                item.sourceType,
                                item.pageReferences.map { localizedFormat("knowledge.page", $0) }
                            ].compactMap { $0 }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · ")).npCaption()
                            }
                            if item.documentId != nil {
                                Button { model.previewKnowledgeSource(item) } label: {
                                    Label(localized("knowledge.preview_source"), systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(NPSecondaryButtonStyle())
                                .disabled(model.isBusy)
                            }
                        }
                    }
                }
            }
        }
    }

    private func documentDisplayName(_ documentId: String?) -> String? {
        guard let documentId else { return nil }
        return model.documents.first(where: { $0.id == documentId })?.displayRemark
            ?? model.gradingDocuments.first(where: { $0.id == documentId })?.displayRemark
    }
}

private struct HomeworkGradingSection: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isCreatingHomework = false
    @State private var selectedReferenceDocumentId = ""
    @State private var isGradingHistoryExpanded = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("grading.title")).npHeading()
                    Text(localized("grading.subtitle")).npCaption()
                }
                Spacer()
                Button { isCreatingHomework = true } label: { Image(systemName: "plus") }
                    .buttonStyle(NPToolbarIconButtonStyle())
                    .disabled(model.homeworkDocumentCandidates.isEmpty)
                    .accessibilityLabel(localized("grading.create_homework"))
                Button { model.loadLearningDashboard(allowOfflineNetwork: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(NPToolbarIconButtonStyle())
                    .disabled(model.isHomeworkLoading)
                    .accessibilityLabel(localized("accessibility.refresh_homework"))
            }

            if model.isHomeworkLoading && model.homeworks.isEmpty {
                ProgressView(localized("grading.loading")).frame(maxWidth: .infinity).padding(.vertical, NPSpacing.xl)
            } else if model.homeworks.isEmpty {
                NPEmptyState(
                    systemImage: "checklist",
                    title: localized("grading.empty.title"),
                    message: localized(model.homeworkDocumentCandidates.isEmpty ? "grading.empty.upload_first" : "grading.empty.create")
                )
            } else {
                Picker(localized("grading.current_homework"), selection: Binding(
                    get: { model.selectedHomeworkId ?? "" },
                    set: { if !$0.isEmpty { model.selectHomework($0) } }
                )) {
                    Text(localized("grading.select_homework")).tag("")
                    ForEach(model.homeworks) { homework in Text(homework.title).tag(homework.id) }
                }
                .pickerStyle(.menu)
                .disabled(model.isHomeworkLoading)
                .accessibilityIdentifier("homeworkPicker")
            }

            if let homework = model.selectedHomework {
                homeworkEditor(homework)
            }
        }
        .accessibilityIdentifier("homeworkGradingSection")
        .sheet(isPresented: $isCreatingHomework) {
            HomeworkCreateSheet(model: model, isPresented: $isCreatingHomework)
        }
        .onChange(of: model.selectedHomeworkId) { _ in
            isGradingHistoryExpanded = false
        }
    }

    private func homeworkEditor(_ homework: HomeworkItem) -> some View {
        VStack(alignment: .leading, spacing: NPSpacing.item) {
            NPSection {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(homework.title).npSubheading()
                            Text([statusLabel(homework.status), homework.dueAt.map(compactDateTime)].compactMap { $0 }.joined(separator: " · "))
                                .npCaption()
                        }
                        Spacer()
                        NPStatusChip(text: statusLabel(homework.status), variant: statusChipVariant(homework.status))
                    }
                    SectionLabel(localized("grading.rubric"))
                    TextEditor(text: $model.homeworkRubricText)
                        .frame(height: 92)
                        .padding(6)
                        .npInputField()
                    LabeledField(title: "grading.max_score") {
                        TextField("100", text: $model.homeworkMaxScoreText)
                            .keyboardType(.decimalPad)
                    }
                    if model.isGradingConfigDirty {
                        Label(localized("grading.unsaved"), systemImage: "exclamationmark.circle")
                            .npCaption()
                            .foregroundStyle(NPColors.warning)
                            .accessibilityIdentifier("gradingConfigUnsavedLabel")
                    }
                    Button { model.saveGradingConfig() } label: {
                        Label(localized("grading.save_config"), systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isHomeworkLoading || !model.isGradingConfigDirty)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(localized("grading.references")).npSubheading()
                if model.homeworkReferences.isEmpty {
                    Text(localized("grading.no_references")).npBody().foregroundStyle(NPColors.textSecondary)
                } else {
                    ForEach(model.homeworkReferences) { reference in
                        HStack(spacing: 10) {
                            Image(systemName: reference.referenceType == "answer_key" ? "checkmark.square" : "list.clipboard")
                                .foregroundStyle(NPColors.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(referenceDocumentName(reference.documentId))
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                                Text(documentKindLabel(reference.referenceType)).npCaption()
                            }
                            Spacer()
                            Button(role: .destructive) { model.deleteHomeworkReference(reference) } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                                .disabled(model.isHomeworkLoading)
                                .accessibilityLabel(localized("accessibility.remove_reference"))
                        }
                        .modifier(NPCardModifier())
                    }
                }
                if model.referenceDocumentCandidates.isEmpty {
                    Text(localized("grading.no_reference_documents"))
                        .npCaption()
                } else {
                    Picker(localized("grading.add_reference"), selection: $selectedReferenceDocumentId) {
                        Text(localized("grading.select_reference")).tag("")
                        ForEach(model.referenceDocumentCandidates) { document in
                            Text("\(documentKindLabel(document.documentKind)) · \(document.displayRemark)").tag(document.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        model.addHomeworkReference(documentId: selectedReferenceDocumentId) {
                            selectedReferenceDocumentId = ""
                        }
                    } label: {
                        Label(localized("grading.add_reference_action"), systemImage: "plus")
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(selectedReferenceDocumentId.isEmpty || model.isHomeworkLoading)
                }
            }

            gradingResultSection
            Button { model.gradeSelectedHomework() } label: {
                Label(localized("grading.start"), systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NPPrimaryButtonStyle())
            .disabled(model.isHomeworkLoading)
            .accessibilityIdentifier("gradeHomeworkButton")
        }
    }

    private var gradingResultSection: some View {
        VStack(alignment: .leading, spacing: NPSpacing.item) {
            NPSection {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("grading.latest_result")).npSubheading()
                    if let result = model.latestGradingResult {
                        gradingResultContent(result, isLatest: true)
                    } else {
                        Label(localized("grading.no_result"), systemImage: "chart.bar.doc.horizontal")
                            .npBody()
                            .foregroundStyle(NPColors.textSecondary)
                            .accessibilityIdentifier("gradingLatestResultEmpty")
                    }
                }
            }
            .accessibilityIdentifier("gradingLatestResult")

            DisclosureGroup(isExpanded: $isGradingHistoryExpanded) {
                gradingHistoryContent
                    .padding(.top, NPSpacing.small)
            } label: {
                Label(localized("grading.history"), systemImage: "clock.arrow.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NPColors.textPrimary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, NPSpacing.card)
            .padding(.vertical, 4)
            .modifier(NPCardModifier())
            .accessibilityIdentifier("gradingHistoryDisclosure")
            .onChange(of: isGradingHistoryExpanded) { isExpanded in
                if isExpanded {
                    model.loadGradingHistory()
                }
            }
        }
    }

    @ViewBuilder
    private var gradingHistoryContent: some View {
        VStack(alignment: .leading, spacing: NPSpacing.small) {
            if model.isGradingHistoryLoading {
                HStack(spacing: NPSpacing.small) {
                    ProgressView()
                    Text(localized("grading.history_loading")).npCaption()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, NPSpacing.small)
            }
            if let error = model.gradingHistoryError {
                Text(error)
                    .npCaption()
                    .foregroundStyle(NPColors.destructive)
                Button {
                    model.loadGradingHistory(force: true)
                } label: {
                    Label(localized("grading.history_retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .accessibilityIdentifier("gradingHistoryRetryButton")
            }
            if !model.isGradingHistoryLoading || model.isSelectedGradingHistoryLoaded {
                if model.gradingResults.isEmpty,
                   model.gradingHistoryError == nil {
                    Text(localized("grading.history_empty"))
                        .npCaption()
                        .foregroundStyle(NPColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, NPSpacing.small)
                        .accessibilityIdentifier("gradingHistoryEmpty")
                } else if !model.gradingResults.isEmpty {
                    LazyVStack(alignment: .leading, spacing: NPSpacing.small) {
                        ForEach(model.gradingResults) { result in
                            gradingResultContent(result, isLatest: false)
                                .padding(NPSpacing.card)
                                .background(NPColors.background.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                                        .stroke(NPColors.border, lineWidth: 1)
                                }
                                .accessibilityIdentifier("gradingHistoryResult.\(result.id)")
                        }
                    }
                }
            }
        }
    }

    private func gradingResultContent(_ result: GradingResult, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: NPSpacing.small) {
                Text(gradingScoreText(result))
                    .font(isLatest ? .title2.weight(.semibold) : .headline)
                    .foregroundStyle(NPColors.textPrimary)
                Spacer(minLength: 8)
                NPStatusChip(
                    text: result.gradingMode == "official"
                        ? localized("grading.mode.official")
                        : localized("grading.mode.diagnostic"),
                    variant: result.gradingMode == "official" ? .brand : .warning
                )
            }
            if let confidence = result.confidence {
                Text(localizedFormat("grading.confidence", String(format: "%.4f", confidence)))
                    .npCaption()
            }
            if let questionId = nonBlank(result.questionId) {
                Text(localizedFormat("grading.question_id", questionId))
                    .npCaption()
                    .lineLimit(1)
            }
            if let feedback = nonBlank(result.feedback) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("grading.feedback"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.textSecondary)
                    Text(feedback)
                        .npBody()
                        .textSelection(.enabled)
                }
            }
            if !result.createdAt.isEmpty {
                Text(localizedFormat("grading.result_time", compactDateTime(result.createdAt)))
                    .npCaption()
            }
        }
    }

    private func gradingScoreText(_ result: GradingResult) -> String {
        guard let score = result.score, let maxScore = result.maxScore else {
            return localized("grading.score_unavailable")
        }
        return localizedFormat("grading.score_value", formattedScore(score), formattedScore(maxScore))
    }

    private func formattedScore(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func referenceDocumentName(_ documentId: String) -> String {
        model.gradingDocuments.first(where: { $0.id == documentId })?.displayRemark ?? documentId
    }
}

private struct HomeworkCreateSheet: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var isPresented: Bool
    @State private var documentId = ""
    @State private var title = ""
    @State private var description = ""
    @State private var hasDueDate = false
    @State private var dueAt = Date()
    @State private var rubricText = ""
    @State private var maxScoreText = "100"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localized("grading.homework_document"))) {
                    Picker(localized("grading.document"), selection: $documentId) {
                        Text(localized("common.select")).tag("")
                        ForEach(model.homeworkDocumentCandidates) { document in
                            Text(document.displayRemark).tag(document.id)
                        }
                    }
                    .onChange(of: documentId) { newValue in
                        if title.isEmpty, let document = model.homeworkDocumentCandidates.first(where: { $0.id == newValue }) {
                            title = document.title ?? document.originalFilename
                        }
                    }
                    TextField(localized("grading.homework_title"), text: $title)
                    TextField(localized("grading.description_optional"), text: $description)
                }
                Section(header: Text(localized("grading.due_date"))) {
                    Toggle(localized("grading.set_due_date"), isOn: $hasDueDate)
                    if hasDueDate { DatePicker(localized("grading.due_date"), selection: $dueAt) }
                }
                Section(header: Text(localized("grading.config"))) {
                    TextEditor(text: $rubricText).frame(height: 90)
                    TextField(localized("grading.max_score"), text: $maxScoreText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle(localized("grading.create_homework"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("common.cancel")) { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("common.create")) {
                        _ = model.createHomework(
                            documentId: documentId,
                            title: title,
                            description: description,
                            dueAt: hasDueDate ? dueAt : nil,
                            rubricText: rubricText,
                            maxScoreText: maxScoreText,
                            onCommitted: { isPresented = false }
                        )
                    }
                    .disabled(documentId.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if documentId.isEmpty, let document = model.homeworkDocumentCandidates.first {
                documentId = document.id
                title = document.title ?? document.originalFilename
            }
        }
        .accessibilityIdentifier("homeworkCreateSheet")
    }
}

private struct LearningEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(NPColors.textSecondary.opacity(0.5))
            Text(localized("review.units.empty.title"))
                .npSubheading()
            Text(localized("review.units.empty.message"))
                .npCaption()
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.vertical, NPSpacing.xxxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OpenClaw Message Bubble

private struct OpenClawMessageBubble: View {
    let message: OpenClawChatMessage
    let onCopy: () -> Void
    let onSelectText: () -> Void
    let onPreviewAttachment: (OpenClawChatAttachment) -> Void
    let onEdit: (() -> Void)?
    @State private var isReasoningExpanded = false

    private var displayedContent: String {
        message.content
    }

    private var processingSteps: [ChatProcessingStep] {
        guard message.status == .sending else { return [] }
        let eventTypes = Set(message.events.map(\.eventType))
        var steps: [ChatProcessingStep] = []

        if eventTypes.contains("openclaw_prepare") {
            steps.append(ChatProcessingStep(id: "prepare", titleKey: "chat.process.preparing_context"))
        }
        if eventTypes.contains("knowledge_retrieved") {
            steps.append(ChatProcessingStep(id: "knowledge", titleKey: "chat.process.knowledge_retrieved"))
        } else if eventTypes.contains("knowledge_retrieval_skipped") {
            steps.append(ChatProcessingStep(id: "knowledge", titleKey: "chat.process.knowledge_skipped"))
        }
        if eventTypes.contains("openclaw_run") || eventTypes.contains("chat_stream_started") {
            steps.append(ChatProcessingStep(id: "model", titleKey: "chat.process.model_started"))
        }
        if eventTypes.contains("chat_answer_delta") {
            steps.append(ChatProcessingStep(id: "answer", titleKey: "chat.process.answer_streaming"))
        }
        return steps
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                if message.role == .assistant {
                    Label(localized("chat.assistant_name"), systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NPColors.brand)
                }
                if message.role == .assistant,
                   !processingSteps.isEmpty || !message.reasoningContent.isEmpty || message.reasoningUnavailable {
                    DisclosureGroup(isExpanded: $isReasoningExpanded) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(processingSteps) { step in
                                Label {
                                    Text(localized(step.titleKey))
                                        .font(.caption)
                                } icon: {
                                    Image(systemName: step.id == processingSteps.last?.id && message.status == .sending
                                          ? "circle.dotted"
                                          : "checkmark.circle.fill")
                                        .foregroundStyle(step.id == processingSteps.last?.id && message.status == .sending
                                                         ? NPColors.brand
                                                         : NPColors.successText)
                                }
                            }

                            if !message.reasoningContent.isEmpty {
                                Divider()
                                Text(message.reasoningContent)
                                    .font(.subheadline)
                                    .foregroundStyle(NPColors.textSecondary)
                                    .textSelection(.disabled)
                            }

                            if message.reasoningUnavailable {
                                Label(localized("chat.reasoning_unavailable_detail"), systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(NPColors.textSecondary)
                            }
                        }
                    } label: {
                        Label(localized("chat.process_summary"), systemImage: "brain")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NPColors.textSecondary)
                    }
                    .accessibilityIdentifier("chatReasoningDisclosure.\(message.id)")
                }
                Group {
                    if message.role == .assistant {
                        switch message.status {
                        case .sending:
                            VStack(alignment: .leading, spacing: NPSpacing.small) {
                                SmoothStreamingText(target: message.streamingContent)
                                if message.streamingContent.isEmpty {
                                    ProgressView(value: Double(message.progress ?? 0), total: 100)
                                }
                            }
                        case .stopped:
                            VStack(alignment: .leading, spacing: NPSpacing.small) {
                                if !message.streamingContent.isEmpty {
                                    LightweightMarkdownText(
                                    markdown: message.streamingContent,
                                    color: foregroundColor,
                                    expandsHorizontally: false,
                                    allowsTextSelection: false
                                    )
                                } else if !displayedContent.isEmpty,
                                          displayedContent != "Thinking...",
                                          displayedContent != localized("chat.thinking") {
                                    LightweightMarkdownText(
                                        markdown: displayedContent,
                                        color: foregroundColor,
                                        expandsHorizontally: false,
                                        allowsTextSelection: false
                                    )
                                }
                                Label(localized("chat.stopped"), systemImage: "stop.circle")
                                    .npCaption()
                                    .foregroundStyle(NPColors.warning)
                            }
                        default:
                            LightweightMarkdownText(
                                markdown: displayedContent,
                                color: foregroundColor,
                                expandsHorizontally: false,
                                allowsTextSelection: false
                            )
                        }
                    } else {
                        Text(displayedContent)
                            .foregroundStyle(foregroundColor)
                            .textSelection(.disabled)
                    }
                }
                if message.streamTruncated {
                    Label(localized("chat.stream_truncated"), systemImage: "exclamationmark.triangle")
                        .npCaption()
                        .foregroundStyle(NPColors.warning)
                }
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NPSpacing.small) {
                            ForEach(message.attachments) { attachment in
                                OpenClawMessageAttachmentView(
                                    attachment: attachment,
                                    onPreview: { onPreviewAttachment(attachment) }
                                )
                            }
                        }
                    }
                    .accessibilityIdentifier("openClawMessageAttachments")
                }
                if let errorEvent = message.events.last(where: { $0.level == "error" }) {
                    Text(localizedFormat("chat.error_event", errorEvent.message))
                        .npCaption()
                        .foregroundStyle(NPColors.destructive)
                        .lineLimit(3)
                }
                if message.sourceStatus == "partially_unavailable" {
                    Label(localized("chat.sources.partially_removed"), systemImage: "exclamationmark.triangle")
                        .npCaption()
                        .foregroundStyle(NPColors.warning)
                } else if message.sourceStatus == "unavailable" {
                    Label(localized("chat.sources.removed"), systemImage: "exclamationmark.triangle.fill")
                        .npCaption()
                        .foregroundStyle(NPColors.warning)
                } else if !message.citations.isEmpty {
                    Text(localizedFormat("chat.citing_sources", String(message.citations.count)))
                        .npCaption()
                }
                if message.role == .assistant,
                   let modelId = message.modelId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !modelId.isEmpty {
                    Text(localizedFormat("chat.model_used", modelId))
                        .npCaption()
                        .foregroundStyle(NPColors.textSecondary)
                        .accessibilityIdentifier("chatModelLabel")
                }
            }
            .padding(NPSpacing.card)
            .frame(maxWidth: message.role == .system ? .infinity : nil, alignment: .leading)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
            .overlay {
                if message.role != .user {
                    RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                        .stroke(NPColors.border, lineWidth: 1)
                    }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chatMessageBubble.\(message.id)")
            .modifier(MessageContextMenuModifier(
                enabled: message.role != .system,
                copyTitle: localized("chat.copy.message"),
                selectTextTitle: localized("chat.select_text.action"),
                editTitle: onEdit == nil ? nil : localized("chat.revision.action"),
                onCopy: onCopy,
                onSelectText: onSelectText,
                onEdit: onEdit
            ))
            .modifier(MessageBubbleAccessibilityActions(
                copyTitle: localized("chat.copy.message"),
                selectTextTitle: localized("chat.select_text.action"),
                editTitle: localized("chat.revision.action"),
                onCopy: message.role == .system ? nil : onCopy,
                onSelectText: message.role == .system ? nil : onSelectText,
                onEdit: message.role == .user ? onEdit : nil
            ))
            .frame(
                maxWidth: message.role == .system ? .infinity : 320,
                alignment: message.role == .user ? .trailing : .leading
            )
            if message.role != .user {
                Spacer(minLength: 28)
            }
        }
        .onAppear {
            isReasoningExpanded = message.status == .sending
        }
        .onChange(of: message.status) { status in
            withAnimation(.easeInOut(duration: 0.18)) {
                isReasoningExpanded = status == .sending
            }
        }
    }

    private var bubbleBackground: Color {
        if message.status == .error {
            return NPColors.destructive.opacity(0.1)
        }
        switch message.role {
        case .user:
            return NPColors.aiUserBubble
        case .system, .assistant:
            return NPColors.surface
        }
    }

    private var foregroundColor: Color {
        if message.role == .user {
            return NPColors.textPrimary
        }
        return NPColors.textPrimary
    }

}

private struct MessageContextMenuModifier: ViewModifier {
    let enabled: Bool
    let copyTitle: String
    let selectTextTitle: String
    let editTitle: String?
    let onCopy: () -> Void
    let onSelectText: () -> Void
    let onEdit: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                if let editTitle, let onEdit {
                    Button(action: onEdit) {
                        Label(editTitle, systemImage: "pencil")
                    }
                }
                Button(action: onCopy) {
                    Label(copyTitle, systemImage: "doc.on.doc")
                }
                Button(action: onSelectText) {
                    Label(selectTextTitle, systemImage: "textformat")
                }
                .accessibilityIdentifier("chatSelectTextAction")
            }
        } else {
            content
        }
    }
}

private struct MessageBubbleAccessibilityActions: ViewModifier {
    let copyTitle: String
    let selectTextTitle: String
    let editTitle: String
    let onCopy: (() -> Void)?
    let onSelectText: (() -> Void)?
    let onEdit: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onCopy {
            if let onEdit {
                content
                    .accessibilityAction(named: Text(copyTitle), onCopy)
                    .accessibilityAction(named: Text(selectTextTitle), onSelectText ?? {})
                    .accessibilityAction(named: Text(editTitle), onEdit)
            } else {
                content
                    .accessibilityAction(named: Text(copyTitle), onCopy)
                    .accessibilityAction(named: Text(selectTextTitle), onSelectText ?? {})
            }
        } else {
            content
        }
    }
}

private struct ChatMessageTextSelectionScreen: View {
    let message: OpenClawChatMessage
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            FullScreenSelectableTextView(
                text: selectionText,
                rendersMarkdown: message.role == .assistant
            )
            .background(NPColors.background)
            .navigationTitle(localized("chat.select_text.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.done"), action: onDone)
                        .accessibilityIdentifier("chatTextSelectionDoneButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("chatTextSelectionScreen")
    }

    private var selectionText: String {
        if message.role == .assistant,
           !message.streamingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           message.status == .sending || message.status == .stopped {
            return message.streamingContent
        }
        return message.content
    }
}

private struct FullScreenSelectableTextView: UIViewRepresentable {
    let text: String
    let rendersMarkdown: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 32, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "chatSelectableFullScreenText"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let attributedText = messageSelectionAttributedText(text, rendersMarkdown: rendersMarkdown)
        guard textView.attributedText != attributedText else { return }
        textView.attributedText = attributedText
    }
}

private func messageSelectionAttributedText(_ text: String, rendersMarkdown: Bool) -> NSAttributedString {
    let displayText = rendersMarkdown ? markdownSelectionDisplayText(text) : text
    let attributed: NSMutableAttributedString
    if rendersMarkdown,
       let parsed = try? AttributedString(
           markdown: displayText,
           options: AttributedString.MarkdownParsingOptions(
               interpretedSyntax: .inlineOnlyPreservingWhitespace,
               failurePolicy: .returnPartiallyParsedIfPossible
           )
       ) {
        attributed = NSMutableAttributedString(parsed)
    } else {
        attributed = NSMutableAttributedString(string: displayText)
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
    attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
        if value == nil {
            attributed.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: range)
        }
    }
    return attributed
}

private func markdownSelectionDisplayText(_ markdown: String) -> String {
    markdown
        .components(separatedBy: .newlines)
        .compactMap { line -> String? in
            let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
            var content = String(line.dropFirst(leadingWhitespace.count))
            if content.hasPrefix("```") {
                return nil
            }
            for level in stride(from: 6, through: 1, by: -1) {
                let prefix = String(repeating: "#", count: level) + " "
                if content.hasPrefix(prefix) {
                    content.removeFirst(prefix.count)
                    break
                }
            }
            if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") {
                content = "• " + content.dropFirst(2)
            } else if content.hasPrefix("> ") {
                content = "│ " + content.dropFirst(2)
            }
            return String(leadingWhitespace) + content
        }
        .joined(separator: "\n")
}

private struct ChatProcessingStep: Identifiable {
    let id: String
    let titleKey: String
}

private struct SmoothStreamingText: View {
    let target: String

    var body: some View {
        Group {
            if target.isEmpty {
                Text(localized("chat.thinking"))
                    .font(.body)
                    .foregroundStyle(NPColors.textPrimary)
            } else {
                LightweightMarkdownText(
                    markdown: target,
                    color: NPColors.textPrimary,
                    expandsHorizontally: false,
                    allowsTextSelection: false
                )
            }
        }
        .textSelection(.disabled)
        .accessibilityIdentifier("chatStreamingContent")
    }
}

private struct OpenClawMessageAttachmentView: View {
    let attachment: OpenClawChatAttachment
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    UploadThumbnailImage(
                        file: attachment.file,
                        size: CGSize(width: 112, height: 88),
                        cornerRadius: 10
                    )
                    if attachment.status == .uploading {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if attachment.status == .unavailable {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.16))
                        Image(systemName: "exclamationmark.icloud")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 112, height: 88)

                Text(attachment.displayName)
                    .font(.caption2)
                    .foregroundStyle(NPColors.textSecondary)
                    .lineLimit(2)
                    .frame(width: 112, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(attachment.status == .uploading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localizedFormat("chat.attachment_accessibility", attachment.displayName))
        .accessibilityHint(localized("common.preview"))
        .accessibilityIdentifier("chatAttachmentPreview.\(attachment.documentId ?? attachment.id.uuidString)")
    }
}

// MARK: - AI Onboarding

private struct AIOnboardingScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @ObservedObject var state: AIExperienceState

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if state.isLoading && state.onboarding == nil {
                    ProgressView(localized("ai.onboarding.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let onboarding = state.onboarding, !onboarding.questions.isEmpty {
                    let index = min(state.currentQuestionIndex, onboarding.questions.count - 1)
                    let question = onboarding.questions[index]
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(localizedFormat("ai.onboarding.progress", String(index + 1), String(onboarding.questions.count)))
                                .npCaption()
                            ProgressView(value: Double(index + 1), total: Double(onboarding.questions.count))
                            Text(aiCatalogText(question.messageKey, fallback: question.id))
                                .font(.title3.weight(.semibold))
                            ForEach(question.options) { option in
                                Button {
                                    state.setAnswer(option.value, for: question.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: state.answer(for: question.id) == option.value
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(NPColors.brand)
                                        Text(aiCatalogText(option.labelKey, fallback: option.value))
                                            .foregroundStyle(NPColors.textPrimary)
                                        Spacer()
                                    }
                                    .frame(minHeight: 48)
                                    .padding(.horizontal, 12)
                                    .modifier(NPListItemModifier())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("aiOnboardingOption.\(question.id).\(option.value)")
                            }
                            if index == onboarding.questions.count - 1 {
                                Text(localized("ai.onboarding.custom_instructions")).npSubheading()
                                TextEditor(text: Binding(
                                    get: { state.draftPreferences.customInstructions ?? "" },
                                    set: { state.draftPreferences.customInstructions = $0 }
                                ))
                                .frame(minHeight: 110)
                                .padding(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NPColors.border))
                                .accessibilityIdentifier("aiOnboardingCustomInstructions")
                                Text("\(state.draftPreferences.customInstructions?.count ?? 0) / 1000").npCaption()
                            }
                            if let error = state.errorMessage {
                                Text(error).npCaption().foregroundStyle(NPColors.destructive)
                            }
                        }
                        .padding(20)
                    }
                    HStack {
                        Button(localized("common.back")) {
                            state.currentQuestionIndex = max(0, index - 1)
                        }
                        .disabled(index == 0 || state.isSaving)
                        Spacer()
                        Button {
                            if index == onboarding.questions.count - 1 {
                                model.saveAIOnboarding()
                            } else {
                                state.currentQuestionIndex = min(onboarding.questions.count - 1, index + 1)
                            }
                        } label: {
                            if state.isSaving { ProgressView() }
                            else { Text(localized(index == onboarding.questions.count - 1 ? "ai.onboarding.complete" : "common.continue")) }
                        }
                        .buttonStyle(NPPrimaryButtonStyle())
                        .disabled(state.isSaving || state.answer(for: question.id).isEmpty)
                        .accessibilityIdentifier(
                            index == onboarding.questions.count - 1
                                ? "aiOnboardingCompleteButton"
                                : "aiOnboardingContinueButton"
                        )
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        Text(state.errorMessage ?? localized("ai.onboarding.load_failed"))
                        Button(localized("common.retry")) { model.loadAIOnboarding(force: true) }
                            .buttonStyle(NPPrimaryButtonStyle())
                    }
                    .padding(24)
                }
            }
            .navigationTitle(localized("ai.onboarding.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("aiOnboardingScreen")
    }
}

private struct AIPreferencesSettingsScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @ObservedObject var state: AIExperienceState

    var body: some View {
        NavigationView {
            Form {
                ForEach(state.onboarding?.questions ?? makeFallbackAIQuestions()) { question in
                    Picker(
                        aiCatalogText(question.messageKey, fallback: question.id),
                        selection: Binding(
                            get: { state.answer(for: question.id) },
                            set: { state.setAnswer($0, for: question.id) }
                        )
                    ) {
                        ForEach(question.options) { option in
                            Text(aiCatalogText(option.labelKey, fallback: option.value)).tag(option.value)
                        }
                    }
                }
                Section(localized("ai.onboarding.custom_instructions")) {
                    TextEditor(text: Binding(
                        get: { state.draftPreferences.customInstructions ?? "" },
                        set: { state.draftPreferences.customInstructions = $0 }
                    ))
                    .frame(minHeight: 100)
                    Text("\(state.draftPreferences.customInstructions?.count ?? 0) / 1000").npCaption()
                }
                if let error = state.errorMessage {
                    Text(error).foregroundStyle(NPColors.destructive)
                }
            }
            .navigationTitle(localized("ai.preferences.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.cancel")) { state.isSettingsPresented = false }
                        .disabled(state.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("common.save")) { model.saveAISettings() }
                        .disabled(state.isSaving)
                        .accessibilityIdentifier("saveAIPreferencesButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("aiPreferencesSettings")
    }
}

private func aiCatalogText(_ key: String, fallback: String) -> String {
    let value = localized(key)
    return value == key ? fallback : value
}

private func makeFallbackAIQuestions() -> [AIOnboardingQuestion] {
    let definitions: [(String, [String])] = [
        ("response_language", ["match_user", "client_locale", "zh-CN", "en-US", "pt-BR"]),
        ("collaboration_style", ["direct", "collaborative", "coach", "socratic"]),
        ("response_depth", ["concise", "balanced", "detailed"]),
        ("response_structure", ["adaptive", "steps", "bullets", "prose"]),
        ("clarification_policy", ["ask_when_ambiguous", "assume_when_safe", "confirm_before_actions"]),
        ("feedback_tone", ["gentle", "neutral", "strict"]),
        ("learning_guidance", ["answer_first", "explain_then_answer", "hint_first"])
    ]
    return definitions.map { id, values in
        AIOnboardingQuestion(
            id: id,
            messageKey: "ai.onboarding.questions.\(id)",
            required: true,
            options: values.map { AIOnboardingOption(value: $0, labelKey: "ai.onboarding.options.\(id).\($0)") }
        )
    }
}

// MARK: - Profile Tab

private struct ProfileTab: View {
    @ObservedObject var model: NotePatchViewModel
    @ObservedObject var profileState: UserProfileState
    @EnvironmentObject private var localization: AppLocalization
    @State private var isEditingProfile = false
    @State private var isShowingAvatarPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CompactPageHeader(
                    title: localized("profile.title"),
                    subtitle: nil
                )

                // ——— Profile Card ———
                NPSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Button {
                                isShowingAvatarPicker = true
                            } label: {
                                profileAvatar
                            }
                            .buttonStyle(.plain)
                            .disabled(profileState.isAvatarUploading || profileState.snapshot == nil)
                            .accessibilityLabel(localized("profile.avatar.choose"))
                            .accessibilityIdentifier("profileAvatarButton")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(NPColors.textPrimary)
                                    .lineLimit(1)
                                Text(profileEmail)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(NPColors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if profileState.isLoading || profileState.isAvatarUploading {
                                ProgressView()
                            } else {
                                Button {
                                    isEditingProfile = true
                                } label: {
                                    ZStack {
                                        Color.clear
                                        Image(systemName: "pencil")
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .buttonStyle(.plain)
                                .foregroundStyle(NPColors.brandDark)
                                .disabled(profileState.snapshot == nil)
                                .accessibilityLabel(localized("profile.edit"))
                                .accessibilityIdentifier("profileEditButton")
                            }
                        }
                        if profileState.hasPendingAvatarRetry,
                           !profileState.isAvatarUploading,
                           !profileState.hasAvatarConflict {
                            Button {
                                model.retryPendingAvatarUpload()
                            } label: {
                                Label(localized("profile.avatar.retry"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(NPColors.brandDark)
                            .accessibilityIdentifier("profileAvatarRetryButton")
                        }
                    }
                }

                // ——— Workspace ———
                WorkspaceManagementSection(model: model)

                // ——— Preferences ———
                languageSection
                feedbackSection
                imageRemarkPreferencesSection
                notePreferencesSection

                // ——— AI ———
                aiSection

                // ——— Server ———
                serverSection

                NPSection {
                    HStack(spacing: 12) {
                        NotePatchLogoImage(height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("profile.about.title"))
                                .font(.body.weight(.semibold))
                            Text(localized("profile.about.subtitle"))
                                .font(.caption)
                                .foregroundStyle(NPColors.textSecondary)
                        }
                    }
                }
                .accessibilityIdentifier("profileAbout")

                // ——— Sign Out ———
                Button(role: .destructive) {
                    model.logout()
                } label: {
                    Label(localized("profile.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .foregroundStyle(NPColors.destructive)
                .disabled(model.isBusy)
                .padding(.bottom, NPSpacing.xl)
                .accessibilityIdentifier("profileSignOut")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .workbenchContentBottomPadding()
        }
        .background(NPColors.background)
        .refreshable {
            model.loadUserProfile(force: true)
            model.loadAIModels(force: true)
            await Task.yield()
            while !Task.isCancelled,
                  profileState.isLoading || model.isAIModelsLoading {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditSheet(
                state: profileState,
                onCancel: {
                    guard !profileState.isSaving else { return }
                    if let snapshot = profileState.snapshot {
                        profileState.apply(snapshot)
                    }
                    isEditingProfile = false
                },
                onSave: model.saveUserProfile
            )
        }
        .sheet(isPresented: $isShowingAvatarPicker) {
            PhotoLibraryPicker(cacheDirectory: model.uploadCacheDirectory, selectionMode: .single) { result in
                isShowingAvatarPicker = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    if let file = files.first {
                        model.uploadUserAvatar(file)
                    }
                case .failure(let error):
                    model.presentError(error)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { model.aiExperienceState.isSettingsPresented },
            set: { model.aiExperienceState.isSettingsPresented = $0 }
        )) {
            AIPreferencesSettingsScreen(model: model, state: model.aiExperienceState)
        }
        .alert(localized("profile.conflict.title"), isPresented: $profileState.hasConflict) {
            Button(localized("common.cancel"), role: .cancel, action: model.cancelUserProfileOverwrite)
            Button(localized("profile.conflict.overwrite"), action: model.confirmUserProfileOverwrite)
        } message: {
            Text(localized("profile.conflict.message"))
        }
        .alert(localized("profile.avatar.conflict.title"), isPresented: $profileState.hasAvatarConflict) {
            Button(localized("common.cancel"), role: .cancel, action: model.cancelAvatarOverwrite)
            Button(localized("profile.conflict.overwrite"), action: model.confirmAvatarOverwrite)
        } message: {
            Text(localized("profile.avatar.conflict.message"))
        }
        .onAppear {
            model.loadUserProfile()
        }
        .onChange(of: profileState.isSaving) { isSaving in
            guard !isSaving,
                  !profileState.hasConflict,
                  let profile = profileState.snapshot?.profile,
                  profile.name == profileState.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                  profile.email.lowercased() == profileState.emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return
            }
            isEditingProfile = false
        }
    }

    private var accountInitial: String {
        let account = profileState.snapshot?.profile.name.isEmpty == false
            ? profileState.snapshot?.profile.name
            : profileEmail
        return account?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)?.uppercased() ?? "N"
    }

    private var profileName: String {
        let name = profileState.snapshot?.profile.name ?? model.session?.fullName ?? ""
        return name.isEmpty ? localized("account.default_user") : name
    }

    private var profileEmail: String {
        profileState.snapshot?.profile.email ?? model.session?.email ?? ""
    }

    @ViewBuilder
    private var profileAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = profileState.avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(NPColors.brandLight)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(accountInitial)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(NPColors.brandDark)
                    )
            }
            Image(systemName: "camera.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NPColors.surface)
                .frame(width: 22, height: 22)
                .background(NPColors.brand)
                .clipShape(Circle())
        }
    }

    private var languageSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                Label(localized("profile.language"), systemImage: "globe")
                    .npSubheading()
                Picker(localized("profile.language"), selection: Binding(
                    get: { localization.language },
                    set: {
                        localization.select($0)
                        model.reloadAIGreetingForLanguageChange()
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(NPColors.brandDark)
                .accessibilityIdentifier("appLanguagePicker")
                Text(localized("profile.language_help"))
                    .npCaption()
            }
        }
    }

    private var feedbackSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                Toggle(localized("profile.global_feedback"), isOn: Binding(
                    get: { model.isGlobalFeedbackEnabled },
                    set: { model.updateGlobalFeedbackEnabled($0) }
                ))
                .accessibilityIdentifier("globalFeedbackToggle")
                Text(localized("profile.global_feedback_help"))
                    .npCaption()
            }
        }
    }

    private var imageRemarkPreferencesSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                Label(localized("image_remark.preference.title"), systemImage: "photo.badge.sparkles")
                    .npSubheading()
                Toggle(localized("image_remark.preference.toggle"), isOn: Binding(
                    get: { model.autoImageRemarkEnabled },
                    set: { model.updateAutoImageRemarkEnabled($0) }
                ))
                .disabled(model.isAutoImageRemarkPreferenceUpdating)
                .accessibilityIdentifier("autoImageRemarkToggle")
                if model.isAutoImageRemarkPreferenceUpdating {
                    HStack(spacing: NPSpacing.small) {
                        ProgressView().controlSize(.small)
                        Text(localized("image_remark.preference.saving"))
                            .npCaption()
                    }
                }
                Text(localized("image_remark.preference.help"))
                    .npCaption()
            }
        }
    }

    private var aiSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.medium) {
                Label(localized("profile.ai"), systemImage: "sparkles")
                    .npSubheading()
                Toggle(localized("profile.ai_history"), isOn: Binding(
                    get: { model.aiHistoryEnabled },
                    set: { model.updateAIHistoryEnabled($0) }
                ))
                .disabled(model.isBusy || model.isAIPreferenceUpdating)
                Text(localized("profile.ai_history_help"))
                    .npCaption()

                Button {
                    model.presentAISettings()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("ai.preferences.title")).font(.body.weight(.semibold))
                            Text(localized("ai.preferences.summary")).npCaption()
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editAIPreferencesButton")

                Divider()

                HStack(spacing: NPSpacing.small) {
                    Text(localized("ai.model.title"))
                        .font(.body.weight(.semibold))
                    Spacer()
                    Button {
                        model.loadAIModels(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NPColors.brandDark)
                    .disabled(model.isAIModelsLoading || model.isAIModelUpdating)
                    .accessibilityLabel(localized("ai.model.refresh"))
                    .accessibilityIdentifier("refreshAIModelsButton")
                }

                if model.isAIModelsLoading && model.aiModelCatalog == nil {
                    HStack(spacing: NPSpacing.small) {
                        ProgressView()
                        Text(localized("ai.model.loading"))
                            .npCaption()
                    }
                } else if let catalog = model.aiModelCatalog {
                    Picker(
                        localized("ai.model.picker"),
                        selection: Binding<String?>(
                            get: { model.selectedAIModelId },
                            set: { model.selectAIModel($0) }
                        )
                    ) {
                        Text(localized("ai.model.deployment_default"))
                            .tag(String?.none)
                        ForEach(catalog.items) { item in
                            Text(item.upstreamId)
                                .tag(Optional(item.id))
                        }
                        if let selectedModelId = model.selectedAIModelId,
                           !catalog.items.contains(where: { $0.id == selectedModelId }) {
                            Text(selectedModelId)
                                .tag(Optional(selectedModelId))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(NPColors.brandDark)
                    .disabled(model.isAIModelUpdating)
                    .accessibilityIdentifier("aiModelPicker")

                    VStack(alignment: .leading, spacing: NPSpacing.xxs) {
                        Text(localizedFormat("ai.model.current", catalog.selectedModel))
                        Text(localizedFormat("ai.model.default", catalog.defaultModel))
                        if !catalog.fetchedAt.isEmpty {
                            Text(localizedFormat("ai.model.fetched_at", compactDateTime(catalog.fetchedAt)))
                        }
                    }
                    .npCaption()

                    if catalog.items.isEmpty {
                        Text(localized("ai.model.empty"))
                            .npCaption()
                    }
                    if catalog.stale {
                        Label(localized("ai.model.cached_warning"), systemImage: "exclamationmark.triangle")
                            .npCaption()
                            .foregroundStyle(NPColors.warning)
                            .accessibilityIdentifier("aiModelStaleWarning")
                    }
                }

                if let error = model.aiModelsError {
                    HStack(alignment: .firstTextBaseline, spacing: NPSpacing.small) {
                        Text(error)
                            .npCaption()
                            .foregroundStyle(NPColors.destructive)
                        Spacer()
                        Button(localized("common.retry")) {
                            model.loadAIModels(force: true)
                        }
                        .disabled(model.isAIModelsLoading)
                    }
                }
            }
        }
    }

    private var notePreferencesSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                Label(localized("note.preferences.title"), systemImage: "note.text.badge.gearshape")
                    .npSubheading()
                Text(localized("note.preferences.scope_help"))
                    .npCaption()

                Picker(localized("note.preferences.content"), selection: $model.notePreferenceDraftContent) {
                    ForEach(NoteContentEditLevel.supportedValues) { level in
                        Text(noteContentEditLevelLabel(level)).tag(level)
                    }
                    if !NoteContentEditLevel.supportedValues.contains(model.notePreferenceDraftContent) {
                        Text(model.notePreferenceDraftContent.rawValue).tag(model.notePreferenceDraftContent)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isNotePreferenceUpdating)
                .accessibilityIdentifier("noteContentPreferencePicker")
                Text(noteContentEditLevelHelp(model.notePreferenceDraftContent)).npCaption()

                Divider()

                Picker(localized("note.preferences.layout"), selection: $model.notePreferenceDraftLayout) {
                    ForEach(NoteLayoutEditLevel.supportedValues) { level in
                        Text(noteLayoutEditLevelLabel(level)).tag(level)
                    }
                    if !NoteLayoutEditLevel.supportedValues.contains(model.notePreferenceDraftLayout) {
                        Text(model.notePreferenceDraftLayout.rawValue).tag(model.notePreferenceDraftLayout)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isNotePreferenceUpdating)
                .accessibilityIdentifier("noteLayoutPreferencePicker")
                Text(noteLayoutEditLevelHelp(model.notePreferenceDraftLayout)).npCaption()

                Divider()

                Stepper(
                    localizedFormat("note.preferences.history_limit", String(model.notePreferenceDraftHistoryLimit)),
                    value: $model.notePreferenceDraftHistoryLimit,
                    in: 0...100
                )
                .disabled(model.isNotePreferenceUpdating)
                .accessibilityIdentifier("noteHistoryLimitStepper")
                Text(localized("note.preferences.history_help")).npCaption()

                Button {
                    model.saveNotePreferences()
                } label: {
                    if model.isNotePreferenceUpdating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(localized("common.save"), systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(NPPrimaryButtonStyle())
                .disabled(!model.isNotePreferenceDirty || model.isNotePreferenceUpdating)
                .accessibilityIdentifier("saveNotePreferencesButton")
            }
        }
    }

    private var serverSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                Label(localized("profile.server"), systemImage: "server.rack")
                    .npSubheading()

                LabeledField(title: "profile.api_address") {
                    TextField(localized("profile.api_address"), text: $model.apiBaseURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                LabeledField(title: "profile.upload_address") {
                    TextField(localized("profile.upload_address_placeholder"), text: $model.tusBaseURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Button {
                    model.saveServerURLs()
                } label: {
                    Label(localized("profile.save_server"), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPPrimaryButtonStyle())
                .disabled(model.isBusy)

                HStack(spacing: NPSpacing.small) {
                    Button {
                        model.checkAPIConnection()
                    } label: {
                        Label(localized("profile.test_api"), systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(model.isBusy)

                    Button {
                        model.checkTUSConnection()
                    } label: {
                        Label(localized("profile.test_tusd"), systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(model.isBusy)
                }
            }
        }
    }
}

private struct ProfileEditSheet: View {
    @ObservedObject var state: UserProfileState
    let onCancel: () -> Void
    let onSave: () -> Void

    private var emailChanged: Bool {
        guard let original = state.snapshot?.profile.email else { return false }
        return state.emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            != original.lowercased()
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(localized("profile.edit.identity"))) {
                    TextField(localized("profile.edit.name"), text: $state.nameDraft)
                        .textContentType(.name)
                        .disabled(state.isSaving)
                        .accessibilityIdentifier("profileNameField")
                    TextField(localized("profile.edit.email"), text: $state.emailDraft)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .disabled(state.isSaving)
                        .accessibilityIdentifier("profileEmailField")
                }
                if emailChanged {
                    Section(
                        header: Text(localized("profile.edit.current_password")),
                        footer: Text(localized("profile.edit.email_reauth_help"))
                    ) {
                        SecureField(localized("profile.edit.current_password_placeholder"), text: $state.currentPassword)
                            .textContentType(.password)
                            .disabled(state.isSaving)
                            .accessibilityIdentifier("profileCurrentPasswordField")
                    }
                }
                if state.isSaving {
                    Section {
                        HStack(spacing: NPSpacing.small) {
                            ProgressView()
                            Text(localized("profile.saving"))
                        }
                    }
                }
            }
            .navigationTitle(localized("profile.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.cancel"), action: onCancel)
                        .disabled(state.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("common.save"), action: onSave)
                        .disabled(state.isSaving)
                        .accessibilityIdentifier("profileSaveButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(state.isSaving)
        .accessibilityIdentifier("profileEditSheet")
    }
}

private struct WorkspaceManagementSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        let selected = model.workspaces.first(where: { $0.id == model.selectedWorkspaceId })
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(localized("profile.workspace"), systemImage: "person.crop.square")
                        .npSubheading()
                    Spacer()
                    Button {
                        model.refreshCurrentWorkspace()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NPColors.brandDark)
                    .disabled(model.isBusy || model.selectedWorkspaceId == nil)
                    .accessibilityLabel(localized("profile.refresh_workspace"))
                }
                if let selected {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(NPColors.warning)
                            .frame(width: 34, height: 34)
                            .background(NPColors.warning.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(NPColors.textPrimary)
                                .lineLimit(1)
                            Text(localized("profile.active_workspace"))
                                .npCaption()
                        }
                    }
                } else {
                    Text(localized("profile.no_workspace"))
                        .foregroundStyle(NPColors.textSecondary)
                }
                Button {
                    model.recoverPersonalWorkspace()
                } label: {
                    Label(localized("profile.restore_workspace"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
    }
}

// MARK: - Markdown Rendering

private struct LightweightMarkdownText: View {
    let markdown: String
    let color: Color
    var horizontalAlignment: HorizontalAlignment = .leading
    var textAlignment: TextAlignment = .leading
    var paragraphFont: Font = .body
    var expandsHorizontally = true
    var allowsTextSelection = true

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            MarkdownUI.Markdown(markdown)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    SelectableMarkdownCodeBlock(
                        code: configuration.content,
                        language: configuration.language
                    )
                }
                .markdownTheme(.basic)
                .markdownTextStyle {
                    ForegroundColor(color)
                    BackgroundColor(nil)
                }
                .markdownTextStyle(\.link) {
                    ForegroundColor(NPColors.brand)
                }
                .font(paragraphFont)
                .tint(NPColors.brand)
                .modifier(ConditionalTextSelectionModifier(enabled: allowsTextSelection))
                .multilineTextAlignment(textAlignment)
                .frame(
                    maxWidth: expandsHorizontally ? .infinity : nil,
                    alignment: contentAlignment
                )
        } else {
            LegacyMarkdownText(
                markdown: markdown,
                color: color,
                horizontalAlignment: horizontalAlignment,
                textAlignment: textAlignment,
                paragraphFont: paragraphFont,
                expandsHorizontally: expandsHorizontally,
                allowsTextSelection: allowsTextSelection
            )
        }
    }

    private var contentAlignment: Alignment {
        switch textAlignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }
}

private struct LegacyMarkdownText: View {
    let markdown: String
    let color: Color
    let horizontalAlignment: HorizontalAlignment
    let textAlignment: TextAlignment
    let paragraphFont: Font
    let expandsHorizontally: Bool
    let allowsTextSelection: Bool
    @StateObject private var renderer = MarkdownRenderState()

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 7) {
            ForEach(renderer.blocks) { block in
                switch block.type {
                case .heading:
                    Text(block.text)
                        .font(block.level == 1 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: contentAlignment)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•")
                        MarkdownInlineText(tokens: block.inlineTokens, color: color)
                    }
                    .font(paragraphFont)
                    .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
                case .ordered:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(max(1, block.level)).")
                        MarkdownInlineText(tokens: block.inlineTokens, color: color)
                    }
                    .font(paragraphFont)
                    .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
                case .quote:
                    HStack(spacing: NPSpacing.small) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(NPColors.brand)
                            .frame(width: 4)
                            .frame(height: 38)
                        MarkdownInlineText(tokens: block.inlineTokens, color: NPColors.textPrimary)
                            .font(paragraphFont)
                    }
                    .padding(NPSpacing.small)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
                case .code:
                    SelectableMarkdownCodeBlock(code: block.text, language: nil)
                case .table:
                    if let table = block.table {
                        MarkdownTableView(
                            table: table,
                            color: color,
                            paragraphFont: paragraphFont
                        )
                    }
                case .paragraph:
                    MarkdownInlineText(tokens: block.inlineTokens, color: color)
                        .font(paragraphFont)
                        .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: contentAlignment)
                }
            }
        }
        .modifier(ConditionalTextSelectionModifier(enabled: allowsTextSelection))
        .multilineTextAlignment(textAlignment)
        .task(id: markdown) {
            renderer.load(markdown)
        }
    }

    private var contentAlignment: Alignment {
        switch textAlignment {
        case .center:
            return .center
        case .trailing:
            return .trailing
        default:
            return .leading
        }
    }
}

private struct ConditionalTextSelectionModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

private struct SelectableMarkdownCodeBlock: View {
    let code: String
    let language: String?
    @State private var isCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NPSpacing.small) {
                if let language = normalizedLanguage {
                    Text(language)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(NPColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: copyCode) {
                    Label(
                        localized(isCopied ? "chat.copy.code_complete" : "chat.copy.code"),
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isCopied ? NPColors.successText : NPColors.textSecondary)
                .accessibilityIdentifier("markdownCodeCopyButton")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(NPColors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NPColors.interactive)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous)
                .stroke(NPColors.border.opacity(0.8), lineWidth: 1)
        }
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
    }

    private var normalizedLanguage: String? {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else {
            return nil
        }
        return language
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        isCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            isCopied = false
            copyResetTask = nil
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let color: Color
    let paragraphFont: Font

    private let columnWidth: CGFloat = 132

    var body: some View {
        ScrollView(.horizontal, showsIndicators: table.headers.count > 2) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(table.headers, isHeader: true, rowIndex: 0)
                Rectangle()
                    .fill(NPColors.border)
                    .frame(height: 1)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, isHeader: false, rowIndex: index)
                    if index < table.rows.count - 1 {
                        Rectangle()
                            .fill(NPColors.border.opacity(0.7))
                            .frame(height: 1)
                    }
                }
            }
            .background(NPColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous)
                    .stroke(NPColors.border, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(_ cells: [String], isHeader: Bool, rowIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(table.headers.indices, id: \.self) { column in
                MarkdownInlineText(
                    tokens: cachedMarkdownInlineTokens(column < cells.count ? cells[column] : ""),
                    color: color
                )
                .font(isHeader ? paragraphFont.weight(.semibold) : paragraphFont)
                .frame(
                    width: columnWidth,
                    alignment: contentAlignment(for: table.alignments[column])
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    isHeader
                        ? NPColors.interactive
                        : (rowIndex.isMultiple(of: 2) ? NPColors.surface : NPColors.background.opacity(0.45))
                )
                .overlay(alignment: .trailing) {
                    if column < table.headers.count - 1 {
                        Rectangle()
                            .fill(NPColors.border.opacity(0.7))
                            .frame(width: 1)
                    }
                }
            }
        }
    }

    private func contentAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }
}

private struct MarkdownInlineText: View {
    let tokens: [MarkdownInlineToken]
    let color: Color

    var body: some View {
        tokens.reduce(Text("")) { partial, token in
            partial + styledText(token)
        }
        .foregroundStyle(color)
    }

    private func styledText(_ token: MarkdownInlineToken) -> Text {
        switch token.type {
        case .text:
            return Text(token.text)
        case .bold:
            return Text(token.text).bold()
        case .code:
            return Text(token.text).font(.system(.body, design: .monospaced))
        case .link:
            return Text(token.text).underline().foregroundColor(NPColors.brand)
        }
    }
}

// MARK: - Reusable Building Blocks

private struct ChoiceGrid<Content: View>: View {
    var minimum: CGFloat = 92
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(localized(text))
            .npSubheading()
    }
}

private struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized(title))
                .npCaption()
            field
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .npInputField()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(NPColors.brand)
        .disabled(!enabled)
        .accessibilityLabel(localized(accessibilityLabel))
    }
}

private struct ChoiceButton: View {
    let text: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(ChoiceChipButtonStyle(selected: selected))
        .disabled(!enabled)
    }

    private var label: some View {
        Text(localized(text))
            .npBody()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
    }
}

private struct ChoiceChipButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(selected ? NPColors.brandDark : NPColors.brandDark)
            .frame(height: 38)
            .padding(.horizontal, NPSpacing.medium)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? NPColors.brandLight.opacity(0.6) : NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(selected ? NPColors.brand : NPColors.border, lineWidth: selected ? 1 : 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npInteractive, value: configuration.isPressed)
    }
}

private struct DetailText: View {
    let text: String
    let lineLimit: Int?

    init(_ text: String, lineLimit: Int? = 2) {
        self.text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(localized(text))
            .npCaption()
            .lineLimit(lineLimit)
    }
}

// MARK: - Inline Feedback

private struct AuthInlineFeedback: View {
    let statusMessage: String
    let errorMessage: String?

    var body: some View {
        if errorMessage != nil || !statusMessage.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .npCaption()
                }
                if let errorMessage {
                    Text(errorMessage)
                        .npCaption()
                        .foregroundStyle(NPColors.destructive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("authInlineFeedback")
        }
    }
}

// MARK: - Helper: NotePatch Brand Logo Image
// Renders the embroidered wordmark on a fully transparent background.
// Blends naturally with any page color (paper warm tones or surface whites).

private struct NotePatchLogoImage: View {
    var height: CGFloat
    var body: some View {
        Image("NotePatchLogo")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

// MARK: - Helper: Status Color / Variant Mapping

private func colorForStatus(_ status: String) -> Color {
    switch status {
    case "failed", "infected", "cancelled", "deleted":
        return NPColors.destructive
    case "created", "uploading", "scanning", "pending", "uploaded", "processing", "queued", "running", "rebuilding":
        return NPColors.warning
    case "ready", "succeeded", "completed":
        return NPColors.brand
    default:
        return NPColors.textSecondary
    }
}

private func documentMetadataSummary(_ document: LearningDocumentItem) -> String {
    var components = [fileTypeLabel(document.fileType)]
    if let fileSize = document.fileSize {
        components.append(formatBytes(fileSize))
    }
    let date = compactDateTime(document.updatedAt)
    if !date.isEmpty {
        components.append(date)
    }
    return components.joined(separator: " · ")
}

private func imageRemarkSourceLabel(_ source: String?) -> String {
    let normalized = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let key: String
    switch normalized {
    case "user", "upload":
        key = "image_remark.source.user"
    case "ai_ocr", "ai":
        key = "image_remark.source.ai_ocr"
    case "original_filename", "filename", "fallback":
        key = "image_remark.source.original_filename"
    default:
        key = "image_remark.source.unknown"
    }
    return localized(key)
}

private func imageRemarkStatusLabel(_ status: String) -> String {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key: String
    switch normalized {
    case "waiting_upload", "waiting_ocr", "queued", "running":
        key = "image_remark.status.processing"
    case "succeeded":
        key = "image_remark.status.succeeded"
    case "failed":
        key = "image_remark.status.failed"
    case "empty_ocr":
        key = "image_remark.status.empty_ocr"
    case "disabled":
        key = "image_remark.status.disabled"
    case "user":
        key = "image_remark.status.user"
    default:
        key = "image_remark.status.unknown"
    }
    return localized(key)
}

private func studyNoteCompletionSummary(_ note: StudyNoteVersion) -> String? {
    let count = note.completionCount ?? 0
    let sourceCount = note.completionSourceDocumentIds.count
    guard count > 0 || sourceCount > 0 else { return nil }
    return localizedFormat(
        "note.completion.summary",
        String(count),
        String(sourceCount)
    )
}

private func primaryDocumentStatus(_ document: LearningDocumentItem) -> String {
    return statusLabel(document.status)
}

private func primaryDocumentStatusVariant(_ document: LearningDocumentItem) -> NPStatusChip.NPStatusChipVariant {
    return statusChipVariant(document.status)
}

private func statusChipVariant(_ status: String) -> NPStatusChip.NPStatusChipVariant {
    switch status {
    case "failed", "infected", "cancelled", "deleted":
        return .destructive
    case "created", "uploading", "scanning", "pending", "uploaded", "processing", "queued", "running", "rebuilding":
        return .warning
    case "ready", "succeeded", "completed":
        return .brand
    default:
        return .neutral
    }
}

private func taskStatusChipVariant(_ task: TaskItem) -> NPStatusChip.NPStatusChipVariant {
    if task.cancelRequestedAt != nil && !["succeeded", "failed", "cancelled"].contains(task.status) {
        return .warning
    }
    return statusChipVariant(task.status)
}

private func workflowStatusLabel(_ status: String) -> String {
    localized("workflow.status.\(status)") == "workflow.status.\(status)"
        ? status.replacingOccurrences(of: "_", with: " ")
        : localized("workflow.status.\(status)")
}

private func workflowStageLabel(_ stage: String) -> String {
    let key = "workflow.stage.\(stage)"
    let value = localized(key)
    return value == key ? stage.replacingOccurrences(of: "_", with: " ") : value
}

private func workflowStatusVariant(_ status: String) -> NPStatusChip.NPStatusChipVariant {
    switch status {
    case "failed", "cancelled": return .destructive
    case "succeeded": return .brand
    case "partially_succeeded", "waiting", "waiting_upload", "queued", "running": return .warning
    default: return .neutral
    }
}

private func workflowTaskIcon(_ status: String) -> String {
    switch status {
    case "succeeded": return "checkmark.circle.fill"
    case "failed", "cancelled": return "exclamationmark.circle.fill"
    case "running": return "arrow.triangle.2.circlepath.circle.fill"
    default: return "clock.fill"
    }
}

private func workflowTaskColor(_ status: String) -> Color {
    switch status {
    case "succeeded": return NPColors.brand
    case "failed", "cancelled": return NPColors.destructive
    default: return NPColors.warning
    }
}

private func noteContentEditLevelLabel(_ level: NoteContentEditLevel) -> String {
    let key = "note.strategy.content.\(level.rawValue)"
    let value = localized(key)
    return value == key ? level.rawValue : value
}

private func noteContentEditLevelHelp(_ level: NoteContentEditLevel) -> String {
    let key = "note.strategy.content.\(level.rawValue).help"
    let value = localized(key)
    return value == key ? noteContentEditLevelLabel(level) : value
}

private func noteLayoutEditLevelLabel(_ level: NoteLayoutEditLevel) -> String {
    let key = "note.strategy.layout.\(level.rawValue)"
    let value = localized(key)
    return value == key ? level.rawValue : value
}

private func noteLayoutEditLevelHelp(_ level: NoteLayoutEditLevel) -> String {
    let key = "note.strategy.layout.\(level.rawValue).help"
    let value = localized(key)
    return value == key ? noteLayoutEditLevelLabel(level) : value
}

private func noteGapStatusLabel(_ status: String) -> String {
    let key = "note_gap.status.\(status)"
    let value = localized(key)
    return value == key ? status.replacingOccurrences(of: "_", with: " ") : value
}

private func noteGapStatusVariant(_ status: String) -> NPStatusChip.NPStatusChipVariant {
    switch status {
    case "accepted": return .brand
    case "rejected", "stale": return .destructive
    case "pending", "draft", "no_base_note": return .warning
    default: return .neutral
    }
}

private func taskStatusLabel(_ task: TaskItem) -> String {
    if task.cancelRequestedAt != nil && !["succeeded", "failed", "cancelled"].contains(task.status) {
        return localized("task.status.cancelling")
    }
    return statusLabel(task.status)
}

private func taskTypeLabel(_ taskType: String) -> String {
    switch taskType {
    case "purge_document":
        return localized("task.type.document_cleanup")
    case "process_document", "document_process":
        return localized("task.type.document_processing")
    case "merge_learning_units":
        return localized("task.type.merge_learning_units")
    case "openclaw", "openclaw_task":
        return localized("task.type.ai_chat")
    default:
        return localized("task.type.other")
    }
}

// MARK: - Chat Scroll Pan Observer

private struct ChatScrollPanValue {
    let startLocation: CGPoint
    let location: CGPoint
    let translation: CGSize
    let scrollBottomY: CGFloat
}

private struct ChatScrollPanObserver: UIViewRepresentable {
    let onPan: (ChatScrollPanValue) -> Void
    let onBottomChange: (Bool) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onPan = onPan
        view.onBottomChange = onBottomChange
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onPan = onPan
        view.onBottomChange = onBottomChange
        view.attachIfNeeded()
    }

    final class ObserverView: UIView {
        var onPan: ((ChatScrollPanValue) -> Void)?
        var onBottomChange: ((Bool) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private weak var observedPanGesture: UIPanGestureRecognizer?
        private var scrollObservations: [NSKeyValueObservation] = []
        private var startLocation: CGPoint?
        private var lastReportedAtBottom: Bool?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.attachIfNeeded()
            }
        }

        deinit {
            observedPanGesture?.removeTarget(self, action: #selector(handlePan))
            scrollObservations.forEach { $0.invalidate() }
        }

        func attachIfNeeded() {
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) {
                candidate = view.superview
            }
            guard let scrollView = candidate as? UIScrollView,
                  observedScrollView !== scrollView else {
                return
            }

            observedPanGesture?.removeTarget(self, action: #selector(handlePan))
            scrollObservations.forEach { $0.invalidate() }
            scrollObservations.removeAll()
            observedScrollView = scrollView
            if UIDevice.current.userInterfaceIdiom == .pad {
                scrollView.keyboardDismissMode = .interactive
            }
            observedPanGesture = scrollView.panGestureRecognizer
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))
            scrollObservations = [
                scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                    self?.reportBottomPosition()
                },
                scrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
                    self?.reportBottomPosition()
                },
                scrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
                    self?.reportBottomPosition()
                }
            ]
            reportBottomPosition()
        }

        private func reportBottomPosition() {
            guard let scrollView = observedScrollView else { return }
            let visibleHeight = max(
                0,
                scrollView.bounds.height
                    - scrollView.adjustedContentInset.top
                    - scrollView.adjustedContentInset.bottom
            )
            let visibleBottom = scrollView.contentOffset.y
                + scrollView.bounds.height
                - scrollView.adjustedContentInset.bottom
            let contentFits = scrollView.contentSize.height <= visibleHeight + 4
            let distanceFromBottom = max(0, scrollView.contentSize.height - visibleBottom)
            let tolerance: CGFloat = lastReportedAtBottom == false ? 10 : 4
            let atBottom = contentFits || distanceFromBottom <= tolerance
            guard lastReportedAtBottom != atBottom else { return }
            lastReportedAtBottom = atBottom
            let callback = onBottomChange
            DispatchQueue.main.async {
                callback?(atBottom)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = observedScrollView else { return }
            let location = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                startLocation = location
            case .changed, .ended:
                guard let startLocation else { return }
                let translation = recognizer.translation(in: nil)
                let visibleHeight = max(
                    0,
                    scrollView.bounds.height
                        - scrollView.adjustedContentInset.top
                        - scrollView.adjustedContentInset.bottom
                )
                if translation.y > 6,
                   scrollView.contentSize.height > visibleHeight + 4,
                   lastReportedAtBottom != false {
                    lastReportedAtBottom = false
                    let callback = onBottomChange
                    DispatchQueue.main.async { callback?(false) }
                }
                onPan?(
                    ChatScrollPanValue(
                        startLocation: startLocation,
                        location: location,
                        translation: CGSize(width: translation.x, height: translation.y),
                        scrollBottomY: scrollView.convert(scrollView.bounds, to: nil).maxY
                    )
                )
                if recognizer.state == .ended {
                    self.startLocation = nil
                }
            case .cancelled, .failed:
                startLocation = nil
            default:
                break
            }
        }
    }
}

// MARK: - Adaptive Composer Text View

private struct AdaptiveComposerTextView: UIViewRepresentable {
    @Environment(\.sizeCategory) private var sizeCategory
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var height: CGFloat
    let availableWidth: CGFloat
    let horizontalInset: CGFloat
    let maximumLines: Int

    func makeUIView(context: Context) -> ComposerTextViewContainer {
        let container = ComposerTextViewContainer()
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(
            top: 9,
            left: horizontalInset,
            bottom: 9,
            right: horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.alwaysBounceHorizontal = false
        textView.isScrollEnabled = false
        textView.accessibilityLabel = localized("chat.composer_accessibility")
        textView.accessibilityIdentifier = "openClawComposerTextView"
        return container
    }

    func updateUIView(_ container: ComposerTextViewContainer, context: Context) {
        let textView = container.textView
        context.coordinator.update(parent: self)
        textView.accessibilityLabel = localized("chat.composer_accessibility")
        let normalizedHorizontalInset = max(0, horizontalInset)
        let didChangeInsets =
            abs(textView.textContainerInset.left - normalizedHorizontalInset) > 0.5 ||
            abs(textView.textContainerInset.right - normalizedHorizontalInset) > 0.5
        if didChangeInsets {
            textView.textContainerInset.left = normalizedHorizontalInset
            textView.textContainerInset.right = normalizedHorizontalInset
        }
        let didReplaceText = textView.text != text
        if textView.text != text {
            textView.text = text
        }
        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        context.coordinator.updateHeight(for: textView, force: didReplaceText || didChangeInsets)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: AdaptiveComposerTextView
        private var lastMeasuredText: String?
        private var lastMeasuredWidth: CGFloat = 0
        private var lastMaximumLines = 0
        private var lastSizeCategory: ContentSizeCategory?

        init(parent: AdaptiveComposerTextView) {
            self.parent = parent
        }

        func update(parent: AdaptiveComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateHeight(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {}

        func updateHeight(for textView: UITextView, force: Bool = false) {
            let width = parent.availableWidth
            guard width.isFinite, width >= ComposerTextLayout.minimumMeasurementWidth else {
                return
            }
            guard force ||
                    lastMeasuredText != textView.text ||
                    abs(lastMeasuredWidth - width) > 0.5 ||
                    lastMaximumLines != parent.maximumLines ||
                    lastSizeCategory != parent.sizeCategory else {
                return
            }
            let trace = NPPerformanceTrace.begin("ComposerMeasure")
            defer { NPPerformanceTrace.end("ComposerMeasure", id: trace) }
            lastMeasuredText = textView.text
            lastMeasuredWidth = width
            lastMaximumLines = parent.maximumLines
            lastSizeCategory = parent.sizeCategory

            guard let measurement = ComposerTextLayout.measure(
                textView: textView,
                availableWidth: width,
                maximumLines: parent.maximumLines
            ) else {
                return
            }
            textView.isScrollEnabled = measurement.requiresScrolling

            if measurement.requiresScrolling {
                textView.scrollRangeToVisible(textView.selectedRange)
            } else if textView.contentOffset.y != 0 {
                textView.setContentOffset(.zero, animated: false)
            }

            if abs(parent.height - measurement.height) > 0.5 {
                let measuredText = textView.text
                let measuredWidth = width
                let measuredMaximumLines = parent.maximumLines
                let measuredHeight = measurement.height
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.lastMeasuredText == measuredText,
                          abs(self.lastMeasuredWidth - measuredWidth) <= 0.5,
                          self.lastMaximumLines == measuredMaximumLines else {
                        return
                    }
                    self.parent.height = measuredHeight
                }
            }
        }
    }
}

private final class ComposerTextViewContainer: UIView {
    let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ComposerTextMeasurement: Equatable {
    let height: CGFloat
    let requiresScrolling: Bool
}

enum ComposerTextLayout {
    static let minimumMeasurementWidth: CGFloat = 44

    static func measure(
        textView: UITextView,
        availableWidth: CGFloat,
        maximumLines: Int
    ) -> ComposerTextMeasurement? {
        guard availableWidth.isFinite, availableWidth >= minimumMeasurementWidth else {
            return nil
        }

        let lineHeight = textView.font?.lineHeight
            ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let minimumHeight = max(44, ceil(lineHeight + verticalInsets))
        let maximumHeight = max(
            minimumHeight,
            ceil(lineHeight * CGFloat(max(1, maximumLines)) + verticalInsets)
        )
        let fittingHeight = textView.sizeThatFits(
            CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height

        return ComposerTextMeasurement(
            height: min(max(fittingHeight, minimumHeight), maximumHeight),
            requiresScrolling: fittingHeight > maximumHeight + 0.5
        )
    }
}

// MARK: - Photo Library Picker

enum PhotoLibrarySelectionMode {
    case multiple
    case single

    var selectionLimit: Int {
        switch self {
        case .multiple: return 0
        case .single: return 1
        }
    }
}

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let cacheDirectory: URL
    let selectionMode: PhotoLibrarySelectionMode
    let onComplete: (Result<[LocalUploadFile], Error>?) -> Void

    init(
        cacheDirectory: URL,
        selectionMode: PhotoLibrarySelectionMode = .multiple,
        onComplete: @escaping (Result<[LocalUploadFile], Error>?) -> Void
    ) {
        self.cacheDirectory = cacheDirectory
        self.selectionMode = selectionMode
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionMode.selectionLimit
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(cacheDirectory: cacheDirectory, onComplete: onComplete)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let cacheDirectory: URL
        let onComplete: (Result<[LocalUploadFile], Error>?) -> Void

        init(cacheDirectory: URL, onComplete: @escaping (Result<[LocalUploadFile], Error>?) -> Void) {
            self.cacheDirectory = cacheDirectory
            self.onComplete = onComplete
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onComplete(nil)
                return
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var selections = Array<LocalUploadFile?>(repeating: nil, count: results.count)
            var firstError: Error?

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .image) == true
                }) else {
                    firstError = firstError ?? LearningBackendError(localizedKey: "error.photo.type_unknown")
                    continue
                }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, error in
                    defer { group.leave() }
                    do {
                        if let error { throw error }
                        guard let temporaryURL else {
                            throw LearningBackendError(localizedKey: "error.photo.read_failed")
                        }
                        let type = UTType(typeIdentifier)
                        let fileExtension = type?.preferredFilenameExtension ?? "jpg"
                        let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let filename = suggestedName?.isEmpty == false
                            ? ((suggestedName! as NSString).pathExtension.isEmpty ? "\(suggestedName!).\(fileExtension)" : suggestedName!)
                            : "selected-\(Int(Date().timeIntervalSince1970 * 1000))-\(index).\(fileExtension)"
                        let file = try copyFileToUploadCache(
                            sourceURL: temporaryURL,
                            fallbackPrefix: "selected-photo",
                            cacheDirectory: self.cacheDirectory,
                            suggestedMimeType: type?.preferredMIMEType ?? contentTypeForFilename(filename),
                            suggestedFilename: filename
                        )
                        lock.lock()
                        selections[index] = file
                        lock.unlock()
                    } catch {
                        lock.lock()
                        firstError = firstError ?? error
                        lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) {
                let loaded = selections.compactMap { $0 }
                if loaded.isEmpty, let firstError {
                    self.onComplete(.failure(firstError))
                } else {
                    self.onComplete(.success(loaded))
                }
            }
        }
    }
}

// MARK: - Camera Picker

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Quick Look Preview

private struct UnsupportedFilePreview: View {
    let preview: DownloadedPreview
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(NPColors.brand)
                    .frame(width: 88, height: 88)
                    .background(NPColors.brandLight)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.medium, style: .continuous))

                VStack(spacing: 8) {
                    Text(localized("preview.unsupported.title"))
                        .npHeading()
                    Text(localized("preview.unsupported.message"))
                        .npBody()
                        .foregroundStyle(NPColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                NPSection {
                    VStack(alignment: .leading, spacing: 10) {
                        DetailText(localizedFormat("preview.file.name", preview.filename))
                        DetailText(localizedFormat("preview.file.type", preview.mimeType ?? localized("common.unknown")))
                        DetailText(localizedFormat("preview.file.size", formatBytes(preview.fileSize)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    isSharing = true
                } label: {
                    Label(localized("preview.open_external"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPPrimaryButtonStyle())
                .accessibilityIdentifier("unsupportedPreviewOpenExternal")
                Spacer()
            }
            .padding(20)
            .background(NPColors.background.ignoresSafeArea())
            .navigationTitle(preview.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("common.done")) {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $isSharing) {
            ActivityViewController(items: [preview.url])
        }
        .accessibilityIdentifier("unsupportedFilePreview")
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Zoomable Image Preview

private struct ZoomableImagePreview: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.addSubview(context.coordinator.imageView)
        scrollView.addSubview(context.coordinator.activityIndicator)
        context.coordinator.activityIndicator.startAnimating()

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.loadGeneration = UUID()
            let generation = context.coordinator.loadGeneration
            context.coordinator.imageView.image = nil
            context.coordinator.activityIndicator.startAnimating()
            scrollView.setZoomScale(1, animated: false)
            let maxPixelSize = min(
                4096,
                max(
                    2048,
                    Int(max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale * 1.5)
                )
            )
            DispatchQueue.global(qos: .userInitiated).async {
                let image = downsampleUploadImage(at: url, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async {
                    guard context.coordinator.loadedURL == url,
                          context.coordinator.loadGeneration == generation else { return }
                    context.coordinator.imageView.image = image
                    context.coordinator.activityIndicator.stopAnimating()
                    context.coordinator.layoutImage(in: scrollView)
                }
            }
        }
        DispatchQueue.main.async {
            context.coordinator.layoutImage(in: scrollView)
        }
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        uiView.isUserInteractionEnabled = false
        uiView.gestureRecognizers?.forEach(uiView.removeGestureRecognizer)
        uiView.delegate = nil
        coordinator.scrollView = nil
        coordinator.loadGeneration = UUID()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        var loadedURL: URL?
        var loadGeneration = UUID()
        let imageView: UIImageView = {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.isUserInteractionEnabled = true
            return view
        }()
        let activityIndicator: UIActivityIndicatorView = {
            let view = UIActivityIndicatorView(style: .large)
            view.color = .white
            view.hidesWhenStopped = true
            return view
        }()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func layoutImage(in scrollView: UIScrollView) {
            activityIndicator.center = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            guard let image = imageView.image, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else {
                return
            }
            let widthScale = scrollView.bounds.width / image.size.width
            let heightScale = scrollView.bounds.height / image.size.height
            let scale = min(widthScale, heightScale)
            let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            if scrollView.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: fittedSize)
            }
            scrollView.contentSize = imageView.frame.size
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else {
                return
            }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
                layoutImage(in: scrollView)
                return
            }
            let point = recognizer.location(in: imageView)
            let zoomScale = min(2.5, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / zoomScale, height: scrollView.bounds.height / zoomScale)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            scrollView.zoom(to: rect, animated: true)
        }

        private func centerImage(in scrollView: UIScrollView) {
            let horizontalInset = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }
    }
}

// MARK: - Image Preview

private struct ImagePreview: View {
    let url: URL
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableImagePreview(url: url)
                .ignoresSafeArea()
            Button {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            } label: {
                Label(localized("common.close"), systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(Color.white)
                    .padding(18)
            }
            .accessibilityIdentifier("imagePreviewCloseButton")
        }
    }
}

// MARK: - Utility

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
