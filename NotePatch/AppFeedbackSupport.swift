import Combine
import SwiftUI
import UIKit

enum AppFeedbackCoordinateSpace {
    static let name = "appFeedback"
}

extension Notification.Name {
    static let notePatchDismissGlobalFeedback = Notification.Name("NotePatchDismissGlobalFeedback")
}

@MainActor
final class AppFeedbackDismissalCenter: ObservableObject {
    static let shared = AppFeedbackDismissalCenter()

    @Published private(set) var revision: UInt = 0

    func dismiss() {
        revision &+= 1
    }
}

enum AppFeedbackKind: String, Equatable {
    case success
    case error
}

struct AppFeedbackItem: Equatable, Identifiable {
    let kind: AppFeedbackKind
    let text: String

    var id: String { "\(kind.rawValue)|\(text)" }
}

enum AppActivityPresentation: Equatable {
    case hidden
    case indeterminate(String)
    case determinate(Int, String)
}

func appFeedbackItem(
    statusMessage: String,
    errorMessage: String?,
    isBusy: Bool
) -> AppFeedbackItem? {
    if let errorMessage = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
       !errorMessage.isEmpty {
        return AppFeedbackItem(kind: .error, text: errorMessage)
    }
    let status = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isBusy, !status.isEmpty else { return nil }
    return AppFeedbackItem(kind: .success, text: status)
}

func appActivityPresentation(
    isBusy: Bool,
    progressPercent: Int?,
    label: String
) -> AppActivityPresentation {
    guard isBusy else { return .hidden }
    if let progressPercent {
        return .determinate(min(max(progressPercent, 0), 100), label)
    }
    return .indeterminate(label)
}

func appActivityTopOffset(
    reportedSafeAreaTop: CGFloat,
    windowSafeAreaTop: CGFloat,
    statusBarHeight: CGFloat = 0
) -> CGFloat {
    resolvedTopSafeAreaInset(
        reportedSafeAreaTop: reportedSafeAreaTop,
        windowSafeAreaTop: windowSafeAreaTop,
        statusBarHeight: statusBarHeight
    ) + 2
}

func appFeedbackBottomOffset(
    containerHeight: CGFloat,
    bottomBarFrame: CGRect,
    isAuthenticated: Bool,
    isUploadPresented: Bool,
    isBottomBarVisible: Bool,
    safeAreaBottom: CGFloat
) -> CGFloat {
    if isAuthenticated, !isUploadPresented, isBottomBarVisible {
        let obstruction = workbenchBottomObstruction(
            containerHeight: containerHeight,
            bottomBarFrame: bottomBarFrame,
            isVisible: true
        )
        if obstruction > 0 {
            return obstruction + 14
        }
    }
    return max(20, safeAreaBottom + 20)
}

func appFeedbackToastWidth(text: String, containerWidth: CGFloat) -> CGFloat {
    let availableWidth = max(0, min(360, containerWidth - 32))
    guard availableWidth > 0 else { return 0 }
    let measured = (text as NSString).size(
        withAttributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
    ).width
    return min(availableWidth, max(min(156, availableWidth), measured + 70))
}

@MainActor
final class AppFeedbackPresentationState: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isPinned = false
    @Published private(set) var originatingTab: WorkbenchTab?
    @Published private(set) var originatingDismissalRevision: UInt = 0

    private let autoDismissNanoseconds: UInt64
    private var identity: String?
    private var dismissTask: Task<Void, Never>?
    private var onDismiss: (() -> Void)?

    init(autoDismissNanoseconds: UInt64 = 2_000_000_000) {
        self.autoDismissNanoseconds = autoDismissNanoseconds
    }

    func present(
        identity: String,
        originatingTab: WorkbenchTab? = nil,
        originatingDismissalRevision: UInt = 0,
        onDismiss: @escaping () -> Void
    ) {
        guard self.identity != identity || !isVisible else { return }
        dismissTask?.cancel()
        self.identity = identity
        self.onDismiss = onDismiss
        self.originatingTab = originatingTab
        self.originatingDismissalRevision = originatingDismissalRevision
        isPinned = false
        isVisible = true

        dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.autoDismissNanoseconds)
            guard !Task.isCancelled, self.identity == identity, !self.isPinned else { return }
            self.dismissCurrent()
        }
    }

    func pin() {
        guard !isPinned else { return }
        dismissTask?.cancel()
        isVisible = true
        isPinned = true
    }

    func dismissFromOutsideTap() {
        guard isPinned else { return }
        dismissCurrent()
    }

    func hide() {
        dismissTask?.cancel()
        identity = nil
        onDismiss = nil
        originatingTab = nil
        isPinned = false
        isVisible = false
    }

    private func dismissCurrent() {
        let callback = onDismiss
        hide()
        callback?()
    }

    deinit {
        dismissTask?.cancel()
    }
}

private struct AppFeedbackFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

struct AppFeedbackOverlay: View {
    @ObservedObject var model: NotePatchViewModel
    @ObservedObject var profileState: UserProfileState
    @ObservedObject var navigationState: WorkbenchNavigationState
    @ObservedObject var presentation: AppFeedbackPresentationState
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    @State private var toastFrame: CGRect = .null
    @State private var suppressedItemID: String?

    private var isBusyUITestFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-NotePatchUITestFeedbackBusy")
    }

    private var uploadErrorUITestFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-NotePatchUITestFeedbackUploadError")
    }



    private var activityTopOffset: CGFloat {
        appActivityTopOffset(
            reportedSafeAreaTop: safeAreaInsets.top,
            windowSafeAreaTop: feedbackWindowSafeAreaInsets().top,
            statusBarHeight: currentAppStatusBarHeight()
        )
    }

    private var isBusy: Bool {
        isBusyUITestFixture || model.isBusy || model.isConversationMutating || model.isAIPreferenceUpdating ||
            model.isHomeworkLoading || model.isStudyNoteSaving || profileState.isSaving ||
            profileState.isAvatarUploading
    }

    private var item: AppFeedbackItem? {
        guard model.isGlobalFeedbackEnabled else { return nil }
        if uploadErrorUITestFixture, model.errorMessage == nil {
            return AppFeedbackItem(kind: .error, text: "Upload failed")
        }
        return appFeedbackItem(
            statusMessage: model.statusMessage,
            errorMessage: model.errorMessage,
            isBusy: isBusy
        )
    }

    private var activity: AppActivityPresentation {
        guard model.isGlobalFeedbackEnabled else { return .hidden }
        return appActivityPresentation(
            isBusy: isBusy,
            progressPercent: model.uploadProgressPercent,
            label: model.statusMessage
        )
    }

    private var visibleItem: AppFeedbackItem? {
        guard let item, item.id != suppressedItemID else { return nil }
        return item
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppActivityLayer(
                presentation: activity,
                topOffset: activityTopOffset,
                containerWidth: containerSize.width
            )
                .allowsHitTesting(false)
                .zIndex(3)

            if let item = visibleItem {
                AppFeedbackToast(
                    item: item,
                    isPinned: presentation.isPinned,
                    originatingTab: presentation.originatingTab,
                    originatingDismissalRevision: presentation.originatingDismissalRevision,
                    navigationState: navigationState
                ) {
                    presentation.pin()
                }
                .id(item.id)
                .frame(width: appFeedbackToastWidth(text: item.text, containerWidth: containerSize.width))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AppFeedbackFramePreferenceKey.self,
                            value: proxy.frame(in: .named(AppFeedbackCoordinateSpace.name))
                        )
                    }
                }
                .padding(.bottom, bottomOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            AppInteractionTapObserver(
                isEnabled: presentation.isPinned,
                excludedFrame: toastFrame,
                onOutsideTap: dismissVisibleFeedback
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: presentation.isVisible)
        .animation(.easeInOut(duration: 0.18), value: item)
        .onAppear { updatePresentation(for: item) }
        .onChange(of: item) { updatePresentation(for: $0) }
        .onChange(of: model.isGlobalFeedbackEnabled) { enabled in
            if !enabled {
                presentation.hide()
            }
        }
        .onReceive(navigationState.$selectedTab.dropFirst()) { _ in
            dismissVisibleFeedback()
        }
        .onChange(of: model.feedbackDismissalRevision) { _ in
            suppressedItemID = item?.id
        }
        .onPreferenceChange(AppFeedbackFramePreferenceKey.self) { toastFrame = $0 }
        .onDisappear { presentation.hide() }
    }

    private var bottomOffset: CGFloat {
        appFeedbackBottomOffset(
            containerHeight: containerSize.height,
            bottomBarFrame: navigationState.bottomBarFrame,
            isAuthenticated: model.session != nil,
            isUploadPresented: navigationState.isUploadPresented,
            isBottomBarVisible: !navigationState.isBottomBarHiddenForKeyboard,
            safeAreaBottom: safeAreaInsets.bottom
        )
    }

    private func updatePresentation(for item: AppFeedbackItem?) {
        guard let item else {
            suppressedItemID = nil
            presentation.hide()
            return
        }
        guard item.id != suppressedItemID else {
            presentation.hide()
            return
        }
        presentation.present(
            identity: item.id,
            originatingTab: model.session == nil ? nil : navigationState.selectedTab,
            originatingDismissalRevision: AppFeedbackDismissalCenter.shared.revision,
            onDismiss: model.dismissGlobalFeedback
        )
    }

    private func dismissVisibleFeedback() {
        AppFeedbackDismissalCenter.shared.dismiss()
        NotificationCenter.default.post(name: .notePatchDismissGlobalFeedback, object: nil)
        suppressedItemID = item?.id
        model.dismissGlobalFeedback()
    }
}

private struct AppActivityLayer: View {
    let presentation: AppActivityPresentation
    let topOffset: CGFloat
    let containerWidth: CGFloat

    var body: some View {
        AppActivityBar(presentation: presentation)
            .frame(width: max(0, containerWidth))
            .frame(height: 3)
            .clipped()
            .position(
                x: max(0, containerWidth) / 2,
                y: topOffset + 1.5
            )
            .accessibilityHidden(presentation == .hidden)
    }
}

private struct AppFeedbackToast: View {
    let item: AppFeedbackItem
    let isPinned: Bool
    let originatingTab: WorkbenchTab?
    let originatingDismissalRevision: UInt
    @ObservedObject var navigationState: WorkbenchNavigationState
    @ObservedObject private var dismissalCenter = AppFeedbackDismissalCenter.shared
    let onTap: () -> Void
    @State private var isLocallyDismissed = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind == .error ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(semanticColor)
                    .padding(.top, 1)
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(NPColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isPinned ? 6 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background { toastBackground }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(semanticColor.opacity(isPinned ? 0.34 : 0.18), lineWidth: isPinned ? 1.25 : 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 16, x: 0, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("globalFeedbackToast")
        .accessibilityValue(isPinned ? localized("feedback.accessibility.pinned") : "")
        .accessibilityHint(isPinned ? localized("feedback.accessibility.dismiss_outside") : localized("feedback.accessibility.keep"))
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
        .onReceive(NotificationCenter.default.publisher(for: .notePatchDismissGlobalFeedback)) { _ in
            isLocallyDismissed = true
        }
    }

    private var isHidden: Bool {
        isLocallyDismissed
            || dismissalCenter.revision != originatingDismissalRevision
            || (originatingTab != nil && navigationState.selectedTab != originatingTab)
    }

    private var semanticColor: Color {
        item.kind == .error ? NPColors.destructive : NPColors.successText
    }

    @ViewBuilder
    private var toastBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(NPColors.surfaceHighlight.opacity(0.05))
        }
    }
}

private struct AppActivityBar: View {
    let presentation: AppActivityPresentation

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()
        case .indeterminate(let label):
            AppIndeterminateProgressBar()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label.isEmpty ? localized("common.processing") : label)
                .accessibilityIdentifier("globalActivityBar")
        case .determinate(let percent, let label):
            GeometryReader { proxy in
                Capsule()
                    .fill(NPColors.brand)
                    .frame(width: proxy.size.width * CGFloat(percent) / 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label.isEmpty ? localized("common.processing") : label)
            .accessibilityValue("\(percent)%")
            .accessibilityIdentifier("globalActivityBar")
        }
    }
}

private struct AppIndeterminateProgressBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(NPColors.brand)
                .frame(width: max(48, proxy.size.width * 0.28))
                .offset(x: isAnimating ? proxy.size.width : -proxy.size.width * 0.28)
        }
        .frame(height: 3)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

private func feedbackWindowSafeAreaInsets() -> UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    return windows.first(where: \.isKeyWindow)?.safeAreaInsets
        ?? windows.first(where: { !$0.isHidden })?.safeAreaInsets
        ?? .zero
}

private struct AppInteractionTapObserver: UIViewRepresentable {
    let isEnabled: Bool
    let excludedFrame: CGRect
    let onOutsideTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutsideTap: onOutsideTap)
    }

    func makeUIView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.isUserInteractionEnabled = false
        view.windowDidChange = { [weak coordinator = context.coordinator, weak view] window in
            coordinator?.update(window: window, referenceView: view)
        }
        return view
    }

    func updateUIView(_ uiView: WindowAttachmentView, context: Context) {
        context.coordinator.onOutsideTap = onOutsideTap
        context.coordinator.excludedFrame = excludedFrame
        context.coordinator.setEnabled(isEnabled, window: uiView.window, referenceView: uiView)
    }

    static func dismantleUIView(_ uiView: WindowAttachmentView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.windowDidChange = nil
    }

    final class WindowAttachmentView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onOutsideTap: () -> Void
        var excludedFrame: CGRect = .null
        private weak var window: UIWindow?
        private weak var referenceView: UIView?
        private var recognizer: UITapGestureRecognizer?
        private var isEnabled = false
        private var ignoreTouchesUntil = Date.distantPast

        init(onOutsideTap: @escaping () -> Void) {
            self.onOutsideTap = onOutsideTap
        }

        func update(window: UIWindow?, referenceView: UIView?) {
            self.referenceView = referenceView
            guard isEnabled else { return }
            attach(to: window)
        }

        func setEnabled(_ enabled: Bool, window: UIWindow?, referenceView: UIView?) {
            self.referenceView = referenceView
            if enabled, !isEnabled {
                // On iOS 15/16 a recognizer installed from a Button action can
                // still observe the touch that installed it.
                ignoreTouchesUntil = Date().addingTimeInterval(0.2)
            }
            isEnabled = enabled
            enabled ? attach(to: window) : detach()
        }

        func detach() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        private func attach(to window: UIWindow?) {
            guard let window else { return }
            if self.window === window, recognizer != nil { return }
            detach()
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            self.window = window
        }

        @objc private func handleTap() {
            onOutsideTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard Date() >= ignoreTouchesUntil, let window else { return false }
            let locationInWindow = touch.location(in: window)
            let location = referenceView?.convert(locationInWindow, from: window) ?? locationInWindow
            return excludedFrame.isNull || !excludedFrame.contains(location)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
