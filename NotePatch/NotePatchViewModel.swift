import Foundation
import Combine
import SwiftUI
import UIKit

private let taskPollIntervalNanoseconds: UInt64 = 1_500_000_000
private let taskMaxPolls = 120
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
        case .documents: return "doc.text"
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

    var id: String { rawValue }
    var title: String {
        switch self {
        case .units: return localized("review.section.units")
        case .search: return localized("review.section.search")
        case .grading: return localized("review.section.grading")
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

    init(
        id: String,
        role: OpenClawChatRole,
        content: String,
        status: OpenClawMessageStatus,
        taskId: String?,
        progress: Int?,
        events: [TaskEventItem],
        citations: [ChatCitation] = [],
        sourceStatus: String? = nil
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
    @Published var learningUnits: [LearningUnit] = []
    @Published var selectedLearningUnitId: String?
    @Published var studyNotes: [StudyNoteVersion] = []
    @Published var isLearningLoading = false
    @Published var studyNoteGroups: [StudyNoteGroup] = []
    @Published var isNotesLoading = false
    @Published var selectedStudyNoteItem: StudyNoteListItem?
    @Published var studyNoteMarkdown: String?
    @Published var studyNoteReaderError: String?
    @Published var isStudyNoteLoading = false
    @Published var isStudyNoteEditorPresented = false
    @Published var studyNoteDraftTitle = ""
    @Published var studyNoteDraftMarkdown = ""
    @Published var studyNoteDraftSummary = "Manual Edit"
    @Published var studyNoteEditorError: String?
    @Published var isStudyNoteSaving = false
    @Published var isStudyNoteConflictPending = false
    @Published var selectedLearningSection: LearningSection = .units
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
    private var nextOpenClawMessageId: Int64 = 1
    private var presenceTask: Task<Void, Never>?
    private var didRestoreSession = false
    private var pendingUITestUploadFile: LocalUploadFile?
    private var retryableDocumentPurgeId: String?
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
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    ) {
        self.openClawState = OpenClawViewState()
        self.openClawComposerState = OpenClawComposerState()
        self.settings = settings
        self.backendSession = backendSession
        self.tusSession = tusSession
        self.cacheDirectory = cacheDirectory
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
        guard !isOfflineTestMode else { return }
        switch scenePhase {
        case .active:
            if let session {
                startPresence(activeSession: session)
            }
        case .background, .inactive:
            stopPresence(activeSession: session, sendOffline: true, clearClientId: false)
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
            }
        case .openClaw:
            loadChatHistory(force: false)
        case .documents, .profile:
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
            errorMessage = nil
            statusMessage = "Checking API..."
            do {
                _ = try await LearningBackendClient(baseURL: baseURL, session: backendSession).healthCheck()
                statusMessage = "API connected."
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func checkTUSConnection() {
        let tusBaseURL = normalizedTUSBaseURL()
        tusBaseURLText = tusBaseURL
        settings.saveTUSBaseURL(tusBaseURL)
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Checking tusd..."
            do {
                try await TusUploader.checkEndpoint(tusBaseURL, session: tusSession)
                statusMessage = "tusd connected."
            } catch {
                showError(error)
            }
            isBusy = false
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
            isBusy = false
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
            errorMessage = nil
            statusMessage = "Refreshing documents..."
            do {
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "Documents refreshed."
            } catch {
                showError(error)
            }
            isBusy = false
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
            isBusy = false
        }
    }

    func recoverPersonalWorkspace() {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        Task {
            isBusy = true
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
                try await loadWorkspaces(activeSession: activeSession, preferredWorkspaceId: workspace.id)
                statusMessage = "Workspace recovered."
            } catch {
                showError(error)
            }
            isBusy = false
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

    func uploadPickedFiles(from sourceURLs: [URL]) {
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
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        Task {
            isBusy = true
            errorMessage = nil
            defer { isBusy = false }
            statusMessage = "Reading selected photos..."
            let outcomes = await FileImportService.shared.writePhotos(selections, cacheDirectory: cacheDirectory)
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
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Reading image..."
            do {
                let uploadFile = try await FileImportService.shared.writeCameraImage(image, cacheDirectory: cacheDirectory)
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

    func stageImportedUploadFiles(_ files: [LocalUploadFile]) {
        let documentKind = uploadDocumentKind
        let learningMetadata = uploadLearningMetadata
        for file in files {
            stageUploadFileForPreview(file, documentKind: documentKind, learningMetadata: learningMetadata)
        }
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
        errorMessage = nil
        Task {
            var failureMessages: [String] = []
            var successCount = 0
            for (offset, id) in selectedIds.enumerated() {
                guard let index = queuedUploadItems.firstIndex(where: { $0.id == id }) else { continue }
                queuedUploadItems[index].state = .uploading
                let item = queuedUploadItems[index]
                setUploadProgress("upload.batch_progress", String(offset + 1), String(selectedIds.count), item.file.filename)
                uploadProgressPercent = 0
                do {
                    try await performUpload(item, activeSession: activeSession, workspaceId: workspaceId)
                    if let completedIndex = queuedUploadItems.firstIndex(where: { $0.id == id }) {
                        let completed = queuedUploadItems.remove(at: completedIndex)
                        UploadThumbnailCache.shared.remove(file: completed.file)
                        removeCachedUploadFile(completed.file)
                    }
                    successCount += 1
                } catch {
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
            uploadProgressPercent = nil
            uploadProgressLabel = ""
            isBusy = false
            if failureMessages.isEmpty {
                statusMessage = "Selected files uploaded."
            } else {
                setError("upload.some_failed", failureMessages.joined(separator: "\n"))
            }
        }
    }

    private func performUpload(_ item: QueuedUploadItem, activeSession: SavedSession, workspaceId: String) async throws {
        let prepared = try await FileImportService.shared.prepareForUpload(item.file, cacheDirectory: cacheDirectory)
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
        statusMessage = "Uploading via tus..."
        let endpoint = uploadSession.tusEndpoint.isEmpty ? activeSession.tusBaseURL : uploadSession.tusEndpoint
        let tusResult = try await TusUploader(session: tusSession).upload(
            fileURL: prepared.url,
            endpoint: endpoint,
            metadataHeader: uploadSession.tusMetadataHeader
        ) { [weak self] uploaded, total in
            let progress = total <= 0 ? 0 : Int((uploaded * 100) / total).clamped(to: 0...100)
            await MainActor.run {
                self?.uploadProgressPercent = progress
                self?.setStatus("upload.tus_progress", String(progress))
            }
        }
        statusMessage = "Confirming upload..."
        _ = try await completeUploadWithRetry(
            client: client,
            workspaceId: workspaceId,
            uploadSession: uploadSession,
            tusResult: tusResult,
            file: prepared
        )
    }

    func startProcessing(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId, !isBusy else {
            return
        }
        guard isProcessableDocument(document) else {
            errorMessage = "Only uploaded, ready, or failed documents can be processed."
            return
        }
        isBusy = true
        errorMessage = nil
        taskEvents = []
        statusMessage = "Starting document processing..."
        Task {
            defer { isBusy = false }
            do {
                let client = clientFor(activeSession)
                let task = try await client.processDocument(
                    workspaceId: workspaceId,
                    documentId: document.id,
                    forceReprocess: shouldForceReprocess(document)
                )
                activeTask = task
                selectedTab = .documents
                selectedDocumentsSection = .tasks
                let finishedTask = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] updatedTask, events in
                    self?.activeTask = updatedTask
                    self?.taskEvents = events
                    self?.setStatus(
                        "task.progress",
                        statusLabel(updatedTask.status),
                        String(updatedTask.progress.clamped(to: 0...100))
                    )
                }
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                selectedArtifactDocumentId = document.id
                selectedArtifacts = try await client.listArtifacts(workspaceId: workspaceId, documentId: document.id)
                if finishedTask.status == "succeeded" {
                    selectedOcrDocumentId = document.id
                    selectedOcrArtifacts = (try? await client.getOcrArtifacts(workspaceId: workspaceId, documentId: document.id).artifacts) ?? []
                    try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                    try? await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                }
                statusMessage = "Document processing complete."
            } catch {
                showError(error)
            }
        }
    }

    @discardableResult
    func startOpenClawChat(prompt rawPrompt: String) -> Bool {
        guard let activeSession = currentSessionOrError() else {
            return false
        }
        guard let workspaceId = selectedWorkspaceId else {
            errorMessage = "Please select or recover a workspace first."
            return false
        }
        guard !isOpenClawSending else { return false }
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            errorMessage = "Please enter an AI Co-pilot prompt."
            return false
        }

        let userMessage = OpenClawChatMessage(
            id: allocateOpenClawMessageId(),
            role: .user,
            content: prompt,
            status: .done,
            taskId: nil,
            progress: nil,
            events: []
        )
        let assistantMessageId = allocateOpenClawMessageId()
        let assistantMessage = OpenClawChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "Thinking...",
            status: .sending,
            taskId: nil,
            progress: 0,
            events: []
        )
        openClawMessages.append(contentsOf: [userMessage, assistantMessage])
        isOpenClawSending = true
        errorMessage = nil
        statusMessage = ""

        Task {
            var latestEvents: [TaskEventItem] = []
            do {
                let task = try await clientFor(activeSession).openClawChat(
                    workspaceId: workspaceId,
                    prompt: prompt,
                    conversationId: selectedConversationId
                )
                if let conversationId = task.payload?.objectStringValue(for: "conversation_id") {
                    selectedConversationId = conversationId
                }
                updateOpenClawMessage(assistantMessageId) {
                    $0.taskId = task.id
                    $0.progress = task.progress.clamped(to: 0...100)
                }
                let finishedTask = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] updatedTask, events in
                    latestEvents = events
                    self?.updateOpenClawMessage(assistantMessageId) {
                        $0.content = "Thinking..."
                        $0.taskId = updatedTask.id
                        $0.progress = updatedTask.progress.clamped(to: 0...100)
                        $0.events = events
                    }
                }
                if let conversationId = selectedConversationId {
                    try await refreshConversationMessages(activeSession: activeSession, workspaceId: workspaceId, conversationId: conversationId)
                    try? await refreshConversations(activeSession: activeSession, workspaceId: workspaceId)
                } else {
                    let answer = formatOpenClawTaskResult(finishedTask.resultText)
                    updateOpenClawMessage(assistantMessageId) {
                        $0.content = answer.isEmpty ? "No content returned." : answer
                        $0.status = .done
                        $0.progress = finishedTask.progress.clamped(to: 0...100)
                        $0.events = latestEvents
                    }
                }
            } catch {
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
            isOpenClawSending = false
        }
        return true
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
        selectedConversationId = conversationId
        openClawMessages = []
        Task {
            isChatHistoryLoading = true
            defer { isChatHistoryLoading = false }
            do {
                try await refreshConversationMessages(activeSession: activeSession, workspaceId: workspaceId, conversationId: conversationId)
            } catch {
                showError(error)
            }
        }
    }

    func startNewConversation() {
        selectedConversationId = nil
        openClawMessages = [welcomeChatMessage]
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
        errorMessage = nil
        statusMessage = "Saving conversation title..."
        Task {
            defer { isConversationMutating = false }
            do {
                let updated = try await clientFor(activeSession).updateConversation(workspaceId: workspaceId, conversationId: conversationId, title: trimmed)
                conversations = conversations.map { $0.id == updated.id ? updated : $0 }
                statusMessage = "Conversation title saved."
            } catch {
                showError(error)
            }
        }
    }

    func deleteCurrentConversation() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId, !isConversationMutating else { return }
        isConversationMutating = true
        errorMessage = nil
        statusMessage = "Deleting conversation..."
        Task {
            defer { isConversationMutating = false }
            do {
                try await clientFor(activeSession).deleteConversation(workspaceId: workspaceId, conversationId: conversationId)
                conversations.removeAll { $0.id == conversationId }
                selectedConversationId = conversations.first?.id
                openClawMessages = [welcomeChatMessage]
                statusMessage = "Conversation deleted."

                do {
                    try await refreshConversations(activeSession: activeSession, workspaceId: workspaceId)
                    if let nextConversationId = selectedConversationId {
                        try await refreshConversationMessages(
                            activeSession: activeSession,
                            workspaceId: workspaceId,
                            conversationId: nextConversationId
                        )
                    }
                } catch {
                    handlePostCommitRefreshFailure(error, completionKey: "operation.conversation_deleted")
                }
            } catch {
                showError(error)
            }
        }
    }

    func updateAIHistoryEnabled(_ enabled: Bool) {
        guard let activeSession = currentSessionOrError(), !isAIPreferenceUpdating else { return }
        let previous = aiHistoryEnabled
        aiHistoryEnabled = enabled
        isAIPreferenceUpdating = true
        errorMessage = nil
        statusMessage = "Saving AI history setting..."
        Task {
            defer { isAIPreferenceUpdating = false }
            do {
                let response = try await clientFor(activeSession).updateAIPreferences(aiHistoryEnabled: enabled)
                saveSession(activeSession.withAIHistoryEnabled(response.aiHistoryEnabled))
                statusMessage = "AI history setting saved."
            } catch {
                aiHistoryEnabled = previous
                showError(error)
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
        cancelStudyNoteEditing()
        selectedStudyNoteItem = item
        studyNoteMarkdown = nil
        studyNoteReaderError = nil

        if isOfflineTestMode, item.note.id == "note-1" {
            studyNoteMarkdown = """
            # Fractions & Ratios

            ## Key Concepts

            A fraction represents a part of a whole, while ratios compare the relationship between two quantities.

            - Antecedent and consequent terms of a ratio must use the same unit.
            - In a proportion, the product of the extremes equals the product of the means.

            > First convert to common units, then simplify and calculate.
            """
            return
        }

        guard let downloadURL = item.note.preferredMarkdownDownloadURL, !downloadURL.isEmpty else {
            if item.note.jsonDownloadURL != nil {
                selectedStudyNoteItem = nil
                downloadAndPreview(item.note)
            } else {
                studyNoteReaderError = "This note has no available Markdown content."
            }
            return
        }
        guard let activeSession = currentSessionOrError() else { return }

        isStudyNoteLoading = true
        Task {
            defer { isStudyNoteLoading = false }
            do {
                let markdown = try await loadStudyNoteMarkdown(activeSession: activeSession, note: item.note)
                guard selectedStudyNoteItem?.id == item.id else { return }
                studyNoteMarkdown = markdown
                statusMessage = "Note loaded."
            } catch {
                guard selectedStudyNoteItem?.id == item.id else { return }
                studyNoteReaderError = friendlyError(error)
            }
        }
    }

    func closeStudyNoteReader() {
        cancelStudyNoteEditing()
        selectedStudyNoteItem = nil
        studyNoteMarkdown = nil
        studyNoteReaderError = nil
        isStudyNoteLoading = false
    }

    var canEditSelectedStudyNote: Bool {
        guard let item = selectedStudyNoteItem,
              let group = studyNoteGroups.first(where: { $0.learningUnit.id == item.learningUnit.id }) else {
            return false
        }
        return group.notes.first?.id == item.id && studyNoteMarkdown != nil && !isStudyNoteLoading
    }

    func beginStudyNoteEditing() {
        guard canEditSelectedStudyNote, let item = selectedStudyNoteItem, let markdown = studyNoteMarkdown else {
            studyNoteReaderError = "Only the latest loaded note version can be edited."
            return
        }
        studyNoteDraftTitle = item.note.title
        studyNoteDraftMarkdown = markdown
        studyNoteDraftSummary = "Manual Edit"
        studyNoteEditorError = nil
        isStudyNoteConflictPending = false
        isStudyNoteEditorPresented = true
    }

    func cancelStudyNoteEditing() {
        isStudyNoteEditorPresented = false
        studyNoteDraftTitle = ""
        studyNoteDraftMarkdown = ""
        studyNoteDraftSummary = "Manual Edit"
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

        let markdown = studyNoteDraftMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = studyNoteDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = studyNoteDraftSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else {
            studyNoteEditorError = "Note content cannot be empty."
            return
        }
        guard markdown.count <= 2_000_000 else {
            studyNoteEditorError = "Note content cannot exceed 2,000,000 characters."
            return
        }
        guard title.isEmpty || title.count <= 255 else {
            studyNoteEditorError = "Title cannot exceed 255 characters."
            return
        }
        guard summary.isEmpty || summary.count <= 500 else {
            studyNoteEditorError = "Revision summary cannot exceed 500 characters."
            return
        }

        isStudyNoteSaving = true
        studyNoteEditorError = nil
        errorMessage = nil
        Task {
            defer { isStudyNoteSaving = false }
            let input = StudyNoteRevisionInput(
                markdown: markdown,
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
                let optimisticItem = StudyNoteListItem(learningUnit: item.learningUnit, note: response.note)
                selectedStudyNoteItem = optimisticItem
                studyNoteMarkdown = markdown
                isStudyNoteEditorPresented = false
                statusMessage = "New note version saved."

                do {
                    let refreshedItems = try await refreshStudyNoteGroup(
                        activeSession: activeSession,
                        workspaceId: workspaceId,
                        learningUnit: item.learningUnit
                    )
                    if let refreshed = refreshedItems.first(where: { $0.note.id == response.note.id }) {
                        selectedStudyNoteItem = refreshed
                    }
                } catch {
                    handlePostCommitRefreshFailure(error, completionKey: "operation.note_revision_saved")
                }
            } catch let error as LearningBackendError where error.statusCode == 409 {
                await handleStudyNoteRevisionConflict(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    learningUnit: item.learningUnit,
                    originalError: error,
                    afterConflictConfirmation: afterConflictConfirmation
                )
            } catch {
                studyNoteEditorError = friendlyError(error)
                if let backendError = error as? LearningBackendError,
                   backendError.shouldClearSession || backendError.statusCode == 403 {
                    showError(error)
                }
            }
        }
    }

    func selectLearningUnit(_ learningUnitId: String) {
        selectedLearningUnitId = learningUnitId
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isLearningLoading = true
            defer { isLearningLoading = false }
            do {
                studyNotes = try await clientFor(activeSession).listStudyNotes(workspaceId: workspaceId, learningUnitId: learningUnitId)
            } catch {
                showError(error)
            }
        }
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
        let query = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "Please enter a knowledge search query."
            return
        }
        guard query.count <= 8000 else {
            errorMessage = "Knowledge search query cannot exceed 8,000 characters."
            return
        }
        knowledgeLimit = knowledgeLimit.clamped(to: 1...20)
        Task {
            isKnowledgeSearching = true
            errorMessage = nil
            defer { isKnowledgeSearching = false }
            do {
                let response = try await clientFor(activeSession).searchKnowledge(
                    workspaceId: workspaceId,
                    query: query,
                    learningUnitId: knowledgeLearningUnitId.nilIfBlank,
                    subject: knowledgeSubject.nilIfBlank,
                    limit: knowledgeLimit
                )
                knowledgeResults = response.items
                hasSearchedKnowledge = true
                if response.items.isEmpty {
                    statusMessage = "No matching results in the knowledge base."
                } else {
                    setStatus("knowledge.results_found", String(response.items.count))
                }
            } catch {
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
            defer { isBusy = false }
            do {
                let document = try await clientFor(activeSession).getDocument(workspaceId: workspaceId, documentId: documentId)
                downloadAndPreview(document)
            } catch {
                showError(error)
            }
        }
    }

    func selectHomework(_ homeworkId: String) {
        selectedHomeworkId = homeworkId
        homeworkReferences = []
        lastGradingTask = nil
        if let homework = homeworks.first(where: { $0.id == homeworkId }) {
            homeworkRubricText = homework.rubricText ?? ""
            homeworkMaxScoreText = formatScore(homework.maxScore)
        }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isHomeworkLoading = true
            defer { isHomeworkLoading = false }
            do {
                homeworkReferences = try await clientFor(activeSession).listHomeworkReferences(workspaceId: workspaceId, homeworkId: homeworkId)
            } catch {
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
        maxScoreText: String
    ) -> Bool {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return false }
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
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            defer { isHomeworkLoading = false }
            do {
                let homework = try await clientFor(activeSession).createHomework(workspaceId: workspaceId, input: input)
                try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                selectHomework(homework.id)
                statusMessage = "Homework created."
            } catch {
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
        isHomeworkLoading = true
        errorMessage = nil
        statusMessage = "Saving grading configuration..."
        Task {
            defer { isHomeworkLoading = false }
            do {
                let updated = try await clientFor(activeSession).updateGradingConfig(workspaceId: workspaceId, homeworkId: homeworkId, input: input)
                homeworks = homeworks.map { $0.id == updated.id ? updated : $0 }
                homeworkRubricText = updated.rubricText ?? ""
                homeworkMaxScoreText = formatScore(updated.maxScore)
                lastGradingTask = nil
                statusMessage = "Grading configuration saved. Please re-grade."
            } catch {
                showError(error)
            }
        }
    }

    func addHomeworkReference(documentId: String) {
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
                homeworkReferences.append(reference)
                lastGradingTask = nil
                statusMessage = "Reference added. Please re-grade."
            } catch {
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
                homeworkReferences.removeAll { $0.id == reference.id }
                lastGradingTask = nil
                statusMessage = "Reference removed. Please re-grade."
                do {
                    homeworkReferences = try await client.listHomeworkReferences(workspaceId: workspaceId, homeworkId: homeworkId)
                } catch {
                    handlePostCommitRefreshFailure(error, completionKey: "operation.reference_removed")
                }
            } catch {
                showError(error)
            }
        }
    }

    func gradeSelectedHomework() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId else { return }
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            taskEvents = []
            lastGradingTask = nil
            defer { isHomeworkLoading = false }
            do {
                let task = try await clientFor(activeSession).gradeHomework(workspaceId: workspaceId, homeworkId: homeworkId)
                activeTask = task
                selectedTab = .documents
                selectedDocumentsSection = .tasks
                let finished = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                    self?.setStatus(
                        "grading.task_progress",
                        statusLabel(task.status),
                        String(task.progress.clamped(to: 0...100))
                    )
                }
                lastGradingTask = finished
                try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "Homework grading complete."
            } catch {
                showError(error)
            }
        }
    }

    func downloadAndPreview(_ note: StudyNoteVersion) {
        let markdownURL = note.preferredMarkdownDownloadURL
        let downloadURL = markdownURL ?? note.jsonDownloadURL
        guard let activeSession = currentSessionOrError(), let downloadURL, !downloadURL.isEmpty else {
            errorMessage = "This note has no available preview link."
            return
        }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let isMarkdown = markdownURL != nil
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: "\(note.title.isEmpty ? note.id : note.title).\(isMarkdown ? "md" : "json")",
                    mimeType: isMarkdown ? "text/markdown" : "application/json",
                    completionMessage: "Study note downloaded."
                )
            } catch {
                showError(error)
            }
        }
    }

    func loadArtifacts(for document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Loading artifacts..."
            do {
                selectedArtifactDocumentId = document.id
                selectedArtifacts = try await clientFor(activeSession).listArtifacts(workspaceId: workspaceId, documentId: document.id)
                statusMessage = "Artifacts loaded."
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func loadOcrArtifacts(for document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Loading OCR results..."
            do {
                selectedOcrDocumentId = document.id
                selectedOcrArtifacts = try await clientFor(activeSession)
                    .getOcrArtifacts(workspaceId: workspaceId, documentId: document.id, includeDownloadURL: true)
                    .artifacts
                statusMessage = selectedOcrArtifacts.isEmpty ? "No OCR results yet." : "OCR results loaded."
            } catch {
                showError(error)
            }
            isBusy = false
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
            defer { isBusy = false }
            do {
                let client = clientFor(activeSession)
                let response = try await client.deleteDocument(workspaceId: workspaceId, documentId: documentId)
                deletionAccepted = true
                retryableDocumentPurgeId = response.documentId
                removeDeletedDocumentFromLocalState(response.documentId)
                selectedTab = .documents
                selectedDocumentsSection = .tasks
                statusMessage = "Document deleted. Cleaning up original and derivative data..."

                let initialTask = try await client.getTask(workspaceId: workspaceId, taskId: response.purgeTaskId)
                activeTask = initialTask
                let finishedTask = try await pollTask(
                    activeSession: activeSession,
                    workspaceId: workspaceId,
                    taskId: response.purgeTaskId
                ) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                    self?.setStatus(
                        "document.cleanup_progress",
                        statusLabel(task.status),
                        String(task.progress.clamped(to: 0...100))
                    )
                }

                guard finishedTask.status == "succeeded" else { return }
                retryableDocumentPurgeId = nil
                isDocumentPurgeRetryAvailable = false
                statusMessage = "Document and derivative data cleanup complete."
                if let refreshError = await refreshAfterDocumentDeletion(activeSession: activeSession, workspaceId: workspaceId) {
                    handlePostCommitRefreshFailure(refreshError, completionKey: "operation.document_cleanup_completed")
                }
            } catch {
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
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) downloaded."
                )
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func downloadAndPreview(_ artifact: OcrArtifactItem) {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        guard let downloadURL = artifact.downloadURL, !downloadURL.isEmpty else {
            errorMessage = "OCR artifact has no available download link. Please reload OCR results."
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Downloading OCR results..."
            do {
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: defaultArtifactFilename(type: artifact.artifactType, mimeType: artifact.mimeType, fallback: artifact.id),
                    mimeType: artifact.mimeType,
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) downloaded."
                )
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func downloadAndPreview(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "Fetching download link..."
            do {
                let client = clientFor(activeSession)
                let response = try await client.getDownloadURL(workspaceId: workspaceId, documentId: document.id)
                statusMessage = "Downloading file..."
                let directory = cacheDirectory.appendingPathComponent("downloads", isDirectory: true)
                let targetURL = directory.appendingPathComponent(sanitizeFileName(document.originalFilename))
                let downloadedURL = try await client.download(downloadURL: response.downloadURL, targetURL: targetURL)
                downloadedPreview = DownloadedPreview(url: downloadedURL, mimeType: document.mimeType ?? contentTypeForFilename(document.originalFilename))
                statusMessage = document.mimeType?.hasPrefix("image/") == true ? "Image downloaded." : "File downloaded."
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    private func downloadAndPreview(
        client: LearningBackendClient,
        downloadURL: String,
        filename: String,
        mimeType: String?,
        completionMessage: String
    ) async throws {
        statusMessage = "Downloading file..."
        let directory = cacheDirectory.appendingPathComponent("downloads", isDirectory: true)
        let safeFilename = sanitizeFileName(filename)
        let targetURL = directory.appendingPathComponent(safeFilename)
        let downloadedURL = try await client.download(downloadURL: downloadURL, targetURL: targetURL)
        downloadedPreview = DownloadedPreview(url: downloadedURL, mimeType: mimeType ?? contentTypeForFilename(safeFilename))
        statusMessage = completionMessage
    }

    private func shouldForceReprocess(_ document: LearningDocumentItem) -> Bool {
        document.status == "ready" || document.status == "failed"
    }

    private func isProcessableDocument(_ document: LearningDocumentItem) -> Bool {
        document.status == "uploaded" || document.status == "ready" || document.status == "failed"
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
            LearningDocumentItem(id: "answer-doc", workspaceId: "ui-workspace", title: "Answer Key", originalFilename: "answer.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "answer_key", status: "ready")
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
        learningUnits = [LearningUnit(id: "unit-1", title: "Fractions & Ratios", subject: "Mathematics", gradeLevel: "Grade 7", topic: "Ratios")]
        studyNotes = [StudyNoteVersion(id: "note-1", learningUnitId: "unit-1", versionNo: 1, title: "Fractions & Ratios Notes", markdownObjectKey: "", jsonObjectKey: "", highlightedObjectKey: nil, highlightMapObjectKey: nil, downloadURLs: [:])]
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
                    events: []
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
        invalidateDeferredContentLoads()
        settings.clearSession()
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
        conversations = []
        selectedConversationId = nil
        openClawMessages = [welcomeChatMessage]
        openClawComposerState.clearDraft(removeAttachmentFiles: true)
        isOpenClawSending = false
        isChatHistoryLoading = false
        isConversationMutating = false
        isAIPreferenceUpdating = false
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
                        return (index, notes.isEmpty ? nil : StudyNoteGroup(learningUnit: unit, notes: notes), nil)
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

    private func refreshWorkspaceContent(activeSession: SavedSession, workspaceId: String) async throws {
        documents = try await clientFor(activeSession).listDocuments(
            workspaceId: workspaceId,
            status: statusFilter.isEmpty ? nil : statusFilter,
            documentKind: documentKindFilter.isEmpty ? nil : documentKindFilter,
            fileType: fileTypeFilter.isEmpty ? nil : fileTypeFilter
        )
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
        if user.email != activeSession.email || user.fullName != activeSession.fullName || user.aiHistoryEnabled != activeSession.aiHistoryEnabled {
            saveSession(
                SavedSession(
                    baseURL: activeSession.baseURL,
                    tusBaseURL: activeSession.tusBaseURL,
                    accessToken: activeSession.accessToken,
                    refreshToken: activeSession.refreshToken,
                    expiresAt: activeSession.expiresAt,
                    userId: user.id,
                    email: user.email,
                    fullName: user.fullName,
                    selectedWorkspaceId: activeSession.selectedWorkspaceId,
                    aiHistoryEnabled: user.aiHistoryEnabled
                )
            )
        }

        var loadedWorkspaces = try await client.listWorkspaces()
        if loadedWorkspaces.isEmpty {
            do {
                loadedWorkspaces = [try await client.createWorkspace(name: defaultPersonalWorkspaceName)]
            } catch let error as LearningBackendError where error.statusCode == 409 {
                loadedWorkspaces = try await client.listWorkspaces()
            }
        }
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
        var pollCount = 0
        var lastPublishedTask: TaskItem?
        var lastPublishedEvents: [TaskEventItem]?
        while pollCount < taskMaxPolls {
            let task = try await client.getTask(workspaceId: workspaceId, taskId: taskId)
            let events = (try? await client.getTaskEvents(workspaceId: workspaceId, taskId: taskId)) ?? []
            if task != lastPublishedTask || events != lastPublishedEvents {
                onUpdate(task, events)
                lastPublishedTask = task
                lastPublishedEvents = events
            }
            switch task.status {
            case "succeeded":
                return task
            case "failed":
                throw LearningBackendError(task.errorMessage ?? "Task \(task.status).")
            case "cancelled":
                let cancellationReason = events.last(where: { $0.eventType.contains("cancel") })?.message
                    ?? events.last(where: { $0.level == "error" })?.message
                    ?? events.last?.message
                    ?? task.errorMessage
                    ?? "Task cancelled."
                throw LearningBackendError(cancellationReason)
            default:
                pollCount += 1
                try await Task.sleep(nanoseconds: taskPollIntervalNanoseconds)
            }
        }
        throw LearningBackendError("Task timed out. Please refresh later to check.")
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
                sourceStatus: chatMessage.sourceStatus
            )
        }
        openClawMessages = messages.isEmpty ? [welcomeChatMessage] : messages
    }

    private func refreshLearningUnits(activeSession: SavedSession, workspaceId: String) async throws {
        learningUnits = try await clientFor(activeSession).listLearningUnits(workspaceId: workspaceId)
        if let selectedLearningUnitId, learningUnits.contains(where: { $0.id == selectedLearningUnitId }) {
            studyNotes = try await clientFor(activeSession).listStudyNotes(workspaceId: workspaceId, learningUnitId: selectedLearningUnitId)
        } else if selectedLearningUnitId != nil {
            self.selectedLearningUnitId = nil
            studyNotes = []
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
        let items = notes.map { StudyNoteListItem(learningUnit: learningUnit, note: $0) }
        let group = StudyNoteGroup(learningUnit: learningUnit, notes: items)
        if let index = studyNoteGroups.firstIndex(where: { $0.learningUnit.id == learningUnit.id }) {
            studyNoteGroups[index] = group
        } else if !items.isEmpty {
            studyNoteGroups.append(group)
        }
        if selectedLearningUnitId == learningUnit.id {
            studyNotes = notes
        }
        return items
    }

    private func loadStudyNoteMarkdown(activeSession: SavedSession, note: StudyNoteVersion) async throws -> String {
        guard let downloadURL = note.preferredMarkdownDownloadURL, !downloadURL.isEmpty else {
            throw LearningBackendError("This note has no available Markdown content.")
        }
        let filename = "\(note.id)-\(sanitizeFileName(note.title.isEmpty ? "study-note" : note.title)).md"
        let targetURL = cacheDirectory
            .appendingPathComponent("study-notes", isDirectory: true)
            .appendingPathComponent(filename)
        let downloadedURL = try await clientFor(activeSession).download(downloadURL: downloadURL, targetURL: targetURL)
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
                throw LearningBackendError("No note versions available on the server for revision.")
            }
            selectedStudyNoteItem = latest
            do {
                studyNoteMarkdown = try await loadStudyNoteMarkdown(activeSession: activeSession, note: latest.note)
            } catch {
                studyNoteReaderError = friendlyError(error)
            }
            studyNoteEditorError = afterConflictConfirmation
                ? "A newer version was generated on the server during save. Latest content refreshed; draft preserved."
                : "A newer note version is available. Latest content refreshed; draft preserved."
            isStudyNoteConflictPending = true
        } catch {
            studyNoteEditorError = "Refresh failed after version conflict: \(friendlyError(error))"
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
        let shouldPreserveDrafts = preserveGradingDrafts && isGradingConfigDirty
        let client = clientFor(activeSession)
        homeworks = try await client.listHomeworks(workspaceId: workspaceId)
        gradingDocuments = try await client.listDocuments(workspaceId: workspaceId, pageSize: 100)
        guard let selectedHomeworkId else { return }
        guard let selected = homeworks.first(where: { $0.id == selectedHomeworkId }) else {
            self.selectedHomeworkId = nil
            homeworkReferences = []
            return
        }
        if !shouldPreserveDrafts {
            homeworkRubricText = selected.rubricText ?? ""
            homeworkMaxScoreText = formatScore(selected.maxScore)
        }
        homeworkReferences = try await clientFor(activeSession).listHomeworkReferences(workspaceId: workspaceId, homeworkId: selectedHomeworkId)
    }

    private func clearLearningWorkspaceState() {
        invalidateDeferredContentLoads()
        queuedUploadItems.forEach {
            UploadThumbnailCache.shared.remove(file: $0.file)
            removeCachedUploadFile($0.file)
        }
        queuedUploadItems = []
        knowledgeResults = []
        hasSearchedKnowledge = false
        homeworks = []
        gradingDocuments = []
        selectedHomeworkId = nil
        homeworkReferences = []
        homeworkRubricText = ""
        homeworkMaxScoreText = "100"
        lastGradingTask = nil
        studyNoteGroups = []
        closeStudyNoteReader()
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
