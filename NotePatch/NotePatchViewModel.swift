import Foundation
import Combine
import SwiftUI
import UIKit

private let taskPollIntervalNanoseconds: UInt64 = 1_500_000_000
private let taskMaxPolls = 120
private let completeUploadMaxRetries = 5
private let defaultPresenceHeartbeatIntervalSeconds = 30
private let defaultPersonalWorkspaceName = "My Workspace"

enum WorkbenchTab: Int, CaseIterable, Identifiable {
    case documents
    case tasks
    case openClaw
    case learning
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .documents: return "文档"
        case .tasks: return "任务"
        case .openClaw: return "OpenClaw"
        case .learning: return "学习"
        case .settings: return "设置"
        }
    }

    var iconName: String {
        switch self {
        case .documents: return "doc.text"
        case .tasks: return "checklist"
        case .openClaw: return "bubble.left.and.bubble.right"
        case .learning: return "book.closed"
        case .settings: return "gearshape"
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
        case .units: return "单元"
        case .search: return "检索"
        case .grading: return "评分"
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
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var selectedTab: WorkbenchTab = .documents

    @Published var workspaces: [WorkspaceItem] = []
    @Published var selectedWorkspaceId: String?
    @Published var documents: [LearningDocumentItem] = []
    @Published var activeTask: TaskItem?
    @Published var taskEvents: [TaskEventItem] = []
    @Published var selectedArtifactDocumentId: String?
    @Published var selectedArtifacts: [DocumentArtifactItem] = []
    @Published var selectedOcrDocumentId: String?
    @Published var selectedOcrArtifacts: [OcrArtifactItem] = []

    @Published var uploadDocumentKind = "homework"
    @Published var statusFilter = ""
    @Published var documentKindFilter = ""
    @Published var fileTypeFilter = ""
    @Published var uploadProgressPercent: Int?
    @Published var uploadProgressLabel = ""
    @Published var openClawInput = ""
    @Published var openClawMessages: [OpenClawChatMessage] = [
        OpenClawChatMessage(
            id: "system",
            role: .system,
            content: "OpenClaw 可以帮你整理想法、分析文档结果，回复支持 Markdown。",
            status: .done,
            taskId: nil,
            progress: nil,
            events: []
        )
    ]
    @Published var isOpenClawSending = false
    @Published var aiHistoryEnabled = true
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: String?
    @Published var isChatHistoryLoading = false
    @Published var learningUnits: [LearningUnit] = []
    @Published var selectedLearningUnitId: String?
    @Published var studyNotes: [StudyNoteVersion] = []
    @Published var isLearningLoading = false
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
    @Published var pendingUploadFile: LocalUploadFile?

    private let settings: SettingsStore
    private let backendSession: URLSession
    private let tusSession: URLSession
    private let cacheDirectory: URL
    private var nextOpenClawMessageId: Int64 = 1
    private var presenceTask: Task<Void, Never>?
    private var didRestoreSession = false
    private var pendingUITestUploadFile: LocalUploadFile?

    convenience init() {
        self.init(settings: SettingsStore())
    }

    init(
        settings: SettingsStore,
        backendSession: URLSession = .shared,
        tusSession: URLSession = .shared,
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    ) {
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
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") {
            let uiSession = SavedSession(
                baseURL: defaultLearningBackendBaseURL,
                tusBaseURL: defaultTUSDBaseURL,
                accessToken: "ui-access",
                refreshToken: "ui-refresh",
                expiresAt: "2026-07-09T12:00:00Z",
                userId: "ui-user",
                email: "ui@example.com",
                fullName: "UI Test",
                selectedWorkspaceId: "ui-workspace",
                aiHistoryEnabled: true
            )
            self.session = uiSession
            self.apiBaseURLText = uiSession.baseURL
            self.tusBaseURLText = uiSession.tusBaseURL
            self.emailText = uiSession.email
            self.fullNameText = uiSession.fullName ?? ""
            self.selectedWorkspaceId = uiSession.selectedWorkspaceId
            self.workspaces = [WorkspaceItem(id: "ui-workspace", name: "My Workspace")]
            self.learningUnits = [LearningUnit(id: "unit-1", title: "分数与比例", subject: "数学", gradeLevel: "七年级", topic: "比例")]
            self.studyNotes = [StudyNoteVersion(id: "note-1", learningUnitId: "unit-1", versionNo: 1, title: "分数与比例笔记", markdownObjectKey: "", jsonObjectKey: "", highlightedObjectKey: nil, highlightMapObjectKey: nil, downloadURLs: [:])]
            self.homeworks = [HomeworkItem(id: "homework-1", workspaceId: "ui-workspace", title: "代数作业 01", documentId: nil, rubricText: "每题 10 分", maxScore: 100)]
            self.selectedHomeworkId = "homework-1"
            self.homeworkRubricText = "每题 10 分"
            self.gradingDocuments = [
                LearningDocumentItem(id: "homework-doc", workspaceId: "ui-workspace", title: "代数作业", originalFilename: "homework.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "homework", status: "ready"),
                LearningDocumentItem(id: "answer-doc", workspaceId: "ui-workspace", title: "参考答案", originalFilename: "answer.pdf", mimeType: "application/pdf", fileType: "pdf", documentKind: "answer_key", status: "ready")
            ]
            self.didRestoreSession = true
        }
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestPendingImage") {
            self.pendingUITestUploadFile = makeUITestPendingImage(in: cacheDirectory)
        }
    }

    func restoreIfNeeded() async {
        if let fixture = pendingUITestUploadFile {
            pendingUITestUploadFile = nil
            await Task.yield()
            pendingUploadFile = fixture
        }
        guard !didRestoreSession, let activeSession = session else {
            return
        }
        didRestoreSession = true
        isBusy = true
        statusMessage = "正在恢复登录状态..."
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
            if let session {
                startPresence(activeSession: session)
            }
        case .background, .inactive:
            stopPresence(activeSession: session, sendOffline: true, clearClientId: false)
        @unknown default:
            break
        }
    }

    func checkAPIConnection() {
        let baseURL = normalizedAPIBaseURL()
        apiBaseURLText = baseURL
        settings.saveBaseURL(baseURL)
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在检测 API..."
            do {
                _ = try await LearningBackendClient(baseURL: baseURL, session: backendSession).healthCheck()
                statusMessage = "API 连接正常。"
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
            statusMessage = "正在检测 tusd..."
            do {
                try await TusUploader.checkEndpoint(tusBaseURL, session: tusSession)
                statusMessage = "tusd 连接正常。"
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func authenticate(register: Bool) {
        let baseURL = normalizedAPIBaseURL()
        let tusBaseURL = normalizedTUSBaseURL()
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordText
        let fullName = fullNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || password.isEmpty {
            errorMessage = "请输入邮箱和密码。"
            return
        }
        if register, password.count < 8 {
            errorMessage = "注册密码至少需要 8 位。"
            return
        }

        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = register ? "正在注册..." : "正在登录..."
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
                statusMessage = "正在加载个人空间..."
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
        statusMessage = "服务器地址已保存。"
        errorMessage = nil
    }

    func logout() {
        let activeSession = session
        stopPresence(activeSession: activeSession, sendOffline: true, clearClientId: true)
        clearLocalSession()
        statusMessage = ""
        errorMessage = nil
        if let activeSession {
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
            errorMessage = "请先选择或恢复个人空间。"
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在刷新文档..."
            do {
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "文档已刷新。"
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
            statusMessage = "正在切换个人空间..."
            do {
                try await refreshWorkspaceContent(activeSession: session ?? activeSession, workspaceId: workspaceId)
                let name = workspaces.first(where: { $0.id == workspaceId })?.name ?? workspaceId
                statusMessage = "已切换到 \(name)。"
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
            statusMessage = "正在恢复个人空间..."
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
                statusMessage = "个人空间已恢复。"
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
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在读取文件..."
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let uploadFile = try copyFileToUploadCache(
                    sourceURL: sourceURL,
                    fallbackPrefix: "file",
                    cacheDirectory: cacheDirectory,
                    suggestedMimeType: contentTypeForFilename(sourceURL.lastPathComponent)
                )
                isBusy = false
                stageUploadFileForPreview(uploadFile)
            } catch {
                showError(error)
                isBusy = false
            }
        }
    }

    func uploadPhotoData(_ data: Data, suggestedFilename: String, mimeType: String?) {
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在读取图片..."
            do {
                let uploadFile = try writePhotoDataToUploadCache(
                    data,
                    suggestedFilename: suggestedFilename,
                    mimeType: mimeType,
                    cacheDirectory: cacheDirectory
                )
                isBusy = false
                stageUploadFileForPreview(uploadFile)
            } catch {
                showError(error)
                isBusy = false
            }
        }
    }

    func uploadCameraImage(_ image: UIImage) {
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在读取图片..."
            do {
                let uploadFile = try writeImageToUploadCache(image, cacheDirectory: cacheDirectory)
                isBusy = false
                stageUploadFileForPreview(uploadFile)
            } catch {
                showError(error)
                isBusy = false
            }
        }
    }

    func stageUploadFileForPreview(_ uploadFile: LocalUploadFile) {
        removeCachedUploadFile(pendingUploadFile)
        pendingUploadFile = uploadFile
        errorMessage = nil
        statusMessage = "已选择 \(uploadFile.filename)，请确认上传。"
    }

    func confirmPendingUpload() {
        guard session != nil else {
            errorMessage = "登录状态已失效，请重新登录。"
            return
        }
        guard selectedWorkspaceId != nil else {
            errorMessage = "请先选择或恢复个人空间。"
            return
        }
        guard let uploadFile = pendingUploadFile else {
            return
        }
        pendingUploadFile = nil
        uploadDocument(uploadFile)
    }

    func discardPendingUpload() {
        let discardedName = pendingUploadFile?.filename
        removeCachedUploadFile(pendingUploadFile)
        pendingUploadFile = nil
        if discardedName != nil {
            errorMessage = nil
            statusMessage = "已取消本次上传。"
        }
    }

    func uploadDocument(_ localUploadFile: LocalUploadFile) {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        guard let workspaceId = selectedWorkspaceId else {
            errorMessage = "请先选择或恢复个人空间。"
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            uploadProgressPercent = 0
            uploadProgressLabel = localUploadFile.filename
            statusMessage = "正在准备文件..."
            defer {
                uploadProgressPercent = nil
                uploadProgressLabel = ""
                isBusy = false
            }
            do {
                let prepared = try prepareUploadFile(localUploadFile, cacheDirectory: cacheDirectory)
                let client = clientFor(activeSession)
                statusMessage = "正在创建上传会话..."
                let uploadSession = try await client.createUploadSession(
                    workspaceId: workspaceId,
                    filename: prepared.filename,
                    mimeType: prepared.mimeType ?? "application/octet-stream",
                    fileSize: prepared.fileSize,
                    documentKind: uploadDocumentKind,
                    learningMetadata: uploadLearningMetadata
                )
                statusMessage = "正在 tus 上传..."
                let endpoint = uploadSession.tusEndpoint.isEmpty ? activeSession.tusBaseURL : uploadSession.tusEndpoint
                let tusResult = try await TusUploader(session: tusSession).upload(
                    fileURL: prepared.url,
                    endpoint: endpoint,
                    metadataHeader: uploadSession.tusMetadataHeader
                ) { [weak self] uploaded, total in
                    let progress = total <= 0 ? 0 : Int((uploaded * 100) / total).clamped(to: 0...100)
                    await MainActor.run {
                        self?.uploadProgressPercent = progress
                        self?.statusMessage = "正在 tus 上传：\(progress)%"
                    }
                }
                statusMessage = "正在确认上传..."
                _ = try await completeUploadWithRetry(
                    client: client,
                    workspaceId: workspaceId,
                    uploadSession: uploadSession,
                    tusResult: tusResult,
                    file: prepared
                )
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "文档上传完成。"
            } catch {
                showError(error)
            }
        }
    }

    func startProcessing(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            taskEvents = []
            statusMessage = "正在触发文档处理..."
            do {
                let client = clientFor(activeSession)
                let task = try await client.processDocument(
                    workspaceId: workspaceId,
                    documentId: document.id,
                    forceReprocess: shouldForceReprocess(document)
                )
                activeTask = task
                selectedTab = .tasks
                let finishedTask = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] updatedTask, events in
                    self?.activeTask = updatedTask
                    self?.taskEvents = events
                    self?.statusMessage = "任务 \(updatedTask.status)：\(updatedTask.progress.clamped(to: 0...100))%"
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
                statusMessage = "文档处理完成。"
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func startOpenClawChat() {
        guard let activeSession = currentSessionOrError() else {
            return
        }
        guard let workspaceId = selectedWorkspaceId else {
            errorMessage = "请先选择或恢复个人空间。"
            return
        }
        let prompt = openClawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            errorMessage = "请输入 OpenClaw prompt。"
            return
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
            content: "思考中...",
            status: .sending,
            taskId: nil,
            progress: 0,
            events: []
        )
        openClawMessages.append(contentsOf: [userMessage, assistantMessage])
        openClawInput = ""

        Task {
            isOpenClawSending = true
            errorMessage = nil
            statusMessage = ""
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
                        $0.content = "思考中..."
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
                        $0.content = answer.isEmpty ? "没有返回内容。" : answer
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
                let message = [friendlyError(error), eventMessage.map { "最近事件：\($0)" }]
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

    func loadChatHistory() {
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isChatHistoryLoading = true
            defer { isChatHistoryLoading = false }
            do {
                try await refreshConversations(activeSession: activeSession, workspaceId: workspaceId)
                if let conversationId = selectedConversationId {
                    try await refreshConversationMessages(activeSession: activeSession, workspaceId: workspaceId, conversationId: conversationId)
                } else {
                    openClawMessages = [welcomeChatMessage]
                }
            } catch {
                showError(error)
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
        openClawInput = ""
    }

    func renameCurrentConversation(to title: String) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let updated = try await clientFor(activeSession).updateConversation(workspaceId: workspaceId, conversationId: conversationId, title: trimmed)
                conversations = conversations.map { $0.id == updated.id ? updated : $0 }
            } catch {
                showError(error)
            }
        }
    }

    func deleteCurrentConversation() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let conversationId = selectedConversationId else { return }
        Task {
            do {
                try await clientFor(activeSession).deleteConversation(workspaceId: workspaceId, conversationId: conversationId)
                conversations.removeAll { $0.id == conversationId }
                if let next = conversations.first {
                    selectConversation(next.id)
                } else {
                    startNewConversation()
                }
            } catch {
                showError(error)
            }
        }
    }

    func updateAIHistoryEnabled(_ enabled: Bool) {
        guard let activeSession = currentSessionOrError() else { return }
        let previous = aiHistoryEnabled
        aiHistoryEnabled = enabled
        Task {
            do {
                let response = try await clientFor(activeSession).updateAIPreferences(aiHistoryEnabled: enabled)
                saveSession(activeSession.withAIHistoryEnabled(response.aiHistoryEnabled))
            } catch {
                aiHistoryEnabled = previous
                showError(error)
            }
        }
    }

    func loadLearningUnits() {
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") { return }
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

    func loadLearningDashboard() {
        if ProcessInfo.processInfo.arguments.contains("-NotePatchUITestWorkbench") { return }
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        Task {
            isLearningLoading = true
            isHomeworkLoading = true
            defer {
                isLearningLoading = false
                isHomeworkLoading = false
            }
            var firstError: Error?
            do { try await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId) }
            catch { firstError = error }
            do { try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId) }
            catch { if firstError == nil { firstError = error } }
            if let firstError { showError(firstError) }
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
        return lastGradingTask.result?.objectStringValue(for: "grading_mode") == "official" ? "正式评分" : "诊断性评分"
    }

    var gradingConfidence: Double? {
        lastGradingTask?.result?.objectDoubleValue(for: "confidence")
    }

    func searchKnowledge() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else { return }
        let query = knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "请输入知识检索内容。"
            return
        }
        guard query.count <= 8000 else {
            errorMessage = "知识检索内容不能超过 8000 个字符。"
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
                statusMessage = response.items.isEmpty ? "知识库暂无匹配内容。" : "找到 \(response.items.count) 条相关内容。"
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
            errorMessage = "请选择已处理完成的作业文档。"
            return false
        }
        guard !trimmedTitle.isEmpty else {
            errorMessage = "请输入作业标题。"
            return false
        }
        guard let maxScore = Double(maxScoreText), maxScore > 0 else {
            errorMessage = "满分必须大于 0。"
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
                statusMessage = "作业已创建。"
            } catch {
                showError(error)
            }
        }
        return true
    }

    func saveGradingConfig() {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId else { return }
        guard let maxScore = Double(homeworkMaxScoreText), maxScore > 0 else {
            errorMessage = "满分必须大于 0。"
            return
        }
        let input = GradingConfigInput(rubricText: homeworkRubricText.nilIfBlank, maxScore: maxScore)
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            defer { isHomeworkLoading = false }
            do {
                let updated = try await clientFor(activeSession).updateGradingConfig(workspaceId: workspaceId, homeworkId: homeworkId, input: input)
                homeworks = homeworks.map { $0.id == updated.id ? updated : $0 }
                homeworkRubricText = updated.rubricText ?? ""
                homeworkMaxScoreText = formatScore(updated.maxScore)
                statusMessage = "评分配置已保存。"
            } catch {
                showError(error)
            }
        }
    }

    func addHomeworkReference(documentId: String) {
        guard let document = referenceDocumentCandidates.first(where: { $0.id == documentId }),
              let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId else { return }
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            defer { isHomeworkLoading = false }
            do {
                let reference = try await clientFor(activeSession).addHomeworkReference(
                    workspaceId: workspaceId,
                    homeworkId: homeworkId,
                    documentId: document.id,
                    referenceType: document.documentKind
                )
                homeworkReferences.append(reference)
                statusMessage = "评分依据已添加。"
            } catch {
                showError(error)
            }
        }
    }

    func deleteHomeworkReference(_ reference: HomeworkReferenceItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId,
              let homeworkId = selectedHomeworkId else { return }
        Task {
            isHomeworkLoading = true
            errorMessage = nil
            defer { isHomeworkLoading = false }
            do {
                try await clientFor(activeSession).deleteHomeworkReference(workspaceId: workspaceId, homeworkId: homeworkId, referenceId: reference.id)
                homeworkReferences.removeAll { $0.id == reference.id }
                statusMessage = "评分依据已删除。"
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
            defer { isHomeworkLoading = false }
            do {
                let task = try await clientFor(activeSession).gradeHomework(workspaceId: workspaceId, homeworkId: homeworkId)
                activeTask = task
                selectedTab = .tasks
                let finished = try await pollTask(activeSession: activeSession, workspaceId: workspaceId, taskId: task.id) { [weak self] task, events in
                    self?.activeTask = task
                    self?.taskEvents = events
                    self?.statusMessage = "评分任务 \(task.status)：\(task.progress.clamped(to: 0...100))%"
                }
                lastGradingTask = finished
                try await refreshHomeworks(activeSession: activeSession, workspaceId: workspaceId)
                try? await refreshLearningUnits(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "作业评分完成。"
            } catch {
                showError(error)
            }
        }
    }

    func downloadAndPreview(_ note: StudyNoteVersion) {
        guard let activeSession = currentSessionOrError(), let downloadURL = note.preferredDownloadURL, !downloadURL.isEmpty else {
            errorMessage = "当前笔记没有可用预览链接。"
            return
        }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: "\(note.title.isEmpty ? note.id : note.title).md",
                    mimeType: "text/markdown",
                    completionMessage: "学习笔记已下载。"
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
            statusMessage = "正在加载 artifacts..."
            do {
                selectedArtifactDocumentId = document.id
                selectedArtifacts = try await clientFor(activeSession).listArtifacts(workspaceId: workspaceId, documentId: document.id)
                statusMessage = "artifacts 已加载。"
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
            statusMessage = "正在加载 OCR 结果..."
            do {
                selectedOcrDocumentId = document.id
                selectedOcrArtifacts = try await clientFor(activeSession)
                    .getOcrArtifacts(workspaceId: workspaceId, documentId: document.id, includeDownloadURL: true)
                    .artifacts
                statusMessage = selectedOcrArtifacts.isEmpty ? "暂无 OCR 结果。" : "OCR 结果已加载。"
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func deleteDocument(_ document: LearningDocumentItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在删除文档..."
            do {
                try await clientFor(activeSession).deleteDocument(workspaceId: workspaceId, documentId: document.id)
                if selectedArtifactDocumentId == document.id {
                    selectedArtifactDocumentId = nil
                    selectedArtifacts = []
                }
                if selectedOcrDocumentId == document.id {
                    selectedOcrDocumentId = nil
                    selectedOcrArtifacts = []
                }
                gradingDocuments.removeAll { $0.id == document.id }
                homeworkReferences.removeAll { $0.documentId == document.id }
                try await refreshWorkspaceContent(activeSession: activeSession, workspaceId: workspaceId)
                statusMessage = "文档已删除。"
            } catch {
                showError(error)
            }
            isBusy = false
        }
    }

    func downloadAndPreview(_ artifact: DocumentArtifactItem) {
        guard let activeSession = currentSessionOrError(), let workspaceId = selectedWorkspaceId else {
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在获取 artifact 下载链接..."
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
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) 已下载。"
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
            errorMessage = "OCR artifact 没有可用下载链接，请重新加载 OCR 结果。"
            return
        }
        Task {
            isBusy = true
            errorMessage = nil
            statusMessage = "正在下载 OCR 结果..."
            do {
                try await downloadAndPreview(
                    client: clientFor(activeSession),
                    downloadURL: downloadURL,
                    filename: defaultArtifactFilename(type: artifact.artifactType, mimeType: artifact.mimeType, fallback: artifact.id),
                    mimeType: artifact.mimeType,
                    completionMessage: "\(artifactTypeLabel(artifact.artifactType)) 已下载。"
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
            statusMessage = "正在获取下载链接..."
            do {
                let client = clientFor(activeSession)
                let response = try await client.getDownloadURL(workspaceId: workspaceId, documentId: document.id)
                statusMessage = "正在下载文件..."
                let directory = cacheDirectory.appendingPathComponent("downloads", isDirectory: true)
                let targetURL = directory.appendingPathComponent(sanitizeFileName(document.originalFilename))
                let downloadedURL = try await client.download(downloadURL: response.downloadURL, targetURL: targetURL)
                downloadedPreview = DownloadedPreview(url: downloadedURL, mimeType: document.mimeType ?? contentTypeForFilename(document.originalFilename))
                statusMessage = document.mimeType?.hasPrefix("image/") == true ? "图片已下载。" : "文件已下载。"
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
        statusMessage = "正在下载文件..."
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
            errorMessage = "请先登录或注册。"
            return nil
        }
        return session
    }

    private func showError(_ error: Error) {
        if let backendError = error as? LearningBackendError, backendError.shouldClearSession {
            clearLocalSession()
        } else if let backendError = error as? LearningBackendError, backendError.statusCode == 403 {
            recoverFromWorkspaceAccessDenied()
        }
        errorMessage = friendlyError(error)
        statusMessage = ""
    }

    private func recoverFromWorkspaceAccessDenied() {
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


    private func clearLocalSession() {
        presenceTask?.cancel()
        presenceTask = nil
        settings.clearSession()
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
        conversations = []
        selectedConversationId = nil
        openClawMessages = [welcomeChatMessage]
        learningUnits = []
        selectedLearningUnitId = nil
        studyNotes = []
        clearLearningWorkspaceState()
        aiHistoryEnabled = true
        passwordText = ""
        removeCachedUploadFile(pendingUploadFile)
        pendingUploadFile = nil
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
        settings.saveSession(updated)
        session = updated
        apiBaseURLText = updated.baseURL
        tusBaseURLText = updated.tusBaseURL
        emailText = updated.email
        fullNameText = updated.fullName ?? ""
        selectedWorkspaceId = updated.selectedWorkspaceId
        aiHistoryEnabled = updated.aiHistoryEnabled
    }

    private func saveSelectedWorkspace(_ workspaceId: String?) {
        selectedWorkspaceId = workspaceId
        settings.saveSelectedWorkspaceId(workspaceId)
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
        ) { [weak self] token in
            Task { @MainActor in
                self?.applyRefreshedToken(token, fallback: activeSession)
            }
        }
    }

    private func applyRefreshedToken(_ token: TokenResponse, fallback: SavedSession) {
        let current = settings.loadSession() ?? session ?? fallback
        saveSession(current.withTokenResponse(token))
    }

    private func startPresence(activeSession: SavedSession) {
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
                        self.statusMessage = "OpenClaw 在线状态同步失败，稍后自动重试。"
                    }
                    delayBeforeNextHeartbeat = UInt64(self.presenceDelayMillis(defaultPresenceHeartbeatIntervalSeconds)) * 1_000_000
                }
            }
        }
    }

    private func stopPresence(activeSession: SavedSession?, sendOffline: Bool, clearClientId: Bool) {
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
            statusMessage = "已加载个人空间：\(selected.name)"
        } else {
            documents = []
            statusMessage = "当前账号还没有个人空间，请在设置里尝试恢复。"
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
        while pollCount < taskMaxPolls {
            let task = try await client.getTask(workspaceId: workspaceId, taskId: taskId)
            let events = (try? await client.getTaskEvents(workspaceId: workspaceId, taskId: taskId)) ?? []
            onUpdate(task, events)
            switch task.status {
            case "succeeded":
                return task
            case "failed", "cancelled":
                throw LearningBackendError(task.errorMessage ?? "任务 \(task.status)。")
            default:
                pollCount += 1
                try await Task.sleep(nanoseconds: taskPollIntervalNanoseconds)
            }
        }
        throw LearningBackendError("等待任务完成超时，请稍后刷新查看。")
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
                statusMessage = "tusd 正在同步文件，等待后重试 \(attempt + 1)/\(completeUploadMaxRetries)..."
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw lastConflict ?? LearningBackendError("上传完成确认失败。")
    }

    private func allocateOpenClawMessageId() -> String {
        let id = nextOpenClawMessageId
        nextOpenClawMessageId += 1
        return "local-\(id)"
    }

    private func updateOpenClawMessage(_ messageId: String, transform: (inout OpenClawChatMessage) -> Void) {
        openClawMessages = openClawMessages.map { message in
            var updated = message
            if updated.id == messageId {
                transform(&updated)
            }
            return updated
        }
    }

    private var welcomeChatMessage: OpenClawChatMessage {
        OpenClawChatMessage(id: "system", role: .system, content: "OpenClaw 可以帮你整理想法、分析文档结果，回复支持 Markdown。", status: .done, taskId: nil, progress: nil, events: [])
    }

    private func refreshConversations(activeSession: SavedSession, workspaceId: String) async throws {
        let response = try await clientFor(activeSession).listConversations(workspaceId: workspaceId)
        conversations = response.items
        if let selectedConversationId, conversations.contains(where: { $0.id == selectedConversationId }) {
            return
        }
        selectedConversationId = conversations.first?.id
    }

    private func refreshConversationMessages(activeSession: SavedSession, workspaceId: String, conversationId: String) async throws {
        let response = try await clientFor(activeSession).listChatMessages(workspaceId: workspaceId, conversationId: conversationId)
        let messages = response.items.map { chatMessage -> OpenClawChatMessage in
            let role: OpenClawChatRole
            switch chatMessage.role {
            case "user": role = .user
            case "system": role = .system
            default: role = .assistant
            }
            let status: OpenClawMessageStatus = chatMessage.status == "failed" ? .error : (chatMessage.status == "queued" || chatMessage.status == "running" ? .sending : .done)
            let content: String
            if status == .sending { content = chatMessage.content.isEmpty ? "思考中..." : chatMessage.content }
            else if status == .error { content = chatMessage.errorMessage ?? chatMessage.content }
            else { content = chatMessage.content }
            return OpenClawChatMessage(id: chatMessage.id, role: role, content: content, status: status, taskId: chatMessage.taskId, progress: nil, events: [])
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

    private func refreshHomeworks(activeSession: SavedSession, workspaceId: String) async throws {
        let client = clientFor(activeSession)
        homeworks = try await client.listHomeworks(workspaceId: workspaceId)
        gradingDocuments = try await client.listDocuments(workspaceId: workspaceId, pageSize: 100)
        guard let selectedHomeworkId else { return }
        guard let selected = homeworks.first(where: { $0.id == selectedHomeworkId }) else {
            self.selectedHomeworkId = nil
            homeworkReferences = []
            return
        }
        homeworkRubricText = selected.rubricText ?? ""
        homeworkMaxScoreText = formatScore(selected.maxScore)
        homeworkReferences = try await clientFor(activeSession).listHomeworkReferences(workspaceId: workspaceId, homeworkId: selectedHomeworkId)
    }

    private func clearLearningWorkspaceState() {
        knowledgeResults = []
        hasSearchedKnowledge = false
        homeworks = []
        gradingDocuments = []
        selectedHomeworkId = nil
        homeworkReferences = []
        homeworkRubricText = ""
        homeworkMaxScoreText = "100"
        lastGradingTask = nil
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
