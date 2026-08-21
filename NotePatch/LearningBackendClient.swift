import Foundation

private struct RefreshFlightKey: Hashable {
    let baseURL: String
    let sessionIdentifier: ObjectIdentifier
    let refreshToken: String
}

private enum RelativeRequestScope {
    case service
    case api
}

@MainActor
private final class RefreshSingleFlight {
    static let shared = RefreshSingleFlight()
    private var tasks: [RefreshFlightKey: Task<TokenResponse, Error>] = [:]

    func value(
        for key: RefreshFlightKey,
        operation: @escaping @MainActor () async throws -> TokenResponse
    ) async throws -> TokenResponse {
        if let task = tasks[key] {
            return try await task.value
        }
        let task = Task { @MainActor in
            try await operation()
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

final class LearningBackendClient {
    private let normalizedBaseURL: String
    private var accessToken: String?
    private var refreshToken: String?
    private let onTokenRefreshed: ((TokenResponse, String) -> Void)?
    private let session: URLSession

    init(
        baseURL: String,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        session: URLSession = .shared,
        onTokenRefreshed: ((TokenResponse, String) -> Void)? = nil
    ) {
        self.normalizedBaseURL = normalizeLearningBackendBaseURL(baseURL)
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.session = session
        self.onTokenRefreshed = onTokenRefreshed
    }

    func healthCheck() async throws -> String {
        let (data, response) = try await data(
            for: request(method: "GET", pathOrURL: "/health", scope: .service)
        )
        try validate(response: response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func register(email: String, password: String, fullName: String?) async throws -> TokenResponse {
        var payload: [String: Any] = [
            "email": email,
            "password": password
        ]
        if let fullName, !fullName.isEmpty {
            payload["full_name"] = fullName
        }
        return try await postJSON("/auth/register", payload: payload, as: TokenResponse.self)
    }

    func login(email: String, password: String) async throws -> TokenResponse {
        try await postJSON(
            "/auth/login",
            payload: [
                "email": email,
                "password": password
            ],
            as: TokenResponse.self
        )
    }

    func me() async throws -> BackendUser {
        try await authedJSON("GET", "/auth/me", payload: nil, as: BackendUser.self)
    }

    func getUserProfile() async throws -> UserProfileSnapshot {
        let request = try request(method: "GET", pathOrURL: "/user/profile")
        let (data, response) = try await authedResponse(for: request, allowRefresh: true)
        let envelope = try await decode(APIResponseEnvelope<UserProfile>.self, from: data)
        return UserProfileSnapshot(
            profile: envelope.data,
            etag: response.value(forHTTPHeaderField: "ETag") ?? "\"profile-\(envelope.data.profileVersion)\""
        )
    }

    func updateUserProfile(
        etag: String,
        idempotencyKey: String,
        fields: [String: Any]
    ) async throws -> UserProfileSnapshot {
        var profileRequest = try request(method: "PUT", pathOrURL: "/user/profile")
        profileRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        profileRequest.setValue(etag, forHTTPHeaderField: "If-Match")
        profileRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        profileRequest.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await authedResponse(for: profileRequest, allowRefresh: true)
        let envelope = try await decode(APIResponseEnvelope<UserProfile>.self, from: data)
        return UserProfileSnapshot(
            profile: envelope.data,
            etag: response.value(forHTTPHeaderField: "ETag") ?? "\"profile-\(envelope.data.profileVersion)\""
        )
    }

    func uploadUserAvatar(
        data avatarData: Data,
        mimeType: String,
        filename: String,
        etag: String,
        idempotencyKey: String
    ) async throws -> UserProfileSnapshot {
        let boundary = "NotePatch-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitizeFileName(filename))\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(avatarData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var avatarRequest = try request(method: "POST", pathOrURL: "/user/avatar/upload")
        avatarRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        avatarRequest.setValue(etag, forHTTPHeaderField: "If-Match")
        avatarRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        avatarRequest.httpBody = body
        let (data, response) = try await authedResponse(for: avatarRequest, allowRefresh: true)
        let envelope = try await decode(APIResponseEnvelope<UserProfile>.self, from: data)
        return UserProfileSnapshot(
            profile: envelope.data,
            etag: response.value(forHTTPHeaderField: "ETag") ?? "\"profile-\(envelope.data.profileVersion)\""
        )
    }

    func getUserAvatarData() async throws -> Data {
        let envelope = try await authedJSON(
            "GET",
            "/user/avatar/download-url",
            payload: nil,
            as: APIResponseEnvelope<AvatarDownloadURL>.self
        )
        let url = try resolveServiceURL(envelope.data.downloadURL)
        var avatarRequest = URLRequest(url: url)
        avatarRequest.httpMethod = "GET"
        avatarRequest.timeoutInterval = 30
        if url.path.contains("/api/v1/user/avatar/") {
            let (data, _) = try await authedResponse(for: avatarRequest, allowRefresh: true)
            return data
        }
        let (data, response) = try await data(for: avatarRequest)
        try validate(response: response, data: data)
        return data
    }

    func updateAIPreferences(aiHistoryEnabled: Bool) async throws -> AIHistoryPreferenceResponse {
        try await authedJSON(
            "PATCH",
            "/auth/preferences",
            payload: ["ai_history_enabled": aiHistoryEnabled],
            as: AIHistoryPreferenceResponse.self
        )
    }

    func listAIModels(workspaceId: String) async throws -> AiModelCatalog {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/ai/models",
            payload: nil,
            as: AiModelCatalog.self
        )
    }

    func selectAIModel(workspaceId: String, modelId: String?) async throws -> AiModelSelectionResponse {
        try await authedJSON(
            "PUT",
            "/workspaces/\(workspaceId.pathSegment)/ai/model",
            payload: ["model_id": modelId ?? NSNull()],
            as: AiModelSelectionResponse.self
        )
    }

    func logout(refreshToken: String) async throws {
        _ = try await postJSON(
            "/auth/logout",
            payload: ["refresh_token": refreshToken],
            as: EmptyResponse.self
        )
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        let refreshed = try await refreshTokenSingleFlight(refreshToken)
        accessToken = refreshed.accessToken
        self.refreshToken = refreshed.refreshToken
        onTokenRefreshed?(refreshed, refreshToken)
        return refreshed
    }

    func heartbeat(clientId: String?) async throws -> PresenceHeartbeatResponse {
        return try await authedJSON(
            "POST",
            "/presence/heartbeat",
            payload: ["client_id": clientId ?? NSNull()],
            as: PresenceHeartbeatResponse.self
        )
    }

    func offline(clientId: String) async throws {
        _ = try await authedText("POST", "/presence/offline", payload: ["client_id": clientId])
    }

    func listWorkspaces() async throws -> [WorkspaceItem] {
        try await authedJSON("GET", "/workspaces", payload: nil, as: [WorkspaceItem].self)
    }

    func createWorkspace(name: String) async throws -> WorkspaceItem {
        try await authedJSON("POST", "/workspaces", payload: ["name": name], as: WorkspaceItem.self)
    }

    func listDocuments(
        workspaceId: String,
        page: Int = 1,
        pageSize: Int = 50,
        status: String? = nil,
        documentKind: String? = nil,
        fileType: String? = nil
    ) async throws -> [LearningDocumentItem] {
        var query = [
            "page=\(page)",
            "page_size=\(pageSize)"
        ]
        if let status, !status.isEmpty {
            query.append("status=\(status.queryValue)")
        }
        if let documentKind, !documentKind.isEmpty {
            query.append("document_kind=\(documentKind.queryValue)")
        }
        if let fileType, !fileType.isEmpty {
            query.append("file_type=\(fileType.queryValue)")
        }
        let path = "/workspaces/\(workspaceId.pathSegment)/documents?\(query.joined(separator: "&"))"
        return try await authedJSON("GET", path, payload: nil, as: [LearningDocumentItem].self)
    }

    func getDocument(workspaceId: String, documentId: String) async throws -> LearningDocumentItem {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)",
            payload: nil,
            as: LearningDocumentItem.self
        )
    }

    func createUploadSession(
        workspaceId: String,
        filename: String,
        mimeType: String?,
        fileSize: Int64?,
        documentKind: String,
        learningMetadata: LearningMetadata? = nil,
        saveToDocuments: Bool? = nil
    ) async throws -> UploadSessionResponse {
        var payload: [String: Any] = [
            "filename": filename,
            "document_kind": documentKind,
            "title": filename,
            "metadata": learningMetadata?.payload ?? [:]
        ]
        if let saveToDocuments {
            payload["save_to_documents"] = saveToDocuments
        }
        if let mimeType {
            payload["mime_type"] = mimeType
        }
        if let fileSize {
            payload["file_size"] = fileSize
        }
        return try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/documents/upload-session",
            payload: payload,
            as: UploadSessionResponse.self
        )
    }

    func completeUpload(
        workspaceId: String,
        uploadSessionId: String,
        tusUploadURL: String,
        tusUploadId: String?,
        fileSize: Int64?,
        mimeType: String?
    ) async throws -> LearningDocumentItem {
        var payload: [String: Any] = [
            "upload_session_id": uploadSessionId,
            "tus_upload_url": tusUploadURL,
            "metadata": [:]
        ]
        if let tusUploadId, !tusUploadId.isEmpty {
            payload["tus_upload_id"] = tusUploadId
        }
        if let fileSize {
            payload["file_size"] = fileSize
        }
        if let mimeType {
            payload["mime_type"] = mimeType
        }
        return try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/documents/complete-upload",
            payload: payload,
            as: LearningDocumentItem.self
        )
    }

    func deleteDocument(workspaceId: String, documentId: String) async throws -> DocumentDeleteResponse {
        try await authedJSON(
            "DELETE",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)",
            payload: nil,
            as: DocumentDeleteResponse.self
        )
    }

    func getDownloadURL(
        workspaceId: String,
        documentId: String,
        expiresSeconds: Int = 900
    ) async throws -> DownloadURLResponse {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)/download-url?expires_seconds=\(expiresSeconds)",
            payload: nil,
            as: DownloadURLResponse.self
        )
    }

    func getArtifactDownloadURL(
        workspaceId: String,
        documentId: String,
        artifactId: String
    ) async throws -> ArtifactDownloadURLResponse {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)/artifacts/\(artifactId.pathSegment)/download-url",
            payload: nil,
            as: ArtifactDownloadURLResponse.self
        )
    }

    func download(downloadURL: String, targetURL: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(
            for: request(method: "GET", pathOrURL: downloadURL)
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningBackendError(localizedKey: "error.server.invalid_response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = (try? Data(contentsOf: temporaryURL)) ?? Data()
            throw LearningBackendError(
                Self.parseErrorMessage(
                    String(data: errorData.prefix(64 * 1024), encoding: .utf8) ?? "",
                    status: httpResponse.statusCode
                ),
                statusCode: httpResponse.statusCode,
                shouldClearSession: httpResponse.statusCode == 401
            )
        }
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
        } catch {
            try FileManager.default.copyItem(at: temporaryURL, to: targetURL)
        }
        return targetURL
    }

    func listArtifacts(workspaceId: String, documentId: String) async throws -> [DocumentArtifactItem] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)/artifacts",
            payload: nil,
            as: [DocumentArtifactItem].self
        )
    }

    func getOcrArtifacts(
        workspaceId: String,
        documentId: String,
        includeDownloadURL: Bool = true
    ) async throws -> OcrArtifactsResponse {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)/ocr?include_download_url=\(includeDownloadURL ? "true" : "false")",
            payload: nil,
            as: OcrArtifactsResponse.self
        )
    }

    func processDocument(workspaceId: String, documentId: String, forceReprocess: Bool = false) async throws -> TaskItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)/process",
            payload: ["options": ["force_reprocess": forceReprocess]],
            as: TaskItem.self
        )
    }

    func openClawChat(
        workspaceId: String,
        prompt: String,
        conversationId: String? = nil,
        input: [String: Any] = [:],
        options: [String: Any] = [:]
    ) async throws -> TaskItem {
        var payload: [String: Any] = [
            "prompt": prompt,
            "input": input,
            "options": options
        ]
        if let conversationId, !conversationId.isEmpty {
            payload["conversation_id"] = conversationId
        }
        return try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/ai/chat",
            payload: payload,
            as: TaskItem.self
        )
    }

    func cancelTask(workspaceId: String, taskId: String) async throws -> TaskItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/tasks/\(taskId.pathSegment)/cancel",
            payload: [:],
            as: TaskItem.self
        )
    }

    func listConversations(workspaceId: String, page: Int = 1, pageSize: Int = 20) async throws -> ChatConversationsResponse {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations?page=\(page)&page_size=\(pageSize)",
            payload: nil,
            as: ChatConversationsResponse.self
        )
    }

    func listChatMessages(workspaceId: String, conversationId: String, page: Int = 1, pageSize: Int = 100) async throws -> ChatMessagesResponse {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations/\(conversationId.pathSegment)/messages?page=\(page)&page_size=\(pageSize)",
            payload: nil,
            as: ChatMessagesResponse.self
        )
    }

    func updateConversation(workspaceId: String, conversationId: String, title: String) async throws -> ChatConversation {
        try await authedJSON(
            "PATCH",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations/\(conversationId.pathSegment)",
            payload: ["title": title],
            as: ChatConversation.self
        )
    }

    func deleteConversation(workspaceId: String, conversationId: String) async throws {
        try await authedNoContent(
            "DELETE",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations/\(conversationId.pathSegment)",
            payload: nil
        )
    }

    func reviseChatMessage(
        workspaceId: String,
        conversationId: String,
        messageId: String,
        prompt: String,
        options: [String: Any]
    ) async throws -> TaskItem {
        let response = try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations/\(conversationId.pathSegment)/messages/\(messageId.pathSegment)/revisions",
            payload: [
                "prompt": prompt,
                "input": NSNull(),
                "options": options
            ],
            as: APIResponseEnvelope<TaskItem>.self
        )
        return response.data
    }

    func listLearningUnits(workspaceId: String) async throws -> [LearningUnit] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units",
            payload: nil,
            as: [LearningUnit].self
        )
    }

    func listStudyNotes(workspaceId: String, learningUnitId: String) async throws -> [StudyNoteVersion] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/notes?include_download_url=true",
            payload: nil,
            as: [StudyNoteVersion].self
        )
    }

    func createStudyNoteRevision(
        workspaceId: String,
        learningUnitId: String,
        baseVersionId: String,
        input: StudyNoteRevisionInput
    ) async throws -> StudyNoteRevisionResponse {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/notes/\(baseVersionId.pathSegment)/revisions",
            payload: input.payload,
            as: StudyNoteRevisionResponse.self
        )
    }

    func mergeLearningUnits(
        workspaceId: String,
        targetLearningUnitId: String,
        sourceLearningUnitIds: [String]
    ) async throws -> TaskItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(targetLearningUnitId.pathSegment)/merge",
            payload: ["source_learning_unit_ids": sourceLearningUnitIds],
            as: TaskItem.self
        )
    }

    func getStudyNoteDownloadURL(
        workspaceId: String,
        learningUnitId: String,
        noteVersionId: String,
        kind: StudyNoteDownloadKind,
        expiresSeconds: Int = 900
    ) async throws -> StudyNoteDownloadURLResponse {
        let clampedExpiry = min(max(expiresSeconds, 60), 86_400)
        return try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/notes/\(noteVersionId.pathSegment)/download-url?kind=\(kind.rawValue)&expires_seconds=\(clampedExpiry)",
            payload: nil,
            as: StudyNoteDownloadURLResponse.self
        )
    }

    func listFlashcardDecks(
        workspaceId: String,
        learningUnitId: String,
        page: Int = 1,
        pageSize: Int = 100
    ) async throws -> [FlashcardDeck] {
        let safePage = max(page, 1)
        let safePageSize = min(max(pageSize, 1), 100)
        return try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/flashcard-decks?page=\(safePage)&page_size=\(safePageSize)",
            payload: nil,
            as: [FlashcardDeck].self
        )
    }

    func getLatestFlashcardDeck(
        workspaceId: String,
        learningUnitId: String
    ) async throws -> FlashcardDeckDetail {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/flashcard-decks/latest",
            payload: nil,
            as: FlashcardDeckDetail.self
        )
    }

    func getFlashcardDeck(
        workspaceId: String,
        learningUnitId: String,
        deckId: String
    ) async throws -> FlashcardDeckDetail {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/learning-units/\(learningUnitId.pathSegment)/flashcard-decks/\(deckId.pathSegment)",
            payload: nil,
            as: FlashcardDeckDetail.self
        )
    }

    func searchKnowledge(
        workspaceId: String,
        query: String,
        learningUnitId: String?,
        subject: String?,
        limit: Int
    ) async throws -> KnowledgeSearchResponse {
        var payload: [String: Any] = ["query": query, "limit": limit]
        if let learningUnitId, !learningUnitId.isEmpty { payload["learning_unit_id"] = learningUnitId }
        if let subject, !subject.isEmpty { payload["subject"] = subject }
        return try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/knowledge/search",
            payload: payload,
            as: KnowledgeSearchResponse.self
        )
    }

    func listHomeworks(workspaceId: String) async throws -> [HomeworkItem] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/homeworks",
            payload: nil,
            as: [HomeworkItem].self
        )
    }

    func getHomework(workspaceId: String, homeworkId: String) async throws -> HomeworkItem {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)",
            payload: nil,
            as: HomeworkItem.self
        )
    }

    func createHomework(workspaceId: String, input: HomeworkCreateInput) async throws -> HomeworkItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/homeworks",
            payload: input.payload,
            as: HomeworkItem.self
        )
    }

    func updateGradingConfig(workspaceId: String, homeworkId: String, input: GradingConfigInput) async throws -> HomeworkItem {
        try await authedJSON(
            "PATCH",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/grading-config",
            payload: input.payload,
            as: HomeworkItem.self
        )
    }

    func listGradingResults(workspaceId: String, homeworkId: String) async throws -> [GradingResult] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/grading-results",
            payload: nil,
            as: [GradingResult].self
        )
    }

    func listHomeworkReferences(workspaceId: String, homeworkId: String) async throws -> [HomeworkReferenceItem] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/references",
            payload: nil,
            as: [HomeworkReferenceItem].self
        )
    }

    func addHomeworkReference(
        workspaceId: String,
        homeworkId: String,
        documentId: String,
        referenceType: String
    ) async throws -> HomeworkReferenceItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/references",
            payload: ["document_id": documentId, "reference_type": referenceType],
            as: HomeworkReferenceItem.self
        )
    }

    func deleteHomeworkReference(workspaceId: String, homeworkId: String, referenceId: String) async throws {
        try await authedNoContent(
            "DELETE",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/references/\(referenceId.pathSegment)",
            payload: nil
        )
    }

    func gradeHomework(workspaceId: String, homeworkId: String) async throws -> TaskItem {
        try await authedJSON(
            "POST",
            "/workspaces/\(workspaceId.pathSegment)/homeworks/\(homeworkId.pathSegment)/grade",
            payload: ["student_user_id": NSNull(), "options": [:]],
            as: TaskItem.self
        )
    }

    func getTask(workspaceId: String, taskId: String) async throws -> TaskItem {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/tasks/\(taskId.pathSegment)",
            payload: nil,
            as: TaskItem.self
        )
    }

    func getTaskEvents(workspaceId: String, taskId: String) async throws -> [TaskEventItem] {
        try await authedJSON(
            "GET",
            "/workspaces/\(workspaceId.pathSegment)/tasks/\(taskId.pathSegment)/events",
            payload: nil,
            as: [TaskEventItem].self
        )
    }

    func streamTaskEvents(
        workspaceId: String,
        taskId: String,
        lastEventID: Int?
    ) -> AsyncThrowingStream<TaskSSEFrame, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    let (bytes, _) = try await openTaskEventStream(
                        workspaceId: workspaceId,
                        taskId: taskId,
                        lastEventID: lastEventID,
                        allowRefresh: true
                    )
                    var decoder = TaskSSEByteDecoder()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for frame in try decoder.append(byte, workspaceId: workspaceId) {
                            continuation.yield(frame)
                        }
                    }
                    for frame in try decoder.finish(workspaceId: workspaceId) {
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in streamTask.cancel() }
        }
    }

    func taskEventStreamRequest(
        workspaceId: String,
        taskId: String,
        lastEventID: Int?
    ) throws -> URLRequest {
        var streamRequest = try request(
            method: "GET",
            pathOrURL: "/workspaces/\(workspaceId.pathSegment)/tasks/\(taskId.pathSegment)/events/stream"
        )
        streamRequest.timeoutInterval = 0
        streamRequest.setValue(try bearerHeader(), forHTTPHeaderField: "Authorization")
        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        streamRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let lastEventID, lastEventID > 0 {
            streamRequest.setValue(String(lastEventID), forHTTPHeaderField: "Last-Event-ID")
        }
        return streamRequest
    }

    func resolveServiceURL(_ pathOrURL: String) throws -> URL {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            guard let url = URL(string: pathOrURL) else {
                throw LearningBackendError(localizedKey: "error.download.invalid_url")
            }
            return url
        }
        let path = pathOrURL.hasPrefix("/") ? pathOrURL : "/\(pathOrURL)"
        let base: String
        if normalizedBaseURL.hasSuffix("/api/v1"), path.hasPrefix("/api/v1/") {
            base = String(normalizedBaseURL.dropLast("/api/v1".count))
        } else {
            base = normalizedBaseURL
        }
        guard let url = URL(string: "\(base)\(path)") else {
            throw LearningBackendError(localizedKey: "error.download.invalid_url")
        }
        return url
    }

    private func postJSON<T: Decodable>(_ path: String, payload: [String: Any], as type: T.Type) async throws -> T {
        var request = try request(method: "POST", pathOrURL: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        return try await decode(type, from: data)
    }

    private func authedJSON<T: Decodable>(
        _ method: String,
        _ path: String,
        payload: [String: Any]?,
        as type: T.Type
    ) async throws -> T {
        let data = try await authedData(method, path, payload: payload, allowRefresh: true)
        return try await decode(type, from: data)
    }

    private func authedText(_ method: String, _ path: String, payload: [String: Any]?) async throws -> String {
        let data = try await authedData(method, path, payload: payload, allowRefresh: true)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func authedNoContent(_ method: String, _ path: String, payload: [String: Any]?) async throws {
        _ = try await authedData(method, path, payload: payload, allowRefresh: true)
    }

    private func authedData(
        _ method: String,
        _ path: String,
        payload: [String: Any]?,
        allowRefresh: Bool
    ) async throws -> Data {
        var request = try request(method: method, pathOrURL: path)
        request.setValue(try bearerHeader(), forHTTPHeaderField: "Authorization")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response) = try await data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, allowRefresh {
            guard let refreshToken else {
                throw LearningBackendError(
                    localizedKey: "error.session.expired",
                    statusCode: status,
                    shouldClearSession: true
                )
            }
            let attemptedRefreshToken = refreshToken
            let refreshed: TokenResponse
            do {
                refreshed = try await refreshTokenSingleFlight(attemptedRefreshToken)
            } catch let error as LearningBackendError {
                throw error.withContext(
                    statusCode: error.statusCode ?? status,
                    shouldClearSession: true,
                    refreshTokenAttempt: attemptedRefreshToken
                )
            }
            self.accessToken = refreshed.accessToken
            self.refreshToken = refreshed.refreshToken
            onTokenRefreshed?(refreshed, attemptedRefreshToken)
            do {
                return try await authedData(method, path, payload: payload, allowRefresh: false)
            } catch let error as LearningBackendError where error.shouldClearSession {
                throw error.withContext(
                    statusCode: error.statusCode,
                    shouldClearSession: true,
                    refreshTokenAttempt: attemptedRefreshToken
                )
            }
        }

        try validate(response: response, data: data)
        return data
    }

    private func authedResponse(
        for originalRequest: URLRequest,
        allowRefresh: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var authenticatedRequest = originalRequest
        authenticatedRequest.setValue(try bearerHeader(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await data(for: authenticatedRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningBackendError(localizedKey: "error.server.invalid_response")
        }
        if httpResponse.statusCode == 401, allowRefresh {
            guard let refreshToken else {
                throw LearningBackendError(
                    localizedKey: "error.session.expired",
                    statusCode: 401,
                    shouldClearSession: true
                )
            }
            let attemptedRefreshToken = refreshToken
            let refreshed = try await refreshTokenSingleFlight(attemptedRefreshToken)
            accessToken = refreshed.accessToken
            self.refreshToken = refreshed.refreshToken
            onTokenRefreshed?(refreshed, attemptedRefreshToken)
            return try await authedResponse(for: originalRequest, allowRefresh: false)
        }
        try validate(response: httpResponse, data: data)
        return (data, httpResponse)
    }

    private func openTaskEventStream(
        workspaceId: String,
        taskId: String,
        lastEventID: Int?,
        allowRefresh: Bool
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let streamRequest = try taskEventStreamRequest(
            workspaceId: workspaceId,
            taskId: taskId,
            lastEventID: lastEventID
        )

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: streamRequest)
        } catch {
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningBackendError(localizedKey: "error.server.invalid_response")
        }
        if httpResponse.statusCode == 401, allowRefresh {
            guard let refreshToken else {
                throw LearningBackendError(
                    localizedKey: "error.session.expired",
                    statusCode: 401,
                    shouldClearSession: true
                )
            }
            let attemptedRefreshToken = refreshToken
            let refreshed: TokenResponse
            do {
                refreshed = try await refreshTokenSingleFlight(attemptedRefreshToken)
            } catch let error as LearningBackendError {
                throw error.withContext(
                    statusCode: error.statusCode ?? 401,
                    shouldClearSession: true,
                    refreshTokenAttempt: attemptedRefreshToken
                )
            }
            accessToken = refreshed.accessToken
            self.refreshToken = refreshed.refreshToken
            onTokenRefreshed?(refreshed, attemptedRefreshToken)
            return try await openTaskEventStream(
                workspaceId: workspaceId,
                taskId: taskId,
                lastEventID: lastEventID,
                allowRefresh: false
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes.prefix(64 * 1024) {
                errorData.append(byte)
            }
            throw LearningBackendError(
                Self.parseErrorMessage(String(data: errorData, encoding: .utf8) ?? "", status: httpResponse.statusCode),
                statusCode: httpResponse.statusCode,
                shouldClearSession: httpResponse.statusCode == 401
            )
        }
        return (bytes, httpResponse)
    }

    private func refreshTokenInternal(_ token: String) async throws -> TokenResponse {
        try await postJSON("/auth/refresh", payload: ["refresh_token": token], as: TokenResponse.self)
    }

    private func refreshTokenSingleFlight(_ token: String) async throws -> TokenResponse {
        let key = RefreshFlightKey(
            baseURL: normalizedBaseURL,
            sessionIdentifier: ObjectIdentifier(session),
            refreshToken: token
        )
        return try await RefreshSingleFlight.shared.value(for: key) { [weak self] in
            guard let self else {
                throw LearningBackendError(localizedKey: "error.session.refresh_cancelled")
            }
            return try await self.refreshTokenInternal(token)
        }
    }

    private func bearerHeader() throws -> String {
        guard let accessToken, !accessToken.isEmpty else {
            throw LearningBackendError(
                localizedKey: "error.auth.required",
                statusCode: 401,
                shouldClearSession: true
            )
        }
        return "Bearer \(accessToken)"
    }

    private func request(
        method: String,
        pathOrURL: String,
        scope: RelativeRequestScope = .api
    ) throws -> URLRequest {
        let url: URL
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            guard let absoluteURL = URL(string: pathOrURL) else {
                throw LearningBackendError(localizedKey: "error.server.invalid_address")
            }
            url = absoluteURL
        } else {
            let path = pathOrURL.hasPrefix("/") ? pathOrURL : "/\(pathOrURL)"
            let prefix: String
            switch scope {
            case .service: prefix = ""
            case .api: prefix = "/api/v1"
            }
            guard let absoluteURL = URL(string: "\(normalizedBaseURL)\(prefix)\(path)") else {
                throw LearningBackendError(localizedKey: "error.server.invalid_address")
            }
            url = absoluteURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        return request
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw error
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningBackendError(localizedKey: "error.server.invalid_response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LearningBackendError(
                Self.parseErrorMessage(String(data: data, encoding: .utf8) ?? "", status: httpResponse.statusCode),
                statusCode: httpResponse.statusCode,
                shouldClearSession: httpResponse.statusCode == 401
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        let payload = data.isEmpty ? Data("{}".utf8) : data
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(type, from: payload)
        }.value
    }

    static func parseErrorMessage(_ body: String, status: Int) -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultErrorMessage(status)
        }
        let data = Data(body.utf8)
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            return defaultErrorMessage(status)
        }
        if let message = object["message"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        guard let detail = object["detail"] else { return defaultErrorMessage(status) }
        if let message = detail as? String {
            return message.isEmpty ? defaultErrorMessage(status) : message
        }
        if let details = detail as? [[String: Any]] {
            let messages = details.compactMap { item -> String? in
                if let message = item["msg"] as? String, !message.isEmpty {
                    return message
                }
                return String(describing: item)
            }
            return messages.joined(separator: "；").nilIfBlank ?? defaultErrorMessage(status)
        }
        if JSONSerialization.isValidJSONObject(detail),
           let data = try? JSONSerialization.data(withJSONObject: detail),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return defaultErrorMessage(status)
    }

    private static func defaultErrorMessage(_ status: Int) -> String {
        switch status {
        case 401:
            return localized("error.http.unauthorized")
        case 403:
            return localized("error.http.forbidden")
        case 404:
            return localized("error.http.not_found")
        case 409:
            return localized("error.http.conflict")
        case 410:
            return localized("error.http.gone")
        case 422:
            return localized("error.http.validation")
        default:
            return localizedFormat("error.http.generic", String(status))
        }
    }
}

private struct EmptyResponse: Decodable {}

private extension String {
    var pathSegment: String {
        addingPercentEncoding(withAllowedCharacters: .notepatchPathSegmentAllowed) ?? self
    }

    var queryValue: String {
        addingPercentEncoding(withAllowedCharacters: .notepatchQueryAllowed) ?? self
    }

    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private extension CharacterSet {
    static let notepatchPathSegmentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let notepatchQueryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
