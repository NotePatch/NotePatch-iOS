import Foundation
import Combine
import SwiftUI
import UIKit

private let taskPollIntervalNanoseconds: UInt64 = 1_500_000_000
private let completeUploadMaxRetries = 5
private let defaultPresenceHeartbeatIntervalSeconds = 30
private let defaultPersonalWorkspaceName = "My Workspace"

private enum DeferredWorkspaceContent: Hashable {
    case notes
    case chat
    case learning
}

private struct DeferredWorkspaceLoadKey: Hashable {
    let workspaceId: String
    let content: DeferredWorkspaceContent
}

enum WorkbenchTab: Int, CaseIterable, Identifiable {
    case documents
    case notes
    case openClaw
    case profile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .documents: return localized("tab.documents")
        case .notes: return localized("tab.notes")
        case .openClaw: return localized("tab.ai")
        case .profile: return localized("tab.me")
        }
    }

    var iconName: String {
        switch self {
        case .documents: return "house"
        case .notes: return "note.text"
        case .openClaw: return "sparkles"
        case .profile: return "person.crop.circle"
        }
    }
}

enum NotesSection: String, CaseIterable, Identifiable {
    case notes
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return localized("notes.section.notes")
        case .review: return localized("notes.section.review")
        }
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

enum LearningSection: String, CaseIterable, Identifiable {
    case units
    case search
    case grading
    case flashcards

    var id: String { rawValue }
    var title: String {
        switch self {
        case .units: return localized("review.section.units")
        case .search: return localized("review.section.search")
        case .grading: return localized("review.section.grading")
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
}

enum OpenClawAttachmentStatus: Equatable {
    case uploading
    case ready
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
    var status: OpenClawMessageStatus
    var taskId: String?
    var progress: Int?
    var events: [TaskEventItem]
    var citations: [ChatCitation]
    var sourceStatus: String?
    var modelId: String?
    var attachments: [OpenClawChatAttachment]

    init(
        id: String,
        role: OpenClawChatRole,
        content: String,
        status: OpenClawMessageStatus,
        taskId: String?,
        progress: Int?,
        events: [TaskEventItem],
        citations: [ChatCitation] = [],
        sourceStatus: String? = nil,
        modelId: String? = nil,
        attachments: [OpenClawChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.taskId = taskId
        self.progress = progress
        self.events = events
        self.citations = citations
        self.sourceStatus = sourceStatus
        self.modelId = modelId
        self.attachments = attachments
    }
}

@MainActor
final class NotePatchViewModel: ObservableObject {
    @Published var session: SavedSession?
    @Published var apiBaseURLText: String
    @Published var tusBaseURLText: String
    @Published var emailText: String
    @Published var passwordText = ""
    @Published var fullNameText: String
    @Published var isBusy = false
    @Published private var statusDisplayText: AppDisplayText = .raw("")
    @Published private var errorDisplayText: AppDisplayText?
    @Published var selectedTab: WorkbenchTab = .documents
    @Published var selectedDocumentsSection: DocumentsSection = .documents
    @Published var selectedNotesSection: NotesSection = .notes

    @Published var workspaces: [WorkspaceItem] = []
    @Published var selectedWorkspaceId: String?
    @Published var documents: [LearningDocumentItem] = []
    @Published var activeTask: TaskItem?
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
    @Published private(set) var aiModelCatalog: AiModelCatalog?
    @Published var selectedAIModelId: String?
    @Published private(set) var isAIModelsLoading = false
    @Published private(set) var isAIModelUpdating = false
    @Published private(set) var aiModelsError: String?
    @Published var learningUnits: [LearningUnit] = []
    @Published var selectedLearningUnitId: String?
    @Published var studyNotes: [StudyNoteVersion] = []
    @Published var isLearningLoading = false
    @Published var studyNoteGroups: [StudyNoteGroup] = []
    @Published var isNotesLoading = false
    @Published var selectedStudyNoteItem: StudyNoteListItem?
    @Published var studyNoteHTML: String?
    @Published var studyNoteRenderedURL: URL?
    @Published var studyNoteReaderError: String?
    @Published var isStudyNoteLoading = false
    @Published var isStudyNoteEditorPresented = false
    @Published var isStudyNoteEditorLoading = false
    @Published var studyNoteDraftTitle = ""
    @Published var studyNoteDraftHTML = ""
    @Published var studyNoteDraftSummary = "Manual Edit"
    @Published var studyNoteEditorError: String?
    @Published var isStudyNoteSaving = false
    @Published var isStudyNoteConflictPending = false
    @Published var selectedLearningSection: LearningSection = .units
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
    @Published var flashcardError: String?
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
    @Published var homeworkRubricText = ""
    @Published var homeworkMaxScoreText = "100"
    @Published var isHomeworkLoading = false
    @Published var lastGradingTask: TaskItem?
    @Published var uploadLearningUnitId = ""
    @Published var uploadLearningUnitTitle = ""
    @Published var uploadSubject = ""
    @Published var uploadGradeLevel = ""
    @Published var uploadTopic = ""
    @Published var downloadedPreview: DownloadedPreview?
    @Published var queuedUploadItems: [QueuedUploadItem] = []
    @Published private(set) var isOfflineTestMode = false

    private let settings: SettingsStore
    private let backendSession: URLSession
    private let tusSession: URLSession
    private let cacheDirectory: URL
    private let taskEventStreamingEnabled: Bool
    private var nextOpenClawMessageId: Int64 = 1
    private var presenceTask: Task<Void, Never>?
    private var studyNoteGenerationPollingTask: Task<Void, Never>?
    private var scanTrackingTask: Task<Void, Never>?
    private var scanTrackingDocumentIds = Set<String>()
    private var scanTrackingWorkspaceId: String?
    private var aiModelLoadTask: Task<Void, Never>?
    private var aiModelLoadGeneration = UUID()
    private var aiModelCatalogWorkspaceId: String?
    private var aiModelSelectionTask: Task<Void, Never>?
    private var aiModelSelectionGeneration = UUID()
    private var isAppActive = true
    private var didRestoreSession = false
    private var pendingUITestUploadFile: LocalUploadFile?
    private var retryableDocumentPurgeId: String?
    private var renderedStudyNoteRefreshAttempted = false
    private var chatAttachmentsByMessageId: [String: [OpenClawChatAttachment]] = [:]
    private var preparedChatAttachmentDocuments: [UUID: LearningDocumentItem] = [:]
    private var openClawChatTask: Task<Void, Never>?
    private var openClawChatGeneration = UUID()
    private var conversationLoadTask: Task<Void, Never>?
    private var conversationLoadGeneration = UUID()
    private var conversationMutationGeneration = UUID()
    private var aiPreferenceTask: Task<Void, Never>?
    private var aiPreferenceGeneration = UUID()
    private var homeworkSelectionTask: Task<Void, Never>?
    private var homeworkSelectionGeneration = UUID()
    private var knowledgeSearchTask: Task<Void, Never>?
    private var knowledgeSearchGeneration = UUID()
    private var uploadImportGeneration = UUID()
    private var uploadQueueGeneration = UUID()
    private var learningUnitSelectionGeneration = UUID()
    private var workspaceContentGeneration = UUID()
    private var learningContentGeneration = UUID()
    private var homeworkContentGeneration = UUID()
    private var studyNoteReaderGeneration = UUID()
    private var studyNoteSaveGeneration = UUID()
    private var loadedDeferredContent = Set<DeferredWorkspaceLoadKey>()
    private var deferredLoadTasks: [DeferredWorkspaceLoadKey: Task<Void, Never>] = [:]
    private var deferredLoadGenerations: [DeferredWorkspaceLoadKey: UUID] = [:]

    var uploadCacheDirectory: URL { cacheDirectory }

    var statusMessage: String {
        get { statusDisplayText.resolved() }
        set { statusDisplayText = newValue.isEmpty ? .raw("") : .localized(newValue) }
    }

    var errorMessage: String? {
        get { errorDisplayText?.resolved() }
        set { errorDisplayText = newValue.map { .localized($0) } }
    }

    var uploadProgressLabel: String {
        get { uploadProgressDisplayText.resolved() }
        set { uploadProgressDisplayText = newValue.isEmpty ? .raw("") : .localized(newValue) }
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
        taskEventStreamingEnabled: Bool = true
    ) {
        self.openClawState = OpenClawViewState()
        self.openClawComposerState = OpenClawComposerState()
        self.settings = settings
        self.backendSession = backendSession
        self.tusSession = tusSession
        self.cacheDirectory = cacheDirectory
        self.taskEventStreamingEnabled = taskEventStreamingEnabled
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestNoSession") {
            settings.clearSession()
        }
        let loadedSession = settings.loadSession()
        self.session = loadedSession
        self.apiBaseURLText = loadedSession?.baseURL ?? settings.loadBaseURL()
        self.tusBaseURLText = loadedSession?.tusBaseURL ?? settings.loadTUSBaseURL()
        self.emailText = loadedSession?.email ?? ""
        self.fullNameText = loadedSession?.fullName ?? ""
        self.selectedWorkspaceId = loadedSession?.selectedWorkspaceId
        self.aiHistoryEnabled = loadedSession?.aiHistoryEnabled ?? true
        self.openClawState.messages = [welcomeChatMessage]
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") {
            activateOfflineTestMode()
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestPendingImage") {
            if let file = makeUITestPendingImage(in: cacheDirectory) {
                queuedUploadItems = [QueuedUploadItem(file: file, documentKind: uploadDocumentKind, learningMetadata: uploadLearningMetadata)]
            }
        }
    }

    func restoreIfNeeded() async {
        guard !didRestoreSession, let activeSession = session else {
            return
        }
        didRestoreSession = true
        isBusy = true
        statusMessage = "Restoring login session..."
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
            startScanTrackingIfNeeded()
            if !isOfflineTestMode, let session {
                startPresence(activeSession: session)
            }
        case .background, .inactive:
            isAppActive = false
            stopStudyNoteGenerationPolling()
            stopScanTracking(clearDocuments: false)
            if !isOfflineTestMode {
                stopPresence(activeSession: session, sendOffline: true, clearClientId: false)
            }
        @unknown default:
            break
        }
    }

    func ensureContentForSelectedTabLoaded() {
        switch selectedTab {
        case .notes:
            if selectedNotesSection == .notes {
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
        case .documents:
            stopStudyNoteGenerationPolling()
            break
        }
    }

    func dismissStatusBanner() {
        errorMessage = nil
        if !isBusy {
            statusMessage = ""
        }
    }

    func checkAPIConnection() {
        let baseURL = normalizedAPIBaseURL()
        apiBaseURLText = baseURL
        settings.saveBaseURL(baseURL)
        Task {
            isBusy = true
            defer { isBusy = false }
            errorMessage = nil
            statusMessage = "Checking API..."
            do {
                _ = try await LearningBackendClient(baseURL: baseURL, session: backendSession).healthCheck()
                statusMessage = "API connected."
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
            statusMessage = "Checking tusd..."
            do {
                try await TusUploader.checkEndpoint(tusBaseURL, session: tusSession)
                statusMessage = "tusd connected."
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
            errorMessage = "Please enter email and password."
            return
        }
        if register, password.count < 8 {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        Task {
            isBusy = true
            defer { isBusy = false }
            errorMessage = nil
            statusMessage = register ? "Registering..." : "Signing in..."
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
                    aiHistoryEnabled: token.user.aiHistoryEnabled
                )
                saveSession(savedSession)
                startPresence(activeSession: savedSession)
                passwordText = ""
                statusMessage = "Loading workspace..."
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
                    aiHistoryEnabled: activeSession.aiHistoryEnabled
                )
            )
        }
        statusMessage = "Server addresses saved."
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
            errorMessage = "Please select or recover a workspace first."
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
            statusMessage = "Refreshing documents..."
            do {
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "Documents refreshed."
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
            statusMessage = "Switching workspace..."
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
            statusMessage = "Recovering workspace..."
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
                statusMessage = "Workspace recovered."
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
            statusMessage = "Reading selected files..."
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
                } else if let message = outcome.errorMessage {
                    errorMessage = message
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
            statusMessage = "Reading selected photos..."
            let outcomes = await FileImportService.shared.writePhotos(selections, cacheDirectory: cacheDirectory)
            guard importGeneration == uploadImportGeneration,
                  isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else {
                discardImportedUploadFiles(outcomes.compactMap(\.file))
                return
            }
            for outcome in outcomes {
                if let uploadFile = outcome.file {
                    stageUploadFileForPreview(uploadFile, documentKind: documentKind, learningMetadata: learningMetadata)
                } else if let message = outcome.errorMessage {
                    errorMessage = message
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
            statusMessage = "Reading image..."
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
        guard !isBusy, let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        queuedUploadItems[index].isSelected.toggle()
    }

    func removeQueuedUpload(_ id: UUID) {
        guard !isBusy, let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { return }
        let item = queuedUploadItems.remove(at: index)
        UploadThumbnailCache.shared.remove(file: item.file)
        removeCachedUploadFile(item.file)
    }

    func uploadSelectedQueuedFiles() {
        guard !isBusy, let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let selectedIds = queuedUploadItems.filter(\.isSelected).map(\.id)
        guard !selectedIds.isEmpty else {
            errorMessage = "Please select files or photos to upload first."
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
            var failureMessages: [String] = []
            var successCount = 0
            var scanningCount = 0
            for (offset, id) in selectedIds.enumerated() {
                guard uploadQueueGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                guard let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { continue }
                queuedUploadItems[index].state = .uploading
                let item = queuedUploadItems[index]
                setUploadProgress("upload.batch_progress", String(offset + 1), String(selectedIds.count), item.file.filename)
                uploadProgressPercent = 0
                do {
                    let uploaded = try await performUpload(item, activeSession: activeSession, workspaceId: workspaceId)
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    if isDocumentAwaitingSecurityScan(uploaded) { scanningCount += 1 }
                    if let completedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) {
                        let completed = queuedUploadItems.remove(at: completedIndex)
                        UploadThumbnailCache.shared.remove(file: completed.file)
                        removeCachedUploadFile(completed.file)
                    }
                    successCount += 1
                } catch {
                    guard uploadQueueGeneration == generation,
                          isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                    let message = friendlyError(error)
                    failureMessages.append("\(item.file.filename): \(message)")
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
            if failureMessages.isEmpty {
                statusMessage = scanningCount > 0
                    ? localized("upload.security_scan_started")
                    : localized("upload.selected_completed")
            } else {
                setError("upload.some_failed", failureMessages.joined(separator: "\n"))
            }
        }
    }

    private func performUpload(_ item: QueuedUploadItem, activeSession: SavedSession, workspaceId: String) async throws -> LearningDocumentItem {
        let prepared = try await FileImportService.shared.prepareForUpload(item.file, cacheDirectory: cacheDirectory)
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        let client = clientFor(activeSession)
        statusMessage = "Creating upload session..."
        let uploadSession = try await client.createUploadSession(
            workspaceId: workspaceId,
            filename: prepared.filename,
            mimeType: prepared.mimeType ?? "application/octet-stream",
            fileSize: prepared.fileSize,
            documentKind: item.documentKind,
            learningMetadata: item.learningMetadata
        )
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        statusMessage = "Uploading via tus..."
        let endpoint = TusUploader.preferredEndpoint(
            configuredEndpoint: activeSession.tusBaseURL,
            serverEndpoint: uploadSession.tusEndpoint
        )
        let tusResult = try await TusUploader(session: tusSession).upload(
            fileURL: prepared.url,
            endpoint: endpoint,
            metadataHeader: uploadSession.tusMetadataHeader
        ) { [weak self] uploaded, total in
            let progress = total <= 0 ? 0 : Int((uploaded * 100) / total).clamped(to: 0...100)
            await MainActor.run {
                guard self?.isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) == true else { return }
                self?.uploadProgressPercent = progress
                self?.setStatus("upload.tus_progress", String(progress))
            }
        }
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        statusMessage = "Confirming upload..."
        let completedDocument = try await completeUploadWithRetry(
            client: client,
            workspaceId: workspaceId,
            uploadSession: uploadSession,
            tusResult: tusResult,
            file: prepared
        )
        guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { throw CancellationError() }
        registerScanningDocuments([completedDocument], workspaceId: workspaceId)
        if isDocumentAwaitingSecurityScan(completedDocument) {
            statusMessage = localized("upload.security_scan_started")
        }
        return completedDocument
    }

    func startProcessing(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId, !isBusy else {
            return
        }
        guard canProcessDocument(document) else {
            errorMessage = isDocumentSecurityBlocked(document)
                ? localized("document.error.security_scan_blocked")
                : localized("document.error.not_processable")
            return
        }
        isBusy = true
        errorMessage = nil
        taskEvents = []
        statusMessage = "Starting document processing..."
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
                selectedTab = .documents
                selectedDocumentsSection = .tasks
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
                statusMessage = "Document processing complete."
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    @discardableResult
    func startOpenClawChat(prompt rawPrompt: String, attachments files: [LocalUploadFile] = []) -> Bool {
        guard let activeSession = currentSessionOrError() else {
            return false
        }
        guard let workspaceId = selectedWorkspaceId else {
            errorMessage = "Please select or recover a workspace first."
            return false
        }
        guard !isOpenClawSending else { return false }
        let trimmedPrompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty || !files.isEmpty else {
            errorMessage = "Please enter an AI Co-pilot prompt."
            return false
        }
        let prompt = trimmedPrompt.isEmpty ? localized("chat.attachment_default_prompt") : trimmedPrompt
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
                        documentKind: "other",
                        learningMetadata: LearningMetadata()
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

                let attachmentInput: [[String: Any]] = uploadedDocuments.map { document in
                    var value: [String: Any] = [
                        "document_id": document.id,
                        "filename": document.originalFilename,
                        "file_type": document.fileType
                    ]
                    if let mimeType = document.detectedMimeType ?? document.mimeType, !mimeType.isEmpty {
                        value["mime_type"] = mimeType
                    }
                    return value
                }
                let input: [String: Any] = attachmentInput.isEmpty ? [:] : ["attachments": attachmentInput]
                let chatSession = session ?? activeSession
                let task = try await clientFor(chatSession).openClawChat(
                    workspaceId: workspaceId,
                    prompt: prompt,
                    conversationId: requestedConversationId,
                    input: input
                )
                taskWasAccepted = true
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
                let finishedTask = try await pollTask(activeSession: chatSession, workspaceId: workspaceId, taskId: task.id) { [weak self] updatedTask, events in
                    latestEvents = events
                    self?.updateOpenClawMessage(assistantMessageId) {
                        $0.content = "Thinking..."
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
                    try? await refreshConversations(activeSession: chatSession, workspaceId: workspaceId)
                } else {
                    let answer = formatOpenClawTaskResult(finishedTask.resultText)
                    updateOpenClawMessage(assistantMessageId) {
                        $0.content = answer.isEmpty ? "No content returned." : answer
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
                if !taskWasAccepted {
                    openClawMessages.removeAll { $0.id == userMessageId || $0.id == assistantMessageId }
                    showError(error)
                    return
                }
                if let backendError = error as? LearningBackendError, backendError.shouldClearSession {
                    showError(error)
                }
                let eventMessage = latestEvents.last(where: { $0.level == "error" })?.message ?? latestEvents.last?.message
                let message = [friendlyError(error), eventMessage.map { "Recent event: \($0)" }]
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
        isOpenClawSending = false
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
            if isDocumentSecurityBlocked(document) {
                throw LearningBackendError(
                    document.scanMessage ?? localized("document.error.security_scan_blocked")
                )
            }
            if ["uploaded", "ready"].contains(document.status), !isDocumentAwaitingSecurityScan(document) {
                return document
            }
            if ["failed", "deleted"].contains(document.status) {
                throw LearningBackendError(document.scanMessage ?? localized("chat.attachment_upload_failed"))
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
            topic: uploadTopic
        )
    }

    func loadChatHistory(force: Bool = true) {
        beginDeferredLoad(
            .chat,
            force: force,
            setLoading: { [weak self] isLoading in self?.isChatHistoryLoading = isLoading }
        ) { [weak self] activeSession, workspaceId, isCurrent in
            guard let self else { return }
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
                self.openClawMessages = [self.welcomeChatMessage]
            }
        }
    }

    func selectConversation(_ conversationId: String) {
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
        openClawMessages = [welcomeChatMessage]
        openClawComposerState.attachments.forEach { preparedChatAttachmentDocuments[$0.id] = nil }
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
    }

    func renameCurrentConversation(to title: String) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId, !isConversationMutating else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a conversation title."
            return
        }
        guard trimmed.count <= 160 else {
            errorMessage = "Conversation title cannot exceed 160 characters."
            return
        }
        isConversationMutating = true
        let generation = UUID()
        conversationMutationGeneration = generation
        errorMessage = nil
        statusMessage = "Saving conversation title..."
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
                statusMessage = "Conversation title saved."
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
        isConversationMutating = true
        let generation = UUID()
        conversationMutationGeneration = generation
        errorMessage = nil
        statusMessage = "Deleting conversation..."
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
                selectedConversationId = conversations.first?.id
                openClawMessages = [welcomeChatMessage]
                statusMessage = "Conversation deleted."

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
        statusMessage = "Saving AI history setting..."
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
                statusMessage = "AI history setting saved."
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
        aiModelsError = nil

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
                self.aiModelsError = friendlyError(error)
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
        aiModelsError = nil

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
                self.aiModelsError = friendlyError(error)
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
        studyNoteReaderError = nil
        renderedStudyNoteRefreshAttempted = false

        if isOfflineTestMode, item.note.id == "note-1" {
            studyNoteHTML = """
            <h1>Fractions &amp; Ratios</h1>
            <h2>Key Concepts</h2>
            <p>A fraction represents a part of a whole, while ratios compare the relationship between two quantities.</p>
            <ul>
              <li>Antecedent and consequent terms of a ratio must use the same unit.</li>
              <li>In a proportion, the product of the extremes equals the product of the means.</li>
            </ul>
            <blockquote>First convert to common units, then simplify and calculate.</blockquote>
            """
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
                statusMessage = localized("operation.note_loaded")
            } catch {
                guard studyNoteReaderGeneration == generation,
                      isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedStudyNoteItem?.id == item.id else { return }
                studyNoteReaderError = friendlyError(error)
            }
        }
    }

    func closeStudyNoteReader() {
        studyNoteReaderGeneration = UUID()
        cancelStudyNoteEditing()
        selectedStudyNoteItem = nil
        studyNoteHTML = nil
        studyNoteRenderedURL = nil
        studyNoteReaderError = nil
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

    func beginStudyNoteEditing() {
        guard canEditSelectedStudyNote,
              let item = selectedStudyNoteItem,
              let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId else {
            studyNoteReaderError = localized("note.error.latest_only")
            return
        }
        studyNoteDraftTitle = item.note.title
        studyNoteDraftSummary = localized("note.editor.default_summary")
        studyNoteDraftHTML = ""
        studyNoteEditorError = nil
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
                studyNoteEditorError = friendlyError(error)
            }
        }
    }

    func cancelStudyNoteEditing() {
        isStudyNoteEditorPresented = false
        isStudyNoteEditorLoading = false
        studyNoteDraftTitle = ""
        studyNoteDraftHTML = ""
        studyNoteDraftSummary = localized("note.editor.default_summary")
        studyNoteEditorError = nil
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
            studyNoteEditorError = localized("note.error.empty_html")
            return
        }
        guard html.count <= 2_000_000 else {
            studyNoteEditorError = localized("note.error.html_too_long")
            return
        }
        guard title.isEmpty || title.count <= 255 else {
            studyNoteEditorError = localized("note.error.title_too_long")
            return
        }
        guard summary.isEmpty || summary.count <= 500 else {
            studyNoteEditorError = localized("note.error.summary_too_long")
            return
        }

        isStudyNoteSaving = true
        let saveGeneration = UUID()
        studyNoteSaveGeneration = saveGeneration
        studyNoteEditorError = nil
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
                isStudyNoteEditorPresented = false
                statusMessage = localized("operation.note_revision_saved")

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
                studyNoteEditorError = friendlyError(error)
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
            errorMessage = localized("merge.error.target_required")
            return
        }
        guard (1...50).contains(mergeSourceLearningUnitIds.count),
              !mergeSourceLearningUnitIds.contains(mergeTargetLearningUnitId) else {
            errorMessage = localized("merge.error.sources_required")
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
            errorMessage = localized("merge.error.sources_required")
            return
        }

        isLearningUnitMerging = true
        errorMessage = nil
        statusMessage = localized("merge.starting")
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
                statusMessage = localized("merge.in_progress")

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
                    statusMessage = localized("merge.completed")
                    if selectedLearningSection == .flashcards {
                        loadFlashcards(learningUnitId: targetId)
                    }
                } else if learningUnits.first(where: { $0.id == targetId })?.mergeStatus == "failed" {
                    errorMessage = "merge.status.failed"
                } else {
                    statusMessage = localized("merge.rebuilding")
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
        selectedTab = .documents
        selectedDocumentsSection = .tasks
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
        guard selectedTab == .notes, selectedNotesSection == .review, selectedLearningSection == .flashcards else { return }
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
        guard let activeSession = currentSessionOrError(),
              let workspaceId = selectedWorkspaceId,
              let unitId = selectedFlashcardLearningUnitId.nilIfBlank,
              !isFlashcardsLoading else { return }
        selectedFlashcardDeckId = deckId
        flashcardIndex = 0
        isFlashcardShowingBack = false
        isFlashcardsLoading = true
        flashcardError = nil
        Task {
            defer { isFlashcardsLoading = false }
            do {
                let detail = try await clientFor(activeSession).getFlashcardDeck(
                    workspaceId: workspaceId,
                    learningUnitId: unitId,
                    deckId: deckId
                )
                guard selectedWorkspaceId == workspaceId,
                      selectedFlashcardLearningUnitId == unitId,
                      selectedFlashcardDeckId == deckId else { return }
                flashcardDeckDetail = sortedFlashcardDetail(detail)
            } catch {
                flashcardError = friendlyError(error)
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
              let workspaceId = selectedWorkspaceId,
              !isFlashcardsLoading else { return }
        selectedFlashcardLearningUnitId = learningUnitId
        isFlashcardsLoading = true
        flashcardError = nil
        Task {
            defer { isFlashcardsLoading = false }
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
                      selectedFlashcardLearningUnitId == learningUnitId else { return }
                flashcardDecks = decks
                flashcardDeckDetail = latest.map(sortedFlashcardDetail)
                selectedFlashcardDeckId = latest?.deck.id
                flashcardIndex = 0
                isFlashcardShowingBack = false
            } catch {
                guard selectedWorkspaceId == workspaceId,
                      selectedFlashcardLearningUnitId == learningUnitId else { return }
                flashcardError = friendlyError(error)
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
        guard let lastGradingTask else { return nil }
        return lastGradingTask.result?.objectStringValue(for: "grading_mode") == "official"
            ? localized("grading.mode.official")
            : localized("grading.mode.diagnostic")
    }

    var gradingConfidence: Double? {
        lastGradingTask?.result?.objectDoubleValue(for: "confidence")
    }

    var canRetryDocumentPurge: Bool {
        isDocumentPurgeRetryAvailable && !isBusy
    }

    func searchKnowledge() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        guard !isKnowledgeSearching else { return }
        let query = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "Please enter a knowledge search query."
            return
        }
        guard query.count <= 8000 else {
            errorMessage = "Knowledge search query cannot exceed 8,000 characters."
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
                    statusMessage = "No matching results in the knowledge base."
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
            errorMessage = "Please select a processed homework document."
            return false
        }
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Please enter a homework title."
            return false
        }
        guard let maxScore = Double(maxScoreText), maxScore > 0 else {
            errorMessage = "Maximum score must be greater than 0."
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
                homeworkRubricText = homework.rubricText ?? ""
                homeworkMaxScoreText = formatScore(homework.maxScore)
                statusMessage = "Homework created."
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
            errorMessage = "Maximum score must be greater than 0."
            return
        }
        guard isGradingConfigDirty else { return }
        let input = GradingConfigInput(rubricText: homeworkRubricText.nilIfBlank, maxScore: maxScore)
        let submittedRubricText = homeworkRubricText
        let submittedMaxScoreText = homeworkMaxScoreText
        isHomeworkLoading = true
        errorMessage = nil
        statusMessage = "Saving grading configuration..."
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
                statusMessage = "Grading configuration saved. Please re-grade."
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
                statusMessage = "Reference added. Please re-grade."
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
        statusMessage = "Removing reference..."
        Task {
            defer { isHomeworkLoading = false }
            do {
                let client = clientFor(activeSession)
                try await client.deleteHomeworkReference(workspaceId: workspaceId, homeworkId: homeworkId, referenceId: reference.id)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId),
                      selectedHomeworkId == homeworkId else { return }
                homeworkReferences.removeAll { $0.id == reference.id }
                lastGradingTask = nil
                statusMessage = "Reference removed. Please re-grade."
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
                selectedTab = .documents
                selectedDocumentsSection = .tasks
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
                try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "Homework grading complete."
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
                    completionMessage: "Study note downloaded.",
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
            errorMessage = localized("document.error.security_scan_blocked")
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
            statusMessage = "Loading artifacts..."
            do {
                let loadedArtifacts = try await clientFor(activeSession).listArtifacts(
                    workspaceId: workspaceId,
                    documentId: document.id
                )
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                selectedArtifactDocumentId = document.id
                selectedArtifacts = loadedArtifacts
                statusMessage = "Artifacts loaded."
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
            errorMessage = localized("document.error.security_scan_blocked")
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
            statusMessage = "Loading OCR results..."
            do {
                let loadedArtifacts = try await clientFor(activeSession)
                    .getOcrArtifacts(workspaceId: workspaceId, documentId: document.id, includeDownloadURL: true)
                    .artifacts
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                selectedOcrDocumentId = document.id
                selectedOcrArtifacts = loadedArtifacts
                statusMessage = selectedOcrArtifacts.isEmpty ? "No OCR results yet." : "OCR results loaded."
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
        statusMessage = "Requesting document deletion..."

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
                selectedTab = .documents
                selectedDocumentsSection = .tasks
                statusMessage = "Document deleted. Cleaning up original and derivative data..."

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
                statusMessage = "Document and derivative data cleanup complete."
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
            statusMessage = "Fetching artifact download link..."
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
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) downloaded.",
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
            errorMessage = "OCR artifact has no available download link. Please reload OCR results."
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
            statusMessage = "Downloading OCR results..."
            do {
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: defaultArtifactFilename(type: artifact.artifactType, mimeType: artifact.mimeType, fallback: artifact.id),
                    mimeType: artifact.mimeType,
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) downloaded.",
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
            errorMessage = localized("document.error.security_scan_blocked")
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
            statusMessage = "Fetching download link..."
            do {
                let client = clientFor(activeSession)
                let response = try await client.getDownloadURL(workspaceId: workspaceId, documentId: document.id)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                statusMessage = "Downloading file..."
                let directory = cacheDirectory.appendingPathComponent("downloads", isDirectory: true)
                let targetURL = directory.appendingPathComponent(sanitizeFileName(document.originalFilename))
                let downloadedURL = try await client.download(downloadURL: response.downloadURL, targetURL: targetURL)
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                downloadedPreview = DownloadedPreview(url: downloadedURL, mimeType: document.mimeType ?? contentTypeForFilename(document.originalFilename))
                statusMessage = document.mimeType?.hasPrefix("image/") == true ? "Image downloaded." : "File downloaded."
            } catch {
                guard isCurrentWorkspaceContext(activeSession, workspaceId: workspaceId) else { return }
                showError(error)
            }
        }
    }

    private func downloadAndPreview(
        client: LearningBackendClient,
        downloadURL: String,
        filename: String,
        mimeType: String?,
        completionMessage: String,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) async throws {
        statusMessage = "Downloading file..."
        let directory = cacheDirectory.appendingPathComponent("downloads", isDirectory: true)
        let safeFilename = sanitizeFileName(filename)
        let targetURL = directory.appendingPathComponent(safeFilename)
        let downloadedURL = try await client.download(downloadURL: downloadURL, targetURL: targetURL)
        guard shouldApply() else { throw CancellationError() }
        downloadedPreview = DownloadedPreview(url: downloadedURL, mimeType: mimeType ?? contentTypeForFilename(safeFilename))
        statusMessage = completionMessage
    }

    private func shouldForceReprocess(_ document: LearningDocumentItem) -> Bool {
        document.status == "ready" || document.status == "failed"
    }

    func canProcessDocument(_ document: LearningDocumentItem) -> Bool {
        ["uploaded", "ready", "failed"].contains(document.status)
            && !isDocumentAwaitingSecurityScan(document)
            && !isDocumentSecurityBlocked(document)
    }

    func canDownloadDocument(_ document: LearningDocumentItem) -> Bool {
        document.status != "deleted"
            && !isDocumentAwaitingSecurityScan(document)
            && !isDocumentSecurityBlocked(document)
    }

    private func isDocumentAwaitingSecurityScan(_ document: LearningDocumentItem) -> Bool {
        document.status == "scanning" || ["pending", "scanning"].contains(document.scanStatus ?? "")
    }

    private func isDocumentSecurityBlocked(_ document: LearningDocumentItem) -> Bool {
        ["infected", "failed"].contains(document.scanStatus ?? "")
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
            errorMessage = "Please sign in or register first."
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
           !backendError.shouldClearSession {
            setRawError(friendlyError(error))
        } else {
            errorMessage = friendlyError(error)
        }
        statusMessage = ""
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
            aiHistoryEnabled: true
        )
        let sampleDocuments = [
            LearningDocumentItem(id: "homework-doc", workspaceId: "ui-workspace", title: "Algebra Homework", originalFilename: "homework.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "homework", status: "ready"),
            LearningDocumentItem(id: "answer-doc", workspaceId: "ui-workspace", title: "Answer Key", originalFilename: "answer.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "answer_key", status: "ready"),
            LearningDocumentItem(id: "scan-doc", workspaceId: "ui-workspace", title: "New Worksheet", originalFilename: "worksheet.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "homework", scanStatus: "scanning", scanMessage: "Checking the uploaded file", status: "scanning")
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
        homeworks = [HomeworkItem(id: "homework-1", workspaceId: "ui-workspace", title: "Algebra Homework 01", documentId: "homework-doc", rubricText: "10 points per question", maxScore: 100)]
        selectedHomeworkId = "homework-1"
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
        installOfflineAIModelFixtureIfNeeded()
        conversations = []
        selectedConversationId = nil
        isOpenClawSending = false
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestLongChat") {
            openClawMessages = (0..<100).map { index in
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
            openClawMessages = [welcomeChatMessage]
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
        statusMessage = "UI Offline Test Mode"
    }


    private func clearLocalSession() {
        presenceTask?.cancel()
        presenceTask = nil
        stopStudyNoteGenerationPolling()
        stopScanTracking(clearDocuments: true)
        invalidateDeferredContentLoads()
        aiPreferenceGeneration = UUID()
        aiPreferenceTask?.cancel()
        aiPreferenceTask = nil
        uploadImportGeneration = UUID()
        uploadQueueGeneration = UUID()
        learningUnitSelectionGeneration = UUID()
        workspaceContentGeneration = UUID()
        learningContentGeneration = UUID()
        homeworkContentGeneration = UUID()
        studyNoteReaderGeneration = UUID()
        studyNoteSaveGeneration = UUID()
        settings.clearSession()
        isBusy = false
        uploadProgressPercent = nil
        uploadProgressLabel = ""
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
        isAIPreferenceUpdating = false
        clearAIModelState()
        learningUnits = []
        selectedLearningUnitId = nil
        studyNotes = []
        studyNoteGroups = []
        closeStudyNoteReader()
        clearLearningWorkspaceState()
        aiHistoryEnabled = true
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

    private func saveSession(_ updated: SavedSession) {
        if !isOfflineTestMode {
            settings.saveSession(updated)
        }
        session = updated
        apiBaseURLText = updated.baseURL
        tusBaseURLText = updated.tusBaseURL
        emailText = updated.email
        fullNameText = updated.fullName ?? ""
        selectedWorkspaceId = updated.selectedWorkspaceId
        aiHistoryEnabled = updated.aiHistoryEnabled
    }

    private func saveSelectedWorkspace(_ workspaceId: String?) {
        if selectedWorkspaceId != workspaceId {
            invalidateDeferredContentLoads()
            clearAIModelState()
            clearChatWorkspaceState()
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
                    aiHistoryEnabled: latest.aiHistoryEnabled
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
                        self.statusMessage = "AI Co-pilot presence sync failed. Will retry automatically."
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
        errorMessage = nil

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
                if self.isCurrentDeferredLoad(key, generation: generation, session: activeSession) {
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
                    if self.selectedNotesSection == .notes {
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
                                self.statusMessage = localized("merge.completed")
                                if self.selectedLearningSection == .flashcards {
                                    self.loadFlashcards(learningUnitId: target.id)
                                }
                            } else if target.mergeStatus == "failed" {
                                self.statusMessage = ""
                                if self.errorMessage == nil {
                                    self.errorMessage = "merge.status.failed"
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
        if selectedNotesSection == .notes {
            return studyNoteGroups.contains(where: { $0.generationState == .generating })
        }
        return selectedNotesSection == .review
            && learningUnits.contains(where: { ["merging", "rebuilding"].contains($0.mergeStatus ?? "") })
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
        registerScanningDocuments(documents, workspaceId: workspaceId)
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

    private func registerScanningDocuments(_ loadedDocuments: [LearningDocumentItem], workspaceId: String) {
        let pendingIds = Set(loadedDocuments.filter(isDocumentAwaitingSecurityScan).map(\.id))
        if scanTrackingWorkspaceId != workspaceId {
            stopScanTracking(clearDocuments: true)
            scanTrackingWorkspaceId = workspaceId
        }
        scanTrackingDocumentIds.formUnion(pendingIds)
        startScanTrackingIfNeeded()
    }

    private func startScanTrackingIfNeeded() {
        guard isAppActive,
              !isOfflineTestMode,
              scanTrackingTask?.isCancelled != false,
              !scanTrackingDocumentIds.isEmpty,
              let activeSession = session,
              let workspaceId = selectedWorkspaceId,
              workspaceId == scanTrackingWorkspaceId else { return }

        scanTrackingTask = Task { [weak self] in
            var failureCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.isAppActive,
                      self.selectedWorkspaceId == workspaceId,
                      self.session?.userId == activeSession.userId else { break }

                let ids = Array(self.scanTrackingDocumentIds)
                guard !ids.isEmpty else { break }
                let results = await self.loadScanningDocuments(
                    ids: ids,
                    activeSession: activeSession,
                    workspaceId: workspaceId
                )
                var transitioned = false
                var successfulRequest = false
                for (documentId, result) in results {
                    switch result {
                    case .success(let document):
                        successfulRequest = true
                        if let index = self.documents.firstIndex(where: { $0.id == document.id }),
                           self.documents[index] != document {
                            self.documents[index] = document
                        }
                        if !self.isDocumentAwaitingSecurityScan(document) {
                            self.scanTrackingDocumentIds.remove(document.id)
                            transitioned = true
                        }
                    case .failure(let error):
                        if let backendError = error as? LearningBackendError, backendError.statusCode == 404 {
                            self.scanTrackingDocumentIds.remove(documentId)
                        }
                    }
                }
                if successfulRequest { failureCount = 0 } else { failureCount += 1 }
                if transitioned {
                    try? await self.refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                }
                if self.scanTrackingDocumentIds.isEmpty { break }
                if !successfulRequest {
                    let delays: [UInt64] = [5, 10, 20, 30]
                    let delay = delays[min(max(failureCount - 1, 0), delays.count - 1)]
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                }
            }
            self?.scanTrackingTask = nil
        }
    }

    private func loadScanningDocuments(
        ids: [String],
        activeSession: SavedSession,
        workspaceId: String
    ) async -> [(String, Result<LearningDocumentItem, Error>)] {
        let client = clientFor(activeSession)
        var results = Array<Result<LearningDocumentItem, Error>?>(repeating: nil, count: ids.count)
        await withTaskGroup(of: (Int, Result<LearningDocumentItem, Error>).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard nextIndex < ids.count else { return }
                let index = nextIndex
                let id = ids[index]
                nextIndex += 1
                group.addTask {
                    do {
                        return (index, .success(try await client.getDocument(workspaceId: workspaceId, documentId: id)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for _ in 0..<min(4, ids.count) { enqueueNext() }
            while let (index, result) = await group.next() {
                results[index] = result
                enqueueNext()
            }
        }
        return results.enumerated().compactMap { index, result in
            result.map { (ids[index], $0) }
        }
    }

    private func stopScanTracking(clearDocuments: Bool) {
        scanTrackingTask?.cancel()
        scanTrackingTask = nil
        if clearDocuments {
            scanTrackingDocumentIds = []
            scanTrackingWorkspaceId = nil
        }
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
        if user.email != activeSession.email || user.fullName != activeSession.fullName || user.aiHistoryEnabled != activeSession.aiHistoryEnabled {
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
            statusMessage = "Your account doesn't have a workspace yet. Please recover one in Settings."
        }
    }

    private func pollTask(
        activeSession: SavedSession,
        workspaceId: String,
        taskId: String,
        onUpdate: @escaping (TaskItem, [TaskEventItem]) -> Void
    ) async throws -> TaskItem {
        let client = clientFor(activeSession)
        var currentTask = activeTask?.id == taskId
            ? activeTask!
            : try await client.getTask(workspaceId: workspaceId, taskId: taskId)
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
                    throw LearningBackendError("Task event stream disconnected.")
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
            throw LearningBackendError(
                task.errorMessage
                    ?? events.last(where: { $0.level == "error" })?.message
                    ?? "Task failed."
            )
        case "cancelled":
            throw LearningBackendError(
                events.last(where: { $0.eventType.contains("cancel") })?.message
                    ?? events.last(where: { $0.level == "error" })?.message
                    ?? events.last?.message
                    ?? task.errorMessage
                    ?? "Task cancelled."
            )
        default:
            throw LearningBackendError("Task event stream ended before the task completed.")
        }
    }

    private func completeUploadWithRetry(
        client: LearningBackendClient,
        workspaceId: String,
        uploadSession: UploadSessionResponse,
        tusResult: TusUploadResult,
        file: LocalUploadFile
    ) async throws -> LearningDocumentItem {
        var lastConflict: LearningBackendError?
        for attempt in 0..<completeUploadMaxRetries {
            do {
                return try await client.completeUpload(
                    workspaceId: workspaceId,
                    uploadSessionId: uploadSession.uploadSession.id,
                    tusUploadURL: tusResult.uploadURL,
                    tusUploadId: tusResult.uploadId,
                    fileSize: file.fileSize,
                    mimeType: file.mimeType ?? "application/octet-stream"
                )
            } catch let error as LearningBackendError where error.statusCode == 409 {
                lastConflict = error
                setStatus("upload.tusd_sync_retry", String(attempt + 1), String(completeUploadMaxRetries))
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw lastConflict ?? LearningBackendError("Upload confirmation failed.")
    }

    private func allocateOpenClawMessageId() -> String {
        let id = nextOpenClawMessageId
        nextOpenClawMessageId += 1
        return "local-\(id)"
    }

    private func updateOpenClawMessage(_ messageId: String, transform: (inout OpenClawChatMessage) -> Void) {
        openClawState.updateMessage(id: messageId, transform: transform)
    }

    private var welcomeChatMessage: OpenClawChatMessage {
        OpenClawChatMessage(id: "system", role: .system, content: "AI Co-pilot can help you organize ideas and analyze document results. Supports Markdown for replies.", status: .done, taskId: nil, progress: nil, events: [])
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
                attachments: chatAttachmentsByMessageId[chatMessage.id] ?? []
            )
        }
        openClawMessages = messages.isEmpty ? [welcomeChatMessage] : messages
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
        aiModelsError = nil
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
        aiModelsError = nil
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
            studyNoteReaderError = localized("note.reader.signed_url_expired")
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
                studyNoteReaderError = nil
            } catch {
                guard selectedStudyNoteItem?.id == item.id else { return }
                studyNoteRenderedURL = nil
                studyNoteReaderError = friendlyError(error)
            }
        }
    }

    func handleRenderedStudyNoteFailure(_ message: String) {
        guard selectedStudyNoteItem != nil else { return }
        studyNoteRenderedURL = nil
        studyNoteReaderError = message
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
                throw LearningBackendError(localized("note.error.no_server_versions"))
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
                studyNoteReaderError = friendlyError(error)
            }
            studyNoteEditorError = afterConflictConfirmation
                ? localized("note.error.conflict_during_save")
                : localized("note.error.conflict_available")
            isStudyNoteConflictPending = true
        } catch {
            studyNoteEditorError = localizedFormat("note.error.conflict_refresh_failed", friendlyError(error))
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
            return
        }
        if !shouldPreserveDrafts {
            homeworkRubricText = selected.rubricText ?? ""
            homeworkMaxScoreText = formatScore(selected.maxScore)
        }
        homeworkReferences = loadedReferences
    }

    private func clearLearningWorkspaceState() {
        invalidateDeferredContentLoads()
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
        stopScanTracking(clearDocuments: true)
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
        flashcardError = nil
        studyNoteGroups = []
        closeStudyNoteReader()
    }

    private func clearChatWorkspaceState() {
        openClawChatGeneration = UUID()
        openClawChatTask?.cancel()
        openClawChatTask = nil
        conversationLoadGeneration = UUID()
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        conversationMutationGeneration = UUID()

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
        openClawMessages = [welcomeChatMessage]
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
        isOpenClawSending = false
        isChatHistoryLoading = false
        isConversationMutating = false
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
