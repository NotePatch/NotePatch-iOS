import Foundation

final class LearningBackendClient {
    private let normalizedBaseURL: String
    private var accessToken: String?
    private var refreshToken: String?
    private let onTokenRefreshed: ((TokenResponse) -> Void)?
    private let session: URLSession

    init(
        baseURL: String,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        session: URLSession = .shared,
        onTokenRefreshed: ((TokenResponse) -> Void)? = nil
    ) {
        self.normalizedBaseURL = normalizeLearningBackendBaseURL(baseURL)
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.session = session
        self.onTokenRefreshed = onTokenRefreshed
    }

    func healthCheck() async throws -> String {
        let (data, response) = try await data(for: request(method: "GET", pathOrURL: "/health"))
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

    func updateAIPreferences(aiHistoryEnabled: Bool) async throws -> AIHistoryPreferenceResponse {
        try await authedJSON(
            "PATCH",
            "/auth/preferences",
            payload: ["ai_history_enabled": aiHistoryEnabled],
            as: AIHistoryPreferenceResponse.self
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
        try await refreshTokenInternal(refreshToken)
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

    func createUploadSession(
        workspaceId: String,
        filename: String,
        mimeType: String?,
        fileSize: Int64?,
        documentKind: String,
        learningMetadata: LearningMetadata? = nil
    ) async throws -> UploadSessionResponse {
        var payload: [String: Any] = [
            "filename": filename,
            "document_kind": documentKind,
            "title": filename,
            "metadata": learningMetadata?.payload ?? [:]
        ]
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

    func deleteDocument(workspaceId: String, documentId: String) async throws {
        _ = try await authedText(
            "DELETE",
            "/workspaces/\(workspaceId.pathSegment)/documents/\(documentId.pathSegment)",
            payload: nil
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
        let (data, response) = try await data(for: request(method: "GET", pathOrURL: downloadURL))
        try validate(response: response, data: data)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: targetURL, options: .atomic)
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

    func openClawChat(workspaceId: String, prompt: String, conversationId: String? = nil) async throws -> TaskItem {
        var payload: [String: Any] = [
            "prompt": prompt,
            "input": [:],
            "options": [:]
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
        _ = try await authedText(
            "DELETE",
            "/workspaces/\(workspaceId.pathSegment)/ai/conversations/\(conversationId.pathSegment)",
            payload: nil
        )
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

    private func postJSON<T: Decodable>(_ path: String, payload: [String: Any], as type: T.Type) async throws -> T {
        var request = try request(method: "POST", pathOrURL: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        return try decode(type, from: data)
    }

    private func authedJSON<T: Decodable>(
        _ method: String,
        _ path: String,
        payload: [String: Any]?,
        as type: T.Type
    ) async throws -> T {
        let data = try await authedData(method, path, payload: payload, allowRefresh: true)
        return try decode(type, from: data)
    }

    private func authedText(_ method: String, _ path: String, payload: [String: Any]?) async throws -> String {
        let data = try await authedData(method, path, payload: payload, allowRefresh: true)
        return String(data: data, encoding: .utf8) ?? ""
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
                throw LearningBackendError("登录已过期，请重新登录。", statusCode: status, shouldClearSession: true)
            }
            let refreshed: TokenResponse
            do {
                refreshed = try await refreshTokenInternal(refreshToken)
            } catch let error as LearningBackendError {
                throw LearningBackendError(
                    error.message,
                    statusCode: error.statusCode ?? status,
                    shouldClearSession: true,
                    cause: error
                )
            }
            self.accessToken = refreshed.accessToken
            self.refreshToken = refreshed.refreshToken
            onTokenRefreshed?(refreshed)
            return try await authedData(method, path, payload: payload, allowRefresh: false)
        }

        try validate(response: response, data: data)
        return data
    }

    private func refreshTokenInternal(_ token: String) async throws -> TokenResponse {
        try await postJSON("/auth/refresh", payload: ["refresh_token": token], as: TokenResponse.self)
    }

    private func bearerHeader() throws -> String {
        guard let accessToken, !accessToken.isEmpty else {
            throw LearningBackendError("请先登录。", statusCode: 401, shouldClearSession: true)
        }
        return "Bearer \(accessToken)"
    }

    private func request(method: String, pathOrURL: String) throws -> URLRequest {
        let url: URL
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            guard let absoluteURL = URL(string: pathOrURL) else {
                throw LearningBackendError("服务器地址格式不正确，请检查 API 或 tus 地址。")
            }
            url = absoluteURL
        } else {
            let path = pathOrURL.hasPrefix("/") ? pathOrURL : "/\(pathOrURL)"
            guard let absoluteURL = URL(string: "\(normalizedBaseURL)\(path)") else {
                throw LearningBackendError("服务器地址格式不正确，请检查 API 或 tus 地址。")
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
            throw LearningBackendError("服务器响应无效。")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LearningBackendError(
                Self.parseErrorMessage(String(data: data, encoding: .utf8) ?? "", status: httpResponse.statusCode),
                statusCode: httpResponse.statusCode,
                shouldClearSession: httpResponse.statusCode == 401
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try JSONDecoder.notepatch.decode(type, from: data.isEmpty ? Data("{}".utf8) : data)
    }

    static func parseErrorMessage(_ body: String, status: Int) -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultErrorMessage(status)
        }
        let data = Data(body.utf8)
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any], let detail = object["detail"] else {
            return defaultErrorMessage(status)
        }
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
            return "登录已过期或无效，请重新登录。"
        case 403:
            return "当前账号无权访问该个人空间。"
        case 404:
            return "资源不存在或已被删除。"
        case 409:
            return "上传尚未完成或请求冲突，请稍后重试。"
        case 410:
            return "当前接口已禁用。"
        case 422:
            return "请求参数不符合服务器要求。"
        default:
            return "服务器请求失败：HTTP \(status)"
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
