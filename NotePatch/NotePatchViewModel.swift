import Foundation
import Combine
import SwiftUI
import UIKit

private let taskPollIntervalNanoseconds: UInt64 = 1_500_000_000
private let completeUploadMaxRetries = 20
private let defaultPresenceHeartbeatIntervalSeconds = 30
private let defaultPersonalWorkspaceName = "My Workspace"

private enum DeferredWorkspaceContent: Hashable {
    case home
    case notes
    case chat
    case learning
}

private struct DeferredWorkspaceLoadKey: Hashable {
    let workspaceId: String
    let content: DeferredWorkspaceContent
}

private struct PendingProfileUpdate: Equatable {
    let name: String
    let email: String
    let currentPassword: String
    let idempotencyKey: String
}

enum WorkbenchTab: Int, CaseIterable, Identifiable {
    case home
    case notes
    case openClaw
    case profile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return localized("tab.home")
        case .notes: return localized("tab.notes")
        case .openClaw: return localized("tab.ai")
        case .profile: return localized("tab.me")
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .notes: return "note.text"
        case .openClaw: return "sparkles.rectangle.stack.fill"
        case .profile: return "person.crop.circle"
        }
    }
}

@MainActor
final class WorkbenchNavigationState: ObservableObject {
    @Published var selectedTab: WorkbenchTab = .home
    @Published var isUploadPresented = false
    @Published var bottomBarFrame: CGRect = .null
    @Published var isBottomBarHiddenForKeyboard = false
}

@MainActor
final class AuthenticationState: ObservableObject {
    @Published var session: SavedSession?

    init(session: SavedSession?) {
        self.session = session
    }
}

enum DocumentsSection: String, CaseIterable, Identifiable {
    case documents
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return localized("documents.section.documents")
        case .tasks: return localized("documents.section.tasks")
        }
    }
}

enum HomeDestination: String, Identifiable {
    case documents
    case tasks

    var id: String { rawValue }
}

enum LearningSection: String, CaseIterable, Identifiable {
    case notes
    case units
    case search
    case homework
    case flashcards

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notes: return localized("review.section.notes")
        case .units: return localized("review.section.units")
        case .search: return localized("review.section.search")
        case .homework: return localized("review.section.homework")
        case .flashcards: return localized("review.section.flashcards")
        }
    }
}

enum OpenClawChatRole: Equatable {
    case user
    case assistant
    case system
}

enum OpenClawMessageStatus: Equatable {
    case sending
    case done
    case error
    case stopped
}

enum OpenClawAttachmentStatus: Equatable {
    case uploading
    case ready
    case unavailable
}

struct OpenClawChatAttachment: Identifiable, Equatable {
    let id: UUID
    let file: LocalUploadFile
    var documentId: String?
    var status: OpenClawAttachmentStatus

    init(file: LocalUploadFile, documentId: String? = nil, status: OpenClawAttachmentStatus = .uploading) {
        id = file.id
        self.file = file
        self.documentId = documentId
        self.status = status
    }
}

struct OpenClawChatMessage: Identifiable, Equatable {
    let id: String
    let role: OpenClawChatRole
    var content: String
    var streamingContent: String
    var reasoningContent: String
    var status: OpenClawMessageStatus
    var taskId: String?
    var progress: Int?
    var events: [TaskEventItem]
    var citations: [ChatCitation]
    var sourceStatus: String?
    var modelId: String?
    var attachments: [OpenClawChatAttachment]
    var streamTruncated: Bool
    var reasoningUnavailable: Bool

    init(
        id: String,
        role: OpenClawChatRole,
        content: String,
        streamingContent: String = "",
        reasoningContent: String = "",
        status: OpenClawMessageStatus,
        taskId: String?,
        progress: Int?,
        events: [TaskEventItem],
        citations: [ChatCitation] = [],
        sourceStatus: String? = nil,
        modelId: String? = nil,
        attachments: [OpenClawChatAttachment] = [],
        streamTruncated: Bool = false,
        reasoningUnavailable: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.streamingContent = streamingContent
        self.reasoningContent = reasoningContent
        self.status = status
        self.taskId = taskId
        self.progress = progress
        self.events = events
        self.citations = citations
        self.sourceStatus = sourceStatus
        self.modelId = modelId
        self.attachments = attachments
        self.streamTruncated = streamTruncated
        self.reasoningUnavailable = reasoningUnavailable
    }
}

@MainActor
final class NotePatchViewModel: ObservableObject {
    let homeDashboardState: HomeDashboardState
    let workbenchNavigationState: WorkbenchNavigationState
    let authenticationState: AuthenticationState
    let userProfileState: UserProfileState
    let learningWorkflowState: LearningWorkflowState
    let aiExperienceState: AIExperienceState
    @Published var apiBaseURLText: String
    @Published var tusBaseURLText: String
    @Published var emailText: String
    @Published var passwordText = ""
    @Published var fullNameText: String
    @Published var isBusy = false
    @Published private(set) var isGlobalFeedbackEnabled: Bool
    @Published private(set) var feedbackDismissalRevision: UInt = 0
    @Published private var statusDisplayText: AppDisplayText = .raw("")
    @Published private var errorDisplayText: AppDisplayText?
    @Published var selectedDocumentsSection: DocumentsSection = .documents

    @Published var workspaces: [WorkspaceItem] = []
    @Published var selectedWorkspaceId: String?
    @Published var documents: [LearningDocumentItem] = [] {
        didSet {
            homeDashboardState.updateDocuments(documents)
            reconcileImageRemarkTracking(with: documents)
        }
    }
    @Published var activeTask: TaskItem? {
        didSet { homeDashboardState.updateActiveTask(activeTask) }
    }
    @Published var taskEvents: [TaskEventItem] = []
    @Published private(set) var isDocumentPurgeRetryAvailable = false
    @Published var selectedArtifactDocumentId: String?
    @Published var selectedArtifacts: [DocumentArtifactItem] = []
    @Published var selectedOcrDocumentId: String?
    @Published var selectedOcrArtifacts: [OcrArtifactItem] = []

    @Published var uploadDocumentKind = "homework"
    @Published var statusFilter = ""
    @Published var documentKindFilter = ""
    @Published var fileTypeFilter = ""
    @Published var uploadProgressPercent: Int?
    @Published private var uploadProgressDisplayText: AppDisplayText = .raw("")
    let openClawState: OpenClawViewState
    let openClawComposerState: OpenClawComposerState
    @Published var aiHistoryEnabled = true
    @Published private(set) var isAIPreferenceUpdating = false
    @Published var autoImageRemarkEnabled = true
    @Published private(set) var isAutoImageRemarkPreferenceUpdating = false
    @Published private(set) var documentRemarkUpdatingId: String?
    @Published var noteContentEditLevel: NoteContentEditLevel = .conceptual
    @Published var noteLayoutEditLevel: NoteLayoutEditLevel = .minor
    @Published var noteHistoryLimit = 3
    @Published var notePreferenceDraftContent: NoteContentEditLevel = .conceptual
    @Published var notePreferenceDraftLayout: NoteLayoutEditLevel = .minor
    @Published var notePreferenceDraftHistoryLimit = 3
    @Published private(set) var isNotePreferenceUpdating = false
    @Published private(set) var aiModelCatalog: AiModelCatalog?
    @Published var selectedAIModelId: String?
    @Published private(set) var isAIModelsLoading = false
    @Published private(set) var isAIModelUpdating = false
    @Published private var aiModelsErrorText: AppDisplayText?
    @Published var learningUnits: [LearningUnit] = []
    @Published var selectedLearningUnitId: String?
    @Published var studyNotes: [StudyNoteVersion] = []
    @Published var isLearningLoading = false
    @Published var studyNoteGroups: [StudyNoteGroup] = []
    @Published var isNotesLoading = false
    @Published var selectedStudyNoteItem: StudyNoteListItem?
    @Published var studyNoteHTML: String?
    @Published var studyNoteRenderedURL: URL?
    @Published private var studyNoteReaderErrorText: AppDisplayText?
    @Published var isStudyNoteLoading = false
    @Published var isStudyNoteEditorPresented = false
    @Published var isStudyNoteEditorLoading = false
    @Published var studyNoteDraftTitle = ""
    @Published var studyNoteDraftHTML = ""
    @Published var studyNoteDraftSummary = ""
    @Published private var studyNoteEditorErrorText: AppDisplayText?
    @Published var isStudyNoteSaving = false
    @Published var isStudyNoteConflictPending = false
    @Published var isNoteGapPresented = false
    @Published private(set) var noteGaps: [NoteGap] = []
    @Published var selectedNoteGapDetail: NoteGapDetail?
    @Published private(set) var isNoteGapLoading = false
    @Published var selectedNoBaseGapIds = Set<String>()
    @Published var selectedGapSourceRefs = Set<NoteSourceReference>()
    @Published var noteGapInstruction = ""
    @Published var noteGapFeedback = ""
    @Published var noteGapDraftHTML = ""
    @Published var noteGapInsertPosition = "after"
    @Published var isNoteCorrectionsPresented = false
    @Published private(set) var studyNoteCorrections: [StudyNoteCorrection] = []
    @Published private(set) var isStudyNoteCorrectionsLoading = false
    @Published var selectedLearningSection: LearningSection = .notes
    @Published var isStudyNoteGenerationPresented = false
    @Published var studyNoteGenerationUnitId = ""
    @Published var studyNoteGenerationUsesOverride = false
    @Published var studyNoteGenerationContentLevel: NoteContentEditLevel = .conceptual
    @Published var studyNoteGenerationLayoutLevel: NoteLayoutEditLevel = .minor
    @Published var studyNoteGenerationForceReprocess = false
    @Published private(set) var isStudyNoteGenerating = false
    @Published var isLearningUnitMergePresented = false
    @Published var isLearningUnitMergeConfirmationPresented = false
    @Published var mergeTargetLearningUnitId = ""
    @Published var mergeSourceLearningUnitIds = Set<String>()
    @Published private(set) var isLearningUnitMerging = false
    @Published private(set) var activeMergeTargetLearningUnitId: String?
    @Published var selectedFlashcardLearningUnitId = ""
    @Published var flashcardDecks: [FlashcardDeck] = []
    @Published var selectedFlashcardDeckId: String?
    @Published var flashcardDeckDetail: FlashcardDeckDetail?
    @Published var flashcardIndex = 0
    @Published var isFlashcardShowingBack = false
    @Published var isFlashcardsLoading = false
    @Published private var flashcardErrorText: AppDisplayText?
    @Published var knowledgeQuery = ""
    @Published var knowledgeLearningUnitId = ""
    @Published var knowledgeSubject = ""
    @Published var knowledgeLimit = 6
    @Published var knowledgeResults: [KnowledgeSearchItem] = []
    @Published var hasSearchedKnowledge = false
    @Published var isKnowledgeSearching = false
    @Published var homeworks: [HomeworkItem] = []
    @Published var gradingDocuments: [LearningDocumentItem] = []
    @Published var selectedHomeworkId: String?
    @Published var homeworkReferences: [HomeworkReferenceItem] = []
    @Published private(set) var gradingResults: [GradingResult] = []
    @Published private(set) var isGradingHistoryLoading = false
    @Published private var gradingHistoryErrorText: AppDisplayText?
    @Published var homeworkRubricText = ""
    @Published var homeworkMaxScoreText = "100"
    @Published var isHomeworkLoading = false
    @Published var lastGradingTask: TaskItem?
    @Published var uploadLearningUnitId = ""
    @Published var uploadLearningUnitTitle = ""
    @Published var uploadSubject = ""
    @Published var uploadGradeLevel = ""
    @Published var uploadTopic = ""
    @Published var uploadUsesCustomNoteStrategy = false
    @Published var uploadNoteContentEditLevel: NoteContentEditLevel = .conceptual
    @Published var uploadNoteLayoutEditLevel: NoteLayoutEditLevel = .minor
    @Published var isContinuousNoteUploadEnabled = false
    @Published var continuousNoteTitle = ""
    @Published private(set) var activeNoteSet: NoteSet?
    @Published var downloadedPreview: DownloadedPreview?
    @Published private(set) var previewLoadingDocumentIds = Set<String>()
    @Published var queuedUploadItems: [QueuedUploadItem] = []
    @Published var isLearningUploadFormatConfirmationPresented = false
    @Published private(set) var pendingLearningFormatConversionIds: [UUID] = []
    @Published private(set) var isOfflineTestMode = false

    private let settings: SettingsStore
    private let backendSession: URLSession
    private let tusSession: URLSession
    private let cacheDirectory: URL
    private let taskEventStreamingEnabled: Bool
    private let imageRemarkSecondNanoseconds: UInt64
    private var nextOpenClawMessageId: Int64 = 1
    private var presenceTask: Task<Void, Never>?
    private var studyNoteGenerationPollingTask: Task<Void, Never>?
    private var aiModelLoadTask: Task<Void, Never>?
    private var aiModelLoadGeneration = UUID()
    private var aiModelCatalogWorkspaceId: String?
    private var aiModelSelectionTask: Task<Void, Never>?
    private var aiModelSelectionGeneration = UUID()
    private var isAppActive = true
    private var didRestoreSession = false
    private var didInstallFeedbackUITestFixture = false
    private var pendingUITestUploadFile: LocalUploadFile?
    private var retryableDocumentPurgeId: String?
    private var workflowLoadTask: Task<Void, Never>?
    private var workflowMonitorTask: Task<Void, Never>?
    private var workflowGeneration = UUID()
    private var renderedStudyNoteRefreshAttempted = false
    private var chatAttachmentsByMessageId: [String: [OpenClawChatAttachment]] = [:]
    private var preparedChatAttachmentDocuments: [UUID: LearningDocumentItem] = [:]
    private var openClawChatTask: Task<Void, Never>?
    private var openClawChatGeneration = UUID()
    private var conversationLoadTask: Task<Void, Never>?
    private var conversationLoadGeneration = UUID()
    private var conversationMutationGeneration = UUID()
    private var messageRevisionTask: Task<Void, Never>?
    private var messageRevisionGeneration = UUID()
    private var aiPreferenceTask: Task<Void, Never>?
    private var aiPreferenceGeneration = UUID()
    private var autoImageRemarkPreferenceTask: Task<Void, Never>?
    private var autoImageRemarkPreferenceGeneration = UUID()
    private var imageRemarkTrackingTask: Task<Void, Never>?
    private var imageRemarkTrackingGeneration = UUID()
    private var trackedImageRemarkDocumentIds = Set<String>()
    private var documentRemarkUpdateTask: Task<Void, Never>?
    private var documentRemarkUpdateGeneration = UUID()
    private var notePreferenceTask: Task<Void, Never>?
    private var notePreferenceGeneration = UUID()
    private var homeworkSelectionTask: Task<Void, Never>?
    private var homeworkSelectionGeneration = UUID()
    private var gradingHistoryTask: Task<Void, Never>?
    private var gradingHistoryGeneration = UUID()
    private var gradingHistoryWorkspaceId: String?
    private var gradingHistoryHomeworkId: String?
    private var flashcardLoadTask: Task<Void, Never>?
    private var flashcardLoadGeneration = UUID()
    private var knowledgeSearchTask: Task<Void, Never>?
    private var knowledgeSearchGeneration = UUID()
    private var profileLoadTask: Task<Void, Never>?
    private var profileSaveTask: Task<Void, Never>?
    private var avatarUploadTask: Task<Void, Never>?
    private var profileGeneration = UUID()
    private var pendingProfileUpdate: PendingProfileUpdate?
    private var pendingAvatarUpload: (data: Data, key: String)?
    private var uploadImportGeneration = UUID()
    private var uploadQueueGeneration = UUID()
    private var activeNoteSetItemIds: [UUID] = []
    private var learningUnitSelectionGeneration = UUID()
    private var workspaceContentGeneration = UUID()
    private var learningContentGeneration = UUID()
    private var homeworkContentGeneration = UUID()
    private var studyNoteReaderGeneration = UUID()
    private var studyNoteSaveGeneration = UUID()
    private var studyNoteGenerateTask: Task<Void, Never>?
    private var noteGapTask: Task<Void, Never>?
    private var noteGapGeneration = UUID()
    private var noteCorrectionsTask: Task<Void, Never>?
    private var loadedDeferredContent = Set<DeferredWorkspaceLoadKey>()
    private var deferredLoadTasks: [DeferredWorkspaceLoadKey: Task<Void, Never>] = [:]
    private var deferredLoadGenerations: [DeferredWorkspaceLoadKey: UUID] = [:]

    var uploadCacheDirectory: URL { cacheDirectory }

    var session: SavedSession? {
        get { authenticationState.session }
        set {
            guard authenticationState.session != newValue else { return }
            objectWillChange.send()
            authenticationState.session = newValue
        }
    }

    var selectedTab: WorkbenchTab {
        get { workbenchNavigationState.selectedTab }
        set { workbenchNavigationState.selectedTab = newValue }
    }

    var aiModelsError: String? { aiModelsErrorText?.resolved() }
    var studyNoteReaderError: String? { studyNoteReaderErrorText?.resolved() }
    var studyNoteEditorError: String? { studyNoteEditorErrorText?.resolved() }
    var flashcardError: String? { flashcardErrorText?.resolved() }
    var gradingHistoryError: String? { gradingHistoryErrorText?.resolved() }

    var selectedHomeDestination: HomeDestination? {
        get { homeDashboardState.destination }
        set { homeDashboardState.destination = newValue }
    }

    var workflows: [WorkflowRun] {
        get { learningWorkflowState.workflows }
        set { learningWorkflowState.workflows = newValue }
    }

    var activeWorkflowDetail: WorkflowDetail? {
        get { learningWorkflowState.activeDetail }
        set {
            learningWorkflowState.activeDetail = newValue
            let homeWorkflow = newValue?.workflow.isTerminal == false ? newValue?.workflow : nil
            homeDashboardState.updateActiveWorkflow(homeWorkflow)
        }
    }

    var workflowEvents: [WorkflowEvent] {
        get { learningWorkflowState.events }
        set { learningWorkflowState.events = newValue }
    }

    var isWorkflowsLoading: Bool {
        get { learningWorkflowState.isLoading }
        set { learningWorkflowState.isLoading = newValue }
    }

    var statusMessage: String {
        get { statusDisplayText.resolved() }
        set { statusDisplayText = .raw(newValue) }
    }

    var errorMessage: String? {
        get { errorDisplayText?.resolved() }
        set { errorDisplayText = newValue.map { .raw($0) } }
    }

    var uploadProgressLabel: String {
        get { uploadProgressDisplayText.resolved() }
        set { uploadProgressDisplayText = .raw(newValue) }
    }

    private func setStatus(_ key: String, _ arguments: String...) {
        statusDisplayText = .localized(key, arguments)
    }

    private func setError(_ key: String, _ arguments: String...) {
        errorDisplayText = .localized(key, arguments)
    }

    private func setRawError(_ message: String) {
        errorDisplayText = .raw(message)
    }

    private func setUploadProgress(_ key: String, _ arguments: String...) {
        uploadProgressDisplayText = .localized(key, arguments)
    }

    func presentError(_ error: Error) {
        showError(error)
    }

    func presentError(_ displayText: AppDisplayText) {
        errorDisplayText = displayText
    }

    func presentStatus(_ key: String, _ arguments: String...) {
        statusDisplayText = .localized(key, arguments)
        errorDisplayText = nil
    }

    var openClawInput: String {
        get { openClawComposerState.text }
        set { openClawComposerState.text = newValue }
    }

    var openClawMessages: [OpenClawChatMessage] {
        get { openClawState.messages }
        set { openClawState.messages = newValue }
    }

    var isOpenClawSending: Bool {
        get { openClawState.isSending }
        set { openClawState.isSending = newValue }
    }

    var conversations: [ChatConversation] {
        get { openClawState.conversations }
        set { openClawState.conversations = newValue }
    }

    var selectedConversationId: String? {
        get { openClawState.selectedConversationId }
        set { openClawState.selectedConversationId = newValue }
    }

    var isChatHistoryLoading: Bool {
        get { openClawState.isHistoryLoading }
        set { openClawState.isHistoryLoading = newValue }
    }

    private(set) var isConversationMutating: Bool {
        get { openClawState.isConversationMutating }
        set {
            guard openClawState.isConversationMutating != newValue else { return }
            objectWillChange.send()
            openClawState.isConversationMutating = newValue
        }
    }

    convenience init() {
        self.init(settings: SettingsStore())
    }

    init(
        settings: SettingsStore,
        backendSession: URLSession = .shared,
        tusSession: URLSession = .shared,
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory,
        taskEventStreamingEnabled: Bool = true,
        imageRemarkSecondNanoseconds: UInt64 = 1_000_000_000
    ) {
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestResetGlobalFeedback") {
            settings.saveGlobalFeedbackEnabled(true)
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestNoSession") {
            settings.clearSession()
        }
        let loadedSession = settings.loadSession()
        self.homeDashboardState = HomeDashboardState()
        self.workbenchNavigationState = WorkbenchNavigationState()
        self.authenticationState = AuthenticationState(session: loadedSession)
        self.userProfileState = UserProfileState()
        self.learningWorkflowState = LearningWorkflowState()
        self.aiExperienceState = AIExperienceState()
        self.openClawState = OpenClawViewState()
        self.openClawComposerState = OpenClawComposerState()
        self.settings = settings
        self.backendSession = backendSession
        self.tusSession = tusSession
        self.cacheDirectory = cacheDirectory
        self.taskEventStreamingEnabled = taskEventStreamingEnabled
        self.imageRemarkSecondNanoseconds = imageRemarkSecondNanoseconds
        self.apiBaseURLText = loadedSession?.baseURL ?? settings.loadBaseURL()
        self.tusBaseURLText = loadedSession?.tusBaseURL ?? settings.loadTUSBaseURL()
        self.emailText = loadedSession?.email ?? ""
        self.fullNameText = loadedSession?.fullName ?? ""
        self.isGlobalFeedbackEnabled = settings.loadGlobalFeedbackEnabled()
        self.selectedWorkspaceId = loadedSession?.selectedWorkspaceId
        self.aiHistoryEnabled = loadedSession?.aiHistoryEnabled ?? true
        self.autoImageRemarkEnabled = loadedSession?.autoImageRemarkEnabled ?? true
        self.noteContentEditLevel = loadedSession?.noteContentEditLevel ?? .conceptual
        self.noteLayoutEditLevel = loadedSession?.noteLayoutEditLevel ?? .minor
        self.noteHistoryLimit = loadedSession?.noteHistoryLimit ?? 3
        self.notePreferenceDraftContent = loadedSession?.noteContentEditLevel ?? .conceptual
        self.notePreferenceDraftLayout = loadedSession?.noteLayoutEditLevel ?? .minor
        self.notePreferenceDraftHistoryLimit = loadedSession?.noteHistoryLimit ?? 3
        self.uploadNoteContentEditLevel = loadedSession?.noteContentEditLevel ?? .conceptual
        self.uploadNoteLayoutEditLevel = loadedSession?.noteLayoutEditLevel ?? .minor
        self.openClawState.messages = []
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") {
            activateOfflineTestMode()
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestPendingImage") {
            if let file = makeUITestPendingImage(in: cacheDirectory) {
                queuedUploadItems = [QueuedUploadItem(file: file, documentKind: uploadDocumentKind, learningMetadata: uploadLearningMetadata)]
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestExtendedLearningConflict"),
           let file = makeUITestPendingFile(named: "workbook.xlsx", in: cacheDirectory) {
            queuedUploadItems = [QueuedUploadItem(
                file: file,
                documentKind: "courseware",
                learningMetadata: LearningMetadata(subject: "math")
            )]
        }
    }

    func installFeedbackUITestFixtureIfNeeded() async {
        guard !didInstallFeedbackUITestFixture else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-NotePatchUITestFeedback") }) else { return }
        didInstallFeedbackUITestFixture = true
        if arguments.contains("-NotePatchUITestFeedbackSuccess") { return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if arguments.contains("-NotePatchUITestFeedbackBusy") {
            isBusy = true
            setStatus("common.processing")
        } else if arguments.contains("-NotePatchUITestFeedbackUploadError") {
            workbenchNavigationState.isUploadPresented = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            setRawError("Upload failed")
        } else if arguments.contains("-NotePatchUITestFeedbackError") {
            setRawError("Connection failed")
        } else {
            presentStatus("operation.api_connected")
        }
    }

    func restoreIfNeeded() async {
        guard !didRestoreSession, let activeSession = session else {
            return
        }
        didRestoreSession = true
        isBusy = true
        setStatus("operation.restoring_session")
        errorMessage = nil
        do {
            try await loadWorkspaces(activeSession: activeSession, preferredWorkspaceId: activeSession.selectedWorkspaceId)
            startPresence(activeSession: settings.loadSession() ?? session ?? activeSession)
        } catch {
            showError(error)
        }
        isBusy = false
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isAppActive = true
            resumeStudyNoteGenerationPollingIfNeeded()
            startImageRemarkTrackingIfNeeded()
            if !isOfflineTestMode, let session {
                startPresence(activeSession: session)
            }
        case .background, .inactive:
            isAppActive = false
            stopStudyNoteGenerationPolling()
            stopImageRemarkTracking(clearTrackedDocuments: false)
            if !isOfflineTestMode {
                stopPresence(activeSession: session, sendOffline: true, clearClientId: false)
            }
        @unknown default:
            break
        }
    }

    func ensureContentForSelectedTabLoaded() {
        switch selectedTab {
        case .home:
            stopStudyNoteGenerationPolling()
            loadHomeDashboard(force: false)
        case .notes:
            if selectedLearningSection == .notes {
                loadNotesOverview(force: false)
            } else {
                loadLearningDashboard(force: false)
                if selectedLearningSection == .flashcards {
                    ensureFlashcardsLoaded()
                }
            }
            resumeStudyNoteGenerationPollingIfNeeded()
        case .openClaw:
            stopStudyNoteGenerationPolling()
            loadChatHistory(force: false)
        case .profile:
            stopStudyNoteGenerationPolling()
            loadAIModels()
            loadUserProfile()
        }
    }

    func loadHomeDashboard(force: Bool = true) {
        if isOfflineTestMode {
            homeDashboardState.applySupplementaryContent(
                learningUnits: learningUnits,
                homeworks: homeworks,
                noteGroups: studyNoteGroups
            )
            return
        }
        loadWorkflows(force: force)
        beginDeferredLoad(
            .home,
            force: force,
            allowOfflineNetwork: false,
            showsGlobalError: false,
            setLoading: { [weak self] isLoading in
                guard let self else { return }
                if isLoading {
                    self.homeDashboardState.beginSupplementaryLoad()
                } else if self.homeDashboardState.isLoadingSupplementaryContent {
                    self.homeDashboardState.finishSupplementaryLoad(error: nil)
                }
            }
        ) { [weak self] activeSession, workspaceId, isCurrent in
            guard let self else { return }
            do {
                let client = self.clientFor(activeSession)
                async let unitsRequest = client.listLearningUnits(workspaceId: workspaceId)
                async let homeworksRequest = client.listHomeworks(workspaceId: workspaceId)
                let (units, loadedHomeworks) = try await (
                    unitsRequest,
                    homeworksRequest
                )
                guard isCurrent() else { throw CancellationError() }
                let noteResults = await self.loadStudyNoteGroupsConcurrently(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    units: units
                )
                guard isCurrent() else { throw CancellationError() }
                let groups = noteResults.compactMap(\.group)
                self.learningUnits = units
                self.homeworks = loadedHomeworks
                self.gradingDocuments = self.documents
                self.studyNoteGroups = groups
                self.homeDashboardState.applySupplementaryContent(
                    learningUnits: units,
                    homeworks: loadedHomeworks,
                    noteGroups: groups
                )
                self.loadedDeferredContent.insert(
                    DeferredWorkspaceLoadKey(workspaceId: workspaceId, content: .notes)
                )
                self.loadedDeferredContent.insert(
                    DeferredWorkspaceLoadKey(workspaceId: workspaceId, content: .learning)
                )
            } catch {
                if isCurrent() {
                    self.homeDashboardState.finishSupplementaryLoad(error: friendlyDisplayText(error))
                }
                throw error
            }
        }
    }

    func refreshHomeDashboard() {
        refreshCurrentWorkspace()
        loadHomeDashboard(force: true)
    }

    func dismissGlobalFeedback() {
        feedbackDismissalRevision &+= 1
        errorMessage = nil
        statusMessage = ""
    }

    func updateGlobalFeedbackEnabled(_ enabled: Bool) {
        guard enabled != isGlobalFeedbackEnabled else { return }
        isGlobalFeedbackEnabled = enabled
        settings.saveGlobalFeedbackEnabled(enabled)
        if !enabled {
            AppFeedbackDismissalCenter.shared.dismiss()
            NotificationCenter.default.post(name: .notePatchDismissGlobalFeedback, object: nil)
        }
        dismissGlobalFeedback()
    }

    func checkAPIConnection() {
        let baseURL = normalizedAPIBaseURL()
        apiBaseURLText = baseURL
        settings.saveBaseURL(baseURL)
        Task {
            isBusy = true
            defer { isBusy = false }
            errorMessage = nil
            setStatus("operation.checking_api")
            do {
                _ = try await LearningBackendClient(baseURL: baseURL, session: backendSession).healthCheck()
                setStatus("operation.api_connected")
            } catch {
                showError(error)
            }
        }
    }

    func checkTUSConnection() {
        let tusBaseURL = normalizedTUSBaseURL()
        tusBaseURLText = tusBaseURL
        settings.saveTUSBaseURL(tusBaseURL)
        Task {
            isBusy = true
            defer { isBusy = false }
            errorMessage = nil
            setStatus("operation.checking_upload_service")
            do {
                try await TusUploader.checkEndpoint(tusBaseURL, session: tusSession)
                setStatus("operation.upload_service_connected")
            } catch {
                showError(error)
            }
        }
    }

    func authenticate(register: Bool) {
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !register, email.lowercased() == "uitest" {
            activateOfflineTestMode()
            return
        }
        let baseURL = normalizedAPIBaseURL()
        let tusBaseURL = normalizedTUSBaseURL()
        let password = passwordText
        let fullName = fullNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || password.isEmpty {
            setError("auth.error.credentials_required")
            return
        }
        if register, password.count < 8 {
            setError("auth.error.password_length")
            return
        }

        Task {
            isBusy = true
            defer { isBusy = false }
            errorMessage = nil
            setStatus(register ? "operation.registering" : "operation.signing_in")
            do {
                let client = LearningBackendClient(baseURL: baseURL, session: backendSession)
                let token: TokenResponse
                if register {
                    token = try await client.register(email: email, password: password, fullName: fullName.isEmpty ? nil : fullName)
                } else {
                    token = try await client.login(email: email, password: password)
                }
                let previousUserId = (settings.loadSession() ?? session)?.userId
                if previousUserId != token.user.id {
                    settings.clearPresenceClientId()
                }
                let savedSession = SavedSession(
                    baseURL: baseURL,
                    tusBaseURL: tusBaseURL,
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken,
                    expiresAt: token.expiresAt,
                    userId: token.user.id,
                    email: token.user.email,
                    fullName: token.user.fullName,
                    selectedWorkspaceId: nil,
                    aiHistoryEnabled: token.user.aiHistoryEnabled,
                    autoImageRemarkEnabled: token.user.autoImageRemarkEnabled,
                    noteContentEditLevel: token.user.noteContentEditLevel,
                    noteLayoutEditLevel: token.user.noteLayoutEditLevel,
                    noteHistoryLimit: token.user.noteHistoryLimit,
                    aiOnboardingVersion: token.user.aiOnboardingVersion,
                    aiOnboardingCompletedAt: token.user.aiOnboardingCompletedAt,
                    aiOnboardingCompleted: token.user.aiOnboardingCompleted,
                    aiPreferences: token.user.aiPreferences
                )
                saveSession(savedSession, synchronizeServerURLFields: true)
                startPresence(activeSession: savedSession)
                passwordText = ""
                setStatus("operation.loading_workspace")
                try await loadWorkspaces(activeSession: savedSession, preferredWorkspaceId: nil)
            } catch {
                showError(error)
            }
        }
    }

    func saveServerURLs() {
        let baseURL = normalizedAPIBaseURL()
        let tusBaseURL = normalizedTUSBaseURL()
        apiBaseURLText = baseURL
        tusBaseURLText = tusBaseURL
        settings.saveBaseURL(baseURL)
        settings.saveTUSBaseURL(tusBaseURL)
        if let activeSession = settings.loadSession() ?? session {
            saveSession(
                SavedSession(
                    baseURL: baseURL,
                    tusBaseURL: tusBaseURL,
                    accessToken: activeSession.accessToken,
                    refreshToken: activeSession.refreshToken,
                    expiresAt: activeSession.expiresAt,
                    userId: activeSession.userId,
                    email: activeSession.email,
                    fullName: activeSession.fullName,
                    selectedWorkspaceId: activeSession.selectedWorkspaceId,
                    aiHistoryEnabled: activeSession.aiHistoryEnabled,
                    autoImageRemarkEnabled: activeSession.autoImageRemarkEnabled,
                    noteContentEditLevel: activeSession.noteContentEditLevel,
                    noteLayoutEditLevel: activeSession.noteLayoutEditLevel,
                    noteHistoryLimit: activeSession.noteHistoryLimit,
                    aiOnboardingVersion: activeSession.aiOnboardingVersion,
                    aiOnboardingCompletedAt: activeSession.aiOnboardingCompletedAt,
                    aiOnboardingCompleted: activeSession.aiOnboardingCompleted,
                    aiPreferences: activeSession.aiPreferences
                ),
                synchronizeServerURLFields: true
            )
        }
        setStatus("operation.server_saved")
        errorMessage = nil
    }

    func logout() {
        let activeSession = session
        let wasOfflineTestMode = isOfflineTestMode
        stopPresence(activeSession: activeSession, sendOffline: true, clearClientId: true)
        clearLocalSession()
        statusMessage = ""
        errorMessage = nil
        if let activeSession, !wasOfflineTestMode {
            Task {
                try? await LearningBackendClient(baseURL: activeSession.baseURL, session: backendSession)
                    .logout(refreshToken: activeSession.refreshToken)
            }
        }
    }

    func refreshCurrentWorkspace() {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        guard let workspaceId = selectedWorkspaceId else {
            setError("workspace.error.required")
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("operation.refreshing_documents")
            do {
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                setStatus("operation.documents_refreshed")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func selectWorkspace(_ workspaceId: String) {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        clearLearningWorkspaceState()
        saveSelectedWorkspace(workspaceId)
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            selectedArtifacts = []
            selectedArtifactDocumentId = nil
            setStatus("operation.switching_workspace")
            do {
                try await refreshWorkspaceContent(activeSession: session ?? activeSession, workspaceId: workspaceId)
                let name = workspaces.first(where: { $0.id == workspaceId })?.name ?? workspaceId
                setStatus("workspace.switched", name)
            } catch {
                showError(error)
            }
        }
    }

    func recoverPersonalWorkspace() {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentSessionContext(activeSession) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("operation.recovering_workspace")
            do {
                let client = clientFor(activeSession)
                let workspace: WorkspaceItem
                do {
                    workspace = try await client.createWorkspace(name: defaultPersonalWorkspaceName)
                } catch let error as LearningBackendError where error.statusCode == 409 {
                    let loadedWorkspaces = try await client.listWorkspaces()
                    guard let existing = loadedWorkspaces.first(where: { $0.type == "personal" }) ?? loadedWorkspaces.first else {
                        throw error
                    }
                    workspace = existing
                }
                guard isCurrentSessionContext(activeSession) else { return }
                try await loadWorkspaces(activeSession: activeSession, preferredWorkspaceId: workspace.id)
                guard isCurrentSessionContext(activeSession) else { return }
                setStatus("operation.workspace_recovered")
            } catch {
                guard isCurrentSessionContext(activeSession) else { return }
                showError(error)
            }
        }
    }

    func setStatusFilter(_ value: String) {
        statusFilter = value
        refreshCurrentWorkspace()
    }

    func setDocumentKindFilter(_ value: String) {
        documentKindFilter = value
        refreshCurrentWorkspace()
    }

    func setFileTypeFilter(_ value: String) {
        fileTypeFilter = value
        refreshCurrentWorkspace()
    }

    func uploadPickedFile(from sourceURL: URL) {
        uploadPickedFiles(from: [sourceURL])
    }

    func uploadPickedFiles(
        from sourceURLs: [URL],
        expectedUserId: String? = nil,
        expectedWorkspaceId: String? = nil
    ) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        if let expectedUserId, let expectedWorkspaceId,
           (activeSession.userId != expectedUserId || workspaceId != expectedWorkspaceId) {
            return
        }
        let importGeneration = uploadImportGeneration
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        Task {
            isBusy = true
            errorMessage = nil
            defer { isBusy = false }
            setStatus("operation.reading_files")
            let outcomes = await FileImportService.shared.importFiles(
                sourceURLs,
                fallbackPrefix: "file",
                cacheDirectory: cacheDirectory
            )
            guard importGeneration == uploadImportGeneration,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
                discardImportedUploadFiles(outcomes.compactMap(\.file))
                return
            }
            for outcome in outcomes {
                if let uploadFile = outcome.file {
                    stageUploadFileForPreview(uploadFile, documentKind: documentKind, learningMetadata: learningMetadata)
                } else if let message = outcome.errorDisplayText {
                    errorDisplayText = message
                }
            }
        }
    }

    func uploadPhotoData(_ data: Data, suggestedFilename: String, mimeType: String?) {
        uploadPhotoData([(data: data, suggestedFilename: suggestedFilename, mimeType: mimeType)])
    }

    func uploadPhotoData(_ selections: [(data: Data, suggestedFilename: String, mimeType: String?)]) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let importGeneration = uploadImportGeneration
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        Task {
            isBusy = true
            errorMessage = nil
            defer { isBusy = false }
            setStatus("operation.reading_photos")
            let outcomes = await FileImportService.shared.writePhotos(selections, cacheDirectory: cacheDirectory)
            guard importGeneration == uploadImportGeneration,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
                discardImportedUploadFiles(outcomes.compactMap(\.file))
                return
            }
            for outcome in outcomes {
                if let uploadFile = outcome.file {
                    stageUploadFileForPreview(uploadFile, documentKind: documentKind, learningMetadata: learningMetadata)
                } else if let message = outcome.errorDisplayText {
                    errorDisplayText = message
                }
            }
        }
    }

    func uploadCameraImage(_ image: UIImage) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let importGeneration = uploadImportGeneration
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        Task {
            isBusy = true
            errorMessage = nil
            setStatus("operation.reading_image")
            do {
                let uploadFile = try await FileImportService.shared.writeCameraImage(image, cacheDirectory: cacheDirectory)
                guard importGeneration == uploadImportGeneration,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
                    discardImportedUploadFiles([uploadFile])
                    return
                }
                isBusy = false
                stageUploadFileForPreview(uploadFile, documentKind: documentKind, learningMetadata: learningMetadata)
            } catch {
                showError(error)
                isBusy = false
            }
        }
    }

    func stageUploadFileForPreview(_ uploadFile: LocalUploadFile) {
        stageUploadFileForPreview(uploadFile, documentKind: uploadDocumentKind, learningMetadata: uploadLearningMetadata)
    }

    func stageImportedUploadFiles(
        _ files: [LocalUploadFile],
        expectedUserId: String? = nil,
        expectedWorkspaceId: String? = nil
    ) {
        if let expectedUserId, let expectedWorkspaceId,
           (session?.userId != expectedUserId || selectedWorkspaceId != expectedWorkspaceId) {
            discardImportedUploadFiles(files)
            return
        }
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        for file in files {
            stageUploadFileForPreview(file, documentKind: documentKind, learningMetadata: learningMetadata)
        }
    }

    func removeOpenClawDraftAttachment(_ file: LocalUploadFile) {
        openClawComposerState.removeAttachment(file)
        preparedChatAttachmentDocuments[file.id] = nil
        UploadThumbnailCache.shared.remove(file: file)
        removeCachedUploadFile(file)
    }

    @discardableResult
    func stageOpenClawDraftAttachments(
        _ files: [LocalUploadFile],
        expectedUserId: String?,
        expectedWorkspaceId: String?
    ) -> Bool {
        guard let expectedUserId, let expectedWorkspaceId,
              session?.userId == expectedUserId,
              selectedWorkspaceId == expectedWorkspaceId else {
            discardImportedUploadFiles(files)
            return false
        }
        openClawComposerState.attachments.append(contentsOf: files)
        return true
    }

    func isCurrentImportContext(userId: String?, workspaceId: String?) -> Bool {
        guard let userId, let workspaceId else { return false }
        return session?.userId == userId && selectedWorkspaceId == workspaceId
    }

    private func stageUploadFileForPreview(
        _ uploadFile: LocalUploadFile,
        documentKind: String,
        learningMetadata: LearningMetadata
    ) {
        queuedUploadItems.append(
            QueuedUploadItem(
                file: uploadFile,
                documentKind: documentKind,
                learningMetadata: learningMetadata
            )
        )
        errorMessage = nil
        setStatus("upload.added_to_queue", uploadFile.filename)
    }

    func toggleQueuedUpload(_ id: UUID) {
        guard activeNoteSet == nil else { return }
        guard !isBusy, let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        queuedUploadItems[index].isSelected.toggle()
    }

    func removeQueuedUpload(_ id: UUID) {
        guard activeNoteSet == nil else { return }
        guard !isBusy, let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        let item = queuedUploadItems.remove(at: index)
        UploadThumbnailCache.shared.remove(file: item.file)
        removeCachedUploadFile(item.file)
    }

    func uploadSelectedQueuedFiles() {
        if isContinuousNoteUploadEnabled || activeNoteSet != nil {
            uploadSelectedContinuousNote()
            return
        }
        guard !isBusy, let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let selectedIds = queuedUploadItems.filter(\.isSelected).map(\.id)
        guard !selectedIds.isEmpty else {
            setError("upload.error.selection_required")
            return
        }
        let incompatibleIds = queuedUploadItems.compactMap { item -> UUID? in
            guard item.isSelected,
                  learningDocumentKinds.contains(item.documentKind),
                  !isSupportedLearningUpload(filename: item.file.filename, mimeType: item.file.mimeType) else {
                return nil
            }
            return item.id
        }
        if !incompatibleIds.isEmpty {
            pendingLearningFormatConversionIds = incompatibleIds
            isLearningUploadFormatConfirmationPresented = true
            return
        }

        isBusy = true
        let generation = UUID()
        uploadQueueGeneration = generation
        errorMessage = nil
        Task {
            defer {
                if uploadQueueGeneration == generation {
                    uploadProgressPercent = nil
                    uploadProgressLabel = ""
                    isBusy = false
                }
            }
            var didFail = false
            var successCount = 0
            for (offset, id) in selectedIds.enumerated() {
                guard uploadQueueGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                guard let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { continue }
                queuedUploadItems[index].state = .uploading
                let item = queuedUploadItems[index]
                setUploadProgress("upload.batch_progress", String(offset + 1), String(selectedIds.count), item.file.filename)
                uploadProgressPercent = 0
                do {
                    _ = try await performUpload(item, activeSession: activeSession, workspaceId: workspaceId)
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    if let completedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) {
                        let completed = queuedUploadItems.remove(at: completedIndex)
                        UploadThumbnailCache.shared.remove(file: completed.file)
                        removeCachedUploadFile(completed.file)
                    }
                    successCount += 1
                } catch {
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    let message = friendlyDisplayText(error)
                    didFail = true
                    if let failedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) {
                        queuedUploadItems[failedIndex].state = .failed(message)
                        queuedUploadItems[failedIndex].isSelected = true
                    }
                }
            }
            if successCount > 0 {
                try? await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
            }
            guard uploadQueueGeneration == generation,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
            if !didFail {
                setStatus("upload.selected_completed")
            } else {
                setError("upload.some_failed_generic")
            }
        }
    }

    var pendingLearningFormatConversionCount: Int {
        pendingLearningFormatConversionIds.count
    }

    func confirmLearningUploadFormatConversion() {
        guard !isBusy, !pendingLearningFormatConversionIds.isEmpty else { return }
        let pendingIds = Set(pendingLearningFormatConversionIds)
        for index in queuedUploadItems.indices where pendingIds.contains(queuedUploadItems[index].id) {
            guard queuedUploadItems[index].remoteState == nil else { continue }
            queuedUploadItems[index].documentKind = "other"
            queuedUploadItems[index].learningMetadata = LearningMetadata()
            queuedUploadItems[index].state = .pending
        }
        cancelLearningUploadFormatConversion()
        uploadSelectedQueuedFiles()
    }

    func cancelLearningUploadFormatConversion() {
        pendingLearningFormatConversionIds = []
        isLearningUploadFormatConfirmationPresented = false
    }

    func moveContinuousNotePage(_ id: UUID, direction: Int) {
        guard activeNoteSet == nil, !isBusy,
              let source = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + direction
        guard queuedUploadItems.indices.contains(destination) else { return }
        queuedUploadItems.swapAt(source, destination)
    }

    private func uploadSelectedContinuousNote() {
        guard !isBusy, let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let ids = activeNoteSetItemIds.isEmpty
            ? queuedUploadItems.filter(\.isSelected).map(\.id)
            : activeNoteSetItemIds
        let items = ids.compactMap { id in queuedUploadItems.first(where: { $0.id == id }) }
        guard items.count >= 2 else {
            setError("note_set.error.minimum_pages")
            return
        }
        guard items.allSatisfy({ $0.documentKind == "note" && $0.file.isImage }) else {
            setError("note_set.error.images_only")
            return
        }
        let title = continuousNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            setError("note_set.error.title_required")
            return
        }

        isBusy = true
        let generation = UUID()
        uploadQueueGeneration = generation
        errorMessage = nil
        Task {
            defer {
                if uploadQueueGeneration == generation {
                    uploadProgressPercent = nil
                    uploadProgressLabel = ""
                    isBusy = false
                }
            }
            do {
                let client = clientFor(activeSession)
                if activeNoteSet == nil {
                    let metadata = items[0].learningMetadata
                    let noteSet = try await client.createNoteSet(
                        workspaceId: workspaceId,
                        input: NoteSetCreateInput(
                            title: title,
                            expectedPageCount: items.count,
                            learningUnitId: metadata.learningUnitId.nilIfBlank,
                            subject: metadata.subject.nilIfBlank,
                            gradeLevel: metadata.gradeLevel.nilIfBlank,
                            topic: metadata.topic.nilIfBlank,
                            contentEditLevel: metadata.noteContentEditLevel,
                            layoutEditLevel: metadata.noteLayoutEditLevel
                        )
                    )
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    activeNoteSet = noteSet
                    activeNoteSetItemIds = ids
                    for (pageIndex, id) in ids.enumerated() {
                        guard let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { continue }
                        queuedUploadItems[index].learningMetadata.noteSetId = noteSet.id
                        queuedUploadItems[index].learningMetadata.pageIndex = pageIndex
                    }
                }

                for (pageIndex, id) in ids.enumerated() {
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
                    if queuedUploadItems[index].state == .uploaded { continue }
                    queuedUploadItems[index].state = .uploading
                    let item = queuedUploadItems[index]
                    setUploadProgress("note_set.uploading_page", String(pageIndex + 1), String(ids.count), item.file.filename)
                    uploadProgressPercent = 0
                    do {
                        _ = try await performUpload(item, activeSession: activeSession, workspaceId: workspaceId)
                        guard let completedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
                        queuedUploadItems[completedIndex].state = .uploaded
                    } catch {
                        guard let failedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
                        queuedUploadItems[failedIndex].state = .failed(friendlyDisplayText(error))
                    }
                }

                let allUploaded = ids.allSatisfy { id in
                    queuedUploadItems.first(where: { $0.id == id })?.state == .uploaded
                }
                guard allUploaded, let noteSetId = activeNoteSet?.id else {
                    setError("note_set.error.some_pages_failed")
                    return
                }
                setStatus("note_set.completing")
                activeNoteSet = try await client.completeNoteSet(workspaceId: workspaceId, noteSetId: noteSetId)
                guard uploadQueueGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                let completedItems = queuedUploadItems.filter { ids.contains($0.id) }
                queuedUploadItems.removeAll { ids.contains($0.id) }
                completedItems.forEach {
                    UploadThumbnailCache.shared.remove(file: $0.file)
                    removeCachedUploadFile($0.file)
                }
                activeNoteSet = nil
                activeNoteSetItemIds = []
                isContinuousNoteUploadEnabled = false
                continuousNoteTitle = ""
                try? await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                setStatus("note_set.completed")
            } catch {
                guard uploadQueueGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    private func performUpload(_ item: QueuedUploadItem, activeSession: SavedSession, workspaceId: String) async throws -> LearningDocumentItem {
        let prepared = try await FileImportService.shared.prepareForUpload(item.file, cacheDirectory: cacheDirectory)
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        let client = clientFor(activeSession)
        var remoteState = item.remoteState
        if remoteState == nil {
            setStatus("upload.creating_session")
            let uploadSession = try await client.createUploadSession(
                workspaceId: workspaceId,
                filename: prepared.filename,
                mimeType: prepared.mimeType ?? "application/octet-stream",
                fileSize: prepared.fileSize,
                documentKind: item.documentKind,
                learningMetadata: item.learningMetadata,
                saveToDocuments: item.documentKind == "chat_attachment" ? item.saveToDocuments : nil,
                remark: item.file.isImage ? item.remark : nil
            )
            remoteState = QueuedUploadRemoteState(
                uploadSessionId: uploadSession.uploadSession.id,
                tusEndpoint: uploadSession.tusEndpoint,
                tusMetadataHeader: uploadSession.tusMetadataHeader,
                tusUploadURL: uploadSession.uploadSession.tusUploadURL,
                tusUploadId: uploadSession.uploadSession.tusUploadId,
                workflowRunId: uploadSession.workflowRunId,
                documentId: uploadSession.document.id
            )
            updateQueuedUploadRemoteState(item.id, remoteState)
        }
        guard var remoteState else {
            throw LearningBackendError(localizedKey: "error.upload.session_missing")
        }
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        setStatus("upload.sending")
        let endpoint = TusUploader.preferredEndpoint(
            configuredEndpoint: activeSession.tusBaseURL,
            serverEndpoint: remoteState.tusEndpoint
        )
        let tusResult = try await TusUploader(session: tusSession).upload(
            fileURL: prepared.url,
            endpoint: endpoint,
            metadataHeader: remoteState.tusMetadataHeader,
            existingUploadURL: remoteState.tusUploadURL,
            onUploadCreated: { [weak self] uploadURL in
                await MainActor.run {
                    remoteState.tusUploadURL = uploadURL
                    remoteState.tusUploadId = TusUploader.extractTusUploadId(uploadURL)
                    self?.updateQueuedUploadRemoteState(item.id, remoteState)
                }
            }
        ) { [weak self] uploaded, total in
            let progress = total <= 0 ? 0 : Int((uploaded * 100) / total).clamped(to: 0...100)
            await MainActor.run {
                guard self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true else { return }
                self?.uploadProgressPercent = progress
                self?.setStatus("upload.tus_progress", String(progress))
            }
        }
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        setStatus("upload.confirming")
        let completedDocument = try await completeUploadWithRetry(
            client: client,
            workspaceId: workspaceId,
            uploadSessionId: remoteState.uploadSessionId,
            documentId: remoteState.documentId,
            tusResult: tusResult,
            file: prepared
        )
        trackImageRemarkIfNeeded(completedDocument)
        remoteState.documentId = completedDocument.id
        remoteState.tusUploadURL = tusResult.uploadURL
        remoteState.tusUploadId = tusResult.uploadId
        updateQueuedUploadRemoteState(item.id, remoteState)
        if let workflowRunId = remoteState.workflowRunId {
            monitorWorkflow(workflowRunId, activeSession: activeSession, workspaceId: workspaceId)
        }
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        return completedDocument
    }

    private func updateQueuedUploadRemoteState(_ id: UUID, _ state: QueuedUploadRemoteState?) {
        guard let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        queuedUploadItems[index].remoteState = state
    }

    func startProcessing(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId, !isBusy else {
            return
        }
        guard canProcessDocument(document) else {
            setError("document.error.not_processable")
            return
        }
        isBusy = true
        errorMessage = nil
        taskEvents = []
        workflowLoadTask?.cancel()
        workflowMonitorTask?.cancel()
        workflows = []
        activeWorkflowDetail = nil
        workflowEvents = []
        noteGapTask?.cancel()
        noteCorrectionsTask?.cancel()
        noteGaps = []
        selectedNoteGapDetail = nil
        studyNoteCorrections = []
        isNoteGapPresented = false
        isNoteCorrectionsPresented = false
        setStatus("document.processing_starting")
        Task {
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            do {
                let client = clientFor(activeSession)
                let task = try await client.processDocument(
                    workspaceId: workspaceId,
                    documentId: document.id,
                    forceReprocess: shouldForceReprocess(document)
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                activeTask = task
                selectedTab = .home
                selectedDocumentsSection = .tasks
                selectedHomeDestination = .tasks
                Task { [weak self] in
                    for delay in [0, 500_000_000, 1_000_000_000, 2_000_000_000] as [UInt64] {
                        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                        guard let self,
                              self.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                        if let detail = try? await client.getDocumentWorkflow(
                            workspaceId: workspaceId,
                            documentId: document.id
                        ) {
                            self.activeWorkflowDetail = detail
                            self.monitorWorkflow(
                                detail.workflow.id,
                                activeSession: activeSession,
                                workspaceId: workspaceId
                            )
                            return
                        }
                    }
                }
                let finishedTask = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] updatedTask, events in
                    guard let self,
                          self.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          self.activeTask?.id == task.id else { return }
                    self.activeTask = updatedTask
                    self.taskEvents = events
                    self.setStatus(
                        "task.progress",
                        statusLabel(updatedTask.status),
                        String(updatedTask.progress.clamped(to: 0...100))
                    )
                }
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      activeTask?.id == task.id else { return }
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      activeTask?.id == task.id else { return }
                selectedArtifactDocumentId = document.id
                selectedArtifacts = try await client.listArtifacts(workspaceId: workspaceId, documentId: document.id)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      activeTask?.id == task.id else { return }
                if finishedTask.status == "succeeded" {
                    selectedOcrDocumentId = document.id
                    selectedOcrArtifacts = (try? await client.getOcrArtifacts(workspaceId: workspaceId, documentId: document.id).artifacts) ?? []
                    guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          activeTask?.id == task.id else { return }
                    try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                    try? await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                }
                setStatus("document.processing_complete")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func loadWorkflows(force: Bool = false) {
        if isOfflineTestMode { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        if !force, !workflows.isEmpty { return }
        workflowLoadTask?.cancel()
        let generation = UUID()
        workflowGeneration = generation
        isWorkflowsLoading = true
        workflowLoadTask = Task {
            defer {
                if workflowGeneration == generation {
                    workflowLoadTask = nil
                    isWorkflowsLoading = false
                }
            }
            do {
                let loaded = try await clientFor(activeSession).listWorkflows(
                    workspaceId: workspaceId,
                    page: 1,
                    pageSize: 50
                )
                guard workflowGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                workflows = loaded
                if activeWorkflowDetail == nil,
                   let active = loaded.first(where: { !$0.isTerminal }) ?? loaded.first {
                    selectWorkflow(active.id)
                }
            } catch is CancellationError {
                return
            } catch {
                guard workflowGeneration == generation else { return }
                showError(error)
            }
        }
    }

    func selectWorkflow(_ workflowRunId: String) {
        if isOfflineTestMode { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        monitorWorkflow(
            workflowRunId,
            activeSession: activeSession,
            workspaceId: workspaceId,
            showLoading: true
        )
    }

    func openWorkflow(for document: LearningDocumentItem) {
        selectedTab = .home
        selectedHomeDestination = .tasks
        if let workflowRunId = document.latestWorkflowRunId {
            selectWorkflow(workflowRunId)
            return
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        workflowMonitorTask?.cancel()
        let generation = UUID()
        workflowGeneration = generation
        workflowMonitorTask = Task {
            do {
                let detail = try await clientFor(activeSession).getDocumentWorkflow(
                    workspaceId: workspaceId,
                    documentId: document.id
                )
                guard workflowGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                activeWorkflowDetail = detail
                monitorWorkflow(detail.workflow.id, activeSession: activeSession, workspaceId: workspaceId)
            } catch {
                guard workflowGeneration == generation else { return }
                showError(error)
            }
        }
    }

    private func monitorWorkflow(
        _ workflowRunId: String,
        activeSession: SavedSession,
        workspaceId: String,
        showLoading: Bool = false
    ) {
        workflowMonitorTask?.cancel()
        let generation = UUID()
        workflowGeneration = generation
        if showLoading { isWorkflowsLoading = true }
        workflowMonitorTask = Task {
            defer {
                if workflowGeneration == generation {
                    workflowMonitorTask = nil
                    isWorkflowsLoading = false
                }
            }
            do {
                var detail = try await clientFor(activeSession).getWorkflow(
                    workspaceId: workspaceId,
                    workflowRunId: workflowRunId
                )
                guard workflowGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                activeWorkflowDetail = detail
                workflowEvents = try await clientFor(activeSession).getWorkflowEvents(
                    workspaceId: workspaceId,
                    workflowRunId: workflowRunId
                )
                if detail.workflow.isTerminal {
                    applyWorkflowToList(detail.workflow)
                    return
                }

                var reconnectAttempt = 0
                var lastSequence = workflowEvents.map(\.sequenceNo).max()
                while !Task.isCancelled && !detail.workflow.isTerminal {
                    do {
                        var receivedDone = false
                        for try await frame in clientFor(session ?? activeSession).streamWorkflowEvents(
                            workspaceId: workspaceId,
                            workflowRunId: workflowRunId,
                            lastEventID: lastSequence
                        ) {
                            try Task.checkCancellation()
                            guard workflowGeneration == generation,
                                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
                            switch frame {
                            case .workflowEvent(let event):
                                guard event.sequenceNo > (lastSequence ?? 0) else { continue }
                                lastSequence = event.sequenceNo
                                if !workflowEvents.contains(where: { $0.id == event.id || $0.sequenceNo == event.sequenceNo }) {
                                    workflowEvents.append(event)
                                }
                                let updatedWorkflow = detail.workflow.applying(event: event)
                                if updatedWorkflow != detail.workflow {
                                    detail = WorkflowDetail(workflow: updatedWorkflow, tasks: detail.tasks)
                                    activeWorkflowDetail = detail
                                    applyWorkflowToList(updatedWorkflow)
                                }
                            case .done:
                                receivedDone = true
                            }
                        }
                        detail = try await clientFor(session ?? activeSession).getWorkflow(
                            workspaceId: workspaceId,
                            workflowRunId: workflowRunId
                        )
                        activeWorkflowDetail = detail
                        applyWorkflowToList(detail.workflow)
                        if detail.workflow.isTerminal || receivedDone { return }
                        throw LearningBackendError(localizedKey: "workflow.stream_disconnected")
                    } catch is CancellationError {
                        return
                    } catch {
                        if reconnectAttempt < 2 {
                            reconnectAttempt += 1
                            try await Task.sleep(nanoseconds: UInt64(reconnectAttempt) * 1_000_000_000)
                            continue
                        }
                        break
                    }
                }

                var retryDelay: UInt64 = 1
                while !Task.isCancelled {
                    do {
                        detail = try await clientFor(session ?? activeSession).getWorkflow(
                            workspaceId: workspaceId,
                            workflowRunId: workflowRunId
                        )
                        guard workflowGeneration == generation,
                              isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                        activeWorkflowDetail = detail
                        applyWorkflowToList(detail.workflow)
                        let loadedEvents = try await clientFor(session ?? activeSession).getWorkflowEvents(
                            workspaceId: workspaceId,
                            workflowRunId: workflowRunId
                        )
                        if loadedEvents != workflowEvents { workflowEvents = loadedEvents }
                        if detail.workflow.isTerminal { return }
                        retryDelay = 1
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                    } catch is CancellationError {
                        return
                    } catch {
                        try await Task.sleep(nanoseconds: retryDelay * 1_000_000_000)
                        retryDelay = min(15, retryDelay * 2)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard workflowGeneration == generation else { return }
                showError(error)
            }
        }
    }

    private func applyWorkflowToList(_ workflow: WorkflowRun) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            if workflows[index] != workflow { workflows[index] = workflow }
        } else {
            workflows.insert(workflow, at: 0)
        }
    }

    @discardableResult
    func startOpenClawChat(prompt rawPrompt: String, attachments files: [LocalUploadFile] = []) -> Bool {
        guard let activeSession = currentSessionOrError() else {
            return false
        }
        guard let workspaceId = selectedWorkspaceId else {
            setError("workspace.error.required")
            return false
        }
        guard !isOpenClawSending else { return false }
        let trimmedPrompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !files.isEmpty else {
            setError("chat.error.prompt_required")
            return false
        }
        let prompt = trimmedPrompt.isEmpty ? localized("chat.attachment_default_prompt") : trimmedPrompt
        if !activeSession.aiOnboardingCompleted {
            aiExperienceState.pendingSubmission = PendingAIChatSubmission(
                prompt: rawPrompt,
                attachments: files,
                userId: activeSession.userId,
                workspaceId: workspaceId,
                didAutoRetry: false
            )
            aiExperienceState.isOnboardingPresented = true
            loadAIOnboarding(force: true)
            return false
        }
        let requestedConversationId = selectedConversationId
        var chatAttachments = files.map { OpenClawChatAttachment(file: $0) }
        let userMessageId = allocateOpenClawMessageId()

        let userMessage = OpenClawChatMessage(
            id: userMessageId,
            role: .user,
            content: prompt,
            status: .done,
            taskId: nil,
            progress: nil,
            events: [],
            attachments: chatAttachments
        )
        let assistantMessageId = allocateOpenClawMessageId()
        let assistantMessage = OpenClawChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: files.isEmpty ? "Thinking..." : localized("chat.uploading_attachments"),
            status: .sending,
            taskId: nil,
            progress: 0,
            events: []
        )
        openClawMessages.append(contentsOf: [userMessage, assistantMessage])
        isOpenClawSending = true
        errorMessage = nil
        statusMessage = ""

        let chatGeneration = UUID()
        openClawChatGeneration = chatGeneration
        openClawChatTask = Task {
            defer { finishOpenClawChat(generation: chatGeneration) }
            var latestEvents: [TaskEventItem] = []
            var taskWasAccepted = false
            var acceptedTaskId: String?
            do {
                var uploadedDocuments: [LearningDocumentItem] = []
                for (index, file) in files.enumerated() {
                    if let preparedDocument = preparedChatAttachmentDocuments[file.id] {
                        uploadedDocuments.append(preparedDocument)
                        chatAttachments[index].documentId = preparedDocument.id
                        chatAttachments[index].status = .ready
                        updateOpenClawMessage(userMessageId) {
                            $0.attachments = chatAttachments
                        }
                        continue
                    }
                    let uploadSession = session ?? activeSession
                    let uploadItem = QueuedUploadItem(
                        file: file,
                        documentKind: "chat_attachment",
                        learningMetadata: LearningMetadata(),
                        saveToDocuments: openClawComposerState.saveAttachmentsToWorkspace
                    )
                    setStatus("chat.uploading_attachment", String(index + 1), String(files.count), file.filename)
                    var document = try await performUpload(
                        uploadItem,
                        activeSession: uploadSession,
                        workspaceId: workspaceId
                    )
                    document = try await waitForChatAttachment(
                        document,
                        activeSession: session ?? uploadSession,
                        workspaceId: workspaceId
                    )
                    preparedChatAttachmentDocuments[file.id] = document
                    uploadedDocuments.append(document)
                    chatAttachments[index].documentId = document.id
                    chatAttachments[index].status = .ready
                    updateOpenClawMessage(userMessageId) {
                        $0.attachments = chatAttachments
                    }
                }

                // Per backend contract, chat attachments are referenced by document_id only;
                // filename/MIME are resolved server-side and must not be treated as trusted input.
                let attachmentInput: [[String: Any]] = uploadedDocuments.map { document in
                    ["document_id": document.id]
                }
                let input: [String: Any] = attachmentInput.isEmpty ? [:] : ["attachments": attachmentInput]
                let chatSession = session ?? activeSession
                let task = try await clientFor(chatSession).openClawChat(
                    workspaceId: workspaceId,
                    prompt: prompt,
                    clientLocale: AppLocalization.shared.language.aiClientLocale,
                    conversationId: requestedConversationId,
                    input: input,
                    options: ["thinking": ["enabled": true, "effort": "adaptive"]]
                )
                taskWasAccepted = true
                acceptedTaskId = task.id
                openClawComposerState.clearDraft(removeAttachmentFiles: false)
                files.forEach { preparedChatAttachmentDocuments[$0.id] = nil }
                let taskConversationId = task.payload?.objectStringValue(for: "conversation_id")
                if selectedConversationId == requestedConversationId, let taskConversationId {
                    selectedConversationId = taskConversationId
                }
                if let serverUserMessageId = task.payload?.objectStringValue(for: "user_message_id"),
                   !chatAttachments.isEmpty {
                    chatAttachmentsByMessageId[serverUserMessageId] = chatAttachments
                }
                updateOpenClawMessage(assistantMessageId) {
                    $0.content = "Thinking..."
                    $0.taskId = task.id
                    $0.progress = task.progress.clamped(to: 0...100)
                    $0.modelId = task.payload?.objectStringValue(for: "ai_model")
                }
                let finishedTask = try await pollTask(
                    activeSession: chatSession,
                    workspaceId: workspaceId,
                    taskId: task.id,
                    initialTask: task
                ) { [weak self] updatedTask, events in
                    latestEvents = events
                    let streamState = Self.reduceChatStreamEvents(events)
                    self?.updateOpenClawMessage(assistantMessageId) {
                        $0.content = streamState.answer.isEmpty ? localized("chat.thinking") : streamState.answer
                        $0.streamingContent = streamState.answer
                        $0.reasoningContent = streamState.reasoning
                        $0.streamTruncated = streamState.truncated
                        $0.reasoningUnavailable = streamState.reasoningUnavailable
                        $0.taskId = updatedTask.id
                        $0.progress = updatedTask.progress.clamped(to: 0...100)
                        $0.events = events
                        if let modelId = updatedTask.payload?.objectStringValue(for: "ai_model") {
                            $0.modelId = modelId
                        }
                    }
                }
                if let conversationId = taskConversationId,
                   selectedConversationId == conversationId,
                   isCurrentWorkspaceContext(chatSession, workspaceId: workspaceId) {
                    try await refreshConversationMessages(
                        activeSession: chatSession,
                        workspaceId: workspaceId,
                        conversationId: conversationId,
                        shouldApply: { [weak self] in
                            self?.isCurrentWorkspaceContext(chatSession, workspaceId: workspaceId) == true
                                && self?.selectedConversationId == conversationId
                        }
                    )
                    let streamState = Self.reduceChatStreamEvents(latestEvents)
                    if let serverAssistantMessageId = task.payload?.objectStringValue(for: "assistant_message_id")
                        ?? openClawMessages.last(where: { $0.taskId == task.id })?.id {
                        updateOpenClawMessage(serverAssistantMessageId) {
                            $0.streamingContent = streamState.answer
                            $0.reasoningContent = streamState.reasoning
                            $0.streamTruncated = streamState.truncated
                            $0.reasoningUnavailable = streamState.reasoningUnavailable
                            $0.events = latestEvents
                        }
                    }
                    try? await refreshConversations(activeSession: chatSession, workspaceId: workspaceId)
                } else {
                    let answer = formatOpenClawTaskResult(finishedTask.resultText)
                    updateOpenClawMessage(assistantMessageId) {
                        $0.content = answer.isEmpty ? localized("chat.no_content") : answer
                        $0.status = .done
                        $0.progress = finishedTask.progress.clamped(to: 0...100)
                        $0.events = latestEvents
                        $0.modelId = taskProviderModelId(finishedTask)
                    }
                }
            } catch {
                if error is CancellationError {
                    return
                }
                if let acceptedTaskId,
                   openClawState.cancellingTaskId == acceptedTaskId {
                    updateOpenClawMessage(assistantMessageId) {
                        $0.status = .stopped
                        $0.progress = nil
                        $0.events = latestEvents
                    }
                    openClawState.cancellingTaskId = nil
                    return
                }
                if !taskWasAccepted {
                    if let backendError = error as? LearningBackendError,
                       backendError.backendCode == "ai_onboarding_required" {
                        openClawMessages.removeAll { $0.id == userMessageId || $0.id == assistantMessageId }
                        aiExperienceState.pendingSubmission = PendingAIChatSubmission(
                            prompt: rawPrompt,
                            attachments: files,
                            userId: activeSession.userId,
                            workspaceId: workspaceId,
                            didAutoRetry: false
                        )
                        aiExperienceState.isOnboardingPresented = true
                        loadAIOnboarding(force: true)
                        return
                    }
                    openClawMessages.removeAll { $0.id == assistantMessageId }
                    showError(error)
                    return
                }
                if let backendError = error as? LearningBackendError, backendError.shouldClearSession {
                    showError(error)
                }
                let eventMessage = latestEvents.last(where: { $0.level == "error" })?.message ?? latestEvents.last?.message
                let message = [friendlyError(error), eventMessage.map { localizedFormat("chat.recent_event", $0) }]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                updateOpenClawMessage(assistantMessageId) {
                    $0.content = message
                    $0.status = .error
                    $0.progress = nil
                    $0.events = latestEvents
                }
            }
        }
        return true
    }

    private func finishOpenClawChat(generation: UUID) {
        guard openClawChatGeneration == generation else { return }
        openClawChatTask = nil
        openClawState.cancellingTaskId = nil
        isOpenClawSending = false
    }

    func stopOpenClawChat() {
        guard isOpenClawSending,
              let assistantMessage = openClawMessages.last(where: { $0.role == .assistant && $0.status == .sending }),
              let taskId = assistantMessage.taskId,
              openClawState.cancellingTaskId == nil,
              let workspaceId = selectedWorkspaceId,
              let activeSession = currentSessionOrError() else {
            return
        }

        openClawState.cancellingTaskId = taskId

        Task {
            do {
                _ = try await clientFor(activeSession).cancelTask(workspaceId: workspaceId, taskId: taskId)
            } catch {
                guard openClawState.cancellingTaskId == taskId else { return }
                openClawState.cancellingTaskId = nil
                showError(error)
            }
        }
    }

    func copyOpenClawMessage(_ message: OpenClawChatMessage) {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentLines = message.attachments.map {
            localizedFormat("chat.copy.attachment", $0.file.filename)
        }
        let text = ([content].filter { !$0.isEmpty } + attachmentLines).joined(separator: "\n")
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        presentStatus("chat.copy.message_complete")
    }

    func copyOpenClawConversation() {
        let blocks = openClawMessages.compactMap { message -> String? in
            guard (message.role == .user || message.role == .assistant),
                  message.status != .error else { return nil }
            let role = message.role == .user
                ? localized("chat.copy.role.user")
                : localized("chat.copy.role.assistant")
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachmentLines = message.attachments.map {
                localizedFormat("chat.copy.attachment", $0.file.filename)
            }
            let body = ([content].filter { !$0.isEmpty } + attachmentLines).joined(separator: "\n")
            guard !body.isEmpty else { return nil }
            return "\(role)\n\(body)"
        }
        guard !blocks.isEmpty else {
            setError("chat.copy.empty")
            return
        }
        UIPasteboard.general.string = blocks.joined(separator: "\n\n")
        presentStatus("chat.copy.conversation_complete")
    }

    func reviseOpenClawMessage(
        _ message: OpenClawChatMessage,
        prompt: String,
        onAccepted: @escaping @MainActor () -> Void
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .user,
              !message.id.hasPrefix("local-"),
              message.id != "system",
              !trimmed.isEmpty else {
            setError("chat.revision.prompt_required")
            return
        }
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId,
              !openClawState.isMessageRevising else { return }

        messageRevisionTask?.cancel()
        let requestGeneration = UUID()
        messageRevisionGeneration = requestGeneration
        openClawState.isMessageRevising = true
        errorMessage = nil

        messageRevisionTask = Task {
            defer {
                if messageRevisionGeneration == requestGeneration {
                    messageRevisionTask = nil
                    openClawState.isMessageRevising = false
                }
            }
            do {
                let task = try await clientFor(activeSession).reviseChatMessage(
                    workspaceId: workspaceId,
                    conversationId: conversationId,
                    messageId: message.id,
                    prompt: trimmed,
                    clientLocale: AppLocalization.shared.language.aiClientLocale,
                    options: ["thinking": ["enabled": true, "effort": "adaptive"]]
                )
                guard messageRevisionGeneration == requestGeneration,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedConversationId == conversationId else { throw CancellationError() }

                openClawChatGeneration = UUID()
                openClawChatTask?.cancel()
                let serverUserMessageId = task.payload?.objectStringValue(for: "user_message_id")
                    ?? task.payload?.objectStringValue(for: "revised_message_id")
                    ?? message.id
                let serverAssistantMessageId = task.payload?.objectStringValue(for: "assistant_message_id")
                    ?? allocateOpenClawMessageId()
                if let index = openClawMessages.firstIndex(where: { $0.id == message.id }) {
                    let revisedMessage = OpenClawChatMessage(
                        id: serverUserMessageId,
                        role: .user,
                        content: trimmed,
                        status: .done,
                        taskId: nil,
                        progress: nil,
                        events: [],
                        attachments: message.attachments
                    )
                    let assistant = OpenClawChatMessage(
                        id: serverAssistantMessageId,
                        role: .assistant,
                        content: localized("chat.thinking"),
                        status: .sending,
                        taskId: task.id,
                        progress: task.progress.clamped(to: 0...100),
                        events: []
                    )
                    openClawMessages = Array(openClawMessages.prefix(index)) + [revisedMessage, assistant]
                }
                onAccepted()
                presentStatus("chat.revision.accepted")
                isOpenClawSending = true

                let chatGeneration = UUID()
                openClawChatGeneration = chatGeneration
                openClawChatTask = Task {
                    defer { finishOpenClawChat(generation: chatGeneration) }
                    var latestEvents: [TaskEventItem] = []
                    do {
                        let finishedTask = try await pollTask(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            taskId: task.id,
                            initialTask: task
                        ) { [weak self] updatedTask, events in
                            guard let self else { return }
                            latestEvents = events
                            let stream = Self.reduceChatStreamEvents(events)
                            self.openClawState.updateMessage(taskId: task.id) {
                                $0.content = stream.answer.isEmpty ? localized("chat.thinking") : stream.answer
                                $0.streamingContent = stream.answer
                                $0.reasoningContent = stream.reasoning
                                $0.streamTruncated = stream.truncated
                                $0.reasoningUnavailable = stream.reasoningUnavailable
                                $0.progress = updatedTask.progress.clamped(to: 0...100)
                                $0.events = events
                            }
                        }
                        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                              selectedConversationId == conversationId else { throw CancellationError() }
                        try await refreshConversationMessages(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            conversationId: conversationId
                        )
                        let stream = Self.reduceChatStreamEvents(latestEvents)
                        if let finalMessageId = task.payload?.objectStringValue(for: "assistant_message_id")
                            ?? openClawMessages.last(where: { $0.taskId == task.id })?.id {
                            updateOpenClawMessage(finalMessageId) {
                                $0.streamingContent = stream.answer
                                $0.reasoningContent = stream.reasoning
                                $0.streamTruncated = stream.truncated
                                $0.reasoningUnavailable = stream.reasoningUnavailable
                                $0.events = latestEvents
                                $0.modelId = taskProviderModelId(finishedTask)
                            }
                        }
                        try? await refreshConversations(activeSession: activeSession, workspaceId: workspaceId)
                    } catch is CancellationError {
                        return
                    } catch {
                        if openClawState.cancellingTaskId == task.id {
                            openClawState.updateMessage(taskId: task.id) {
                                $0.status = .stopped
                                $0.progress = nil
                                $0.events = latestEvents
                            }
                            openClawState.cancellingTaskId = nil
                        } else {
                            openClawState.updateMessage(taskId: task.id) {
                                $0.status = .error
                                $0.content = friendlyError(error)
                                $0.progress = nil
                                $0.events = latestEvents
                            }
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard messageRevisionGeneration == requestGeneration else { return }
                showError(error)
            }
        }
    }

    struct ChatStreamState: Equatable {
        var answer = ""
        var reasoning = ""
        var truncated = false
        var reasoningUnavailable = false
    }

    static func reduceChatStreamEvents(_ events: [TaskEventItem]) -> ChatStreamState {
        let sorted = events.sorted {
            if $0.sequenceNo != $1.sequenceNo { return $0.sequenceNo < $1.sequenceNo }
            return $0.createdAt < $1.createdAt
        }
        var state = ChatStreamState()
        var rawAnswer = ""
        for event in sorted {
            switch event.eventType {
            case "chat_stream_started":
                rawAnswer = ""
                state.reasoning = ""
                state.truncated = false
                state.reasoningUnavailable = false
            case "chat_answer_delta", "chat_reasoning_delta":
                guard let delta = event.data?.objectStringValue(for: "delta") else { continue }
                let declaredStream = event.data?.objectStringValue(for: "stream")?.lowercased()
                if declaredStream == "reasoning" || (declaredStream == nil && event.eventType == "chat_reasoning_delta") {
                    state.reasoning += delta
                } else {
                    rawAnswer += delta
                }
            case "chat_stream_truncated":
                state.truncated = true
            case "chat_reasoning_unavailable":
                state.reasoningUnavailable = true
            default:
                continue
            }
        }
        state.answer = rawAnswer
        if !state.reasoning.isEmpty {
            state.reasoningUnavailable = false
        }
        return state
    }

    private func waitForChatAttachment(
        _ initialDocument: LearningDocumentItem,
        activeSession: SavedSession,
        workspaceId: String
    ) async throws -> LearningDocumentItem {
        var document = initialDocument
        var retryDelaySeconds: UInt64 = 5
        while true {
            try Task.checkCancellation()
            guard selectedWorkspaceId == workspaceId else { throw CancellationError() }
            if ["uploaded", "ready"].contains(document.status) {
                return document
            }
            if ["failed", "deleted"].contains(document.status) {
                throw LearningBackendError(localized("chat.attachment_upload_failed"))
            }

            try await Task.sleep(nanoseconds: 3_000_000_000)
            do {
                document = try await clientFor(session ?? activeSession).getDocument(
                    workspaceId: workspaceId,
                    documentId: document.id
                )
                retryDelaySeconds = 5
            } catch let error as LearningBackendError
                where !error.shouldClearSession && (error.statusCode == nil || (error.statusCode ?? 0) >= 500) {
                try await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
                retryDelaySeconds = min(retryDelaySeconds * 2, 30)
            }
        }
    }

    private func taskProviderModelId(_ task: TaskItem) -> String? {
        task.result?.objectStringValue(for: "provider_model")
            ?? task.payload?.objectStringValue(for: "ai_model")
    }

    var selectedConversation: ChatConversation? {
        conversations.first(where: { $0.id == selectedConversationId })
    }

    var uploadLearningMetadata: LearningMetadata {
        LearningMetadata(
            learningUnitId: uploadLearningUnitId,
            learningUnitTitle: uploadLearningUnitTitle,
            subject: uploadSubject,
            gradeLevel: uploadGradeLevel,
            topic: uploadTopic,
            noteContentEditLevel: uploadDocumentKind == "note" && uploadUsesCustomNoteStrategy
                ? uploadNoteContentEditLevel
                : nil,
            noteLayoutEditLevel: uploadDocumentKind == "note" && uploadUsesCustomNoteStrategy
                ? uploadNoteLayoutEditLevel
                : nil
        )
    }

    func loadChatHistory(force: Bool = true) {
        beginDeferredLoad(
            .chat,
            force: force,
            setLoading: { [weak self] isLoading in self?.isChatHistoryLoading = isLoading }
        ) { [weak self] activeSession, workspaceId, isCurrent in
            guard let self else { return }
            let client = self.clientFor(activeSession)
            self.aiExperienceState.isGreetingLoading = true
            async let greetingRequest = try? client.getChatGreeting(
                workspaceId: workspaceId,
                clientLocale: AppLocalization.shared.language.aiClientLocale
            )
            async let onboardingRequest = try? client.getAIOnboarding()
            var chatError: Error?
            do {
                try await self.refreshConversations(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    shouldApply: isCurrent
                )
                if let conversationId = self.selectedConversationId {
                    try await self.refreshConversationMessages(
                        activeSession: activeSession,
                        workspaceId: workspaceId,
                        conversationId: conversationId,
                        shouldApply: isCurrent
                    )
                } else if isCurrent() {
                    self.openClawMessages = []
                }
            } catch {
                chatError = error
            }
            if let greeting = await greetingRequest, isCurrent() {
                self.aiExperienceState.greeting = greeting
                self.aiExperienceState.greetingError = nil
            } else if isCurrent() {
                self.aiExperienceState.greetingError = localized("ai.greeting.load_failed")
            }
            if isCurrent() {
                self.aiExperienceState.isGreetingLoading = false
            }
            if let onboarding = await onboardingRequest, isCurrent() {
                self.aiExperienceState.apply(onboarding, presentIfRequired: true)
                if let current = self.session, current.userId == activeSession.userId {
                    self.saveSession(current.withAIOnboarding(onboarding))
                }
            } else if isCurrent(), !activeSession.aiOnboardingCompleted {
                self.aiExperienceState.errorMessage = localized("ai.onboarding.load_failed")
                self.aiExperienceState.isOnboardingPresented = true
            }
            if let chatError {
                throw chatError
            }
        }
    }

    func loadAIOnboarding(force: Bool = false) {
        guard let activeSession = currentSessionOrError() else { return }
        if aiExperienceState.isLoading && !force { return }
        aiExperienceState.isLoading = true
        aiExperienceState.errorMessage = nil
        Task {
            defer { aiExperienceState.isLoading = false }
            do {
                let response = try await clientFor(activeSession).getAIOnboarding()
                guard isCurrentSessionContext(activeSession) else { return }
                aiExperienceState.apply(response, presentIfRequired: true)
                if let current = session, current.userId == activeSession.userId {
                    saveSession(current.withAIOnboarding(response))
                }
            } catch {
                guard isCurrentSessionContext(activeSession) else { return }
                aiExperienceState.errorMessage = friendlyError(error)
            }
        }
    }

    func saveAIOnboarding() {
        guard let activeSession = currentSessionOrError(),
              let onboarding = aiExperienceState.onboarding,
              !aiExperienceState.isSaving else { return }
        let custom = aiExperienceState.draftPreferences.customInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (custom?.count ?? 0) <= 1000 else {
            aiExperienceState.errorMessage = localized("ai.onboarding.custom_too_long")
            return
        }
        for question in onboarding.questions where question.required {
            guard question.options.contains(where: { $0.value == aiExperienceState.answer(for: question.id) }) else {
                aiExperienceState.errorMessage = localized("ai.onboarding.answer_required")
                return
            }
        }
        aiExperienceState.draftPreferences.customInstructions = custom?.isEmpty == true ? nil : custom

        if isOfflineTestMode {
            let completed = AIOnboardingResponse(
                version: onboarding.version,
                completed: true,
                completedAt: ISO8601DateFormatter().string(from: Date()),
                answers: aiExperienceState.draftPreferences,
                questions: onboarding.questions
            )
            aiExperienceState.apply(completed, presentIfRequired: false)
            aiExperienceState.isOnboardingPresented = false
            if let current = session {
                saveSession(current.withAIOnboarding(completed))
            }
            return
        }

        aiExperienceState.isSaving = true
        aiExperienceState.errorMessage = nil
        Task {
            defer { aiExperienceState.isSaving = false }
            do {
                let response = try await clientFor(activeSession).completeAIOnboarding(
                    version: onboarding.version,
                    preferences: aiExperienceState.draftPreferences
                )
                guard isCurrentSessionContext(activeSession) else { return }
                aiExperienceState.apply(response, presentIfRequired: false)
                aiExperienceState.isOnboardingPresented = false
                if let current = session, current.userId == activeSession.userId {
                    saveSession(current.withAIOnboarding(response))
                }
                resumePendingAIChatIfPossible()
            } catch let error as LearningBackendError where error.backendCode == "ai_onboarding_version_mismatch" {
                let preserved = aiExperienceState.draftPreferences
                do {
                    let refreshed = try await clientFor(activeSession).getAIOnboarding()
                    guard isCurrentSessionContext(activeSession) else { return }
                    aiExperienceState.apply(refreshed, presentIfRequired: true)
                    aiExperienceState.draftPreferences = preserved
                    aiExperienceState.errorMessage = localized("ai.onboarding.version_changed")
                } catch {
                    aiExperienceState.errorMessage = friendlyError(error)
                }
            } catch {
                guard isCurrentSessionContext(activeSession) else { return }
                aiExperienceState.errorMessage = friendlyError(error)
            }
        }
    }

    func presentAISettings() {
        guard let session else { return }
        if !session.aiOnboardingCompleted {
            aiExperienceState.isOnboardingPresented = true
            loadAIOnboarding(force: true)
            return
        }
        aiExperienceState.beginSettings(with: session.aiPreferences)
    }

    func saveAISettings() {
        guard let activeSession = currentSessionOrError(), !aiExperienceState.isSaving else { return }
        let custom = aiExperienceState.draftPreferences.customInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (custom?.count ?? 0) <= 1000 else {
            aiExperienceState.errorMessage = localized("ai.onboarding.custom_too_long")
            return
        }
        aiExperienceState.draftPreferences.customInstructions = custom?.isEmpty == true ? nil : custom
        let patch = aiExperienceState.draftPreferences.patch(comparedTo: activeSession.aiPreferences)
        guard !patch.isEmpty else {
            aiExperienceState.isSettingsPresented = false
            return
        }
        aiExperienceState.isSaving = true
        Task {
            defer { aiExperienceState.isSaving = false }
            do {
                let user = try await clientFor(activeSession).updateAIProfilePreferences(patch)
                guard isCurrentSessionContext(activeSession), let current = session else { return }
                saveSession(current.withUser(user))
                aiExperienceState.draftPreferences = user.aiPreferences
                aiExperienceState.isSettingsPresented = false
                setStatus("ai.preferences.saved")
            } catch {
                aiExperienceState.errorMessage = friendlyError(error)
            }
        }
    }

    func reloadAIGreetingForLanguageChange() {
        aiExperienceState.greeting = nil
        loadChatHistory(force: true)
    }

    private func resumePendingAIChatIfPossible() {
        guard var pending = aiExperienceState.pendingSubmission,
              !pending.didAutoRetry,
              session?.userId == pending.userId,
              selectedWorkspaceId == pending.workspaceId else {
            aiExperienceState.pendingSubmission = nil
            return
        }
        pending.didAutoRetry = true
        aiExperienceState.pendingSubmission = nil
        _ = startOpenClawChat(prompt: pending.prompt, attachments: pending.attachments)
    }

    func selectConversation(_ conversationId: String) {
        if isOfflineTestMode {
            conversationLoadTask?.cancel()
            selectedConversationId = conversationId
            openClawMessages = [
                OpenClawChatMessage(
                    id: "\(conversationId)-m1",
                    role: .user,
                    content: "你好，请帮我复习这个单元。",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                ),
                OpenClawChatMessage(
                    id: "\(conversationId)-m2",
                    role: .assistant,
                    content: "好的，我们先从最近的学习笔记开始。",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                )
            ]
            return
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        conversationLoadTask?.cancel()
        let generation = UUID()
        conversationLoadGeneration = generation
        selectedConversationId = conversationId
        openClawMessages = []
        isChatHistoryLoading = true
        conversationLoadTask = Task {
            defer {
                if conversationLoadGeneration == generation {
                    conversationLoadTask = nil
                    isChatHistoryLoading = false
                }
            }
            do {
                try await refreshConversationMessages(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    conversationId: conversationId,
                    shouldApply: { [weak self] in
                        self?.conversationLoadGeneration == generation
                            && self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                            && self?.selectedConversationId == conversationId
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                guard conversationLoadGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedConversationId == conversationId else { return }
                showError(error)
            }
        }
    }

    func startNewConversation() {
        conversationLoadGeneration = UUID()
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        isChatHistoryLoading = false
        selectedConversationId = nil
        openClawMessages = []
        openClawComposerState.attachments.forEach { preparedChatAttachmentDocuments[$0.id] = nil }
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
    }

    func renameCurrentConversation(to title: String) {
        guard let conversationId = selectedConversationId else { return }
        renameConversation(conversationId, to: title)
    }

    func renameConversation(_ conversationId: String, to title: String) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              !isConversationMutating else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setError("chat.error.title_required")
            return
        }
        guard trimmed.count <= 160 else {
            setError("chat.error.title_length")
            return
        }
        isConversationMutating = true
        let generation = UUID()
        conversationMutationGeneration = generation
        errorMessage = nil
        setStatus("chat.saving_title")
        Task {
            defer {
                if conversationMutationGeneration == generation {
                    isConversationMutating = false
                }
            }
            do {
                let updated = try await clientFor(activeSession).updateConversation(workspaceId: workspaceId, conversationId: conversationId, title: trimmed)
                guard conversationMutationGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                conversations = conversations.map { $0.id == updated.id ? updated : $0 }
                setStatus("chat.title_saved")
            } catch {
                guard conversationMutationGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func deleteCurrentConversation() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId, !isConversationMutating else { return }
        deleteConversation(conversationId, activeSession: activeSession, workspaceId: workspaceId)
    }

    func deleteConversation(_ conversationId: String) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        deleteConversation(conversationId, activeSession: activeSession, workspaceId: workspaceId)
    }

    private func deleteConversation(
        _ conversationId: String,
        activeSession: SavedSession,
        workspaceId: String
    ) {
        guard !isConversationMutating else { return }
        isConversationMutating = true
        let generation = UUID()
        conversationMutationGeneration = generation
        errorMessage = nil
        setStatus("chat.deleting_conversation")
        Task {
            defer {
                if conversationMutationGeneration == generation {
                    isConversationMutating = false
                }
            }
            do {
                try await clientFor(activeSession).deleteConversation(workspaceId: workspaceId, conversationId: conversationId)
                guard conversationMutationGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                conversations.removeAll { $0.id == conversationId }
                setStatus("chat.conversation_deleted")

                if selectedConversationId == conversationId {
                    selectedConversationId = conversations.first?.id
                    openClawMessages = []

                    do {
                        try await refreshConversations(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            shouldApply: { [weak self] in
                                self?.conversationMutationGeneration == generation
                                    && self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                            }
                        )
                        if let nextConversationId = selectedConversationId {
                            try await refreshConversationMessages(
                                activeSession: activeSession,
                                workspaceId: workspaceId,
                                conversationId: nextConversationId,
                                shouldApply: { [weak self] in
                                    self?.conversationMutationGeneration == generation
                                        && self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                                        && self?.selectedConversationId == nextConversationId
                                }
                            )
                        }
                    } catch {
                        handlePostCommitRefreshFailure(error, completionKey: "operation.conversation_deleted")
                    }
                }
            } catch {
                guard conversationMutationGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func updateAIHistoryEnabled(_ enabled: Bool) {
        guard let activeSession = currentSessionOrError(), !isAIPreferenceUpdating else { return }
        let previous = aiHistoryEnabled
        aiHistoryEnabled = enabled
        isAIPreferenceUpdating = true
        let generation = UUID()
        aiPreferenceGeneration = generation
        errorMessage = nil
        setStatus("profile.saving_ai_history")
        aiPreferenceTask = Task {
            defer {
                if aiPreferenceGeneration == generation {
                    aiPreferenceTask = nil
                    isAIPreferenceUpdating = false
                }
            }
            do {
                let response = try await clientFor(activeSession).updateAIPreferences(aiHistoryEnabled: enabled)
                guard aiPreferenceGeneration == generation,
                      let currentSession = session,
                      currentSession.userId == activeSession.userId else { return }
                saveSession(currentSession.withAIHistoryEnabled(response.aiHistoryEnabled))
                setStatus("profile.ai_history_saved")
            } catch is CancellationError {
                return
            } catch {
                guard aiPreferenceGeneration == generation,
                      session?.userId == activeSession.userId else { return }
                aiHistoryEnabled = previous
                showError(error)
            }
        }
    }

    func updateAutoImageRemarkEnabled(_ enabled: Bool) {
        guard let activeSession = currentSessionOrError(), !isAutoImageRemarkPreferenceUpdating else { return }
        let previous = autoImageRemarkEnabled
        autoImageRemarkEnabled = enabled
        isAutoImageRemarkPreferenceUpdating = true
        let generation = UUID()
        autoImageRemarkPreferenceGeneration = generation
        errorMessage = nil
        setStatus("image_remark.preference.saving")
        autoImageRemarkPreferenceTask?.cancel()
        autoImageRemarkPreferenceTask = Task {
            defer {
                if autoImageRemarkPreferenceGeneration == generation {
                    autoImageRemarkPreferenceTask = nil
                    isAutoImageRemarkPreferenceUpdating = false
                }
            }
            do {
                let user = try await clientFor(activeSession).updateAutoImageRemarkPreference(enabled: enabled)
                guard autoImageRemarkPreferenceGeneration == generation,
                      let current = session,
                      current.userId == activeSession.userId else { return }
                saveSession(current.withUser(user))
                setStatus("image_remark.preference.saved")
            } catch is CancellationError {
                return
            } catch {
                guard autoImageRemarkPreferenceGeneration == generation,
                      session?.userId == activeSession.userId else { return }
                autoImageRemarkEnabled = previous
                showError(error)
            }
        }
    }

    func updateQueuedUploadRemark(_ id: UUID, remark: String) -> Bool {
        guard !isBusy,
              let index = queuedUploadItems.firstIndex(where: { $0.id == id }),
              queuedUploadItems[index].file.isImage,
              queuedUploadItems[index].remoteState == nil else { return false }
        let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 255 else {
            setError("image_remark.error.too_long")
            return false
        }
        queuedUploadItems[index].remark = trimmed.isEmpty ? nil : trimmed
        return true
    }

    func updateDocumentRemark(
        _ document: LearningDocumentItem,
        remark: String,
        onSaved: @escaping @MainActor () -> Void = {}
    ) {
        let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setError("image_remark.error.required")
            return
        }
        guard trimmed.count <= 255 else {
            setError("image_remark.error.too_long")
            return
        }
        guard documentRemarkUpdatingId == nil,
              let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId else { return }
        let generation = UUID()
        documentRemarkUpdateGeneration = generation
        documentRemarkUpdatingId = document.id
        errorMessage = nil
        setStatus("image_remark.saving")
        documentRemarkUpdateTask?.cancel()
        documentRemarkUpdateTask = Task {
            defer {
                if documentRemarkUpdateGeneration == generation {
                    documentRemarkUpdateTask = nil
                    documentRemarkUpdatingId = nil
                }
            }
            do {
                let updated = try await clientFor(activeSession).updateDocumentRemark(
                    workspaceId: workspaceId,
                    documentId: document.id,
                    remark: trimmed
                )
                guard documentRemarkUpdateGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                applyUpdatedDocument(updated)
                trackedImageRemarkDocumentIds.remove(updated.id)
                setStatus("image_remark.saved")
                onSaved()
            } catch is CancellationError {
                return
            } catch {
                guard documentRemarkUpdateGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    var isNotePreferenceDirty: Bool {
        notePreferenceDraftContent != noteContentEditLevel
            || notePreferenceDraftLayout != noteLayoutEditLevel
            || notePreferenceDraftHistoryLimit != noteHistoryLimit
    }

    func saveNotePreferences() {
        guard let activeSession = currentSessionOrError(), !isNotePreferenceUpdating else { return }
        let content = notePreferenceDraftContent
        let layout = notePreferenceDraftLayout
        let historyLimit = min(100, max(0, notePreferenceDraftHistoryLimit))
        guard NoteContentEditLevel.supportedValues.contains(content),
              NoteLayoutEditLevel.supportedValues.contains(layout) else {
            setError("note.preferences.unsupported")
            return
        }
        notePreferenceDraftHistoryLimit = historyLimit
        guard isNotePreferenceDirty else { return }
        isNotePreferenceUpdating = true
        let generation = UUID()
        notePreferenceGeneration = generation
        errorMessage = nil
        setStatus("note.preferences.saving")
        notePreferenceTask?.cancel()
        notePreferenceTask = Task {
            defer {
                if notePreferenceGeneration == generation {
                    notePreferenceTask = nil
                    isNotePreferenceUpdating = false
                }
            }
            do {
                let user = try await clientFor(activeSession).updateNotePreferences(
                    contentEditLevel: content,
                    layoutEditLevel: layout,
                    historyLimit: historyLimit
                )
                guard notePreferenceGeneration == generation,
                      let current = session,
                      current.userId == activeSession.userId else { return }
                saveSession(current.withUser(user))
                setStatus("note.preferences.saved")
            } catch is CancellationError {
                return
            } catch {
                guard notePreferenceGeneration == generation,
                      session?.userId == activeSession.userId else { return }
                showError(error)
            }
        }
    }

    func loadUserProfile(force: Bool = false) {
        if isOfflineTestMode {
            guard let session else { return }
            userProfileState.apply(UserProfileSnapshot(
                profile: UserProfile(
                    id: session.userId,
                    name: session.fullName ?? localized("account.default_user"),
                    email: session.email,
                    avatarURL: nil,
                    profileVersion: 1,
                    reauthenticationRequired: false
                ),
                etag: "\"profile-1\""
            ))
            return
        }
        guard force || userProfileState.snapshot == nil else { return }
        guard let activeSession = currentSessionOrError() else { return }
        profileLoadTask?.cancel()
        let generation = UUID()
        profileGeneration = generation
        userProfileState.isLoading = true
        profileLoadTask = Task {
            defer {
                if profileGeneration == generation {
                    profileLoadTask = nil
                    userProfileState.isLoading = false
                }
            }
            do {
                let client = clientFor(activeSession)
                let snapshot = try await client.getUserProfile()
                guard profileGeneration == generation, session?.userId == activeSession.userId else {
                    throw CancellationError()
                }
                userProfileState.apply(snapshot)
                saveSession(activeSession.withProfile(snapshot.profile))
                await loadUserAvatar(using: client, profile: snapshot.profile, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard profileGeneration == generation else { return }
                showError(error)
            }
        }
    }

    func saveUserProfile() {
        saveUserProfile(forceOverwrite: false)
    }

    func confirmUserProfileOverwrite() {
        userProfileState.hasConflict = false
        saveUserProfile(forceOverwrite: true)
    }

    func cancelUserProfileOverwrite() {
        userProfileState.hasConflict = false
    }

    private func saveUserProfile(forceOverwrite: Bool) {
        guard let activeSession = currentSessionOrError(),
              let snapshot = userProfileState.snapshot,
              !userProfileState.isSaving else { return }
        let name = userProfileState.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = userProfileState.emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = userProfileState.currentPassword
        guard !name.isEmpty else {
            setError("profile.validation.name_required")
            return
        }
        guard Self.isValidEmailAddress(email) else {
            setError("profile.validation.email_invalid")
            return
        }
        let emailChanged = email != snapshot.profile.email.lowercased()
        guard !emailChanged || !password.isEmpty else {
            setError("profile.validation.password_required")
            return
        }
        let nameChanged = name != snapshot.profile.name
        guard nameChanged || emailChanged else {
            presentStatus("profile.no_changes")
            return
        }

        let matchingPending = pendingProfileUpdate.flatMap { pending -> PendingProfileUpdate? in
            guard !forceOverwrite,
                  pending.name == name,
                  pending.email == email,
                  pending.currentPassword == password else { return nil }
            return pending
        }
        let pending = matchingPending ?? PendingProfileUpdate(
            name: name,
            email: email,
            currentPassword: password,
            idempotencyKey: UUID().uuidString
        )
        pendingProfileUpdate = pending
        let generation = profileGeneration
        userProfileState.isSaving = true
        profileSaveTask?.cancel()
        profileSaveTask = Task {
            defer {
                profileSaveTask = nil
                userProfileState.isSaving = false
            }
            var fields: [String: Any] = [:]
            if nameChanged { fields["name"] = name }
            if emailChanged {
                fields["email"] = email
                fields["current_password"] = password
            }
            do {
                let updated = try await clientFor(activeSession).updateUserProfile(
                    etag: snapshot.etag,
                    idempotencyKey: pending.idempotencyKey,
                    fields: fields
                )
                guard profileGeneration == generation, session?.userId == activeSession.userId else {
                    throw CancellationError()
                }
                pendingProfileUpdate = nil
                userProfileState.apply(updated)
                if updated.profile.reauthenticationRequired {
                    clearLocalSession()
                    presentStatus("profile.reauthentication_required")
                } else {
                    saveSession(activeSession.withProfile(updated.profile))
                    presentStatus("profile.saved")
                }
            } catch is CancellationError {
                return
            } catch let error as LearningBackendError where error.statusCode == 412 {
                do {
                    let latest = try await clientFor(activeSession).getUserProfile()
                    guard profileGeneration == generation else { return }
                    userProfileState.apply(latest)
                    userProfileState.nameDraft = name
                    userProfileState.emailDraft = email
                    userProfileState.currentPassword = password
                    pendingProfileUpdate = nil
                    userProfileState.hasConflict = true
                } catch {
                    showError(error)
                }
            } catch {
                showError(error)
            }
        }
    }

    func uploadUserAvatar(_ file: LocalUploadFile, forceOverwrite: Bool = false) {
        performAvatarUpload(file, preparedData: nil, forceOverwrite: forceOverwrite)
    }

    private func performAvatarUpload(
        _ file: LocalUploadFile,
        preparedData: Data?,
        forceOverwrite: Bool
    ) {
        guard let activeSession = currentSessionOrError(),
              let snapshot = userProfileState.snapshot,
              !userProfileState.isAvatarUploading else { return }
        userProfileState.isAvatarUploading = true
        avatarUploadTask?.cancel()
        let generation = profileGeneration
        avatarUploadTask = Task {
            defer {
                avatarUploadTask = nil
                userProfileState.isAvatarUploading = false
            }
            do {
                let avatarData: Data
                if let preparedData {
                    avatarData = preparedData
                } else {
                    avatarData = try await Task.detached(priority: .userInitiated) {
                        guard let image = downsampleUploadImage(at: file.url, maxPixelSize: 2_048),
                              let data = image.jpegData(compressionQuality: 0.86) else {
                            throw LearningBackendError(localizedKey: "profile.avatar.invalid")
                        }
                        return data
                    }.value
                }
                let pending: (data: Data, key: String)
                if !forceOverwrite, let existing = pendingAvatarUpload, existing.data == avatarData {
                    pending = existing
                } else {
                    pending = (avatarData, UUID().uuidString)
                }
                pendingAvatarUpload = pending
                userProfileState.hasPendingAvatarRetry = true
                let updated = try await clientFor(activeSession).uploadUserAvatar(
                    data: pending.data,
                    mimeType: "image/jpeg",
                    filename: "avatar.jpg",
                    etag: snapshot.etag,
                    idempotencyKey: pending.key
                )
                guard profileGeneration == generation, session?.userId == activeSession.userId else {
                    throw CancellationError()
                }
                pendingAvatarUpload = nil
                userProfileState.hasPendingAvatarRetry = false
                userProfileState.apply(updated)
                userProfileState.avatarImage = UIImage(data: pending.data)
                saveSession(activeSession.withProfile(updated.profile))
                presentStatus("profile.avatar.saved")
            } catch is CancellationError {
                return
            } catch let error as LearningBackendError where error.statusCode == 412 {
                do {
                    let latest = try await clientFor(activeSession).getUserProfile()
                    guard profileGeneration == generation else { return }
                    userProfileState.apply(latest)
                    userProfileState.avatarImage = pendingAvatarUpload.flatMap { UIImage(data: $0.data) }
                    userProfileState.hasAvatarConflict = true
                } catch {
                    showError(error)
                }
            } catch {
                showError(error)
            }
        }
    }

    func confirmAvatarOverwrite() {
        userProfileState.hasAvatarConflict = false
        retryPendingAvatarUpload(forceOverwrite: true)
    }

    func retryPendingAvatarUpload(forceOverwrite: Bool = false) {
        guard let pending = pendingAvatarUpload,
              let image = UIImage(data: pending.data),
              let file = try? writeImageToUploadCache(image, cacheDirectory: cacheDirectory) else { return }
        performAvatarUpload(file, preparedData: pending.data, forceOverwrite: forceOverwrite)
    }

    func cancelAvatarOverwrite() {
        userProfileState.hasAvatarConflict = false
    }

    private func loadUserAvatar(
        using client: LearningBackendClient,
        profile: UserProfile,
        generation: UUID
    ) async {
        guard profile.avatarURL?.isEmpty == false else {
            userProfileState.avatarImage = nil
            return
        }
        do {
            let data = try await client.getUserAvatarData()
            let image = await Task.detached(priority: .utility) { UIImage(data: data) }.value
            guard profileGeneration == generation else { return }
            userProfileState.avatarImage = image
        } catch {
            guard profileGeneration == generation else { return }
            userProfileState.avatarImage = nil
        }
    }

    private static func isValidEmailAddress(_ email: String) -> Bool {
        email.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
    }

    func loadAIModels(force: Bool = false) {
        if isOfflineTestMode {
            installOfflineAIModelFixtureIfNeeded()
            return
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        if !force {
            if aiModelCatalogWorkspaceId == workspaceId, aiModelCatalog != nil {
                return
            }
            if aiModelLoadTask != nil {
                return
            }
        }

        aiModelLoadTask?.cancel()
        let generation = UUID()
        aiModelLoadGeneration = generation
        isAIModelsLoading = true
        aiModelsErrorText = nil

        aiModelLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.aiModelLoadGeneration == generation {
                    self.isAIModelsLoading = false
                    self.aiModelLoadTask = nil
                }
            }
            do {
                let catalog = try await self.clientFor(activeSession).listAIModels(workspaceId: workspaceId)
                try Task.checkCancellation()
                guard self.aiModelLoadGeneration == generation,
                      self.selectedWorkspaceId == workspaceId,
                      self.session != nil else {
                    return
                }
                self.aiModelCatalog = catalog
                self.aiModelCatalogWorkspaceId = workspaceId
                self.selectedAIModelId = catalog.selectedModel == catalog.defaultModel
                    ? nil
                    : catalog.selectedModel
            } catch is CancellationError {
                return
            } catch {
                guard self.aiModelLoadGeneration == generation else { return }
                self.aiModelsErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    self.showError(error)
                }
            }
        }
    }

    func selectAIModel(_ modelId: String?) {
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              !isAIModelUpdating else {
            return
        }
        let previousSelection = selectedAIModelId
        let previousCatalog = aiModelCatalog
        let generation = UUID()
        aiModelSelectionGeneration = generation
        selectedAIModelId = modelId
        isAIModelUpdating = true
        aiModelsErrorText = nil

        aiModelSelectionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.aiModelSelectionGeneration == generation {
                    self.isAIModelUpdating = false
                    self.aiModelSelectionTask = nil
                }
            }
            do {
                let response = try await self.clientFor(activeSession).selectAIModel(
                    workspaceId: workspaceId,
                    modelId: modelId
                )
                try Task.checkCancellation()
                guard self.aiModelSelectionGeneration == generation,
                      self.selectedWorkspaceId == workspaceId,
                      self.session != nil else {
                    return
                }
                self.selectedAIModelId = response.selectedModel == response.defaultModel
                    ? nil
                    : response.preferredModel
                if let catalog = self.aiModelCatalog {
                    self.aiModelCatalog = catalog.applying(response)
                    self.aiModelCatalogWorkspaceId = workspaceId
                }
                self.setStatus("operation.ai_model_saved")
            } catch is CancellationError {
                return
            } catch {
                guard self.aiModelSelectionGeneration == generation,
                      self.selectedWorkspaceId == workspaceId else {
                    return
                }
                self.selectedAIModelId = previousSelection
                self.aiModelCatalog = previousCatalog
                self.aiModelsErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    self.showError(error)
                }
            }
        }
    }

    func loadLearningUnits(allowOfflineNetwork: Bool = false) {
        if isOfflineTestMode && !allowOfflineNetwork { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isLearningLoading = true
            defer { isLearningLoading = false }
            do {
                try await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
            } catch {
                showError(error)
            }
        }
    }

    func loadLearningDashboard(allowOfflineNetwork: Bool = false, force: Bool = true) {
        beginDeferredLoad(
            .learning,
            force: force,
            allowOfflineNetwork: allowOfflineNetwork,
            setLoading: { [weak self] isLoading in
                self?.isLearningLoading = isLoading
                self?.isHomeworkLoading = isLoading
            }
        ) { [weak self] activeSession, workspaceId, isCurrent in
            guard let self else { return }
            try await self.loadLearningDashboardContent(
                activeSession: activeSession,
                workspaceId: workspaceId,
                shouldApply: isCurrent
            )
        }
    }

    func loadNotesOverview(allowOfflineNetwork: Bool = false, force: Bool = true) {
        beginDeferredLoad(
            .notes,
            force: force,
            allowOfflineNetwork: allowOfflineNetwork,
            setLoading: { [weak self] isLoading in self?.isNotesLoading = isLoading }
        ) { [weak self] activeSession, workspaceId, isCurrent in
            guard let self else { return }
            try await self.loadNotesOverviewContent(
                activeSession: activeSession,
                workspaceId: workspaceId,
                shouldApply: isCurrent
            )
        }
    }

    func openStudyNote(_ item: StudyNoteListItem) {
        let generation = UUID()
        studyNoteReaderGeneration = generation
        cancelStudyNoteEditing()
        selectedStudyNoteItem = item
        studyNoteHTML = nil
        studyNoteRenderedURL = nil
        studyNoteReaderErrorText = nil
        renderedStudyNoteRefreshAttempted = false

        if isOfflineTestMode, item.note.id == "note-1" {
            studyNoteHTML = #"""
            <h1>Fractions &amp; Ratios</h1>
            <h2>Key Concepts</h2>
            <p>A fraction represents a part of a whole, while ratios compare the relationship between two quantities.</p>
            <p>An equivalent ratio can be written inline as \(\frac{a}{b}=\frac{c}{d}\).</p>
            <p>Cross multiplication gives:</p>
            <p>$$a \times d = b \times c$$</p>
            <ul>
              <li>Antecedent and consequent terms of a ratio must use the same unit.</li>
              <li>In a proportion, the product of the extremes equals the product of the means.</li>
            </ul>
            <blockquote>First convert to common units, then simplify and calculate.</blockquote>
            """#
            return
        }

        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }

        isStudyNoteLoading = true
        Task {
            defer {
                if studyNoteReaderGeneration == generation {
                    isStudyNoteLoading = false
                }
            }
            do {
                try await loadStudyNoteReader(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    learningUnitId: item.learningUnit.id,
                    note: item.note
                )
                guard studyNoteReaderGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedStudyNoteItem?.id == item.id else { return }
                setStatus("operation.note_loaded")
            } catch {
                guard studyNoteReaderGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedStudyNoteItem?.id == item.id else { return }
                studyNoteReaderErrorText = friendlyDisplayText(error)
            }
        }
    }

    func closeStudyNoteReader() {
        studyNoteReaderGeneration = UUID()
        cancelStudyNoteEditing()
        selectedStudyNoteItem = nil
        studyNoteHTML = nil
        studyNoteRenderedURL = nil
        studyNoteReaderErrorText = nil
        isStudyNoteLoading = false
        renderedStudyNoteRefreshAttempted = false
    }

    var canEditSelectedStudyNote: Bool {
        guard let item = selectedStudyNoteItem,
              let group = studyNoteGroups.first(where: { $0.learningUnit.id == item.learningUnit.id }) else {
            return false
        }
        return group.notes.first?.id == item.id && !isStudyNoteLoading
    }

    func presentNoteGaps(for learningUnitId: String) {
        selectedLearningUnitId = learningUnitId
        isNoteGapPresented = true
        loadNoteGaps(learningUnitId: learningUnitId, force: true)
    }

    func loadNoteGaps(learningUnitId: String? = nil, force: Bool = false) {
        if isOfflineTestMode { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let unitId = learningUnitId ?? selectedLearningUnitId, !unitId.isEmpty else { return }
        if !force, !noteGaps.isEmpty { return }
        noteGapTask?.cancel()
        let generation = UUID()
        noteGapGeneration = generation
        isNoteGapLoading = true
        noteGapTask = Task {
            defer {
                if noteGapGeneration == generation {
                    noteGapTask = nil
                    isNoteGapLoading = false
                }
            }
            do {
                let loaded = try await clientFor(activeSession).listNoteGaps(
                    workspaceId: workspaceId,
                    learningUnitId: unitId
                )
                guard noteGapGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedLearningUnitId == unitId else { return }
                noteGaps = loaded
                selectedNoBaseGapIds = selectedNoBaseGapIds.intersection(Set(loaded.filter { $0.status == "no_base_note" }.map(\.id)))
            } catch is CancellationError {
                return
            } catch {
                guard noteGapGeneration == generation else { return }
                showError(error)
            }
        }
    }

    func selectNoteGap(_ gap: NoteGap) {
        if isOfflineTestMode {
            selectedNoteGapDetail = NoteGapDetail(suggestion: gap, drafts: [])
            selectedGapSourceRefs = Set(gap.sourceRefs)
            noteGapInsertPosition = gap.insertPosition
            return
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let generation = UUID()
        noteGapGeneration = generation
        isNoteGapLoading = true
        noteGapTask?.cancel()
        noteGapTask = Task {
            defer {
                if noteGapGeneration == generation {
                    noteGapTask = nil
                    isNoteGapLoading = false
                }
            }
            do {
                let detail = try await clientFor(activeSession).getNoteGap(
                    workspaceId: workspaceId,
                    learningUnitId: gap.learningUnitId,
                    gapId: gap.id
                )
                guard noteGapGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                selectedNoteGapDetail = detail
                selectedGapSourceRefs = Set(detail.suggestion.sourceRefs)
                let latestDraft = detail.drafts.max { $0.versionNo < $1.versionNo }
                noteGapDraftHTML = latestDraft?.html ?? ""
                noteGapInsertPosition = latestDraft?.insertPosition ?? detail.suggestion.insertPosition
                noteGapInstruction = latestDraft?.instruction ?? ""
                noteGapFeedback = ""
            } catch {
                guard noteGapGeneration == generation else { return }
                showError(error)
            }
        }
    }

    func toggleGapSourceReference(_ reference: NoteSourceReference) {
        if selectedGapSourceRefs.contains(reference) {
            selectedGapSourceRefs.remove(reference)
        } else {
            selectedGapSourceRefs.insert(reference)
        }
    }

    func previewGapSource(_ reference: NoteSourceReference) {
        guard let documentId = reference.documentId,
              let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        if let document = documents.first(where: { $0.id == documentId }) {
            downloadAndPreview(document)
            return
        }
        Task {
            do {
                let document = try await clientFor(activeSession).getDocument(
                    workspaceId: workspaceId,
                    documentId: documentId
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                downloadAndPreview(document)
            } catch {
                showError(error)
            }
        }
    }

    func toggleNoBaseGap(_ id: String) {
        if selectedNoBaseGapIds.contains(id) { selectedNoBaseGapIds.remove(id) }
        else if selectedNoBaseGapIds.count < 100 { selectedNoBaseGapIds.insert(id) }
    }

    func jumpToSelectedGapAnchor() {
        guard let anchor = selectedNoteGapDetail?.suggestion.targetAnchor,
              var components = studyNoteRenderedURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return
        }
        components.fragment = anchor
        if let url = components.url { studyNoteRenderedURL = url }
        isNoteGapPresented = false
    }

    func createSelectedNoteGapDraft() {
        guard let detail = selectedNoteGapDetail else { return }
        let instruction = noteGapInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard instruction.count <= 2_000 else {
            setError("note_gap.error.instruction_length")
            return
        }
        runNoteGapTask(
            learningUnitId: detail.suggestion.learningUnitId,
            gapId: detail.suggestion.id,
            operation: { client, workspaceId in
                try await client.createNoteGapDraft(
                    workspaceId: workspaceId,
                    learningUnitId: detail.suggestion.learningUnitId,
                    gapId: detail.suggestion.id,
                    selectedSourceRefs: Array(self.selectedGapSourceRefs),
                    targetSectionId: detail.suggestion.targetSectionId,
                    insertPosition: self.noteGapInsertPosition,
                    instruction: instruction.nilIfBlank
                )
            }
        )
    }

    func saveSelectedNoteGapDraft() {
        guard let detail = selectedNoteGapDetail else { return }
        guard noteGapDraftHTML.count <= 500_000 else {
            setError("note_gap.error.html_length")
            return
        }
        runNoteGapMutation(learningUnitId: detail.suggestion.learningUnitId, gapId: detail.suggestion.id) { client, workspaceId in
            _ = try await client.updateNoteGapDraft(
                workspaceId: workspaceId,
                learningUnitId: detail.suggestion.learningUnitId,
                gapId: detail.suggestion.id,
                html: self.noteGapDraftHTML,
                targetSectionId: detail.suggestion.targetSectionId,
                insertPosition: self.noteGapInsertPosition
            )
        }
    }

    func regenerateSelectedNoteGapDraft() {
        guard let detail = selectedNoteGapDetail else { return }
        let feedback = noteGapFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty, feedback.count <= 2_000 else {
            setError("note_gap.error.feedback_required")
            return
        }
        runNoteGapTask(
            learningUnitId: detail.suggestion.learningUnitId,
            gapId: detail.suggestion.id,
            operation: { client, workspaceId in
                try await client.regenerateNoteGapDraft(
                    workspaceId: workspaceId,
                    learningUnitId: detail.suggestion.learningUnitId,
                    gapId: detail.suggestion.id,
                    feedback: feedback
                )
            }
        )
    }

    func acceptSelectedNoteGap() {
        guard let detail = selectedNoteGapDetail else { return }
        runNoteGapMutation(learningUnitId: detail.suggestion.learningUnitId, gapId: detail.suggestion.id) { client, workspaceId in
            _ = try await client.acceptNoteGap(
                workspaceId: workspaceId,
                learningUnitId: detail.suggestion.learningUnitId,
                gapId: detail.suggestion.id
            )
        }
    }

    func rejectSelectedNoteGap() {
        guard let detail = selectedNoteGapDetail else { return }
        runNoteGapMutation(learningUnitId: detail.suggestion.learningUnitId, gapId: detail.suggestion.id) { client, workspaceId in
            _ = try await client.rejectNoteGap(
                workspaceId: workspaceId,
                learningUnitId: detail.suggestion.learningUnitId,
                gapId: detail.suggestion.id
            )
        }
    }

    func createNoteFromSelectedGaps() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let unitId = selectedLearningUnitId, !selectedNoBaseGapIds.isEmpty else { return }
        isNoteGapLoading = true
        noteGapTask = Task {
            defer { isNoteGapLoading = false }
            do {
                let task = try await clientFor(activeSession).createStudyNoteFromGaps(
                    workspaceId: workspaceId,
                    learningUnitId: unitId,
                    gapIds: Array(selectedNoBaseGapIds),
                    title: nil,
                    contentEditLevel: nil,
                    layoutEditLevel: nil
                )
                activeTask = task
                selectedTab = .home
                selectedHomeDestination = .tasks
                _ = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                }
                loadNoteGaps(learningUnitId: unitId, force: true)
                setStatus("note_gap.note_created")
            } catch {
                showError(error)
            }
        }
    }

    private func runNoteGapTask(
        learningUnitId: String,
        gapId: String,
        operation: @escaping (LearningBackendClient, String) async throws -> TaskItem
    ) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        isNoteGapLoading = true
        noteGapTask?.cancel()
        noteGapTask = Task {
            defer { isNoteGapLoading = false }
            do {
                let task = try await operation(clientFor(activeSession), workspaceId)
                activeTask = task
                _ = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                }
                let detail = try await clientFor(session ?? activeSession).getNoteGap(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId,
                    gapId: gapId
                )
                selectedNoteGapDetail = detail
                noteGapDraftHTML = detail.drafts.max { $0.versionNo < $1.versionNo }?.html ?? ""
                loadNoteGaps(learningUnitId: learningUnitId, force: true)
            } catch {
                showError(error)
            }
        }
    }

    private func runNoteGapMutation(
        learningUnitId: String,
        gapId: String,
        operation: @escaping (LearningBackendClient, String) async throws -> Void
    ) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        isNoteGapLoading = true
        noteGapTask?.cancel()
        noteGapTask = Task {
            defer { isNoteGapLoading = false }
            do {
                try await operation(clientFor(activeSession), workspaceId)
                selectedNoteGapDetail = try? await clientFor(session ?? activeSession).getNoteGap(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId,
                    gapId: gapId
                )
                loadNoteGaps(learningUnitId: learningUnitId, force: true)
                try? await refreshLearningUnits(activeSession: session ?? activeSession, workspaceId: workspaceId)
                if let notes = try? await clientFor(session ?? activeSession).listStudyNotes(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId
                ).sorted(by: { $0.versionNo > $1.versionNo }) {
                    if selectedLearningUnitId == learningUnitId { studyNotes = notes }
                    if let unit = learningUnits.first(where: { $0.id == learningUnitId }),
                       let groupIndex = studyNoteGroups.firstIndex(where: { $0.learningUnit.id == learningUnitId }) {
                        studyNoteGroups[groupIndex] = StudyNoteGroup(
                            learningUnit: unit,
                            notes: notes.map { StudyNoteListItem(learningUnit: unit, note: $0) }
                        )
                    }
                }
                setStatus("note_gap.saved")
            } catch let error as LearningBackendError where error.statusCode == 409 {
                selectedNoteGapDetail = try? await clientFor(session ?? activeSession).getNoteGap(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId,
                    gapId: gapId
                )
                setError("note_gap.error.conflict")
            } catch {
                showError(error)
            }
        }
    }

    func loadStudyNoteCorrections() {
        guard let item = selectedStudyNoteItem,
              let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        isNoteCorrectionsPresented = true
        isStudyNoteCorrectionsLoading = true
        noteCorrectionsTask?.cancel()
        noteCorrectionsTask = Task {
            defer { isStudyNoteCorrectionsLoading = false }
            do {
                studyNoteCorrections = try await clientFor(activeSession).listStudyNoteCorrections(
                    workspaceId: workspaceId,
                    learningUnitId: item.learningUnit.id,
                    noteVersionId: item.note.id
                )
            } catch {
                showError(error)
            }
        }
    }

    func presentStudyNoteGeneration(for learningUnitId: String) {
        studyNoteGenerationUnitId = learningUnitId
        studyNoteGenerationUsesOverride = false
        studyNoteGenerationContentLevel = noteContentEditLevel
        studyNoteGenerationLayoutLevel = noteLayoutEditLevel
        studyNoteGenerationForceReprocess = false
        isStudyNoteGenerationPresented = true
    }

    func generateStudyNote() {
        guard !isStudyNoteGenerating,
              let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              !studyNoteGenerationUnitId.isEmpty else { return }
        let unitId = studyNoteGenerationUnitId
        isStudyNoteGenerating = true
        errorMessage = nil
        setStatus("note.generation.starting")
        studyNoteGenerateTask?.cancel()
        studyNoteGenerateTask = Task {
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isStudyNoteGenerating = false
                    studyNoteGenerateTask = nil
                }
            }
            do {
                let task = try await clientFor(activeSession).generateStudyNote(
                    workspaceId: workspaceId,
                    learningUnitId: unitId,
                    contentEditLevel: studyNoteGenerationUsesOverride ? studyNoteGenerationContentLevel : nil,
                    layoutEditLevel: studyNoteGenerationUsesOverride ? studyNoteGenerationLayoutLevel : nil,
                    forceReprocess: studyNoteGenerationForceReprocess
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                activeTask = task
                taskEvents = []
                isStudyNoteGenerationPresented = false
                selectedTab = .home
                selectedHomeDestination = .tasks
                _ = try await pollTask(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    taskId: task.id
                ) { [weak self] updated, events in
                    guard let self else { return }
                    self.activeTask = updated
                    self.taskEvents = events
                }
                try await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                let notes = try await clientFor(session ?? activeSession).listStudyNotes(
                    workspaceId: workspaceId,
                    learningUnitId: unitId
                )
                if selectedLearningUnitId == unitId { studyNotes = notes.sorted { $0.versionNo > $1.versionNo } }
                loadedDeferredContent = Set(loadedDeferredContent.filter {
                    $0.workspaceId != workspaceId || $0.content != .notes
                })
                setStatus("note.generation.completed")
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func beginStudyNoteEditing() {
        guard canEditSelectedStudyNote,
              let item = selectedStudyNoteItem,
              let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId else {
            studyNoteReaderErrorText = .localized("note.error.latest_only")
            return
        }
        studyNoteDraftTitle = item.note.title
        studyNoteDraftSummary = localized("note.editor.default_summary")
        studyNoteDraftHTML = ""
        studyNoteEditorErrorText = nil
        isStudyNoteConflictPending = false
        isStudyNoteEditorPresented = true
        isStudyNoteEditorLoading = true

        if isOfflineTestMode, item.note.id == "note-1" {
            studyNoteDraftHTML = studyNoteHTML ?? "<p>Fractions &amp; Ratios</p>"
            isStudyNoteEditorLoading = false
            return
        }

        Task {
            defer { isStudyNoteEditorLoading = false }
            do {
                let html = try await loadStudyNoteHTML(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    learningUnitId: item.learningUnit.id,
                    note: item.note,
                    prefersHighlighted: false
                )
                guard selectedStudyNoteItem?.id == item.id, isStudyNoteEditorPresented else { return }
                studyNoteDraftHTML = html
            } catch {
                studyNoteEditorErrorText = friendlyDisplayText(error)
            }
        }
    }

    func cancelStudyNoteEditing() {
        isStudyNoteEditorPresented = false
        isStudyNoteEditorLoading = false
        studyNoteDraftTitle = ""
        studyNoteDraftHTML = ""
        studyNoteDraftSummary = localized("note.editor.default_summary")
        studyNoteEditorErrorText = nil
        isStudyNoteConflictPending = false
        isStudyNoteSaving = false
    }

    func saveStudyNoteRevision() {
        guard !isStudyNoteConflictPending else { return }
        saveStudyNoteRevision(afterConflictConfirmation: false)
    }

    func confirmStudyNoteConflictAndSave() {
        isStudyNoteConflictPending = false
        saveStudyNoteRevision(afterConflictConfirmation: true)
    }

    private func saveStudyNoteRevision(afterConflictConfirmation: Bool) {
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              let item = selectedStudyNoteItem,
              canEditSelectedStudyNote,
              !isStudyNoteSaving else {
            return
        }

        let html = studyNoteDraftHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = studyNoteDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = studyNoteDraftSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HTMLNoteSecurity.hasVisibleContent(html) else {
            studyNoteEditorErrorText = .localized("note.error.empty_html")
            return
        }
        guard html.count <= 2_000_000 else {
            studyNoteEditorErrorText = .localized("note.error.html_too_long")
            return
        }
        guard title.isEmpty || title.count <= 255 else {
            studyNoteEditorErrorText = .localized("note.error.title_too_long")
            return
        }
        guard summary.isEmpty || summary.count <= 500 else {
            studyNoteEditorErrorText = .localized("note.error.summary_too_long")
            return
        }

        isStudyNoteSaving = true
        let saveGeneration = UUID()
        studyNoteSaveGeneration = saveGeneration
        studyNoteEditorErrorText = nil
        errorMessage = nil
        Task {
            defer {
                if studyNoteSaveGeneration == saveGeneration {
                    isStudyNoteSaving = false
                }
            }
            let input = StudyNoteRevisionInput(
                html: html,
                title: title.nilIfBlank,
                editSummary: summary.nilIfBlank
            )
            do {
                let response = try await clientFor(activeSession).createStudyNoteRevision(
                    workspaceId: workspaceId,
                    learningUnitId: item.learningUnit.id,
                    baseVersionId: item.note.id,
                    input: input
                )
                guard studyNoteSaveGeneration == saveGeneration,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedStudyNoteItem?.id == item.id,
                      isStudyNoteEditorPresented else { return }
                let optimisticItem = StudyNoteListItem(learningUnit: item.learningUnit, note: response.note)
                selectedStudyNoteItem = optimisticItem
                studyNoteHTML = html
                studyNoteRenderedURL = nil
                studyNoteReaderErrorText = nil
                isStudyNoteEditorPresented = false
                setStatus("operation.note_revision_saved")

                do {
                    let refreshedItems = try await refreshStudyNoteGroup(
                        activeSession: activeSession,
                        workspaceId: workspaceId,
                        learningUnit: item.learningUnit
                    )
                    guard studyNoteSaveGeneration == saveGeneration,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          selectedStudyNoteItem?.note.id == response.note.id else { return }
                    if let refreshed = refreshedItems.first(where: { $0.note.id == response.note.id }) {
                        selectedStudyNoteItem = refreshed
                        await refreshRenderedStudyNoteAfterRevision(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            item: refreshed,
                            fallbackHTML: html
                        )
                    }
                } catch {
                    handlePostCommitRefreshFailure(error, completionKey: "operation.note_revision_saved")
                }
            } catch let error as LearningBackendError where error.statusCode == 409 {
                guard studyNoteSaveGeneration == saveGeneration,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      isStudyNoteEditorPresented else { return }
                await handleStudyNoteRevisionConflict(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    learningUnit: item.learningUnit,
                    originalError: error,
                    afterConflictConfirmation: afterConflictConfirmation
                )
            } catch {
                guard studyNoteSaveGeneration == saveGeneration,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      isStudyNoteEditorPresented else { return }
                studyNoteEditorErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    showError(error)
                }
            }
        }
    }

    func selectLearningUnit(_ learningUnitId: String) {
        let generation = UUID()
        learningUnitSelectionGeneration = generation
        selectedLearningUnitId = learningUnitId
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isLearningLoading = true
            defer {
                if learningUnitSelectionGeneration == generation {
                    isLearningLoading = false
                }
            }
            do {
                let loadedNotes = try await clientFor(activeSession).listStudyNotes(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId
                )
                guard learningUnitSelectionGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedLearningUnitId == learningUnitId else { return }
                studyNotes = loadedNotes
            } catch {
                guard learningUnitSelectionGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedLearningUnitId == learningUnitId else { return }
                showError(error)
            }
        }
    }

    var canBeginLearningUnitMerge: Bool {
        learningUnits.filter { $0.mergedIntoId == nil }.count >= 2 && !isLearningUnitMerging
    }

    func beginLearningUnitMerge() {
        guard canBeginLearningUnitMerge else { return }
        if !learningUnits.contains(where: { $0.id == mergeTargetLearningUnitId }) {
            mergeTargetLearningUnitId = selectedLearningUnitId
                ?? learningUnits.first(where: { $0.mergedIntoId == nil })?.id
                ?? ""
        }
        mergeSourceLearningUnitIds.remove(mergeTargetLearningUnitId)
        isLearningUnitMergePresented = true
        errorMessage = nil
    }

    func setLearningUnitMergeTarget(_ learningUnitId: String) {
        mergeTargetLearningUnitId = learningUnitId
        mergeSourceLearningUnitIds.remove(learningUnitId)
    }

    func toggleLearningUnitMergeSource(_ learningUnitId: String) {
        guard learningUnitId != mergeTargetLearningUnitId else { return }
        if mergeSourceLearningUnitIds.contains(learningUnitId) {
            mergeSourceLearningUnitIds.remove(learningUnitId)
        } else if mergeSourceLearningUnitIds.count < 50 {
            mergeSourceLearningUnitIds.insert(learningUnitId)
        }
    }

    func requestLearningUnitMergeConfirmation() {
        guard learningUnits.contains(where: { $0.id == mergeTargetLearningUnitId }) else {
            setError("merge.error.target_required")
            return
        }
        guard (1...50).contains(mergeSourceLearningUnitIds.count),
              !mergeSourceLearningUnitIds.contains(mergeTargetLearningUnitId) else {
            setError("merge.error.sources_required")
            return
        }
        isLearningUnitMergeConfirmationPresented = true
    }

    func confirmLearningUnitMerge() {
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              !isLearningUnitMerging else { return }
        let targetId = mergeTargetLearningUnitId
        let sourceIds = Array(mergeSourceLearningUnitIds).sorted()
        guard learningUnits.contains(where: { $0.id == targetId }),
              (1...50).contains(sourceIds.count),
              !sourceIds.contains(targetId) else {
            setError("merge.error.sources_required")
            return
        }

        isLearningUnitMerging = true
        errorMessage = nil
        setStatus("merge.starting")
        taskEvents = []
        Task {
            defer { isLearningUnitMerging = false }
            var mergeRequestAccepted = false
            do {
                let task = try await clientFor(activeSession).mergeLearningUnits(
                    workspaceId: workspaceId,
                    targetLearningUnitId: targetId,
                    sourceLearningUnitIds: sourceIds
                )
                mergeRequestAccepted = true
                activeTask = task
                activeMergeTargetLearningUnitId = targetId
                isLearningUnitMergePresented = false
                isLearningUnitMergeConfirmationPresented = false
                mergeSourceLearningUnitIds = []
                setStatus("merge.in_progress")

                _ = try await pollTask(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    taskId: task.id
                ) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                    self?.setStatus("merge.task_progress", statusLabel(task.status), String(task.progress.clamped(to: 0...100)))
                }

                try await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId, preserveGradingDrafts: true)
                selectedFlashcardLearningUnitId = targetId
                selectedFlashcardDeckId = nil
                flashcardDecks = []
                flashcardDeckDetail = nil
                if let target = learningUnits.first(where: { $0.id == targetId }),
                   target.mergeStatus == "completed" {
                    _ = try? await refreshStudyNoteGroup(
                        activeSession: activeSession,
                        workspaceId: workspaceId,
                        learningUnit: target
                    )
                    activeMergeTargetLearningUnitId = nil
                    setStatus("merge.completed")
                    if selectedLearningSection == .flashcards {
                        loadFlashcards(learningUnitId: targetId)
                    }
                } else if learningUnits.first(where: { $0.id == targetId })?.mergeStatus == "failed" {
                    setError("merge.status.failed")
                } else {
                    setStatus("merge.rebuilding")
                    resumeStudyNoteGenerationPollingIfNeeded()
                }
            } catch {
                if mergeRequestAccepted {
                    try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                }
                showError(error)
            }
        }
    }

    func viewLearningUnitMergeTask() {
        selectedTab = .home
        selectedDocumentsSection = .tasks
        selectedHomeDestination = .tasks
    }

    func displayedMergeStatus(for unit: LearningUnit) -> String? {
        if activeMergeTargetLearningUnitId == unit.id, isLearningUnitMerging {
            return "merging"
        }
        return unit.mergeStatus
    }

    var currentFlashcard: Flashcard? {
        guard let cards = flashcardDeckDetail?.cards.sorted(by: { $0.rank < $1.rank }),
              cards.indices.contains(flashcardIndex) else { return nil }
        return cards[flashcardIndex]
    }

    func ensureFlashcardsLoaded(force: Bool = false) {
        guard selectedTab == .notes, selectedLearningSection == .flashcards else { return }
        let unitId = selectedFlashcardLearningUnitId.nilIfBlank
            ?? selectedLearningUnitId
            ?? learningUnits.first?.id
        guard let unitId else {
            flashcardDecks = []
            flashcardDeckDetail = nil
            selectedFlashcardDeckId = nil
            return
        }
        if !force,
           selectedFlashcardLearningUnitId == unitId,
           flashcardDeckDetail != nil || (!flashcardDecks.isEmpty && selectedFlashcardDeckId == nil) {
            return
        }
        loadFlashcards(learningUnitId: unitId)
    }

    func selectFlashcardLearningUnit(_ learningUnitId: String) {
        guard selectedFlashcardLearningUnitId != learningUnitId || flashcardDeckDetail == nil else { return }
        selectedFlashcardLearningUnitId = learningUnitId
        flashcardDecks = []
        selectedFlashcardDeckId = nil
        flashcardDeckDetail = nil
        flashcardIndex = 0
        isFlashcardShowingBack = false
        loadFlashcards(learningUnitId: learningUnitId)
    }

    func selectFlashcardDeck(_ deckId: String) {
        guard selectedFlashcardDeckId != deckId || flashcardDeckDetail?.deck.id != deckId else { return }
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              let unitId = selectedFlashcardLearningUnitId.nilIfBlank else { return }
        selectedFlashcardDeckId = deckId
        flashcardIndex = 0
        isFlashcardShowingBack = false
        isFlashcardsLoading = true
        flashcardErrorText = nil
        flashcardLoadGeneration = UUID()
        let generation = flashcardLoadGeneration
        flashcardLoadTask?.cancel()
        flashcardLoadTask = Task {
            defer {
                if flashcardLoadGeneration == generation {
                    isFlashcardsLoading = false
                    flashcardLoadTask = nil
                }
            }
            do {
                let detail = try await clientFor(activeSession).getFlashcardDeck(
                    workspaceId: workspaceId,
                    learningUnitId: unitId,
                    deckId: deckId
                )
                guard selectedWorkspaceId == workspaceId,
                      flashcardLoadGeneration == generation,
                      selectedFlashcardLearningUnitId == unitId,
                      selectedFlashcardDeckId == deckId else { return }
                flashcardDeckDetail = sortedFlashcardDetail(detail)
            } catch is CancellationError {
                return
            } catch {
                guard flashcardLoadGeneration == generation else { return }
                flashcardErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    showError(error)
                }
            }
        }
    }

    func flipCurrentFlashcard() {
        guard currentFlashcard != nil else { return }
        isFlashcardShowingBack.toggle()
    }

    func showPreviousFlashcard() {
        guard flashcardIndex > 0 else { return }
        flashcardIndex -= 1
        isFlashcardShowingBack = false
    }

    func showNextFlashcard() {
        guard let count = flashcardDeckDetail?.cards.count, flashcardIndex + 1 < count else { return }
        flashcardIndex += 1
        isFlashcardShowingBack = false
    }

    private func loadFlashcards(learningUnitId: String) {
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId else { return }
        selectedFlashcardLearningUnitId = learningUnitId
        isFlashcardsLoading = true
        flashcardErrorText = nil
        flashcardLoadGeneration = UUID()
        let generation = flashcardLoadGeneration
        flashcardLoadTask?.cancel()
        flashcardLoadTask = Task {
            defer {
                if flashcardLoadGeneration == generation {
                    isFlashcardsLoading = false
                    flashcardLoadTask = nil
                }
            }
            do {
                let client = clientFor(activeSession)
                async let decksRequest = client.listFlashcardDecks(
                    workspaceId: workspaceId,
                    learningUnitId: learningUnitId,
                    page: 1,
                    pageSize: 100
                )
                let latest: FlashcardDeckDetail?
                do {
                    latest = try await client.getLatestFlashcardDeck(
                        workspaceId: workspaceId,
                        learningUnitId: learningUnitId
                    )
                } catch let error as LearningBackendError where error.statusCode == 404 {
                    latest = nil
                }
                let loadedDecks = try await decksRequest
                let decks = loadedDecks.sorted {
                    if $0.versionNo != $1.versionNo { return $0.versionNo > $1.versionNo }
                    return $0.createdAt > $1.createdAt
                }
                guard selectedWorkspaceId == workspaceId,
                      flashcardLoadGeneration == generation,
                      selectedFlashcardLearningUnitId == learningUnitId else { return }
                flashcardDecks = decks
                flashcardDeckDetail = latest.map(sortedFlashcardDetail)
                selectedFlashcardDeckId = latest?.deck.id
                flashcardIndex = 0
                isFlashcardShowingBack = false
            } catch is CancellationError {
                return
            } catch {
                guard selectedWorkspaceId == workspaceId,
                      flashcardLoadGeneration == generation,
                      selectedFlashcardLearningUnitId == learningUnitId else { return }
                flashcardErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    showError(error)
                }
            }
        }
    }

    private func sortedFlashcardDetail(_ detail: FlashcardDeckDetail) -> FlashcardDeckDetail {
        FlashcardDeckDetail(deck: detail.deck, cards: detail.cards.sorted { $0.rank < $1.rank })
    }

    var selectedHomework: HomeworkItem? {
        homeworks.first(where: { $0.id == selectedHomeworkId })
    }

    var latestGradingResult: GradingResult? {
        selectedHomework?.latestGradingResult
    }

    var isSelectedGradingHistoryLoaded: Bool {
        gradingHistoryWorkspaceId == selectedWorkspaceId
            && gradingHistoryHomeworkId == selectedHomeworkId
    }

    var isGradingConfigDirty: Bool {
        guard let selectedHomework else { return false }
        let draftRubric = homeworkRubricText.nilIfBlank
        let savedRubric = selectedHomework.rubricText?.nilIfBlank
        guard let draftMaxScore = Double(homeworkMaxScoreText) else { return true }
        return draftRubric != savedRubric || abs(draftMaxScore - selectedHomework.maxScore) > 0.000_001
    }

    var homeworkDocumentCandidates: [LearningDocumentItem] {
        gradingDocuments.filter {
            $0.status == "ready" && ($0.documentKind == "homework" || $0.documentKind == "corrected_homework")
        }
    }

    var referenceDocumentCandidates: [LearningDocumentItem] {
        let attachedIds = Set(homeworkReferences.map(\.documentId))
        return gradingDocuments.filter {
            $0.status == "ready" && ($0.documentKind == "answer_key" || $0.documentKind == "rubric") && !attachedIds.contains($0.id)
        }
    }

    var gradingModeLabel: String? {
        guard let latestGradingResult else { return nil }
        return latestGradingResult.gradingMode == "official"
            ? localized("grading.mode.official")
            : localized("grading.mode.diagnostic")
    }

    var gradingConfidence: Double? {
        latestGradingResult?.confidence
    }

    var canRetryDocumentPurge: Bool {
        isDocumentPurgeRetryAvailable && !isBusy
    }

    func searchKnowledge() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        guard !isKnowledgeSearching else { return }
        let query = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            setError("knowledge.error.query_required")
            return
        }
        guard query.count <= 8000 else {
            setError("knowledge.error.query_length")
            return
        }
        let limit = knowledgeLimit.clamped(to: 1...20)
        let learningUnitId = knowledgeLearningUnitId.nilIfBlank
        let subject = knowledgeSubject.nilIfBlank
        knowledgeLimit = limit
        knowledgeSearchTask?.cancel()
        let generation = UUID()
        knowledgeSearchGeneration = generation
        isKnowledgeSearching = true
        errorMessage = nil
        knowledgeSearchTask = Task {
            defer {
                if knowledgeSearchGeneration == generation {
                    knowledgeSearchTask = nil
                    isKnowledgeSearching = false
                }
            }
            do {
                let response = try await clientFor(activeSession).searchKnowledge(
                    workspaceId: workspaceId,
                    query: query,
                    learningUnitId: learningUnitId,
                    subject: subject,
                    limit: limit
                )
                guard knowledgeSearchGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                knowledgeResults = response.items
                hasSearchedKnowledge = true
                if response.items.isEmpty {
                    setStatus("knowledge.no_results")
                } else {
                    setStatus("knowledge.results_found", String(response.items.count))
                }
            } catch is CancellationError {
                return
            } catch {
                guard knowledgeSearchGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func previewKnowledgeSource(_ item: KnowledgeSearchItem) {
        guard let documentId = item.documentId else { return }
        if let document = (documents + gradingDocuments).first(where: { $0.id == documentId }) {
            downloadAndPreview(document)
            return
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            do {
                let document = try await clientFor(activeSession).getDocument(workspaceId: workspaceId, documentId: documentId)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                downloadAndPreview(document)
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func selectHomework(_ homeworkId: String) {
        homeworkSelectionTask?.cancel()
        let generation = UUID()
        homeworkSelectionGeneration = generation
        selectedHomeworkId = homeworkId
        homeworkReferences = []
        lastGradingTask = nil
        clearGradingHistoryState()
        if let homework = homeworks.first(where: { $0.id == homeworkId }) {
            homeworkRubricText = homework.rubricText ?? ""
            homeworkMaxScoreText = formatScore(homework.maxScore)
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        isHomeworkLoading = true
        homeworkSelectionTask = Task {
            defer {
                if homeworkSelectionGeneration == generation {
                    homeworkSelectionTask = nil
                    isHomeworkLoading = false
                }
            }
            do {
                let references = try await clientFor(activeSession).listHomeworkReferences(workspaceId: workspaceId, homeworkId: homeworkId)
                guard homeworkSelectionGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                homeworkReferences = references
            } catch is CancellationError {
                return
            } catch {
                guard homeworkSelectionGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                showError(error)
            }
        }
    }

    func loadGradingHistory(force: Bool = false) {
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId else { return }
        if !force, isGradingHistoryLoading {
            return
        }
        if !force,
           gradingHistoryWorkspaceId == workspaceId,
           gradingHistoryHomeworkId == homeworkId {
            return
        }

        gradingHistoryTask?.cancel()
        let generation = UUID()
        gradingHistoryGeneration = generation
        gradingHistoryErrorText = nil
        isGradingHistoryLoading = true
        gradingHistoryTask = Task {
            defer {
                if gradingHistoryGeneration == generation {
                    gradingHistoryTask = nil
                    isGradingHistoryLoading = false
                }
            }
            do {
                let results = try await clientFor(activeSession).listGradingResults(
                    workspaceId: workspaceId,
                    homeworkId: homeworkId
                )
                guard gradingHistoryGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                gradingResults = results.sorted { $0.createdAt > $1.createdAt }
                gradingHistoryWorkspaceId = workspaceId
                gradingHistoryHomeworkId = homeworkId
            } catch is CancellationError {
                return
            } catch {
                guard gradingHistoryGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                gradingHistoryErrorText = friendlyDisplayText(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    showError(error)
                }
            }
        }
    }

    @discardableResult
    func createHomework(
        documentId: String,
        title: String,
        description: String,
        dueAt: Date?,
        rubricText: String,
        maxScoreText: String,
        onCommitted: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              !isHomeworkLoading else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard homeworkDocumentCandidates.contains(where: { $0.id == documentId }) else {
            setError("grading.error.document_required")
            return false
        }
        guard !trimmedTitle.isEmpty else {
            setError("grading.error.title_required")
            return false
        }
        guard let maxScore = Double(maxScoreText), maxScore > 0 else {
            setError("grading.error.max_score")
            return false
        }
        let input = HomeworkCreateInput(
            title: trimmedTitle,
            description: description.nilIfBlank,
            documentId: documentId,
            dueAt: dueAt.map { ISO8601DateFormatter().string(from: $0) },
            rubricText: rubricText.nilIfBlank,
            maxScore: maxScore
        )
        isHomeworkLoading = true
        errorMessage = nil
        Task {
            defer { isHomeworkLoading = false }
            do {
                let homework = try await clientFor(activeSession).createHomework(workspaceId: workspaceId, input: input)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                if let index = homeworks.firstIndex(where: { $0.id == homework.id }) {
                    homeworks[index] = homework
                } else {
                    homeworks.insert(homework, at: 0)
                }
                selectedHomeworkId = homework.id
                homeworkReferences = []
                clearGradingHistoryState()
                homeworkRubricText = homework.rubricText ?? ""
                homeworkMaxScoreText = formatScore(homework.maxScore)
                setStatus("grading.homework_created")
                onCommitted()
                do {
                    try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                } catch {
                    guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    handlePostCommitRefreshFailure(error, completionKey: "Homework created.")
                }
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
        return true
    }

    func saveGradingConfig() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId, !isHomeworkLoading else { return }
        guard let maxScore = Double(homeworkMaxScoreText), maxScore > 0 else {
            setError("grading.error.max_score")
            return
        }
        guard isGradingConfigDirty else { return }
        let input = GradingConfigInput(rubricText: homeworkRubricText.nilIfBlank, maxScore: maxScore)
        let submittedRubricText = homeworkRubricText
        let submittedMaxScoreText = homeworkMaxScoreText
        isHomeworkLoading = true
        errorMessage = nil
        setStatus("grading.saving_config")
        Task {
            defer { isHomeworkLoading = false }
            do {
                let updated = try await clientFor(activeSession).updateGradingConfig(workspaceId: workspaceId, homeworkId: homeworkId, input: input)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                homeworks = homeworks.map { $0.id == updated.id ? updated : $0 }
                if homeworkRubricText == submittedRubricText,
                   homeworkMaxScoreText == submittedMaxScoreText {
                    homeworkRubricText = updated.rubricText ?? ""
                    homeworkMaxScoreText = formatScore(updated.maxScore)
                }
                lastGradingTask = nil
                setStatus("grading.config_saved")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                showError(error)
            }
        }
    }

    func addHomeworkReference(
        documentId: String,
        onCommitted: @escaping @MainActor () -> Void = {}
    ) {
        guard let document = referenceDocumentCandidates.first(where: { $0.id == documentId }),
              let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId, !isHomeworkLoading else { return }
        isHomeworkLoading = true
        errorMessage = nil
        Task {
            defer { isHomeworkLoading = false }
            do {
                let reference = try await clientFor(activeSession).addHomeworkReference(
                    workspaceId: workspaceId,
                    homeworkId: homeworkId,
                    documentId: document.id,
                    referenceType: document.documentKind
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                if let index = homeworkReferences.firstIndex(where: { $0.id == reference.id }) {
                    homeworkReferences[index] = reference
                } else {
                    homeworkReferences.append(reference)
                }
                lastGradingTask = nil
                setStatus("grading.reference_added")
                onCommitted()
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                showError(error)
            }
        }
    }

    func deleteHomeworkReference(_ reference: HomeworkReferenceItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId, !isHomeworkLoading else { return }
        isHomeworkLoading = true
        errorMessage = nil
        setStatus("grading.removing_reference")
        Task {
            defer { isHomeworkLoading = false }
            do {
                let client = clientFor(activeSession)
                try await client.deleteHomeworkReference(workspaceId: workspaceId, homeworkId: homeworkId, referenceId: reference.id)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                homeworkReferences.removeAll { $0.id == reference.id }
                lastGradingTask = nil
                setStatus("grading.reference_removed")
                do {
                    let refreshedReferences = try await client.listHomeworkReferences(workspaceId: workspaceId, homeworkId: homeworkId)
                    guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          selectedHomeworkId == homeworkId else { return }
                    homeworkReferences = refreshedReferences
                } catch {
                    handlePostCommitRefreshFailure(error, completionKey: "operation.reference_removed")
                }
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                showError(error)
            }
        }
    }

    func gradeSelectedHomework() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId, !isHomeworkLoading else { return }
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            taskEvents = []
            lastGradingTask = nil
            defer { isHomeworkLoading = false }
            do {
                let task = try await clientFor(activeSession).gradeHomework(workspaceId: workspaceId, homeworkId: homeworkId)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                activeTask = task
                selectedTab = .home
                selectedDocumentsSection = .tasks
                selectedHomeDestination = .tasks
                let finished = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] task, events in
                    guard let self,
                          self.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          self.activeTask?.id == task.id else { return }
                    self.activeTask = task
                    self.taskEvents = events
                    self.setStatus(
                        "grading.task_progress",
                        statusLabel(task.status),
                        String(task.progress.clamped(to: 0...100))
                    )
                }
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                lastGradingTask = finished
                let shouldRefreshHistory = isSelectedGradingHistoryLoaded
                try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                if shouldRefreshHistory,
                   selectedHomeworkId == homeworkId {
                    loadGradingHistory(force: true)
                }
                try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                setStatus("grading.complete")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                showError(error)
            }
        }
    }

    func downloadAndPreview(_ note: StudyNoteVersion) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            do {
                let client = clientFor(activeSession)
                let response = try await client.getStudyNoteDownloadURL(
                    workspaceId: workspaceId,
                    learningUnitId: note.learningUnitId,
                    noteVersionId: note.id,
                    kind: note.highlightedHTMLObjectKey == nil ? .html : .highlightedHTML
                )
                try await downloadAndPreview(
                    client: client,
                    downloadURL: response.downloadURL,
                    filename: response.filename,
                    mimeType: "text/html",
                    cacheKey: note.id,
                    completionText: .localized("operation.note_downloaded"),
                    shouldApply: { [weak self] in
                        self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                    }
                )
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func loadArtifacts(for document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        guard canDownloadDocument(document) else {
            setError("document.error.not_available")
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("document.loading_artifacts")
            do {
                let loadedArtifacts = try await clientFor(activeSession).listArtifacts(
                    workspaceId: workspaceId,
                    documentId: document.id
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                selectedArtifactDocumentId = document.id
                selectedArtifacts = loadedArtifacts
                setStatus("document.artifacts_loaded")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func loadOcrArtifacts(for document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        guard canDownloadDocument(document) else {
            setError("document.error.not_available")
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("document.loading_ocr")
            do {
                let loadedArtifacts = try await clientFor(activeSession)
                    .getOcrArtifacts(workspaceId: workspaceId, documentId: document.id, includeDownloadURL: true)
                    .artifacts
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                selectedOcrDocumentId = document.id
                selectedOcrArtifacts = loadedArtifacts
                setStatus(selectedOcrArtifacts.isEmpty ? "document.ocr_empty" : "document.ocr_loaded")
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func deleteDocument(_ document: LearningDocumentItem) {
        startDocumentPurge(documentId: document.id)
    }

    func retryDocumentPurge() {
        guard let documentId = retryableDocumentPurgeId else { return }
        startDocumentPurge(documentId: documentId)
    }

    private func startDocumentPurge(documentId: String) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId, !isBusy else {
            return
        }
        isBusy = true
        isDocumentPurgeRetryAvailable = false
        errorMessage = nil
        taskEvents = []
        setStatus("document.deleting")

        Task {
            var deletionAccepted = false
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            do {
                let client = clientFor(activeSession)
                let response = try await client.deleteDocument(workspaceId: workspaceId, documentId: documentId)
                deletionAccepted = true
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                retryableDocumentPurgeId = response.documentId
                removeDeletedDocumentFromLocalState(response.documentId)
                selectedTab = .home
                selectedDocumentsSection = .tasks
                selectedHomeDestination = .tasks
                setStatus("document.cleanup_started")

                let initialTask = try await client.getTask(workspaceId: workspaceId, taskId: response.purgeTaskId)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                activeTask = initialTask
                let finishedTask = try await pollTask(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    taskId: response.purgeTaskId
                ) { [weak self] task, events in
                    guard let self,
                          self.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                          self.activeTask?.id == response.purgeTaskId else { return }
                    self.activeTask = task
                    self.taskEvents = events
                    self.setStatus(
                        "document.cleanup_progress",
                        statusLabel(task.status),
                        String(task.progress.clamped(to: 0...100))
                    )
                }

                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      activeTask?.id == response.purgeTaskId else { return }
                guard finishedTask.status == "succeeded" else { return }
                retryableDocumentPurgeId = nil
                isDocumentPurgeRetryAvailable = false
                setStatus("document.cleanup_complete")
                if let refreshError = await refreshAfterDocumentDeletion(activeSession: activeSession, workspaceId: workspaceId) {
                    handlePostCommitRefreshFailure(refreshError, completionKey: "operation.document_cleanup_completed")
                }
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                if deletionAccepted && !shouldStopPostCommitRefresh(for: error) {
                    isDocumentPurgeRetryAvailable = true
                }
                showError(error)
            }
        }
    }

    private func removeDeletedDocumentFromLocalState(_ documentId: String) {
        let affectsGrading = homeworkReferences.contains(where: { $0.documentId == documentId })
            || homeworks.contains(where: { $0.documentId == documentId })
        documents.removeAll { $0.id == documentId }
        if selectedArtifactDocumentId == documentId {
            selectedArtifactDocumentId = nil
            selectedArtifacts = []
        }
        if selectedOcrDocumentId == documentId {
            selectedOcrDocumentId = nil
            selectedOcrArtifacts = []
        }
        gradingDocuments.removeAll { $0.id == documentId }
        homeworkReferences.removeAll { $0.documentId == documentId }
        if affectsGrading {
            lastGradingTask = nil
        }
    }

    func downloadAndPreview(_ artifact: DocumentArtifactItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("document.fetching_artifact_link")
            do {
                let client = clientFor(activeSession)
                let response = try await client.getArtifactDownloadURL(
                    workspaceId: workspaceId,
                    documentId: artifact.documentId,
                    artifactId: artifact.id
                )
                let filename = response.filename.isEmpty
                    ? defaultArtifactFilename(type: artifact.artifactType, mimeType: artifact.mimeType, fallback: artifact.id)
                    : response.filename
                try await downloadAndPreview(
                    client: client,
                    downloadURL: response.downloadURL,
                    filename: filename,
                    mimeType: response.mimeType ?? artifact.mimeType,
                    fileSize: artifact.fileSize,
                    cacheKey: artifact.id,
                    completionText: .localized(
                        "document.artifact_downloaded",
                        [artifactTypeLabel(artifact.artifactType)]
                    ),
                    shouldApply: { [weak self] in
                        self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                    }
                )
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func downloadAndPreview(_ artifact: OcrArtifactItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        guard let downloadURL = artifact.downloadURL, !downloadURL.isEmpty else {
            setError("document.error.ocr_link_missing")
            return
        }
        Task {
            isBusy = true
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    isBusy = false
                }
            }
            errorMessage = nil
            setStatus("document.downloading_ocr")
            do {
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: defaultArtifactFilename(type: artifact.artifactType, mimeType: artifact.mimeType, fallback: artifact.id),
                    mimeType: artifact.mimeType,
                    fileSize: artifact.fileSize,
                    cacheKey: artifact.id,
                    completionText: .localized(
                        "document.artifact_downloaded",
                        [artifactTypeLabel(artifact.artifactType)]
                    ),
                    shouldApply: { [weak self] in
                        self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true
                    }
                )
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func downloadAndPreview(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        guard canDownloadDocument(document) else {
            setError("document.error.not_available")
            return
        }
        guard !previewLoadingDocumentIds.contains(document.id) else { return }
        previewLoadingDocumentIds.insert(document.id)
        Task {
            defer {
                if isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) {
                    previewLoadingDocumentIds.remove(document.id)
                }
            }
            errorMessage = nil
            setStatus("document.fetching_download_link")
            do {
                let client = clientFor(activeSession)
                let safeFilename = sanitizeFileName(document.originalFilename)
                let targetURL = cacheDirectory
                    .appendingPathComponent("downloads", isDirectory: true)
                    .appendingPathComponent(sanitizeFileName(document.id), isDirectory: true)
                    .appendingPathComponent(safeFilename)
                var downloadedURL: URL?
                var lastError: Error?
                for attempt in 0..<2 {
                    do {
                        let response = try await client.getDownloadURL(workspaceId: workspaceId, documentId: document.id)
                        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
                        setStatus("document.downloading")
                        downloadedURL = try await client.download(downloadURL: response.downloadURL, targetURL: targetURL)
                        break
                    } catch {
                        lastError = error
                        guard attempt == 0, shouldRetryDocumentPreviewDownload(error) else { throw error }
                    }
                }
                guard let downloadedURL else {
                    throw lastError ?? LearningBackendError(localizedKey: "document.error.not_available")
                }
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                downloadedPreview = DownloadedPreview(
                    url: downloadedURL,
                    mimeType: document.mimeType ?? contentTypeForFilename(document.originalFilename),
                    filename: document.originalFilename,
                    fileSize: document.fileSize
                )
                setStatus(
                    document.mimeType?.hasPrefix("image/") == true
                        ? "operation.image_downloaded"
                        : "operation.file_downloaded"
                )
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    func documentThumbnailIdentifier(for document: LearningDocumentItem) -> String {
        guard let activeSession = session else {
            return [document.workspaceId, document.id, document.updatedAt, document.originalFilename]
                .joined(separator: "|")
        }
        return documentThumbnailCacheKey(
            baseURL: activeSession.baseURL,
            userId: activeSession.userId,
            workspaceId: document.workspaceId,
            document: document
        )
    }

    func generateDocumentThumbnail(
        for document: LearningDocumentItem,
        maxPixelSize: Int = 160
    ) async -> UIImage? {
        guard documentSupportsImageThumbnail(document),
              !isOfflineTestMode,
              let activeSession = session,
              let workspaceId = selectedWorkspaceId,
              document.workspaceId == workspaceId else {
            return nil
        }

        let thumbnailURL = documentThumbnailCacheURL(
            cacheDirectory: cacheDirectory,
            baseURL: activeSession.baseURL,
            userId: activeSession.userId,
            workspaceId: workspaceId,
            document: document
        )
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            return await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: thumbnailURL.path)
            }.value
        }

        let sourceURL = cacheDirectory
            .appendingPathComponent("document-thumbnail-sources", isDirectory: true)
            .appendingPathComponent(sanitizeFileName(workspaceId), isDirectory: true)
            .appendingPathComponent(sanitizeFileName(document.id), isDirectory: true)
            .appendingPathComponent(sanitizeFileName(document.originalFilename))
        let client = clientFor(activeSession)

        do {
            var downloadedSource: URL?
            for attempt in 0..<2 {
                do {
                    let response = try await client.getDownloadURL(
                        workspaceId: workspaceId,
                        documentId: document.id
                    )
                    downloadedSource = try await client.download(
                        downloadURL: response.downloadURL,
                        targetURL: sourceURL
                    )
                    break
                } catch {
                    guard attempt == 0, shouldRetryDocumentPreviewDownload(error) else {
                        throw error
                    }
                }
            }
            guard let downloadedSource,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
                return nil
            }
            return await Task.detached(priority: .utility) {
                defer { try? FileManager.default.removeItem(at: downloadedSource) }
                guard let image = downsampleUploadImage(
                    at: downloadedSource,
                    maxPixelSize: max(1, maxPixelSize)
                ) else {
                    return nil
                }
                do {
                    try FileManager.default.createDirectory(
                        at: thumbnailURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if let data = image.pngData() {
                        try data.write(to: thumbnailURL, options: .atomic)
                    }
                } catch {
                    // A memory-cached thumbnail is still useful if disk caching fails.
                }
                return image
            }.value
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            return nil
        }
    }

    private func downloadAndPreview(
        client: LearningBackendClient,
        downloadURL: String,
        filename: String,
        mimeType: String?,
        fileSize: Int64? = nil,
        cacheKey: String = "shared",
        completionText: AppDisplayText,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async throws {
        setStatus("document.downloading")
        let directory = cacheDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(sanitizeFileName(cacheKey), isDirectory: true)
        let safeFilename = sanitizeFileName(filename)
        let targetURL = directory.appendingPathComponent(safeFilename)
        let downloadedURL = try await client.download(downloadURL: downloadURL, targetURL: targetURL)
        guard shouldApply() else { throw CancellationError() }
        downloadedPreview = DownloadedPreview(
            url: downloadedURL,
            mimeType: mimeType ?? contentTypeForFilename(safeFilename),
            filename: filename,
            fileSize: fileSize
        )
        statusDisplayText = completionText
    }

    private func shouldRetryDocumentPreviewDownload(_ error: Error) -> Bool {
        guard let backendError = error as? LearningBackendError else { return false }
        return backendError.statusCode == 401 || backendError.statusCode == 403
    }

    private func shouldForceReprocess(_ document: LearningDocumentItem) -> Bool {
        document.status == "ready" || document.status == "failed"
    }

    func canProcessDocument(_ document: LearningDocumentItem) -> Bool {
        learningDocumentKinds.contains(document.documentKind)
            && learningPipelineFileTypes.contains(document.fileType)
            && ["uploaded", "ready", "failed"].contains(document.status)
    }

    func canDownloadDocument(_ document: LearningDocumentItem) -> Bool {
        document.status != "deleted" && document.purgeStatus != "completed"
    }

    func isDocumentPreviewLoading(_ documentId: String) -> Bool {
        previewLoadingDocumentIds.contains(documentId)
    }

    private func defaultArtifactFilename(type: String, mimeType: String?, fallback: String) -> String {
        let base = sanitizeFileName(type.isEmpty ? fallback : type)
        guard (base as NSString).pathExtension.isEmpty,
              let ext = extensionForContentType(mimeType) else {
            return base
        }
        return "\(base).\(ext)"
    }

    private func formatScore(_ score: Double) -> String {
        score.rounded() == score ? String(Int(score)) : String(score)
    }

    private func normalizedAPIBaseURL() -> String {
        normalizeLearningBackendBaseURL(apiBaseURLText)
    }

    private func normalizedTUSBaseURL() -> String {
        normalizeTUSBaseURL(tusBaseURLText)
    }

    private func currentSessionOrError() -> SavedSession? {
        guard let session else {
            setError("auth.error.session_required")
            return nil
        }
        return session
    }

    private func isCurrentWorkspaceContext(_ activeSession: SavedSession, workspaceId: String) -> Bool {
        guard let currentSession = session else { return false }
        return currentSession.userId == activeSession.userId && selectedWorkspaceId == workspaceId
    }

    private func isCurrentSessionContext(_ activeSession: SavedSession) -> Bool {
        session?.userId == activeSession.userId
    }

    private func showError(_ error: Error) {
        if let backendError = error as? LearningBackendError, backendError.shouldClearSession {
            let currentRefreshToken = (settings.loadSession() ?? session)?.refreshToken
            if shouldClearPersistedSession(for: backendError, currentRefreshToken: currentRefreshToken) {
                clearLocalSession()
            }
        } else if let backendError = error as? LearningBackendError, backendError.statusCode == 403 {
            recoverFromWorkspaceAccessDenied()
        }
        if let backendError = error as? LearningBackendError,
           backendError.statusCode != nil,
           backendError.localizationKey == nil,
           !backendError.shouldClearSession {
            setRawError(backendError.message)
        } else {
            errorDisplayText = friendlyDisplayText(error)
        }
        statusDisplayText = .raw("")
    }

    private func handlePostCommitRefreshFailure(_ error: Error, completionKey: String) {
        if shouldStopPostCommitRefresh(for: error) {
            showError(error)
            return
        }
        errorMessage = nil
        setStatus("operation.refresh_failed", localized(completionKey), localized(friendlyError(error)))
    }

    private func shouldStopPostCommitRefresh(for error: Error) -> Bool {
        guard let backendError = error as? LearningBackendError else { return false }
        return backendError.shouldClearSession || backendError.statusCode == 403
    }

    private func recoverFromWorkspaceAccessDenied() {
        invalidateDeferredContentLoads()
        clearAIModelState()
        selectedWorkspaceId = nil
        selectedHomeDestination = nil
        settings.saveSelectedWorkspaceId(nil)
        documents = []
        selectedArtifacts = []
        selectedArtifactDocumentId = nil
        selectedOcrArtifacts = []
        selectedOcrDocumentId = nil
        clearLearningWorkspaceState()
        guard let activeSession = settings.loadSession() ?? session else {
            return
        }
        Task {
            do {
                try await loadWorkspaces(activeSession: activeSession, preferredWorkspaceId: nil)
            } catch {
                workspaces = []
            }
        }
    }

    private func activateOfflineTestMode() {
        presenceTask?.cancel()
        presenceTask = nil
        let onboardingRequired = ProcessInfo.processInfo.arguments.contains("-NotePatchUITestAIOnboardingRequired")
        let uiSession = SavedSession(
            baseURL: normalizeLearningBackendBaseURL(apiBaseURLText),
            tusBaseURL: normalizeTUSBaseURL(tusBaseURLText),
            accessToken: "ui-access",
            refreshToken: "ui-refresh",
            expiresAt: "2099-12-31T23:59:59Z",
            userId: "ui-user",
            email: "uitest",
            fullName: "UI Test",
            selectedWorkspaceId: "ui-workspace",
            aiHistoryEnabled: true,
            autoImageRemarkEnabled: true,
            aiOnboardingVersion: onboardingRequired ? 0 : 1,
            aiOnboardingCompletedAt: onboardingRequired ? nil : "2026-08-22T00:00:00Z",
            aiOnboardingCompleted: !onboardingRequired,
            aiPreferences: .defaults
        )
        let sampleDocuments = [
            LearningDocumentItem(id: "remark-doc", workspaceId: "ui-workspace", title: "Whiteboard", remark: "CPU pipeline diagram", remarkSource: "ai_ocr", originalFilename: "IMG_0001.png", mimeType: "image/png", fileType: "image", documentKind: "note", status: "uploaded", imageRemarkStatus: "running"),
            LearningDocumentItem(id: "homework-doc", workspaceId: "ui-workspace", title: "Algebra Homework", originalFilename: "homework.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "homework", status: "ready"),
            LearningDocumentItem(id: "answer-doc", workspaceId: "ui-workspace", title: "Answer Key", originalFilename: "answer.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "answer_key", status: "ready"),
            LearningDocumentItem(id: "preparing-doc", workspaceId: "ui-workspace", title: "New Worksheet", originalFilename: "worksheet.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "homework", status: "scanning")
        ]
        isOfflineTestMode = true
        didRestoreSession = true
        session = uiSession
        apiBaseURLText = uiSession.baseURL
        tusBaseURLText = uiSession.tusBaseURL
        emailText = "uitest"
        passwordText = ""
        fullNameText = uiSession.fullName ?? ""
        selectedWorkspaceId = uiSession.selectedWorkspaceId
        workspaces = [WorkspaceItem(id: "ui-workspace", name: "My Workspace")]
        let onboarding = AIOnboardingResponse(
            version: 1,
            completed: !onboardingRequired,
            completedAt: onboardingRequired ? nil : "2026-08-22T00:00:00Z",
            answers: .defaults,
            questions: makeUITestAIOnboardingQuestions()
        )
        aiExperienceState.greeting = ChatGreeting(
            assistantName: "NotePatch AI",
            message: "NotePatch AI 可以帮助整理思路、分析学习资料并回答问题，回复支持 Markdown。",
            locale: "zh-CN",
            onboardingRequired: onboardingRequired,
            onboardingVersion: 1,
            questions: onboarding.questions
        )
        aiExperienceState.apply(onboarding, presentIfRequired: onboardingRequired)
        documents = sampleDocuments
        learningUnits = [
            LearningUnit(
                id: "unit-1",
                workspaceId: "ui-workspace",
                title: "Fractions & Ratios",
                subject: "Mathematics",
                gradeLevel: "Grade 7",
                topic: "Ratios",
                knowledgeRevision: 1,
                notesGeneratedRevision: 1
            ),
            LearningUnit(
                id: "unit-2",
                workspaceId: "ui-workspace",
                title: "Linear Equations",
                subject: "Mathematics",
                gradeLevel: "Grade 7",
                topic: "Equations",
                knowledgeRevision: 1,
                notesGeneratedRevision: 1
            )
        ]
        studyNotes = [StudyNoteVersion(
            id: "note-1",
            workspaceId: "ui-workspace",
            learningUnitId: "unit-1",
            versionNo: 1,
            title: "Fractions & Ratios Notes",
            htmlObjectKey: "notes/note-1.html",
            jsonObjectKey: "notes/note-1.json"
        )]
        studyNoteGroups = [
            StudyNoteGroup(
                learningUnit: learningUnits[0],
                notes: [StudyNoteListItem(learningUnit: learningUnits[0], note: studyNotes[0])]
            )
        ]
        let latestGradingResult = GradingResult(
            id: "grading-result-2",
            workspaceId: "ui-workspace",
            homeworkId: "homework-1",
            questionId: nil,
            studentUserId: nil,
            score: 92,
            maxScore: 100,
            gradingMode: "official",
            confidence: 0.94,
            feedback: "Clear reasoning and accurate final answers.",
            createdAt: "2026-08-20T08:30:00Z"
        )
        homeworks = [HomeworkItem(
            id: "homework-1",
            workspaceId: "ui-workspace",
            title: "Algebra Homework 01",
            documentId: "homework-doc",
            rubricText: "10 points per question",
            maxScore: 100,
            latestGradingResult: latestGradingResult
        )]
        homeDashboardState.applySupplementaryContent(
            learningUnits: learningUnits,
            homeworks: homeworks,
            noteGroups: studyNoteGroups
        )
        selectedHomeworkId = "homework-1"
        gradingResults = [
            latestGradingResult,
            GradingResult(
                id: "grading-result-1",
                workspaceId: "ui-workspace",
                homeworkId: "homework-1",
                questionId: nil,
                studentUserId: nil,
                score: 78,
                maxScore: 100,
                gradingMode: "provisional",
                confidence: 0.71,
                feedback: "Add an answer key before using this as an official grade.",
                createdAt: "2026-08-19T08:30:00Z"
            )
        ]
        gradingHistoryWorkspaceId = "ui-workspace"
        gradingHistoryHomeworkId = "homework-1"
        homeworkRubricText = "10 points per question"
        homeworkMaxScoreText = "100"
        gradingDocuments = sampleDocuments
        let sampleDeck = FlashcardDeck(
            id: "deck-1",
            workspaceId: "ui-workspace",
            learningUnitId: "unit-1",
            studyNoteVersionId: "note-1",
            versionNo: 1,
            attemptRevision: 0,
            createdAt: "2026-07-14T00:00:00Z"
        )
        let sampleCards = [
            Flashcard(
                id: "card-1",
                knowledgePointId: "point-1",
                front: "What does a **ratio** compare?",
                back: "The relationship between **two quantities**.",
                priorityScore: 1.8,
                priorityFactors: ["base": .number(1), "error_pressure": .number(0.4), "success_pressure": .number(0.1), "recent_correct_streak": .number(0)],
                reviewHint: FlashcardReviewHint(
                    primary: FlashcardHintItem(
                        code: "frequent_recent_errors",
                        messageKey: "flashcards.hints.frequent_recent_errors",
                        tone: "warning",
                        params: ["count": .number(3), "window_days": .number(30)]
                    ),
                    badges: [
                        FlashcardHintItem(
                            code: "historical_errors",
                            messageKey: "flashcards.badges.historical_errors",
                            tone: "neutral",
                            params: ["count": .number(4)]
                        ),
                        FlashcardHintItem(
                            code: "latest_outcome",
                            messageKey: "flashcards.badges.latest_outcome",
                            tone: "warning",
                            params: ["outcome": .string("incorrect")]
                        )
                    ]
                ),
                rank: 1,
                createdAt: "2026-07-14T00:00:00Z"
            ),
            Flashcard(
                id: "card-2",
                knowledgePointId: "point-2",
                front: "## How do you solve a proportion?",
                back: "1. Set the cross products equal.\n2. Solve for the `unknown`.",
                priorityScore: 1.2,
                priorityFactors: ["base": .number(1), "recent_correct_streak": .number(1)],
                reviewHint: FlashcardReviewHint(
                    primary: FlashcardHintItem(
                        code: "from_notes",
                        messageKey: "flashcards.hints.from_notes",
                        tone: "neutral"
                    ),
                    dataQuality: "legacy"
                ),
                rank: 2,
                createdAt: "2026-07-14T00:00:00Z"
            )
        ]
        selectedFlashcardLearningUnitId = "unit-1"
        flashcardDecks = [sampleDeck]
        selectedFlashcardDeckId = sampleDeck.id
        flashcardDeckDetail = FlashcardDeckDetail(deck: sampleDeck, cards: sampleCards)
        flashcardIndex = 0
        isFlashcardShowingBack = false
        if let workflowDetail = try? JSONDecoder.notepatch.decode(
            WorkflowDetail.self,
            from: Data(#"{"workflow":{"id":"workflow-ui","workspace_id":"ui-workspace","document_id":"preparing-doc","trigger_type":"upload","status":"waiting","core_status":"succeeded","enrichment_status":"waiting","current_stage":"generate_study_notes","progress":76,"waiting_until":"2026-08-22T03:00:00Z","result":{},"metadata":{},"created_at":"","updated_at":""},"tasks":[]}"#.utf8)
        ) {
            workflows = [workflowDetail.workflow]
            activeWorkflowDetail = workflowDetail
        }
        noteGaps = (try? JSONDecoder.notepatch.decode(
            [NoteGap].self,
            from: Data(#"[{"id":"gap-pending","workspace_id":"ui-workspace","learning_unit_id":"unit-1","knowledge_point_id":"Equivalent ratios","status":"pending","coverage_score":0.42,"source_refs":[{"document_id":"homework-doc","page_index":0,"excerpt":"Equivalent ratios use the same multiplier."}],"insert_position":"after","created_at":"","updated_at":""},{"id":"gap-no-base","workspace_id":"ui-workspace","learning_unit_id":"unit-1","knowledge_point_id":"Unit rates","status":"no_base_note","coverage_score":0.0,"source_refs":[],"insert_position":"after","created_at":"","updated_at":""}]"#.utf8)
        )) ?? []
        installOfflineAIModelFixtureIfNeeded()
        conversations = []
        selectedConversationId = nil
        isOpenClawSending = false
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestConversations") {
            conversations = [
                ChatConversation(
                    id: "ui-conv-1",
                    workspaceId: "ui-workspace",
                    title: ProcessInfo.processInfo.arguments.contains("-NotePatchUITestLongConversationTitle")
                        ? "数学作业讲解与本周错题复习计划详细讨论"
                        : "数学作业讲解",
                    lastMessageAt: "2026-08-18T09:30:00Z",
                    createdAt: "2026-08-18T09:00:00Z",
                    updatedAt: "2026-08-18T09:30:00Z"
                ),
                ChatConversation(
                    id: "ui-conv-2",
                    workspaceId: "ui-workspace",
                    title: "英语阅读笔记",
                    lastMessageAt: nil,
                    createdAt: "2026-08-17T14:00:00Z",
                    updatedAt: "2026-08-17T14:00:00Z"
                )
            ]
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestBubbleSizing") {
            openClawMessages = [
                OpenClawChatMessage(
                    id: "ui-sizing-user-short",
                    role: .user,
                    content: "Hi",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                ),
                OpenClawChatMessage(
                    id: "ui-sizing-assistant-short",
                    role: .assistant,
                    content: "OK",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: [],
                    modelId: "openai/gpt-5.6-terra"
                ),
                OpenClawChatMessage(
                    id: "ui-sizing-user-long",
                    role: .user,
                    content: "This is a deliberately long message that should grow from the screen edge toward the opposite side and wrap only after reaching the maximum bubble width.",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                ),
                OpenClawChatMessage(
                    id: "ui-sizing-assistant-long",
                    role: .assistant,
                    content: "A longer assistant response should expand from the leading edge and then wrap naturally when it reaches the same maximum width.",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                )
            ]
        } else if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestReasoningStates") {
            openClawMessages = [
                OpenClawChatMessage(
                    id: "ui-reasoning-present",
                    role: .assistant,
                    content: "包含思考摘要的最终回答。",
                    reasoningContent: "先确认问题，再组织最终答案。",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                ),
                OpenClawChatMessage(
                    id: "ui-reasoning-absent",
                    role: .assistant,
                    content: "没有思考事件也能正常回答。",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: []
                ),
                OpenClawChatMessage(
                    id: "ui-reasoning-unavailable",
                    role: .assistant,
                    content: "模型未提供摘要时的最终回答。",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: [],
                    reasoningUnavailable: true
                )
            ]
        } else if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestFullMarkdown") {
            openClawMessages = [
                OpenClawChatMessage(
                    id: "ui-full-markdown",
                    role: .assistant,
                    content: """
                    # Full Markdown

                    Paragraph with **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`, and [a link](https://example.com).

                    - [x] Completed task
                    - [ ] Pending task

                    > A block quote with **formatting**.

                    | Name | Score | Result |
                    | :--- | ---: | :---: |
                    | Alice | 98 | **Excellent** |
                    | Bob | 87 | Good |

                    ```swift
                    let value = 42
                    print(value)
                    ```

                    ---

                    ###### Final heading
                    """,
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: [],
                    modelId: "openai/gpt-4.1-mini"
                )
            ]
        } else if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestLongChat") {
            let messageCount = ProcessInfo.processInfo.arguments.contains("-NotePatchUITestKeyboardBoundary") ? 12 : 100
            openClawMessages = (0..<messageCount).map { index in
                OpenClawChatMessage(
                    id: "ui-chat-\(index)",
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: index.isMultiple(of: 2)
                        ? "Test prompt \(index)"
                        : "## Test reply \(index)\n\nA cached **Markdown** response with `inline code`.\n\n- First point\n- Second point",
                    status: .done,
                    taskId: nil,
                    progress: nil,
                    events: [],
                    modelId: index.isMultiple(of: 2) ? nil : "openai/gpt-4.1-mini"
                )
            }
        } else {
            openClawMessages = []
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestPurgeFailure") {
            activeTask = TaskItem(
                id: "purge-task",
                workspaceId: "ui-workspace",
                taskType: "purge_document",
                status: "failed",
                resourceType: "document",
                resourceId: "homework-doc",
                payload: .object(["document_id": .string("homework-doc")]),
                errorMessage: "Document purge failed",
                progress: 45
            )
            retryableDocumentPurgeId = "homework-doc"
            isDocumentPurgeRetryAvailable = true
        }
        errorMessage = nil
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("-NotePatchUITestFeedbackSuccess") {
            presentStatus("operation.api_connected")
        } else if !launchArguments.contains(where: { $0.hasPrefix("-NotePatchUITestFeedback") }) {
            setStatus("operation.offline_test_mode")
        } else {
            statusMessage = ""
        }
    }


    private func clearLocalSession() {
        presenceTask?.cancel()
        presenceTask = nil
        stopStudyNoteGenerationPolling()
        invalidateDeferredContentLoads()
        aiPreferenceGeneration = UUID()
        aiPreferenceTask?.cancel()
        aiPreferenceTask = nil
        autoImageRemarkPreferenceGeneration = UUID()
        autoImageRemarkPreferenceTask?.cancel()
        autoImageRemarkPreferenceTask = nil
        documentRemarkUpdateGeneration = UUID()
        documentRemarkUpdateTask?.cancel()
        documentRemarkUpdateTask = nil
        documentRemarkUpdatingId = nil
        stopImageRemarkTracking(clearTrackedDocuments: true)
        uploadImportGeneration = UUID()
        uploadQueueGeneration = UUID()
        learningUnitSelectionGeneration = UUID()
        workspaceContentGeneration = UUID()
        learningContentGeneration = UUID()
        homeworkContentGeneration = UUID()
        studyNoteReaderGeneration = UUID()
        studyNoteSaveGeneration = UUID()
        flashcardLoadGeneration = UUID()
        flashcardLoadTask?.cancel()
        flashcardLoadTask = nil
        profileGeneration = UUID()
        profileLoadTask?.cancel()
        profileLoadTask = nil
        profileSaveTask?.cancel()
        profileSaveTask = nil
        avatarUploadTask?.cancel()
        avatarUploadTask = nil
        pendingProfileUpdate = nil
        pendingAvatarUpload = nil
        userProfileState.clear()
        settings.clearSession()
        DocumentThumbnailPipeline.shared.removeAll()
        isBusy = false
        uploadProgressPercent = nil
        uploadProgressLabel = ""
        cancelLearningUploadFormatConversion()
        isOfflineTestMode = false
        didRestoreSession = false
        session = nil
        selectedWorkspaceId = nil
        workspaces = []
        documents = []
        selectedArtifacts = []
        selectedArtifactDocumentId = nil
        selectedOcrArtifacts = []
        selectedOcrDocumentId = nil
        activeTask = nil
        taskEvents = []
        retryableDocumentPurgeId = nil
        isDocumentPurgeRetryAvailable = false
        clearChatWorkspaceState()
        aiExperienceState.reset()
        isAIPreferenceUpdating = false
        isAutoImageRemarkPreferenceUpdating = false
        notePreferenceTask?.cancel()
        notePreferenceTask = nil
        isNotePreferenceUpdating = false
        clearAIModelState()
        learningUnits = []
        selectedLearningUnitId = nil
        studyNotes = []
        studyNoteGroups = []
        closeStudyNoteReader()
        clearLearningWorkspaceState()
        aiHistoryEnabled = true
        autoImageRemarkEnabled = true
        noteContentEditLevel = .conceptual
        noteLayoutEditLevel = .minor
        noteHistoryLimit = 3
        notePreferenceDraftContent = .conceptual
        notePreferenceDraftLayout = .minor
        notePreferenceDraftHistoryLimit = 3
        passwordText = ""
        queuedUploadItems.forEach {
            UploadThumbnailCache.shared.remove(file: $0.file)
            removeCachedUploadFile($0.file)
        }
        queuedUploadItems = []
    }

    private func removeCachedUploadFile(_ file: LocalUploadFile?) {
        guard let file else {
            return
        }
        let cachePath = cacheDirectory.standardizedFileURL.path
        let filePath = file.url.standardizedFileURL.path
        guard filePath == cachePath || filePath.hasPrefix(cachePath + "/") else {
            return
        }
        try? FileManager.default.removeItem(at: file.url)
    }

    private func discardImportedUploadFiles(_ files: [LocalUploadFile]) {
        for file in files {
            UploadThumbnailCache.shared.remove(file: file)
            removeCachedUploadFile(file)
        }
    }

    private func saveSession(_ updated: SavedSession, synchronizeServerURLFields: Bool = false) {
        if !isOfflineTestMode {
            settings.saveSession(updated)
        }
        session = updated
        if synchronizeServerURLFields {
            apiBaseURLText = updated.baseURL
            tusBaseURLText = updated.tusBaseURL
        }
        emailText = updated.email
        fullNameText = updated.fullName ?? ""
        selectedWorkspaceId = updated.selectedWorkspaceId
        aiHistoryEnabled = updated.aiHistoryEnabled
        autoImageRemarkEnabled = updated.autoImageRemarkEnabled
        noteContentEditLevel = updated.noteContentEditLevel
        noteLayoutEditLevel = updated.noteLayoutEditLevel
        noteHistoryLimit = updated.noteHistoryLimit
        if !isNotePreferenceUpdating {
            notePreferenceDraftContent = updated.noteContentEditLevel
            notePreferenceDraftLayout = updated.noteLayoutEditLevel
            notePreferenceDraftHistoryLimit = updated.noteHistoryLimit
        }
        if !uploadUsesCustomNoteStrategy {
            uploadNoteContentEditLevel = updated.noteContentEditLevel
            uploadNoteLayoutEditLevel = updated.noteLayoutEditLevel
        }
        if !studyNoteGenerationUsesOverride {
            studyNoteGenerationContentLevel = updated.noteContentEditLevel
            studyNoteGenerationLayoutLevel = updated.noteLayoutEditLevel
        }
    }

    private func saveSelectedWorkspace(_ workspaceId: String?) {
        if selectedWorkspaceId != workspaceId {
            stopImageRemarkTracking(clearTrackedDocuments: true)
            documentRemarkUpdateGeneration = UUID()
            documentRemarkUpdateTask?.cancel()
            documentRemarkUpdateTask = nil
            documentRemarkUpdatingId = nil
            invalidateDeferredContentLoads()
            DocumentThumbnailPipeline.shared.removeAll()
            clearAIModelState()
            clearChatWorkspaceState()
            aiExperienceState.reset()
            workflowLoadTask?.cancel()
            workflowMonitorTask?.cancel()
            workflows = []
            activeWorkflowDetail = nil
            workflowEvents = []
            noteGapTask?.cancel()
            noteCorrectionsTask?.cancel()
            noteGaps = []
            selectedNoteGapDetail = nil
            studyNoteCorrections = []
        }
        selectedWorkspaceId = workspaceId
        if !isOfflineTestMode {
            settings.saveSelectedWorkspaceId(workspaceId)
        }
        let latest = settings.loadSession() ?? session
        if let latest {
            saveSession(
                SavedSession(
                    baseURL: latest.baseURL,
                    tusBaseURL: latest.tusBaseURL,
                    accessToken: latest.accessToken,
                    refreshToken: latest.refreshToken,
                    expiresAt: latest.expiresAt,
                    userId: latest.userId,
                    email: latest.email,
                    fullName: latest.fullName,
                    selectedWorkspaceId: workspaceId,
                    aiHistoryEnabled: latest.aiHistoryEnabled,
                    autoImageRemarkEnabled: latest.autoImageRemarkEnabled,
                    noteContentEditLevel: latest.noteContentEditLevel,
                    noteLayoutEditLevel: latest.noteLayoutEditLevel,
                    noteHistoryLimit: latest.noteHistoryLimit,
                    aiOnboardingVersion: latest.aiOnboardingVersion,
                    aiOnboardingCompletedAt: latest.aiOnboardingCompletedAt,
                    aiOnboardingCompleted: latest.aiOnboardingCompleted,
                    aiPreferences: latest.aiPreferences
                )
            )
        }
    }

    private func clientFor(_ activeSession: SavedSession) -> LearningBackendClient {
        LearningBackendClient(
            baseURL: activeSession.baseURL,
            accessToken: activeSession.accessToken,
            refreshToken: activeSession.refreshToken,
            session: backendSession
        ) { [weak self] token, attemptedRefreshToken in
            Task { @MainActor in
                self?.applyRefreshedToken(token, attemptedRefreshToken: attemptedRefreshToken, fallback: activeSession)
            }
        }
    }

    private func applyRefreshedToken(_ token: TokenResponse, attemptedRefreshToken: String, fallback: SavedSession) {
        let current = settings.loadSession() ?? session ?? fallback
        guard current.refreshToken == attemptedRefreshToken else {
            return
        }
        saveSession(current.withTokenResponse(token))
    }

    private func startPresence(activeSession: SavedSession) {
        guard !isOfflineTestMode else { return }
        guard presenceTask?.isCancelled != false else {
            return
        }
        presenceTask = Task { [weak self] in
            var delayBeforeNextHeartbeat: UInt64 = 0
            while !Task.isCancelled {
                if delayBeforeNextHeartbeat > 0 {
                    try? await Task.sleep(nanoseconds: delayBeforeNextHeartbeat)
                }
                guard !Task.isCancelled, let self else {
                    break
                }
                let latestSession = self.settings.loadSession() ?? self.session ?? activeSession
                do {
                    let heartbeat = try await self.clientFor(latestSession).heartbeat(clientId: self.settings.loadPresenceClientId())
                    self.settings.savePresenceClientId(heartbeat.clientId)
                    delayBeforeNextHeartbeat = UInt64(self.presenceDelayMillis(heartbeat.heartbeatIntervalSeconds)) * 1_000_000
                } catch {
                    if Task.isCancelled {
                        break
                    }
                    if !self.isBusy {
                        self.setStatus("chat.presence_retry")
                    }
                    delayBeforeNextHeartbeat = UInt64(self.presenceDelayMillis(defaultPresenceHeartbeatIntervalSeconds)) * 1_000_000
                }
            }
        }
    }

    private func stopPresence(activeSession: SavedSession?, sendOffline: Bool, clearClientId: Bool) {
        guard !isOfflineTestMode else {
            presenceTask?.cancel()
            presenceTask = nil
            return
        }
        presenceTask?.cancel()
        presenceTask = nil
        let clientId = settings.loadPresenceClientId()
        if clearClientId {
            settings.clearPresenceClientId()
        }
        guard sendOffline, let activeSession, let clientId, !clientId.isEmpty else {
            return
        }
        Task {
            try? await LearningBackendClient(
                baseURL: activeSession.baseURL,
                accessToken: activeSession.accessToken,
                refreshToken: activeSession.refreshToken,
                session: backendSession
            ).offline(clientId: clientId)
        }
    }

    private func presenceDelayMillis(_ intervalSeconds: Int) -> Int {
        let seconds = intervalSeconds > 0 ? intervalSeconds : defaultPresenceHeartbeatIntervalSeconds
        return seconds * 1000
    }

    private func beginDeferredLoad(
        _ content: DeferredWorkspaceContent,
        force: Bool,
        allowOfflineNetwork: Bool = false,
        showsGlobalError: Bool = true,
        setLoading: @escaping @MainActor (Bool) -> Void,
        operation: @escaping @MainActor (SavedSession, String, @escaping @MainActor () -> Bool) async throws -> Void
    ) {
        if isOfflineTestMode && !allowOfflineNetwork { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let key = DeferredWorkspaceLoadKey(workspaceId: workspaceId, content: content)
        if !force, loadedDeferredContent.contains(key) || deferredLoadTasks[key] != nil {
            return
        }

        deferredLoadTasks[key]?.cancel()
        let generation = UUID()
        deferredLoadGenerations[key] = generation
        setLoading(true)
        if showsGlobalError {
            errorMessage = nil
        }

        deferredLoadTasks[key] = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            let isCurrent = { @MainActor [weak self] in
                self?.isCurrentDeferredLoad(key, generation: generation, session: activeSession) ?? false
            }
            do {
                try Task.checkCancellation()
                try await operation(activeSession, workspaceId, isCurrent)
                try Task.checkCancellation()
                succeeded = true
            } catch is CancellationError {
                // The workspace or session changed while this request was in flight.
            } catch {
                if showsGlobalError,
                   self.isCurrentDeferredLoad(key, generation: generation, session: activeSession) {
                    self.showError(error)
                }
            }
            self.finishDeferredLoad(
                key,
                generation: generation,
                activeSession: activeSession,
                succeeded: succeeded,
                setLoading: setLoading
            )
        }
    }

    private func isCurrentDeferredLoad(
        _ key: DeferredWorkspaceLoadKey,
        generation: UUID,
        session activeSession: SavedSession
    ) -> Bool {
        deferredLoadGenerations[key] == generation
            && selectedWorkspaceId == key.workspaceId
            && session?.userId == activeSession.userId
    }

    private func finishDeferredLoad(
        _ key: DeferredWorkspaceLoadKey,
        generation: UUID,
        activeSession: SavedSession,
        succeeded: Bool,
        setLoading: @escaping @MainActor (Bool) -> Void
    ) {
        guard isCurrentDeferredLoad(key, generation: generation, session: activeSession) else { return }
        deferredLoadTasks[key] = nil
        if succeeded {
            loadedDeferredContent.insert(key)
        }
        setLoading(false)
    }

    private func invalidateDeferredContentLoads() {
        stopStudyNoteGenerationPolling()
        deferredLoadTasks.values.forEach { $0.cancel() }
        deferredLoadTasks = [:]
        deferredLoadGenerations = [:]
        loadedDeferredContent = []
        isNotesLoading = false
        isChatHistoryLoading = false
        isLearningLoading = false
        isHomeworkLoading = false
    }

    private func loadLearningDashboardContent(
        activeSession: SavedSession,
        workspaceId: String,
        shouldApply: @escaping @MainActor () -> Bool
    ) async throws {
        let client = clientFor(activeSession)
        async let unitsRequest = client.listLearningUnits(workspaceId: workspaceId)
        async let homeworksRequest = client.listHomeworks(workspaceId: workspaceId)
        async let documentsRequest = client.listDocuments(workspaceId: workspaceId, pageSize: 100)
        let (units, loadedHomeworks, loadedDocuments) = try await (unitsRequest, homeworksRequest, documentsRequest)
        guard shouldApply() else { throw CancellationError() }

        learningUnits = units
        homeworks = loadedHomeworks
        gradingDocuments = loadedDocuments
        if selectedLearningSection == .flashcards {
            ensureFlashcardsLoaded()
        }
        guard let selectedHomeworkId else { return }
        guard let selected = loadedHomeworks.first(where: { $0.id == selectedHomeworkId }) else {
            self.selectedHomeworkId = nil
            homeworkReferences = []
            clearGradingHistoryState()
            return
        }
        if !isGradingConfigDirty {
            homeworkRubricText = selected.rubricText ?? ""
            homeworkMaxScoreText = formatScore(selected.maxScore)
        }
        homeworkReferences = try await client.listHomeworkReferences(
            workspaceId: workspaceId,
            homeworkId: selectedHomeworkId
        )
        guard shouldApply() else { throw CancellationError() }
    }

    private func loadNotesOverviewContent(
        activeSession: SavedSession,
        workspaceId: String,
        shouldApply: @escaping @MainActor () -> Bool
    ) async throws {
        let units = try await clientFor(activeSession).listLearningUnits(workspaceId: workspaceId)
        guard shouldApply() else { throw CancellationError() }
        learningUnits = units
        guard !units.isEmpty else {
            studyNoteGroups = []
            stopStudyNoteGenerationPolling()
            return
        }

        let results = await loadStudyNoteGroupsConcurrently(
            activeSession: activeSession,
            workspaceId: workspaceId,
            units: units
        )
        guard shouldApply() else { throw CancellationError() }
        let groups = results.compactMap(\.group)
        studyNoteGroups = groups
        let failedCount = results.filter { $0.error != nil }.count
        if failedCount > 0 {
            setStatus("notes.partial_load", String(groups.count), String(failedCount))
        }
        resumeStudyNoteGenerationPollingIfNeeded()
    }

    private func loadStudyNoteGroupsConcurrently(
        activeSession: SavedSession,
        workspaceId: String,
        units: [LearningUnit]
    ) async -> [(group: StudyNoteGroup?, error: Error?)] {
        let maxConcurrentRequests = 4
        var results = Array<(group: StudyNoteGroup?, error: Error?)>(
            repeating: (nil, nil),
            count: units.count
        )
        await withTaskGroup(of: (Int, StudyNoteGroup?, Error?).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < units.count else { return }
                let index = nextIndex
                let unit = units[index]
                nextIndex += 1
                group.addTask { [weak self] in
                    guard let self else { return (index, nil, CancellationError()) }
                    do {
                        let notes = try await self.clientFor(activeSession)
                            .listStudyNotes(workspaceId: workspaceId, learningUnitId: unit.id)
                            .sorted { $0.versionNo > $1.versionNo }
                            .map { StudyNoteListItem(learningUnit: unit, note: $0) }
                        return (index, StudyNoteGroup(learningUnit: unit, notes: notes), nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for _ in 0..<min(maxConcurrentRequests, units.count) {
                enqueueNext()
            }
            while let (index, loadedGroup, error) = await group.next() {
                results[index] = (loadedGroup, error)
                enqueueNext()
            }
        }
        return results
    }

    private func resumeStudyNoteGenerationPollingIfNeeded() {
        guard isAppActive,
              selectedTab == .notes,
              needsStudyRefreshPolling,
              !isOfflineTestMode,
              session != nil,
              selectedWorkspaceId != nil else {
            stopStudyNoteGenerationPolling()
            return
        }
        guard studyNoteGenerationPollingTask?.isCancelled != false else { return }

        studyNoteGenerationPollingTask = Task { [weak self] in
            var failureCount = 0
            while !Task.isCancelled {
                let delaySeconds: UInt64
                switch failureCount {
                case 0: delaySeconds = 8
                case 1: delaySeconds = 16
                default: delaySeconds = 30
                }
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.isAppActive,
                      self.selectedTab == .notes,
                      let activeSession = self.session,
                      let workspaceId = self.selectedWorkspaceId else { break }

                do {
                    if self.selectedLearningSection == .notes {
                        try await self.loadNotesOverviewContent(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            shouldApply: { [weak self] in
                                self?.selectedWorkspaceId == workspaceId && self?.session != nil
                            }
                        )
                    } else {
                        try await self.refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                        if let targetId = self.activeMergeTargetLearningUnitId,
                           let target = self.learningUnits.first(where: { $0.id == targetId }) {
                            if target.mergeStatus == "completed" {
                                _ = try? await self.refreshStudyNoteGroup(
                                    activeSession: activeSession,
                                    workspaceId: workspaceId,
                                    learningUnit: target
                                )
                                self.activeMergeTargetLearningUnitId = nil
                                self.setStatus("merge.completed")
                                if self.selectedLearningSection == .flashcards {
                                    self.loadFlashcards(learningUnitId: target.id)
                                }
                            } else if target.mergeStatus == "failed" {
                                self.statusMessage = ""
                                if self.errorMessage == nil {
                                    self.setError("merge.status.failed")
                                }
                            }
                        }
                    }
                    failureCount = 0
                    if !self.needsStudyRefreshPolling {
                        break
                    }
                } catch is CancellationError {
                    break
                } catch {
                    failureCount += 1
                }
            }
            self?.studyNoteGenerationPollingTask = nil
        }
    }

    private var needsStudyRefreshPolling: Bool {
        if selectedLearningSection == .notes {
            return studyNoteGroups.contains(where: { $0.generationState == .generating })
        }
        return learningUnits.contains(where: { ["merging", "rebuilding"].contains($0.mergeStatus ?? "") })
    }

    private func stopStudyNoteGenerationPolling() {
        studyNoteGenerationPollingTask?.cancel()
        studyNoteGenerationPollingTask = nil
    }

    private func refreshWorkspaceContent(activeSession: SavedSession, workspaceId: String) async throws {
        let generation = UUID()
        workspaceContentGeneration = generation
        let requestedStatus = statusFilter.nilIfBlank
        let requestedDocumentKind = documentKindFilter.nilIfBlank
        let requestedFileType = fileTypeFilter.nilIfBlank
        let loadedDocuments = try await clientFor(activeSession).listDocuments(
            workspaceId: workspaceId,
            status: requestedStatus,
            documentKind: requestedDocumentKind,
            fileType: requestedFileType
        )
        guard workspaceContentGeneration == generation,
              isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
              statusFilter.nilIfBlank == requestedStatus,
              documentKindFilter.nilIfBlank == requestedDocumentKind,
              fileTypeFilter.nilIfBlank == requestedFileType else {
            throw CancellationError()
        }
        documents = loadedDocuments
        if let selectedArtifactDocumentId,
           !documents.contains(where: { $0.id == selectedArtifactDocumentId }) {
            self.selectedArtifactDocumentId = nil
            selectedArtifacts = []
        }
        if let selectedOcrDocumentId,
           !documents.contains(where: { $0.id == selectedOcrDocumentId }) {
            self.selectedOcrDocumentId = nil
            selectedOcrArtifacts = []
        }
    }

    private func reconcileImageRemarkTracking(with loadedDocuments: [LearningDocumentItem]) {
        guard !isOfflineTestMode else { return }
        for document in loadedDocuments where document.fileType == "image" {
            if document.isImageRemarkActive {
                trackedImageRemarkDocumentIds.insert(document.id)
            } else {
                trackedImageRemarkDocumentIds.remove(document.id)
            }
        }
        startImageRemarkTrackingIfNeeded()
    }

    private func trackImageRemarkIfNeeded(_ document: LearningDocumentItem) {
        guard document.fileType == "image", document.isImageRemarkActive else {
            trackedImageRemarkDocumentIds.remove(document.id)
            return
        }
        trackedImageRemarkDocumentIds.insert(document.id)
        startImageRemarkTrackingIfNeeded()
    }

    private func applyUpdatedDocument(_ document: LearningDocumentItem) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            guard documents[index] != document else {
                trackImageRemarkIfNeeded(document)
                return
            }
            documents[index] = document
        }
        trackImageRemarkIfNeeded(document)
    }

    private func startImageRemarkTrackingIfNeeded() {
        guard isAppActive,
              !isOfflineTestMode,
              imageRemarkTrackingTask == nil,
              !trackedImageRemarkDocumentIds.isEmpty,
              let activeSession = session,
              let workspaceId = selectedWorkspaceId else { return }
        let generation = UUID()
        imageRemarkTrackingGeneration = generation
        imageRemarkTrackingTask = Task {
            defer {
                if imageRemarkTrackingGeneration == generation {
                    imageRemarkTrackingTask = nil
                }
            }
            var retryDelay: UInt64 = 3
            while imageRemarkTrackingGeneration == generation,
                  isAppActive,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                  !trackedImageRemarkDocumentIds.isEmpty {
                do {
                    try await Task.sleep(nanoseconds: retryDelay * imageRemarkSecondNanoseconds)
                    try Task.checkCancellation()
                    let ids = Array(trackedImageRemarkDocumentIds)
                    let results = await loadImageRemarkDocumentsConcurrently(
                        activeSession: session ?? activeSession,
                        workspaceId: workspaceId,
                        documentIds: ids
                    )
                    guard imageRemarkTrackingGeneration == generation,
                          isAppActive,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    var successfulCount = 0
                    var firstError: Error?
                    for result in results {
                        if let document = result.document {
                            successfulCount += 1
                            applyUpdatedDocument(document)
                        } else if firstError == nil {
                            firstError = result.error
                        }
                    }
                    if firstError == nil && successfulCount > 0 {
                        retryDelay = 3
                    } else {
                        retryDelay = min(30, retryDelay == 3 ? 5 : retryDelay * 2)
                    }
                    if let backendError = firstError as? LearningBackendError,
                       backendError.shouldClearSession || backendError.statusCode == 403 {
                        showError(backendError)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    retryDelay = min(30, retryDelay == 3 ? 5 : retryDelay * 2)
                }
            }
        }
    }

    private func stopImageRemarkTracking(clearTrackedDocuments: Bool) {
        imageRemarkTrackingGeneration = UUID()
        imageRemarkTrackingTask?.cancel()
        imageRemarkTrackingTask = nil
        if clearTrackedDocuments {
            trackedImageRemarkDocumentIds = []
        }
    }

    private func loadImageRemarkDocumentsConcurrently(
        activeSession: SavedSession,
        workspaceId: String,
        documentIds: [String]
    ) async -> [(document: LearningDocumentItem?, error: Error?)] {
        let maxConcurrentRequests = 4
        var results = Array<(document: LearningDocumentItem?, error: Error?)>(
            repeating: (nil, nil),
            count: documentIds.count
        )
        await withTaskGroup(of: (Int, LearningDocumentItem?, Error?).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < documentIds.count else { return }
                let index = nextIndex
                let documentId = documentIds[index]
                nextIndex += 1
                group.addTask { [weak self] in
                    guard let self else { return (index, nil, CancellationError()) }
                    do {
                        let document = try await self.clientFor(activeSession).getDocument(
                            workspaceId: workspaceId,
                            documentId: documentId
                        )
                        return (index, document, nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for _ in 0..<min(maxConcurrentRequests, documentIds.count) {
                enqueueNext()
            }
            while let (index, document, error) = await group.next() {
                results[index] = (document, error)
                enqueueNext()
            }
        }
        return results
    }

    private func refreshAfterDocumentDeletion(activeSession: SavedSession, workspaceId: String) async -> Error? {
        var firstError: Error?

        do {
            try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
        } catch {
            firstError = error
            if shouldStopPostCommitRefresh(for: error) { return error }
        }

        do {
            try await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
        } catch {
            if firstError == nil { firstError = error }
            if shouldStopPostCommitRefresh(for: error) { return error }
        }

        do {
            try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId, preserveGradingDrafts: true)
        } catch {
            if firstError == nil { firstError = error }
        }

        return firstError
    }

    private func loadWorkspaces(activeSession: SavedSession, preferredWorkspaceId: String?) async throws {
        let client = clientFor(activeSession)
        let user = try await client.me()
        guard isCurrentSessionContext(activeSession) else { throw CancellationError() }
        if user.email != activeSession.email
            || user.fullName != activeSession.fullName
            || user.aiHistoryEnabled != activeSession.aiHistoryEnabled
            || user.autoImageRemarkEnabled != activeSession.autoImageRemarkEnabled
            || user.noteContentEditLevel != activeSession.noteContentEditLevel
            || user.noteLayoutEditLevel != activeSession.noteLayoutEditLevel
            || user.noteHistoryLimit != activeSession.noteHistoryLimit
            || user.aiOnboardingVersion != activeSession.aiOnboardingVersion
            || user.aiOnboardingCompletedAt != activeSession.aiOnboardingCompletedAt
            || user.aiOnboardingCompleted != activeSession.aiOnboardingCompleted
            || user.aiPreferences != activeSession.aiPreferences {
            guard let currentSession = session, currentSession.userId == activeSession.userId else {
                throw CancellationError()
            }
            saveSession(currentSession.withUser(user))
        }

        var loadedWorkspaces = try await client.listWorkspaces()
        if loadedWorkspaces.isEmpty {
            do {
                loadedWorkspaces = [try await client.createWorkspace(name: defaultPersonalWorkspaceName)]
            } catch let error as LearningBackendError where error.statusCode == 409 {
                loadedWorkspaces = try await client.listWorkspaces()
            }
        }
        guard isCurrentSessionContext(activeSession) else { throw CancellationError() }
        let personalWorkspaces = loadedWorkspaces.filter { $0.type == "personal" }
        let selectableWorkspaces = personalWorkspaces.isEmpty ? loadedWorkspaces : personalWorkspaces
        workspaces = selectableWorkspaces
        let selected = selectableWorkspaces.first(where: { $0.id == preferredWorkspaceId })
            ?? selectableWorkspaces.first(where: { $0.id == activeSession.selectedWorkspaceId })
            ?? selectableWorkspaces.first

        saveSelectedWorkspace(selected?.id)
        if let selected {
            try await refreshWorkspaceContent(activeSession: session ?? activeSession, workspaceId: selected.id)
            setStatus("workspace.loaded", selected.name)
            ensureContentForSelectedTabLoaded()
        } else {
            documents = []
            setStatus("workspace.recovery_needed")
        }
    }

    private func pollTask(
        activeSession: SavedSession,
        workspaceId: String,
        taskId: String,
        initialTask: TaskItem? = nil,
        onUpdate: @escaping (TaskItem, [TaskEventItem]) -> Void
    ) async throws -> TaskItem {
        let client = clientFor(activeSession)
        var currentTask: TaskItem
        if let initialTask, initialTask.id == taskId {
            currentTask = initialTask
        } else if activeTask?.id == taskId, let activeTask {
            currentTask = activeTask
        } else {
            currentTask = try await client.getTask(workspaceId: workspaceId, taskId: taskId)
        }
        var events = taskEvents.filter { $0.taskId == taskId }
        var seenEventIds = Set(events.map(\.id))
        var seenSequences = Set(events.map(\.sequenceNo).filter { $0 > 0 })
        var lastSequenceNo = events.map(\.sequenceNo).max()
        var lastPublishedTask: TaskItem?
        var lastPublishedEvents: [TaskEventItem]?

        func publishIfChanged() {
            guard currentTask != lastPublishedTask || events != lastPublishedEvents else { return }
            onUpdate(currentTask, events)
            lastPublishedTask = currentTask
            lastPublishedEvents = events
        }

        func appendEvent(_ event: TaskEventItem) {
            guard !seenEventIds.contains(event.id),
                  event.sequenceNo <= 0 || !seenSequences.contains(event.sequenceNo) else { return }
            seenEventIds.insert(event.id)
            if event.sequenceNo > 0 {
                seenSequences.insert(event.sequenceNo)
                lastSequenceNo = max(lastSequenceNo ?? 0, event.sequenceNo)
            }
            events.append(event)
            events.sort {
                if $0.sequenceNo != $1.sequenceNo { return $0.sequenceNo < $1.sequenceNo }
                return $0.createdAt < $1.createdAt
            }
            currentTask = currentTask.applyingLiveEvent(event)
            publishIfChanged()
        }

        publishIfChanged()
        if currentTask.isTerminal {
            if let authoritativeEvents = try? await client.getTaskEvents(workspaceId: workspaceId, taskId: taskId) {
                authoritativeEvents.forEach(appendEvent)
            }
            publishIfChanged()
            return try terminalTaskResult(currentTask, events: events)
        }

        if taskEventStreamingEnabled {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                do {
                    var receivedDone = false
                    for try await frame in client.streamTaskEvents(
                        workspaceId: workspaceId,
                        taskId: taskId,
                        lastEventID: lastSequenceNo
                    ) {
                        try Task.checkCancellation()
                        switch frame {
                        case .taskEvent(let event):
                            appendEvent(event)
                        case .done:
                            receivedDone = true
                        }
                        if receivedDone { break }
                    }
                    if receivedDone {
                        currentTask = try await client.getTask(workspaceId: workspaceId, taskId: taskId)
                        if let authoritativeEvents = try? await client.getTaskEvents(workspaceId: workspaceId, taskId: taskId) {
                            authoritativeEvents.forEach(appendEvent)
                        }
                        publishIfChanged()
                        if currentTask.isTerminal {
                            break
                        }
                        break
                    }
                    throw LearningBackendError(localizedKey: "error.task.stream_disconnected")
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LearningBackendError
                    where [404, 405, 406].contains(error.statusCode ?? 0) {
                    break
                } catch let error as LearningBackendError
                    where error.shouldClearSession || [401, 403, 422].contains(error.statusCode ?? 0) {
                    throw error
                } catch {
                    guard attempt < 2 else { break }
                    let reconnectDelay = UInt64(attempt + 1)
                    try await Task.sleep(nanoseconds: reconnectDelay * 1_000_000_000)
                }
            }
            if currentTask.isTerminal {
                return try terminalTaskResult(currentTask, events: events)
            }
        }

        var failureCount = 0
        while true {
            try Task.checkCancellation()
            var reachedTerminal = false
            do {
                currentTask = try await client.getTask(workspaceId: workspaceId, taskId: taskId)
                if let refreshedEvents = try? await client.getTaskEvents(workspaceId: workspaceId, taskId: taskId) {
                    refreshedEvents.forEach(appendEvent)
                }
                publishIfChanged()
                failureCount = 0
                reachedTerminal = currentTask.isTerminal
                if !reachedTerminal {
                    try await Task.sleep(nanoseconds: taskPollIntervalNanoseconds)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LearningBackendError
                where error.shouldClearSession || [400, 401, 403, 404, 409, 422].contains(error.statusCode ?? 0) {
                throw error
            } catch {
                failureCount += 1
                let delaySeconds = min(15, 1 << min(failureCount, 4))
                try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
            if reachedTerminal {
                return try terminalTaskResult(currentTask, events: events)
            }
        }
    }

    private func terminalTaskResult(_ task: TaskItem, events: [TaskEventItem]) throws -> TaskItem {
        switch task.status {
        case "succeeded":
            return task
        case "failed":
            if let message = task.errorMessage ?? events.last(where: { $0.level == "error" })?.message {
                throw LearningBackendError(message)
            }
            throw LearningBackendError(localizedKey: "error.task.failed")
        case "cancelled":
            if let message = events.last(where: { $0.eventType.contains("cancel") })?.message
                ?? events.last(where: { $0.level == "error" })?.message
                ?? events.last?.message
                ?? task.errorMessage {
                throw LearningBackendError(message)
            }
            throw LearningBackendError(localizedKey: "task.cancelled_fallback")
        default:
            throw LearningBackendError(localizedKey: "error.task.stream_incomplete")
        }
    }

    private func completeUploadWithRetry(
        client: LearningBackendClient,
        workspaceId: String,
        uploadSessionId: String,
        documentId: String?,
        tusResult: TusUploadResult,
        file: LocalUploadFile
    ) async throws -> LearningDocumentItem {
        var lastConflict: LearningBackendError?
        for attempt in 0..<completeUploadMaxRetries {
            try Task.checkCancellation()
            do {
                return try await client.completeUpload(
                    workspaceId: workspaceId,
                    uploadSessionId: uploadSessionId,
                    tusUploadURL: tusResult.uploadURL,
                    tusUploadId: tusResult.uploadId,
                    fileSize: file.fileSize,
                    mimeType: file.mimeType ?? "application/octet-stream"
                )
            } catch let error as LearningBackendError where error.statusCode == 409 {
                lastConflict = error
                if let documentId, let document = try? await client.getDocument(
                    workspaceId: workspaceId,
                    documentId: documentId
                ), ["uploaded", "processing", "ready", "scanning"].contains(document.status) {
                    return document
                }
                setStatus("upload.tusd_sync_retry", String(attempt + 1), String(completeUploadMaxRetries))
                let delaySeconds = min(3, 1 + attempt / 5)
                try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
        }
        throw lastConflict ?? LearningBackendError(localizedKey: "error.upload.confirmation_failed")
    }

    private func allocateOpenClawMessageId() -> String {
        let id = nextOpenClawMessageId
        nextOpenClawMessageId += 1
        return "local-\(id)"
    }

    private func updateOpenClawMessage(_ messageId: String, transform: (inout OpenClawChatMessage) -> Void) {
        openClawState.updateMessage(id: messageId, transform: transform)
    }

    private func refreshConversations(
        activeSession: SavedSession,
        workspaceId: String,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async throws {
        let response = try await clientFor(activeSession).listConversations(workspaceId: workspaceId)
        guard shouldApply() else { throw CancellationError() }
        conversations = response.items
        if let selectedConversationId, conversations.contains(where: { $0.id == selectedConversationId }) {
            return
        }
        selectedConversationId = conversations.first?.id
    }

    private func refreshConversationMessages(
        activeSession: SavedSession,
        workspaceId: String,
        conversationId: String,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async throws {
        let response = try await clientFor(activeSession).listChatMessages(workspaceId: workspaceId, conversationId: conversationId)
        guard shouldApply() else { throw CancellationError() }
        var serverAttachmentsByMessageId: [String: [ChatMessageAttachment]] = [:]
        let messages = response.items.map { chatMessage -> OpenClawChatMessage in
            let role: OpenClawChatRole
            switch chatMessage.role {
            case "user": role = .user
            case "system": role = .system
            default: role = .assistant
            }
            let status: OpenClawMessageStatus = chatMessage.status == "failed" ? .error : (chatMessage.status == "queued" || chatMessage.status == "running" ? .sending : .done)
            let content: String
            if status == .sending { content = chatMessage.content.isEmpty ? "Thinking..." : chatMessage.content }
            else if status == .error { content = chatMessage.errorMessage ?? chatMessage.content }
            else { content = chatMessage.content }
            let serverAttachments = chatMessage.attachments ?? []
            if !serverAttachments.isEmpty {
                serverAttachmentsByMessageId[chatMessage.id] = serverAttachments
            }
            let restoredAttachments = restoreChatAttachments(
                serverAttachments,
                messageId: chatMessage.id,
                workspaceId: workspaceId
            )
            return OpenClawChatMessage(
                id: chatMessage.id,
                role: role,
                content: content,
                status: status,
                taskId: chatMessage.taskId,
                progress: nil,
                events: [],
                citations: chatMessage.citations ?? [],
                sourceStatus: chatMessage.sourceStatus,
                modelId: chatMessage.modelId,
                attachments: restoredAttachments
            )
        }
        openClawMessages = messages
        try await hydrateChatAttachments(
            serverAttachmentsByMessageId,
            activeSession: activeSession,
            workspaceId: workspaceId,
            shouldApply: shouldApply
        )
    }

    private func restoreChatAttachments(
        _ serverAttachments: [ChatMessageAttachment],
        messageId: String,
        workspaceId: String
    ) -> [OpenClawChatAttachment] {
        let validAttachments = serverAttachments.filter { !$0.documentId.isEmpty }
        guard !validAttachments.isEmpty else {
            return chatAttachmentsByMessageId[messageId] ?? []
        }
        let existing = chatAttachmentsByMessageId[messageId] ?? []
        let restored = validAttachments.map { attachment -> OpenClawChatAttachment in
            if let local = existing.first(where: { $0.documentId == attachment.documentId }),
               FileManager.default.fileExists(atPath: local.file.url.path) {
                var ready = local
                ready.status = .ready
                return ready
            }
            let file = localChatAttachmentFile(attachment, workspaceId: workspaceId)
            let fileExists = FileManager.default.fileExists(atPath: file.url.path)
            let shouldDownload = attachment.isImage && attachment.availability != "unavailable"
            return OpenClawChatAttachment(
                file: file,
                documentId: attachment.documentId,
                status: fileExists ? .ready : (shouldDownload ? .uploading : .unavailable)
            )
        }
        chatAttachmentsByMessageId[messageId] = restored
        return restored
    }

    private func hydrateChatAttachments(
        _ attachmentsByMessageId: [String: [ChatMessageAttachment]],
        activeSession: SavedSession,
        workspaceId: String,
        shouldApply: @escaping @MainActor () -> Bool
    ) async throws {
        guard !attachmentsByMessageId.isEmpty else { return }
        let client = clientFor(activeSession)
        for (messageId, attachments) in attachmentsByMessageId {
            for attachment in attachments where !attachment.documentId.isEmpty && attachment.isImage && attachment.availability != "unavailable" {
                try Task.checkCancellation()
                guard shouldApply() else { throw CancellationError() }
                let file = localChatAttachmentFile(attachment, workspaceId: workspaceId)
                if FileManager.default.fileExists(atPath: file.url.path) {
                    updateRestoredChatAttachment(messageId: messageId, documentId: attachment.documentId, file: file, status: .ready)
                    continue
                }
                do {
                    let response = try await client.getDownloadURL(
                        workspaceId: workspaceId,
                        documentId: attachment.documentId
                    )
                    let downloadedURL = try await client.download(
                        downloadURL: response.downloadURL,
                        targetURL: file.url
                    )
                    guard shouldApply() else { throw CancellationError() }
                    let downloadedFile = LocalUploadFile(
                        id: file.id,
                        url: downloadedURL,
                        filename: file.filename,
                        mimeType: file.mimeType
                    )
                    updateRestoredChatAttachment(
                        messageId: messageId,
                        documentId: attachment.documentId,
                        file: downloadedFile,
                        status: .ready
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard shouldApply() else { throw CancellationError() }
                    updateRestoredChatAttachment(
                        messageId: messageId,
                        documentId: attachment.documentId,
                        file: file,
                        status: .unavailable
                    )
                }
            }
        }
    }

    private func localChatAttachmentFile(
        _ attachment: ChatMessageAttachment,
        workspaceId: String
    ) -> LocalUploadFile {
        let filename = sanitizeFileName(
            attachment.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (attachment.title ?? attachment.documentId)
                : attachment.filename
        )
        let directory = cacheDirectory
            .appendingPathComponent("chat-attachments", isDirectory: true)
            .appendingPathComponent(sanitizeFileName(workspaceId), isDirectory: true)
            .appendingPathComponent(sanitizeFileName(attachment.documentId), isDirectory: true)
        return LocalUploadFile(
            id: UUID(uuidString: attachment.documentId) ?? UUID(),
            url: directory.appendingPathComponent(filename),
            filename: filename,
            mimeType: attachment.mimeType ?? contentTypeForFilename(filename)
        )
    }

    private func updateRestoredChatAttachment(
        messageId: String,
        documentId: String,
        file: LocalUploadFile,
        status: OpenClawAttachmentStatus
    ) {
        var attachments = chatAttachmentsByMessageId[messageId] ?? []
        guard let index = attachments.firstIndex(where: { $0.documentId == documentId }) else { return }
        attachments[index] = OpenClawChatAttachment(file: file, documentId: documentId, status: status)
        chatAttachmentsByMessageId[messageId] = attachments
        updateOpenClawMessage(messageId) { message in
            message.attachments = attachments
        }
    }

    private func installOfflineAIModelFixtureIfNeeded() {
        guard aiModelCatalog == nil else { return }
        let items = [
            AiModel(
                id: "openai/gpt-4.1-mini",
                upstreamId: "gpt-4.1-mini",
                ownedBy: "openai",
                created: nil
            ),
            AiModel(
                id: "openai/gpt-4.1",
                upstreamId: "gpt-4.1",
                ownedBy: "openai",
                created: nil
            )
        ]
        aiModelCatalog = AiModelCatalog(
            provider: "openai",
            defaultModel: items[0].id,
            selectedModel: items[0].id,
            items: items,
            fetchedAt: "2026-07-28T00:00:00Z",
            stale: true
        )
        selectedAIModelId = nil
        aiModelCatalogWorkspaceId = selectedWorkspaceId
        aiModelsErrorText = nil
    }

    private func clearAIModelState() {
        aiModelLoadGeneration = UUID()
        aiModelLoadTask?.cancel()
        aiModelLoadTask = nil
        aiModelSelectionGeneration = UUID()
        aiModelSelectionTask?.cancel()
        aiModelSelectionTask = nil
        aiModelCatalogWorkspaceId = nil
        aiModelCatalog = nil
        selectedAIModelId = nil
        isAIModelsLoading = false
        isAIModelUpdating = false
        aiModelsErrorText = nil
    }

    private func refreshLearningUnits(activeSession: SavedSession, workspaceId: String) async throws {
        let generation = UUID()
        learningContentGeneration = generation
        let loadedUnits = try await clientFor(activeSession).listLearningUnits(workspaceId: workspaceId)
        guard learningContentGeneration == generation,
              isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
            throw CancellationError()
        }
        let requestedUnitId = selectedLearningUnitId
        var loadedNotes: [StudyNoteVersion] = []
        if let requestedUnitId, loadedUnits.contains(where: { $0.id == requestedUnitId }) {
            loadedNotes = try await clientFor(activeSession).listStudyNotes(
                workspaceId: workspaceId,
                learningUnitId: requestedUnitId
            )
            guard learningContentGeneration == generation,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                  selectedLearningUnitId == requestedUnitId else {
                throw CancellationError()
            }
        }
        learningUnits = loadedUnits
        if requestedUnitId != nil, !loadedUnits.contains(where: { $0.id == requestedUnitId }) {
            self.selectedLearningUnitId = nil
            studyNotes = []
        } else if requestedUnitId != nil {
            studyNotes = loadedNotes
        }
    }

    private func refreshStudyNoteGroup(
        activeSession: SavedSession,
        workspaceId: String,
        learningUnit: LearningUnit
    ) async throws -> [StudyNoteListItem] {
        let notes = try await clientFor(activeSession)
            .listStudyNotes(workspaceId: workspaceId, learningUnitId: learningUnit.id)
            .sorted { $0.versionNo > $1.versionNo }
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
            throw CancellationError()
        }
        let items = notes.map { StudyNoteListItem(learningUnit: learningUnit, note: $0) }
        let group = StudyNoteGroup(learningUnit: learningUnit, notes: items)
        if let index = studyNoteGroups.firstIndex(where: { $0.learningUnit.id == learningUnit.id }) {
            studyNoteGroups[index] = group
        } else {
            studyNoteGroups.append(group)
        }
        if selectedLearningUnitId == learningUnit.id {
            studyNotes = notes
        }
        return items
    }

    private func loadStudyNoteReader(
        activeSession: SavedSession,
        workspaceId: String,
        learningUnitId: String,
        note: StudyNoteVersion
    ) async throws {
        let client = clientFor(activeSession)
        if let embedded = note.renderedHTMLDownloadURL, !embedded.isEmpty {
            studyNoteRenderedURL = try client.resolveServiceURL(embedded)
            studyNoteHTML = nil
            return
        }

        do {
            let response = try await client.getStudyNoteDownloadURL(
                workspaceId: workspaceId,
                learningUnitId: learningUnitId,
                noteVersionId: note.id,
                kind: .renderedHTML
            )
            studyNoteRenderedURL = try client.resolveServiceURL(response.downloadURL)
            studyNoteHTML = nil
        } catch let error as LearningBackendError where [404, 422].contains(error.statusCode ?? 0) {
            studyNoteRenderedURL = nil
            studyNoteHTML = try await loadStudyNoteHTML(
                activeSession: activeSession,
                workspaceId: workspaceId,
                learningUnitId: learningUnitId,
                note: note,
                prefersHighlighted: true
            )
        }
    }

    private func refreshRenderedStudyNoteAfterRevision(
        activeSession: SavedSession,
        workspaceId: String,
        item: StudyNoteListItem,
        fallbackHTML: String
    ) async {
        studyNoteHTML = fallbackHTML
        studyNoteRenderedURL = nil
        do {
            let client = clientFor(activeSession)
            let response = try await client.getStudyNoteDownloadURL(
                workspaceId: workspaceId,
                learningUnitId: item.learningUnit.id,
                noteVersionId: item.note.id,
                kind: .renderedHTML
            )
            guard selectedStudyNoteItem?.id == item.id else { return }
            studyNoteRenderedURL = try client.resolveServiceURL(response.downloadURL)
            studyNoteHTML = nil
        } catch {
            guard selectedStudyNoteItem?.id == item.id else { return }
            studyNoteHTML = fallbackHTML
            studyNoteRenderedURL = nil
        }
    }

    func handleRenderedStudyNoteExpired() {
        guard !renderedStudyNoteRefreshAttempted,
              let item = selectedStudyNoteItem,
              let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId else {
            studyNoteReaderErrorText = .localized("note.reader.signed_url_expired")
            studyNoteRenderedURL = nil
            return
        }
        renderedStudyNoteRefreshAttempted = true
        isStudyNoteLoading = true
        Task {
            defer { isStudyNoteLoading = false }
            do {
                let response = try await clientFor(activeSession).getStudyNoteDownloadURL(
                    workspaceId: workspaceId,
                    learningUnitId: item.learningUnit.id,
                    noteVersionId: item.note.id,
                    kind: .renderedHTML
                )
                guard selectedStudyNoteItem?.id == item.id else { return }
                studyNoteRenderedURL = try clientFor(activeSession).resolveServiceURL(response.downloadURL)
                studyNoteReaderErrorText = nil
            } catch {
                guard selectedStudyNoteItem?.id == item.id else { return }
                studyNoteRenderedURL = nil
                studyNoteReaderErrorText = friendlyDisplayText(error)
            }
        }
    }

    func handleRenderedStudyNoteFailure(_ message: String) {
        guard selectedStudyNoteItem != nil else { return }
        studyNoteRenderedURL = nil
        studyNoteReaderErrorText = .raw(message)
    }

    private func loadStudyNoteHTML(
        activeSession: SavedSession,
        workspaceId: String,
        learningUnitId: String,
        note: StudyNoteVersion,
        prefersHighlighted: Bool
    ) async throws -> String {
        let client = clientFor(activeSession)
        let hasHighlightedHTML = note.highlightedHTMLObjectKey != nil
            || note.downloadURLs["highlighted_html"] != nil
            || note.downloadURLs["highlighted"] != nil
        let preferredKind: StudyNoteDownloadKind = prefersHighlighted && hasHighlightedHTML
            ? .highlightedHTML
            : .html
        let embeddedURL: String? = {
            if preferredKind == .highlightedHTML {
                return note.downloadURLs["highlighted_html"] ?? note.downloadURLs["highlighted"]
            }
            return note.downloadURLs["html"] ?? note.downloadURLs["markdown"]
        }()
        let filename = "\(note.id)-\(sanitizeFileName(note.title.isEmpty ? "study-note" : note.title)).html"
        let targetURL = cacheDirectory
            .appendingPathComponent("study-notes", isDirectory: true)
            .appendingPathComponent(filename)

        if let embeddedURL, !embeddedURL.isEmpty {
            do {
                let downloadedURL = try await client.download(downloadURL: embeddedURL, targetURL: targetURL)
                return try await FileImportService.shared.readUTF8File(at: downloadedURL)
            } catch {
                // Signed URLs are short-lived. Refresh once through the authenticated endpoint.
            }
        }

        let response: StudyNoteDownloadURLResponse
        do {
            response = try await client.getStudyNoteDownloadURL(
                workspaceId: workspaceId,
                learningUnitId: learningUnitId,
                noteVersionId: note.id,
                kind: preferredKind
            )
        } catch let error as LearningBackendError where preferredKind == .highlightedHTML && error.statusCode == 404 {
            response = try await client.getStudyNoteDownloadURL(
                workspaceId: workspaceId,
                learningUnitId: learningUnitId,
                noteVersionId: note.id,
                kind: .html
            )
        }
        let downloadedURL = try await client.download(downloadURL: response.downloadURL, targetURL: targetURL)
        return try await FileImportService.shared.readUTF8File(at: downloadedURL)
    }

    private func handleStudyNoteRevisionConflict(
        activeSession: SavedSession,
        workspaceId: String,
        learningUnit: LearningUnit,
        originalError: LearningBackendError,
        afterConflictConfirmation: Bool
    ) async {
        do {
            let refreshedItems = try await refreshStudyNoteGroup(
                activeSession: activeSession,
                workspaceId: workspaceId,
                learningUnit: learningUnit
            )
            guard let latest = refreshedItems.first else {
                throw LearningBackendError(localizedKey: "note.error.no_server_versions")
            }
            selectedStudyNoteItem = latest
            do {
                studyNoteHTML = try await loadStudyNoteHTML(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    learningUnitId: learningUnit.id,
                    note: latest.note,
                    prefersHighlighted: true
                )
            } catch {
                studyNoteReaderErrorText = friendlyDisplayText(error)
            }
            studyNoteEditorErrorText = .localized(
                afterConflictConfirmation
                    ? "note.error.conflict_during_save"
                    : "note.error.conflict_available"
            )
            isStudyNoteConflictPending = true
        } catch {
            studyNoteEditorErrorText = .localized("note.error.conflict_refresh_failed_generic")
            if let backendError = error as? LearningBackendError,
               backendError.shouldClearSession || backendError.statusCode == 403 {
                showError(error)
            }
        }
        _ = originalError
    }

    private func refreshHomeworks(
        activeSession: SavedSession,
        workspaceId: String,
        preserveGradingDrafts: Bool = false
    ) async throws {
        let generation = UUID()
        homeworkContentGeneration = generation
        let shouldPreserveDrafts = preserveGradingDrafts && isGradingConfigDirty
        let client = clientFor(activeSession)
        async let homeworksRequest = client.listHomeworks(workspaceId: workspaceId)
        async let documentsRequest = client.listDocuments(workspaceId: workspaceId, pageSize: 100)
        let loadedHomeworks = try await homeworksRequest
        let loadedDocuments = try await documentsRequest
        guard homeworkContentGeneration == generation,
              isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
            throw CancellationError()
        }

        let requestedHomeworkId = selectedHomeworkId
        var loadedReferences: [HomeworkReferenceItem] = []
        if let requestedHomeworkId, loadedHomeworks.contains(where: { $0.id == requestedHomeworkId }) {
            loadedReferences = try await client.listHomeworkReferences(
                workspaceId: workspaceId,
                homeworkId: requestedHomeworkId
            )
            guard homeworkContentGeneration == generation,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                  selectedHomeworkId == requestedHomeworkId else {
                throw CancellationError()
            }
        }

        homeworks = loadedHomeworks
        gradingDocuments = loadedDocuments
        guard let requestedHomeworkId else {
            homeworkReferences = []
            return
        }
        guard let selected = loadedHomeworks.first(where: { $0.id == requestedHomeworkId }) else {
            self.selectedHomeworkId = nil
            homeworkReferences = []
            clearGradingHistoryState()
            return
        }
        if !shouldPreserveDrafts {
            homeworkRubricText = selected.rubricText ?? ""
            homeworkMaxScoreText = formatScore(selected.maxScore)
        }
        homeworkReferences = loadedReferences
    }

    private func clearGradingHistoryState() {
        gradingHistoryGeneration = UUID()
        gradingHistoryTask?.cancel()
        gradingHistoryTask = nil
        gradingHistoryWorkspaceId = nil
        gradingHistoryHomeworkId = nil
        gradingResults = []
        gradingHistoryErrorText = nil
        isGradingHistoryLoading = false
    }

    private func clearLearningWorkspaceState() {
        invalidateDeferredContentLoads()
        homeDashboardState.reset()
        homeworkSelectionGeneration = UUID()
        homeworkSelectionTask?.cancel()
        homeworkSelectionTask = nil
        knowledgeSearchGeneration = UUID()
        knowledgeSearchTask?.cancel()
        knowledgeSearchTask = nil
        uploadImportGeneration = UUID()
        uploadQueueGeneration = UUID()
        learningUnitSelectionGeneration = UUID()
        workspaceContentGeneration = UUID()
        learningContentGeneration = UUID()
        homeworkContentGeneration = UUID()
        studyNoteReaderGeneration = UUID()
        studyNoteSaveGeneration = UUID()
        isBusy = false
        uploadProgressPercent = nil
        uploadProgressLabel = ""
        cancelLearningUploadFormatConversion()
        isLearningUnitMergePresented = false
        isLearningUnitMergeConfirmationPresented = false
        mergeTargetLearningUnitId = ""
        mergeSourceLearningUnitIds = []
        isLearningUnitMerging = false
        activeMergeTargetLearningUnitId = nil
        queuedUploadItems.forEach {
            UploadThumbnailCache.shared.remove(file: $0.file)
            removeCachedUploadFile($0.file)
        }
        queuedUploadItems = []
        knowledgeResults = []
        hasSearchedKnowledge = false
        isKnowledgeSearching = false
        homeworks = []
        gradingDocuments = []
        selectedHomeworkId = nil
        homeworkReferences = []
        clearGradingHistoryState()
        homeworkRubricText = ""
        homeworkMaxScoreText = "100"
        lastGradingTask = nil
        selectedFlashcardLearningUnitId = ""
        flashcardDecks = []
        selectedFlashcardDeckId = nil
        flashcardDeckDetail = nil
        flashcardIndex = 0
        isFlashcardShowingBack = false
        isFlashcardsLoading = false
        isHomeworkLoading = false
        flashcardErrorText = nil
        studyNoteGroups = []
        closeStudyNoteReader()
        aiExperienceState.reset()
    }

    private func clearChatWorkspaceState() {
        openClawChatGeneration = UUID()
        openClawChatTask?.cancel()
        openClawChatTask = nil
        conversationLoadGeneration = UUID()
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        conversationMutationGeneration = UUID()
        messageRevisionGeneration = UUID()
        messageRevisionTask?.cancel()
        messageRevisionTask = nil

        var cachedFiles: [UUID: LocalUploadFile] = [:]
        for attachment in chatAttachmentsByMessageId.values.flatMap({ $0 }) {
            cachedFiles[attachment.file.id] = attachment.file
        }
        for message in openClawMessages {
            for attachment in message.attachments {
                cachedFiles[attachment.file.id] = attachment.file
            }
        }
        for file in cachedFiles.values {
            UploadThumbnailCache.shared.remove(file: file)
            removeCachedUploadFile(file)
        }
        chatAttachmentsByMessageId = [:]
        preparedChatAttachmentDocuments = [:]

        conversations = []
        selectedConversationId = nil
        openClawMessages = []
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
        isOpenClawSending = false
        isChatHistoryLoading = false
        isConversationMutating = false
        openClawState.isMessageRevising = false
        openClawState.cancellingTaskId = nil
    }
}

private func makeUITestPendingImage(in cacheDirectory: URL) -> LocalUploadFile? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 640))
    let image = renderer.image { context in
        UIColor.systemBackground.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 80, y: 80, width: 800, height: 480))
    }
    return try? writeImageToUploadCache(image, cacheDirectory: cacheDirectory)
}

private func makeUITestPendingFile(named filename: String, in cacheDirectory: URL) -> LocalUploadFile? {
    let directory = cacheDirectory.appendingPathComponent("uploads", isDirectory: true)
    let url = directory.appendingPathComponent(filename)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url, options: .atomic)
        return LocalUploadFile(url: url, filename: filename, mimeType: contentTypeForFilename(filename))
    } catch {
        return nil
    }
}

private func makeUITestAIOnboardingQuestions() -> [AIOnboardingQuestion] {
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
            options: values.map {
                AIOnboardingOption(value: $0, labelKey: "ai.onboarding.options.\(id).\($0)")
            }
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
