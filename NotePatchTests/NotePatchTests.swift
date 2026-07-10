import Foundation
import Testing
@testable import NotePatch

@Suite(.serialized)
struct NotePatchTests {
    @Test func normalizeBaseURLs_defaultAndAddScheme() {
        #expect(normalizeLearningBackendBaseURL("") == defaultLearningBackendBaseURL)
        #expect(normalizeLearningBackendBaseURL("192.168.100.123:8001/") == "http://192.168.100.123:8001")
        #expect(normalizeLearningBackendBaseURL("https://example.test/api/") == "https://example.test/api")

        #expect(normalizeTUSBaseURL("") == defaultTUSDBaseURL)
        #expect(normalizeTUSBaseURL("192.168.100.123:1080/files") == "http://192.168.100.123:1080/files/")
        #expect(normalizeTUSBaseURL("https://example.test/files/") == "https://example.test/files/")
    }

    @Test func fileHelpers_sanitizeMimeAndByteFormatting() {
        #expect(sanitizeFileName("a/b:c?.pdf") == "a_b_c_.pdf")
        #expect(contentTypeForFilename("photo.jpg") == "image/jpeg")
        #expect(contentTypeForFilename("slides.pptx") == "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        #expect(replacingFilenameExtension("exam.pdf", with: "jpg") == "exam.jpg")
        #expect(formatBytes(512) == "512 B")
        #expect(formatBytes(2048) == "2.0 KB")
    }

    @Test @MainActor func pendingUpload_previewClassificationAndCacheCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepatch-preview-tests-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = cache.appendingPathComponent("selected.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        let imageFile = LocalUploadFile(url: imageURL, filename: "selected.jpg", mimeType: "image/jpeg")
        #expect(imageFile.previewKind(canQuickLookPreview: false) == .image)

        let pdfURL = cache.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.7".utf8).write(to: pdfURL)
        let pdfFile = LocalUploadFile(url: pdfURL, filename: "notes.pdf", mimeType: "application/pdf")
        #expect(pdfFile.previewKind(canQuickLookPreview: true) == .quickLook)
        #expect(pdfFile.previewKind(canQuickLookPreview: false) == .unsupported)

        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var networkRequestCount = 0
        let session = Self.mockSession { request in
            networkRequestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cache
        )

        model.stageUploadFileForPreview(pdfFile)
        #expect(model.pendingUploadFile?.filename == "notes.pdf")
        #expect(networkRequestCount == 0)
        model.discardPendingUpload()
        #expect(model.pendingUploadFile == nil)
        #expect(!FileManager.default.fileExists(atPath: pdfURL.path))

        let externalURL = root.appendingPathComponent("external.bin")
        try Data([0x00, 0x01]).write(to: externalURL)
        model.stageUploadFileForPreview(LocalUploadFile(url: externalURL, filename: "external.bin", mimeType: nil))
        model.discardPendingUpload()
        #expect(FileManager.default.fileExists(atPath: externalURL.path))

        let confirmURL = cache.appendingPathComponent("confirm.pdf")
        try Data("%PDF-1.7".utf8).write(to: confirmURL)
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: "2026-07-10T12:00:00Z",
            userId: "user-1",
            email: "user@example.com",
            fullName: "Test User",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.stageUploadFileForPreview(LocalUploadFile(url: confirmURL, filename: "confirm.pdf", mimeType: "application/pdf"))
        model.confirmPendingUpload()
        #expect(model.pendingUploadFile == nil)

        for _ in 0..<50 where networkRequestCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(networkRequestCount == 1)
    }

    @Test func tusHelpers_resolveURLAndUploadId() throws {
        let relative = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "abc")
        let absolutePath = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "/files/abc")
        let otherHost = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "http://other.test/upload/xyz")
        #expect(relative == "http://192.168.100.123:1080/files/abc")
        #expect(absolutePath == "http://192.168.100.123:1080/files/abc")
        #expect(otherHost == "http://other.test/upload/xyz")
        #expect(TusUploader.extractTusUploadId("http://192.168.100.123:1080/files/abc") == "abc")
    }

    @Test func decodeTokenWorkspaceUploadArtifactAndTaskJSON() throws {
        let token = try JSONDecoder.notepatch.decode(
            TokenResponse.self,
            from: Data(
                """
                {
                  "access_token": "access",
                  "refresh_token": "refresh",
                  "token_type": "bearer",
                  "expires_at": "2026-07-09T12:00:00Z",
                  "user": {
                    "id": "user-1",
                    "email": "alice@example.com",
                    "full_name": "Alice",
                    "is_active": true,
                    "created_at": "2026-07-09T11:00:00Z"
                  }
                }
                """.utf8
            )
        )
        #expect(token.accessToken == "access")
        #expect(token.user.fullName == "Alice")

        let workspace = try JSONDecoder.notepatch.decode(
            WorkspaceItem.self,
            from: Data(
                """
                {
                  "id": "ws-1",
                  "name": "My Workspace",
                  "owner_user_id": "user-1",
                  "created_at": "2026-07-09T10:00:00Z",
                  "updated_at": "2026-07-09T10:00:00Z"
                }
                """.utf8
            )
        )
        #expect(workspace.type == "personal")

        let uploadSession = try JSONDecoder.notepatch.decode(UploadSessionResponse.self, from: Data(Self.uploadSessionJSON.utf8))
        #expect(uploadSession.document.id == "doc-1")
        #expect(uploadSession.uploadSession.id == "upload-1")
        #expect(uploadSession.tusMetadataHeader == "workspace_id d3MtMQ==,document_id ZG9jLTE=")
        #expect(uploadSession.tusMetadata["document_id"] == "doc-1")

        let artifacts = try JSONDecoder.notepatch.decode(
            [DocumentArtifactItem].self,
            from: Data(
                """
                [
                  {
                    "id": "artifact-1",
                    "workspace_id": "ws-1",
                    "document_id": "doc-1",
                    "artifact_type": "ocr_json",
                    "bucket": "notepatch",
                    "object_key": "workspaces/ws-1/documents/doc-1/artifacts/ocr.json",
                    "mime_type": "application/json",
                    "file_size": 12,
                    "metadata": {"processor":"doctr"},
                    "created_at": "2026-07-09T10:01:00Z"
                  }
                ]
                """.utf8
            )
        )
        #expect(artifacts.first?.metadataProcessor == "doctr")

        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(
                """
                {
                  "id": "task-1",
                  "workspace_id": "ws-1",
                  "task_type": "openclaw",
                  "status": "succeeded",
                  "resource_type": "document",
                  "resource_id": "doc-1",
                  "payload": {"conversation_id":"conversation-1"},
                  "result": {"runner":"mock","answer":"ok"},
                  "error_message": null,
                  "progress": 100,
                  "created_at": "2026-07-09T10:00:00Z",
                  "updated_at": "2026-07-09T10:00:30Z",
                  "started_at": "2026-07-09T10:00:01Z",
                  "finished_at": "2026-07-09T10:00:30Z"
                }
                """.utf8
            )
        )
        #expect(task.progress == 100)
        #expect(task.payload?.objectStringValue(for: "conversation_id") == "conversation-1")
        #expect(task.result == .object(["runner": .string("mock"), "answer": .string("ok")]))
        #expect(formatOpenClawTaskResult(task.resultText) == "ok")

        let documentDownload = try JSONDecoder.notepatch.decode(
            DownloadURLResponse.self,
            from: Data(#"{"download_url":"https://download.test/original","expires_in":900}"#.utf8)
        )
        #expect(documentDownload.downloadURL == "https://download.test/original")
        #expect(documentDownload.expiresSeconds == 900)

        let artifactDownload = try JSONDecoder.notepatch.decode(
            ArtifactDownloadURLResponse.self,
            from: Data(
                """
                {
                  "artifact_id": "artifact-1",
                  "document_id": "doc-1",
                  "artifact_type": "ocr_markdown",
                  "filename": "ocr.md",
                  "mime_type": "text/markdown",
                  "expires_in": 900,
                  "download_url": "https://download.test/ocr.md"
                }
                """.utf8
            )
        )
        #expect(artifactDownload.filename == "ocr.md")
        #expect(artifactDownload.expiresSeconds == 900)

        let ocrArtifacts = try JSONDecoder.notepatch.decode(
            OcrArtifactsResponse.self,
            from: Data(
                """
                {
                  "document_id": "doc-1",
                  "artifacts": [
                    {
                      "id": "ocr-md",
                      "artifact_type": "ocr_markdown",
                      "mime_type": "text/markdown",
                      "file_size": 99,
                      "created_at": "2026-07-09T10:02:00Z",
                      "download_url": "https://download.test/ocr.md"
                    }
                  ]
                }
                """.utf8
            )
        )
        #expect(ocrArtifacts.artifacts.first?.artifactType == "ocr_markdown")
        #expect(ocrArtifacts.artifacts.first?.downloadURL == "https://download.test/ocr.md")
    }

    @Test func parseErrorMessage_handlesCommonDetailShapes() {
        #expect(LearningBackendClient.parseErrorMessage(#"{"detail":"Invalid token"}"#, status: 401) == "Invalid token")
        #expect(
            LearningBackendClient.parseErrorMessage(#"{"detail":[{"msg":"Field required"},{"msg":"Too short"}]}"#, status: 422)
            == "Field required；Too short"
        )
        #expect(LearningBackendClient.parseErrorMessage("", status: 409) == "上传尚未完成或请求冲突，请稍后重试。")
        #expect(LearningBackendClient.parseErrorMessage("", status: 410) == "当前接口已禁用。")
    }

    @Test func openClawAndMarkdownHelpers_matchAndroidBehavior() {
        #expect(formatOpenClawTaskResult(#"{"runner":"mock","answer":"hello"}"#) == "hello")
        let openClawResult = formatOpenClawTaskResult(
                """
                {
                  "runner": "gateway",
                  "output_key": "workspaces/ws-1/openclaw/output.md",
                  "output_keys": [
                    "workspaces/ws-1/openclaw/a.md",
                    "workspaces/ws-1/openclaw/b.json"
                  ],
                  "gateway_container": "openclaw-user-1",
                  "user_workspace_dir": "/srv/openclaw/users/user-1"
                }
                """
            )
        #expect(
            openClawResult
            ==
            """
            runner: gateway
            output_key: workspaces/ws-1/openclaw/output.md
            output_keys: workspaces/ws-1/openclaw/a.md, workspaces/ws-1/openclaw/b.json
            """
        )
        #expect(!openClawResult.contains("gateway_container"))
        #expect(!openClawResult.contains("user_workspace_dir"))
        #expect(formatOpenClawTaskResult("plain text") == "plain text")
        #expect(formatOpenClawTaskResult(nil) == "")

        let blocks = parseMarkdownBlocks(
            """
            # Title

            Paragraph with **bold** and `code`.
            - one
            1. two
            > quote
            ```
            val x = 1
            ```
            """
        )
        #expect(blocks[0].type == .heading)
        #expect(blocks[0].level == 1)
        #expect(blocks[2].type == .bullet)
        #expect(blocks[2].text == "one")
        #expect(blocks[5].type == .code)
        #expect(blocks[5].text == "val x = 1")

        let tokens = parseMarkdownInline("A **bold** `code` [link](https://example.com)")
        #expect(tokens[1].type == .bold)
        #expect(tokens[1].text == "bold")
        #expect(tokens[3].type == .code)
        #expect(tokens[5].type == .link)
        #expect(tokens[5].text == "link (https://example.com)")
    }

    @Test func authedRequest_refreshesTokenOnUnauthorized() async throws {
        let session = Self.mockSession { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired":
                return Self.response(request, status: 401, body: #"{"detail":"expired"}"#)
            case ("POST", "/auth/refresh"):
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "access_token": "new-access",
                      "refresh_token": "new-refresh",
                      "token_type": "bearer",
                      "expires_at": "2026-07-09T12:00:00Z",
                      "user": {
                        "id": "user-1",
                        "email": "alice@example.com",
                        "full_name": "Alice",
                        "is_active": true,
                        "created_at": "2026-07-09T11:00:00Z"
                      }
                    }
                    """
                )
            case ("GET", "/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "id": "user-1",
                      "email": "alice@example.com",
                      "full_name": "Alice",
                      "is_active": true,
                      "created_at": "2026-07-09T11:00:00Z"
                    }
                    """
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }

        var refreshed: TokenResponse?
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "expired",
            refreshToken: "refresh",
            session: session
        ) { token in
            refreshed = token
        }

        let user = try await client.me()
        #expect(user.email == "alice@example.com")
        #expect(refreshed?.accessToken == "new-access")
    }

    @Test func createUploadSession_sendsExpectedRequestShape() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.uploadSessionJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        let upload = try await client.createUploadSession(
            workspaceId: "ws 1",
            filename: "exam.pdf",
            mimeType: "application/pdf",
            fileSize: 12345,
            documentKind: "homework",
            learningMetadata: LearningMetadata(learningUnitTitle: "分数", subject: "数学", gradeLevel: "七年级", topic: "比例")
        )

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.absoluteString == "https://api.test/workspaces/ws%201/documents/upload-session")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        #expect(capturedBody?["filename"] as? String == "exam.pdf")
        #expect(capturedBody?["document_kind"] as? String == "homework")
        let metadata = capturedBody?["metadata"] as? [String: String]
        #expect(metadata?["learning_unit_title"] == "分数")
        #expect(metadata?["subject"] == "数学")
        #expect(upload.document.originalFilename == "exam.pdf")
    }

    @Test func processDocument_sendsForceReprocessOption() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let task = try await client.processDocument(workspaceId: "ws-1", documentId: "doc-1", forceReprocess: true)

        let options = capturedBody?["options"] as? [String: Any]
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/workspaces/ws-1/documents/doc-1/process")
        #expect(options?["force_reprocess"] as? Bool == true)
        #expect(task.id == "task-1")
    }

    @Test func openClawChat_usesChatEndpointAndPromptPayload() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let task = try await client.openClawChat(workspaceId: "ws-1", prompt: "总结本周错题", conversationId: "conversation-1")

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/workspaces/ws-1/ai/chat")
        #expect(capturedBody?["prompt"] as? String == "总结本周错题")
        #expect(capturedBody?["conversation_id"] as? String == "conversation-1")
        #expect(capturedBody?["input"] as? [String: Any] != nil)
        #expect(capturedBody?["options"] as? [String: Any] != nil)
        #expect(task.id == "task-1")
    }

    @Test func artifactAndOcrRequests_useDocumentScopedEndpoints() async throws {
        var paths: [String] = []
        let session = Self.mockSession { request in
            paths.append(request.url?.absoluteString ?? "")
            switch request.url?.path ?? "" {
            case "/workspaces/ws-1/documents/doc-1/artifacts/artifact-1/download-url":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "artifact_id": "artifact-1",
                      "document_id": "doc-1",
                      "artifact_type": "ocr_text",
                      "filename": "ocr.txt",
                      "mime_type": "text/plain",
                      "expires_seconds": 600,
                      "download_url": "https://download.test/ocr.txt"
                    }
                    """
                )
            case "/workspaces/ws-1/documents/doc-1/ocr":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "document_id": "doc-1",
                      "artifacts": [
                        {
                          "id": "ocr-text",
                          "artifact_type": "ocr_text",
                          "mime_type": "text/plain",
                          "file_size": 10,
                          "created_at": "2026-07-09T10:03:00Z",
                          "download_url": "https://download.test/ocr.txt"
                        }
                      ]
                    }
                    """
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let artifact = try await client.getArtifactDownloadURL(workspaceId: "ws-1", documentId: "doc-1", artifactId: "artifact-1")
        let ocr = try await client.getOcrArtifacts(workspaceId: "ws-1", documentId: "doc-1", includeDownloadURL: true)

        #expect(artifact.downloadURL == "https://download.test/ocr.txt")
        #expect(ocr.artifacts.first?.downloadURL == "https://download.test/ocr.txt")
        #expect(paths.contains("https://api.test/workspaces/ws-1/documents/doc-1/ocr?include_download_url=true"))
    }

    @Test func aiHistoryConversationAndLearningRequests_useDocumentedPaths() async throws {
        var requests: [URLRequest] = []
        let session = Self.mockSession { request in
            requests.append(request)
            switch request.url?.path ?? "" {
            case "/auth/preferences":
                return Self.response(request, status: 200, body: #"{"ai_history_enabled":false}"#)
            case "/workspaces/ws-1/ai/conversations":
                if request.httpMethod == "GET" {
                    return Self.response(request, status: 200, body: #"{"items":[{"id":"c-1","workspace_id":"ws-1","title":"复习","created_at":"","updated_at":""}],"page":1,"page_size":20,"total":1}"#)
                }
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "/workspaces/ws-1/ai/conversations/c-1/messages":
                return Self.response(request, status: 200, body: #"{"items":[{"id":"m-1","conversation_id":"c-1","role":"assistant","content":"完成","status":"succeeded","created_at":""}],"page":1,"page_size":100,"total":1}"#)
            case "/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"u-1","title":"分数","subject":"数学","grade_level":"七年级","topic":"比例"}]"#)
            case "/workspaces/ws-1/learning-units/u-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"n-1","learning_unit_id":"u-1","version_no":2,"title":"笔记","markdown_object_key":"m","json_object_key":"j","download_urls":{"highlighted":"https://download.test/highlighted"}}]"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)
        let preference = try await client.updateAIPreferences(aiHistoryEnabled: false)
        let conversations = try await client.listConversations(workspaceId: "ws-1")
        let messages = try await client.listChatMessages(workspaceId: "ws-1", conversationId: "c-1")
        let units = try await client.listLearningUnits(workspaceId: "ws-1")
        let notes = try await client.listStudyNotes(workspaceId: "ws-1", learningUnitId: "u-1")

        #expect(preference.aiHistoryEnabled == false)
        #expect(conversations.items.first?.title == "复习")
        #expect(messages.items.first?.status == "succeeded")
        #expect(units.first?.gradeLevel == "七年级")
        #expect(notes.first?.preferredDownloadURL == "https://download.test/highlighted")
        #expect(requests.contains { $0.url?.query == "include_download_url=true" })
    }

    @Test func decodeKnowledgeHomeworkReferenceAndGradingResult() throws {
        let search = try JSONDecoder.notepatch.decode(
            KnowledgeSearchResponse.self,
            from: Data(#"{"items":[{"id":"k-1","workspace_id":"ws-1","document_id":null,"subject":null,"grade_level":"IGCSE","source_type":"courseware","content":"斜率表示变化率","metadata":{"title":"一次函数","page_refs":[2,3]},"score":0.8731,"created_at":""}]}"#.utf8)
        )
        #expect(search.items.first?.metadataTitle == "一次函数")
        #expect(search.items.first?.pageReferences == "2, 3")
        #expect(search.items.first?.documentId == nil)
        #expect(search.items.first?.score == 0.8731)

        let homework = try JSONDecoder.notepatch.decode(
            HomeworkItem.self,
            from: Data(#"{"id":"h-1","workspace_id":"ws-1","title":"代数作业","description":null,"document_id":"doc-1","due_at":null,"status":"draft","rubric_text":"过程 4 分","max_score":100.0,"metadata":{},"created_by_user_id":"u-1","created_at":"","updated_at":""}"#.utf8)
        )
        let references = try JSONDecoder.notepatch.decode(
            [HomeworkReferenceItem].self,
            from: Data(#"[{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}]"#.utf8)
        )
        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"t-1","workspace_id":"ws-1","status":"succeeded","payload":{},"result":{"grading_mode":"provisional","confidence":0.82},"progress":100}"#.utf8)
        )
        #expect(homework.maxScore == 100)
        #expect(references.first?.referenceType == "answer_key")
        #expect(task.result?.objectStringValue(for: "grading_mode") == "provisional")
        #expect(task.result?.objectDoubleValue(for: "confidence") == 0.82)
    }

    @Test func knowledgeAndHomeworkRequests_matchOpenAPI() async throws {
        var bodies: [String: [String: Any]] = [:]
        let homeworkJSON = #"{"id":"h-1","workspace_id":"ws-1","title":"代数作业","document_id":"doc-1","status":"draft","rubric_text":"过程 4 分","max_score":100.0,"metadata":{},"created_by_user_id":"u-1","created_at":"","updated_at":""}"#
        let referenceJSON = #"{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}"#
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            if let data = Self.requestBodyData(request) {
                bodies[key] = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            switch key {
            case "POST /workspaces/ws-1/knowledge/search":
                return Self.response(request, status: 200, body: #"{"items":[]}"#)
            case "GET /workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[\(homeworkJSON)]")
            case "GET /workspaces/ws-1/homeworks/h-1", "POST /workspaces/ws-1/homeworks", "PATCH /workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: request.httpMethod == "POST" ? 201 : 200, body: homeworkJSON)
            case "GET /workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 200, body: "[\(referenceJSON)]")
            case "POST /workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 201, body: referenceJSON)
            case "DELETE /workspaces/ws-1/homeworks/h-1/references/r-1":
                return Self.response(request, status: 204, body: "")
            case "POST /workspaces/ws-1/homeworks/h-1/grade":
                return Self.response(request, status: 201, body: Self.taskJSON)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)
        _ = try await client.searchKnowledge(workspaceId: "ws-1", query: "斜率", learningUnitId: "unit-1", subject: "math", limit: 6)
        _ = try await client.listHomeworks(workspaceId: "ws-1")
        _ = try await client.getHomework(workspaceId: "ws-1", homeworkId: "h-1")
        _ = try await client.createHomework(workspaceId: "ws-1", input: HomeworkCreateInput(title: "代数作业", description: nil, documentId: "doc-1", dueAt: nil, rubricText: nil, maxScore: 100))
        _ = try await client.updateGradingConfig(workspaceId: "ws-1", homeworkId: "h-1", input: GradingConfigInput(rubricText: nil, maxScore: 80))
        _ = try await client.listHomeworkReferences(workspaceId: "ws-1", homeworkId: "h-1")
        _ = try await client.addHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key")
        try await client.deleteHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", referenceId: "r-1")
        _ = try await client.gradeHomework(workspaceId: "ws-1", homeworkId: "h-1")

        #expect(bodies["POST /workspaces/ws-1/knowledge/search"]?["learning_unit_id"] as? String == "unit-1")
        #expect(bodies["POST /workspaces/ws-1/knowledge/search"]?["limit"] as? Int == 6)
        #expect(bodies["POST /workspaces/ws-1/homeworks"]?["document_id"] as? String == "doc-1")
        #expect(bodies["PATCH /workspaces/ws-1/homeworks/h-1/grading-config"]?["max_score"] as? Double == 80)
        #expect(bodies["PATCH /workspaces/ws-1/homeworks/h-1/grading-config"]?["rubric_text"] is NSNull)
        #expect(bodies["POST /workspaces/ws-1/homeworks/h-1/references"]?["reference_type"] as? String == "answer_key")
        #expect(bodies["POST /workspaces/ws-1/homeworks/h-1/grade"]?["student_user_id"] is NSNull)
    }

    @Test @MainActor func gradingViewModel_validatesAndFiltersCandidates() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)))
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.searchKnowledge()
        #expect(model.errorMessage == "请输入知识检索内容。")

        let documents = try JSONDecoder.notepatch.decode(
            [LearningDocumentItem].self,
            from: Data(Self.gradingDocumentsJSON.utf8)
        )
        model.gradingDocuments = documents
        model.homeworkReferences = [HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key", createdAt: "")]
        #expect(model.homeworkDocumentCandidates.map(\.id) == ["homework-1"])
        #expect(model.referenceDocumentCandidates.map(\.id) == ["rubric-1"])

        model.selectedHomeworkId = "h-1"
        model.homeworkMaxScoreText = "0"
        model.saveGradingConfig()
        #expect(model.errorMessage == "满分必须大于 0。")
    }
}

private extension NotePatchTests {
    static let gradingDocumentsJSON =
        """
        [
          {"id":"homework-1","workspace_id":"ws-1","uploaded_by":"u","title":"作业","original_filename":"homework.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"homework","storage_backend":"seaweedfs","bucket":"b","object_key":"homework","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"answer-1","workspace_id":"ws-1","uploaded_by":"u","title":"答案","original_filename":"answer.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"answer_key","storage_backend":"seaweedfs","bucket":"b","object_key":"answer","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"rubric-1","workspace_id":"ws-1","uploaded_by":"u","title":"标准","original_filename":"rubric.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"rubric","storage_backend":"seaweedfs","bucket":"b","object_key":"rubric","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"pending-1","workspace_id":"ws-1","uploaded_by":"u","title":"未处理答案","original_filename":"pending.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"answer_key","storage_backend":"seaweedfs","bucket":"b","object_key":"pending","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"uploaded","created_at":"","updated_at":"","artifacts":[]}
        ]
        """

    static let uploadSessionJSON =
        """
        {
          "document": {
            "id": "doc-1",
            "workspace_id": "ws-1",
            "uploaded_by": "user-1",
            "title": "exam.pdf",
            "original_filename": "exam.pdf",
            "mime_type": "application/pdf",
            "file_size": 12345,
            "file_type": "pdf",
            "document_kind": "homework",
            "storage_backend": "seaweedfs",
            "bucket": "notepatch",
            "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf",
            "upload_id": null,
            "tus_upload_url": null,
            "sha256": null,
            "status": "created",
            "metadata": {},
            "created_at": "2026-07-09T10:00:00Z",
            "updated_at": "2026-07-09T10:00:00Z",
            "artifacts": []
          },
          "upload_session": {
            "id": "upload-1",
            "workspace_id": "ws-1",
            "user_id": "user-1",
            "document_id": "doc-1",
            "tus_upload_id": null,
            "tus_upload_url": null,
            "bucket": "notepatch",
            "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf",
            "status": "created",
            "expires_at": null,
            "created_at": "2026-07-09T10:00:00Z",
            "updated_at": "2026-07-09T10:00:00Z"
          },
          "tus_endpoint": "http://192.168.100.123:1080/files/",
          "tus_metadata": {
            "workspace_id": "ws-1",
            "document_id": "doc-1"
          },
          "tus_metadata_header": "workspace_id d3MtMQ==,document_id ZG9jLTE=",
          "bucket": "notepatch",
          "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf"
        }
        """

    static let taskJSON =
        """
        {
          "id": "task-1",
          "workspace_id": "ws-1",
          "task_type": "document_processing_pipeline",
          "status": "queued",
          "resource_type": "document",
          "resource_id": "doc-1",
          "payload": {},
          "result": null,
          "error_message": null,
          "progress": 0,
          "created_at": "2026-07-09T10:00:00Z",
          "updated_at": "2026-07-09T10:00:00Z",
          "started_at": null,
          "finished_at": null
        }
        """

    static func mockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(_ request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.test")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    static func requestBodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer {
            stream.close()
        }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: LearningBackendError("Missing mock handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
