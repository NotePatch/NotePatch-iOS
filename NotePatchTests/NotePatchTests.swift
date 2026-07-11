import Foundation
import QuickLookThumbnailing
import SwiftUI
import Testing
@testable import NotePatch

@Suite(.serialized)
struct NotePatchTests {
    @Test func normalizeBaseURLs_defaultAndAddScheme() {
        #expect(normalizeLearningBackendBaseURL("") == defaultLearningBackendBaseURL)
        #expect(normalizeLearningBackendBaseURL("192.168.100.123:8001/") == "http://192.168.100.123:8001/api/v1")
        #expect(normalizeLearningBackendBaseURL("https://example.test/api/v1/") == "https://example.test/api/v1")
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

    @Test @MainActor func uploadThumbnail_classificationCacheKeyAndImageDownsampling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepatch-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600))
        let sourceImage = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        let imageURL = root.appendingPathComponent("large.png")
        try #require(sourceImage.pngData()).write(to: imageURL)
        let imageFile = LocalUploadFile(url: imageURL, filename: "large.png", mimeType: "image/png")

        #expect(uploadThumbnailKind(for: imageFile, canQuickLookPreview: false) == .image)
        let thumbnail = try #require(downsampleUploadImage(at: imageURL, maxPixelSize: 160))
        #expect(max(thumbnail.size.width * thumbnail.scale, thumbnail.size.height * thumbnail.scale) <= 160)
        #expect(thumbnail.size.width < sourceImage.size.width)

        let firstKey = uploadThumbnailCacheKey(for: imageFile)
        var changedData = try Data(contentsOf: imageURL)
        changedData.append(0)
        try changedData.write(to: imageURL, options: .atomic)
        let secondKey = uploadThumbnailCacheKey(for: imageFile)
        #expect(firstKey != secondKey)

        let pdfURL = root.appendingPathComponent("notes.pdf")
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try pdfRenderer.pdfData { context in
            context.beginPage()
            NSString(string: "NotePatch PDF").draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }.write(to: pdfURL)
        let pdfFile = LocalUploadFile(url: pdfURL, filename: "notes.pdf", mimeType: "application/pdf")
        let unknownFile = LocalUploadFile(url: root.appendingPathComponent("blob.unknown"), filename: "blob.unknown", mimeType: nil)
        #expect(uploadThumbnailKind(for: pdfFile, canQuickLookPreview: true) == .quickLook)
        #expect(uploadThumbnailKind(for: unknownFile, canQuickLookPreview: false) == .unsupported)

        let request = QLThumbnailGenerator.Request(
            fileAt: pdfURL,
            size: CGSize(width: 56, height: 64),
            scale: 2,
            representationTypes: .thumbnail
        )
        let pdfThumbnail = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
        #expect(pdfThumbnail != nil)

        let cache = UploadThumbnailCache.shared
        cache.insert(thumbnail, forKey: uploadThumbnailCacheKey(for: imageFile))
        #expect(cache.image(forKey: uploadThumbnailCacheKey(for: imageFile)) != nil)
        cache.remove(file: imageFile)
        #expect(cache.image(forKey: uploadThumbnailCacheKey(for: imageFile)) == nil)
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
        #expect(model.queuedUploadItems.count == 1)
        #expect(model.queuedUploadItems.first?.file.filename == "notes.pdf")
        #expect(model.queuedUploadItems.first?.documentKind == "homework")
        #expect(networkRequestCount == 0)
        let pdfId = try #require(model.queuedUploadItems.first?.id)
        model.removeQueuedUpload(pdfId)
        #expect(model.queuedUploadItems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pdfURL.path))

        let externalURL = root.appendingPathComponent("external.bin")
        try Data([0x00, 0x01]).write(to: externalURL)
        model.stageUploadFileForPreview(LocalUploadFile(url: externalURL, filename: "external.bin", mimeType: nil))
        let externalId = try #require(model.queuedUploadItems.first?.id)
        model.removeQueuedUpload(externalId)
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
        model.uploadDocumentKind = "homework"
        model.stageUploadFileForPreview(LocalUploadFile(url: confirmURL, filename: "confirm.pdf", mimeType: "application/pdf"))
        #expect(model.queuedUploadItems.first?.documentKind == "homework")
        model.uploadDocumentKind = "note"
        model.uploadSelectedQueuedFiles()

        for _ in 0..<50 where networkRequestCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        for _ in 0..<50 where model.isBusy {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(networkRequestCount == 1)
        #expect(model.queuedUploadItems.count == 1)
        if case .failed = model.queuedUploadItems[0].state {
            // Expected: the mocked backend rejects the upload session request.
        } else {
            Issue.record("Failed queue items must remain available for retry")
        }
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

    @Test @MainActor func uploadQueue_preservesKindsUploadsInOrderAndRemovesSuccesses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotePatchQueueTests-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = cache.appendingPathComponent("first.pdf")
        let secondURL = cache.appendingPathComponent("second.pdf")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        var kinds: [String] = []
        var tusCreateCount = 0
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path == "/api/v1/workspaces/ws-1/documents/upload-session" {
                let body = try #require(Self.requestBodyData(request))
                let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                kinds.append(try #require(object["document_kind"] as? String))
                return Self.response(request, status: 201, body: Self.uploadSessionJSON)
            }
            if request.httpMethod == "POST", request.url?.host == "192.168.100.123", path.hasPrefix("/files") {
                tusCreateCount += 1
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Location": "upload-\(tusCreateCount)", "Tus-Resumable": "1.0.0"]
                )!
                return (response, Data())
            }
            if request.httpMethod == "POST", path == "/api/v1/workspaces/ws-1/documents/complete-upload" {
                return Self.response(request, status: 200, body: Self.completedDocumentJSON)
            }
            if request.httpMethod == "GET", path == "/api/v1/workspaces/ws-1/documents" {
                return Self.response(request, status: 200, body: "[]")
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let suiteName = "NotePatchQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cache
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "http://192.168.100.123:1080/files/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.uploadDocumentKind = "homework"
        model.stageUploadFileForPreview(LocalUploadFile(url: firstURL, filename: "first.pdf", mimeType: "application/pdf"))
        model.uploadDocumentKind = "note"
        model.stageUploadFileForPreview(LocalUploadFile(url: secondURL, filename: "second.pdf", mimeType: "application/pdf"))

        model.uploadSelectedQueuedFiles()
        try await Self.waitUntil { model.queuedUploadItems.isEmpty || model.errorMessage != nil }

        #expect(kinds == ["homework", "note"])
        #expect(tusCreateCount == 2)
        #expect(model.queuedUploadItems.isEmpty)
        #expect(model.statusMessage == "已上传所选文件。")
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

        let deletion = try JSONDecoder.notepatch.decode(
            DocumentDeleteResponse.self,
            from: Data(#"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#.utf8)
        )
        #expect(deletion.purgeTaskId == "purge-1")

        let cancellingTask = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"task-cancel","workspace_id":"ws-1","status":"running","progress":20,"cancel_requested_at":"2026-07-11T00:00:00Z"}"#.utf8)
        )
        #expect(cancellingTask.cancelRequestedAt != nil)

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
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired":
                return Self.response(request, status: 401, body: #"{"detail":"expired"}"#)
            case ("POST", "/api/v1/auth/refresh"):
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
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access":
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
        #expect(capturedRequest?.url?.absoluteString == "https://api.test/api/v1/workspaces/ws%201/documents/upload-session")
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
        #expect(capturedRequest?.url?.path == "/api/v1/workspaces/ws-1/documents/doc-1/process")
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
        #expect(capturedRequest?.url?.path == "/api/v1/workspaces/ws-1/ai/chat")
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
            case "/api/v1/workspaces/ws-1/documents/doc-1/artifacts/artifact-1/download-url":
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
            case "/api/v1/workspaces/ws-1/documents/doc-1/ocr":
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
        #expect(paths.contains("https://api.test/api/v1/workspaces/ws-1/documents/doc-1/ocr?include_download_url=true"))
    }

    @Test func aiHistoryConversationAndLearningRequests_useDocumentedPaths() async throws {
        var requests: [URLRequest] = []
        let session = Self.mockSession { request in
            requests.append(request)
            switch request.url?.path ?? "" {
            case "/api/v1/auth/preferences":
                return Self.response(request, status: 200, body: #"{"ai_history_enabled":false}"#)
            case "/api/v1/workspaces/ws-1/ai/conversations":
                if request.httpMethod == "GET" {
                    return Self.response(request, status: 200, body: #"{"items":[{"id":"c-1","workspace_id":"ws-1","title":"复习","created_at":"","updated_at":""}],"page":1,"page_size":20,"total":1}"#)
                }
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "/api/v1/workspaces/ws-1/ai/conversations/c-1/messages":
                return Self.response(request, status: 200, body: #"{"items":[{"id":"m-1","conversation_id":"c-1","role":"assistant","content":"完成","status":"succeeded","created_at":""}],"page":1,"page_size":100,"total":1}"#)
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"u-1","title":"分数","subject":"数学","grade_level":"七年级","topic":"比例"}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-1/notes":
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

    @Test @MainActor func notesOverview_groupsVersionsAndLoadsMarkdownOnDemand() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            switch request.url?.path ?? "" {
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"u-1","title":"比例","subject":"数学","grade_level":"七年级","topic":"比"},{"id":"u-2","title":"单元二","subject":null,"grade_level":null,"topic":null}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"n-1","learning_unit_id":"u-1","version_no":1,"title":"旧笔记","markdown_object_key":"m1","json_object_key":"j1","download_urls":{"markdown":"https://download.test/n-1.md"}},{"id":"n-2","learning_unit_id":"u-1","version_no":2,"title":"新笔记","markdown_object_key":"m2","json_object_key":"j2","download_urls":{"highlighted":"https://download.test/n-2.md"}}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-2/notes":
                return Self.response(request, status: 200, body: "[]")
            default:
                if request.url?.host == "download.test" {
                    return Self.response(request, status: 200, body: "# 比例\n\n- 外项积等于内项积")
                }
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        model.loadNotesOverview()
        try await Self.waitUntil { !model.isNotesLoading }
        let group = try #require(model.studyNoteGroups.first)
        #expect(model.studyNoteGroups.count == 1)
        #expect(group.learningUnit.title == "比例")
        #expect(group.notes.map(\.note.versionNo) == [2, 1])

        let latest = try #require(group.notes.first)
        model.openStudyNote(latest)
        try await Self.waitUntil { !model.isStudyNoteLoading }
        #expect(model.studyNoteMarkdown?.contains("外项积等于内项积") == true)
        #expect(model.studyNoteReaderError == nil)
    }

    @Test func persistentMutationRequests_matchDocumentedContracts() async throws {
        var requests: [URLRequest] = []
        var bodies: [String: [String: Any]] = [:]
        let session = Self.mockSession { request in
            requests.append(request)
            let encodedPath = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            } ?? ""
            let key = "\(request.httpMethod ?? "") \(encodedPath)"
            if let data = Self.requestBodyData(request) {
                bodies[key] = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc%2F1":
                return Self.response(request, status: 202, body: #"{"ok":true,"document_id":"doc/1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#)
            case "PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1":
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "DELETE /api/v1/workspaces/ws-1/ai/conversations/c-1",
                 "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                return Self.response(request, status: 204, body: "")
            case "PATCH /api/v1/auth/preferences":
                return Self.response(request, status: 200, body: #"{"id":"u-1","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)

        let deleted = try await client.deleteDocument(workspaceId: "ws-1", documentId: "doc/1")
        let renamed = try await client.updateConversation(workspaceId: "ws-1", conversationId: "c-1", title: "新标题")
        try await client.deleteConversation(workspaceId: "ws-1", conversationId: "c-1")
        let preference = try await client.updateAIPreferences(aiHistoryEnabled: false)
        try await client.deleteHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", referenceId: "r-1")

        #expect(renamed.title == "新标题")
        #expect(deleted.purgeStatus == "queued")
        #expect(deleted.purgeTaskId == "purge-1")
        #expect(preference.aiHistoryEnabled == false)
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1"]?["title"] as? String == "新标题")
        #expect(bodies["PATCH /api/v1/auth/preferences"]?["ai_history_enabled"] as? Bool == false)
        #expect(requests.filter { $0.httpMethod == "DELETE" }.count == 3)
    }

    @Test func decodeDocumentPurgeAndTaskCancellationFields() throws {
        let document = try JSONDecoder.notepatch.decode(
            LearningDocumentItem.self,
            from: Data(
                #"{"id":"doc-1","workspace_id":"ws-1","uploaded_by":"u-1","original_filename":"homework.pdf","file_type":"pdf","document_kind":"homework","storage_backend":"seaweedfs","bucket":"b","object_key":"documents/doc-1","status":"deleted","purge_status":"running","purge_task_id":"purge-1","purged_at":null,"created_at":"","updated_at":"","artifacts":[]}"#.utf8
            )
        )
        let deletion = try JSONDecoder.notepatch.decode(
            DocumentDeleteResponse.self,
            from: Data(#"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#.utf8)
        )
        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"task-1","workspace_id":"ws-1","task_type":"purge_document","status":"running","payload":{},"progress":40,"cancel_requested_at":"2026-07-11T01:00:00Z","created_at":"","updated_at":""}"#.utf8)
        )

        #expect(document.purgeStatus == "running")
        #expect(document.purgeTaskId == "purge-1")
        #expect(deletion.documentId == "doc-1")
        #expect(deletion.purgeTaskId == "purge-1")
        #expect(task.cancelRequestedAt == "2026-07-11T01:00:00Z")
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
            case "POST /api/v1/workspaces/ws-1/knowledge/search":
                return Self.response(request, status: 200, body: #"{"items":[]}"#)
            case "GET /api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[\(homeworkJSON)]")
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1", "POST /api/v1/workspaces/ws-1/homeworks", "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: request.httpMethod == "POST" ? 201 : 200, body: homeworkJSON)
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 200, body: "[\(referenceJSON)]")
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 201, body: referenceJSON)
            case "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                return Self.response(request, status: 204, body: "")
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/grade":
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

        #expect(bodies["POST /api/v1/workspaces/ws-1/knowledge/search"]?["learning_unit_id"] as? String == "unit-1")
        #expect(bodies["POST /api/v1/workspaces/ws-1/knowledge/search"]?["limit"] as? Int == 6)
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks"]?["document_id"] as? String == "doc-1")
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config"]?["max_score"] as? Double == 80)
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config"]?["rubric_text"] is NSNull)
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks/h-1/references"]?["reference_type"] as? String == "answer_key")
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks/h-1/grade"]?["student_user_id"] is NSNull)
    }

    @Test @MainActor func conversationMutations_waitForServerAndDeduplicateRequests() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var renameCount = 0
        var deleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1":
                renameCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "DELETE /api/v1/workspaces/ws-1/ai/conversations/c-1":
                deleteCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 204, body: "")
            case "GET /api/v1/workspaces/ws-1/ai/conversations":
                return Self.response(request, status: 200, body: #"{"items":[],"page":1,"page_size":20,"total":0}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedConversationId = "c-1"
        model.conversations = [ChatConversation(id: "c-1", workspaceId: "ws-1", title: "旧标题", lastMessageAt: nil, createdAt: "", updatedAt: "")]

        model.renameCurrentConversation(to: "新标题")
        model.renameCurrentConversation(to: "重复请求")
        #expect(model.isConversationMutating)
        #expect(model.selectedConversation?.title == "旧标题")
        try await Self.waitUntil { !model.isConversationMutating }
        #expect(renameCount == 1)
        #expect(model.selectedConversation?.title == "新标题")
        #expect(model.statusMessage == "对话标题已保存。")

        model.renameCurrentConversation(to: String(repeating: "a", count: 161))
        #expect(model.errorMessage == "对话标题不能超过 160 个字符。")
        #expect(renameCount == 1)

        model.deleteCurrentConversation()
        model.deleteCurrentConversation()
        #expect(model.isConversationMutating)
        #expect(model.conversations.count == 1)
        try await Self.waitUntil { !model.isConversationMutating }
        #expect(deleteCount == 1)
        #expect(model.conversations.isEmpty)
        #expect(model.selectedConversationId == nil)
        #expect(model.statusMessage == "对话已删除。")
    }

    @Test @MainActor func documentDeletion_keepsServerCommitWhenRefreshFails() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            if request.httpMethod == "DELETE" {
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 500, body: #"{"detail":"delete rejected"}"#)
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let document = LearningDocumentItem(id: "doc-1", workspaceId: "ws-1", title: "作业", originalFilename: "homework.pdf", fileType: "pdf", documentKind: "homework", status: "ready")
        let reference = HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "doc-1", referenceType: "answer_key", createdAt: "")
        model.documents = [document]
        model.gradingDocuments = [document]
        model.homeworkReferences = [reference]

        model.deleteDocument(document)
        #expect(model.isBusy)
        #expect(model.documents == [document])
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents == [document])
        #expect(model.gradingDocuments == [document])
        #expect(model.homeworkReferences == [reference])
        #expect(model.errorMessage == "delete rejected")

        MockURLProtocol.handler = { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc-1":
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 202, body: #"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#)
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-1", status: "succeeded", progress: 100))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1/events":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"refresh unavailable"}"#)
            }
        }
        model.errorMessage = nil
        model.deleteDocument(document)
        #expect(model.documents == [document])
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents.isEmpty)
        #expect(model.gradingDocuments.isEmpty)
        #expect(model.homeworkReferences.isEmpty)
        #expect(model.selectedTab == .documents)
        #expect(model.selectedDocumentsSection == .tasks)
        #expect(model.activeTask?.taskType == "purge_document")
        #expect(model.activeTask?.status == "succeeded")
        #expect(model.errorMessage == nil)
        #expect(model.statusMessage.contains("文档及派生数据已清理，但刷新失败"))
    }

    @Test @MainActor func failedDocumentPurge_canBeRetriedWithoutRestoringDocument() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var deleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc-1":
                deleteCount += 1
                let taskId = deleteCount == 1 ? "purge-1" : "purge-2"
                return Self.response(request, status: 202, body: "{\"ok\":true,\"document_id\":\"doc-1\",\"status\":\"deleted\",\"purge_status\":\"queued\",\"purge_task_id\":\"\(taskId)\"}")
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-1", status: "failed", progress: 45, errorMessage: "purge failed"))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1/events":
                return Self.response(request, status: 200, body: "[]")
            case "GET /api/v1/workspaces/ws-1/tasks/purge-2":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-2", status: "succeeded", progress: 100))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-2/events":
                return Self.response(request, status: 200, body: "[]")
            case "GET /api/v1/workspaces/ws-1/documents",
                 "GET /api/v1/workspaces/ws-1/learning-units",
                 "GET /api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let document = LearningDocumentItem(id: "doc-1", workspaceId: "ws-1", title: "作业", originalFilename: "homework.pdf", fileType: "pdf", documentKind: "homework", status: "ready")
        model.documents = [document]

        model.deleteDocument(document)
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents.isEmpty)
        #expect(model.activeTask?.status == "failed")
        #expect(model.canRetryDocumentPurge)
        #expect(model.errorMessage == "purge failed")

        model.retryDocumentPurge()
        try await Self.waitUntil { !model.isBusy }
        #expect(deleteCount == 2)
        #expect(model.documents.isEmpty)
        #expect(model.activeTask?.id == "purge-2")
        #expect(model.activeTask?.status == "succeeded")
        #expect(!model.canRetryDocumentPurge)
        #expect(model.statusMessage == "文档及派生数据清理完成。")
    }

    @Test @MainActor func processingValidationAndCancellation_stopResultReads() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var requestCount = 0
        var resultReadCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "POST /api/v1/workspaces/ws-1/documents/doc-ready/process":
                return Self.response(request, status: 201, body: Self.taskJSON)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1":
                return Self.response(request, status: 200, body: #"{"id":"task-1","workspace_id":"ws-1","task_type":"process_document","status":"cancelled","resource_type":"document","resource_id":"doc-ready","payload":{},"result":null,"error_message":null,"progress":25,"cancel_requested_at":"2026-07-11T01:00:00Z","created_at":"","updated_at":""}"#)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1/events":
                return Self.response(request, status: 200, body: #"[{"id":"event-1","workspace_id":"ws-1","task_id":"task-1","event_type":"task_cancelled","level":"warning","message":"Source document was deleted","progress":25,"data":{},"created_at":""}]"#)
            default:
                resultReadCount += 1
                return Self.response(request, status: 500, body: #"{"detail":"unexpected result read"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        let invalidDocument = LearningDocumentItem(id: "doc-created", workspaceId: "ws-1", originalFilename: "created.pdf", fileType: "pdf", documentKind: "homework", status: "created")
        model.startProcessing(invalidDocument)
        #expect(requestCount == 0)
        #expect(model.errorMessage == "只有已上传、就绪或失败的文档可以处理。")

        let readyDocument = LearningDocumentItem(id: "doc-ready", workspaceId: "ws-1", originalFilename: "ready.pdf", fileType: "pdf", documentKind: "homework", status: "uploaded")
        model.startProcessing(readyDocument)
        try await Self.waitUntil { !model.isBusy }
        #expect(model.activeTask?.status == "cancelled")
        #expect(model.activeTask?.cancelRequestedAt != nil)
        #expect(model.taskEvents.last?.message == "Source document was deleted")
        #expect(model.errorMessage == "Source document was deleted")
        #expect(resultReadCount == 0)
    }

    @Test @MainActor func aiPreference_isSerializedPersistedAndRolledBackOnFailure() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        defer {
            settings.clearSession()
            defaults.removePersistentDomain(forName: suiteName)
        }
        var requestCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            Thread.sleep(forTimeInterval: 0.08)
            return Self.response(request, status: 200, body: #"{"id":"u","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#)
        }
        let model = NotePatchViewModel(settings: settings, backendSession: session, tusSession: session)
        let activeSession = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.session = activeSession
        model.selectedWorkspaceId = "ws-1"
        model.aiHistoryEnabled = true

        model.updateAIHistoryEnabled(false)
        model.updateAIHistoryEnabled(true)
        #expect(model.isAIPreferenceUpdating)
        #expect(model.aiHistoryEnabled == false)
        try await Self.waitUntil { !model.isAIPreferenceUpdating }
        #expect(requestCount == 1)
        #expect(settings.loadSession()?.aiHistoryEnabled == false)
        #expect(model.statusMessage == "AI 历史设置已保存。")

        MockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"preference rejected"}"#)
        }
        model.updateAIHistoryEnabled(true)
        try await Self.waitUntil { !model.isAIPreferenceUpdating }
        #expect(model.aiHistoryEnabled == false)
        #expect(settings.loadSession()?.aiHistoryEnabled == false)
        #expect(model.errorMessage == "preference rejected")
    }

    @Test @MainActor func gradingDraftAndReferenceDeletion_reflectServerState() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var referenceDeleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: 500, body: #"{"detail":"grading rejected"}"#)
            case "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                referenceDeleteCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 204, body: "")
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业", rubricText: "旧标准", maxScore: 100)]
        model.selectedHomeworkId = "h-1"
        model.homeworkRubricText = "旧标准"
        model.homeworkMaxScoreText = "100"
        #expect(!model.isGradingConfigDirty)

        model.homeworkRubricText = "新标准"
        #expect(model.isGradingConfigDirty)
        model.saveGradingConfig()
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.homeworkRubricText == "新标准")
        #expect(model.selectedHomework?.rubricText == "旧标准")
        #expect(model.isGradingConfigDirty)
        #expect(model.errorMessage == "grading rejected")
        #expect(!model.statusMessage.contains("已保存"))

        let reference = HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key", createdAt: "")
        model.homeworkReferences = [reference]
        model.lastGradingTask = TaskItem(id: "grade-1", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", result: .object(["grading_mode": .string("official")]), progress: 100)
        model.deleteHomeworkReference(reference)
        model.deleteHomeworkReference(reference)
        #expect(model.homeworkReferences == [reference])
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(referenceDeleteCount == 1)
        #expect(model.homeworkReferences.isEmpty)
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == "评分依据已删除，请重新评分。")
    }

    @Test @MainActor func successfulGradingMutations_clearStaleResult() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: 200, body: #"{"id":"h-1","workspace_id":"ws-1","title":"作业","document_id":"homework-1","status":"draft","rubric_text":"新标准","max_score":100,"metadata":{},"created_by_user_id":"u","created_at":"","updated_at":""}"#)
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 201, body: #"{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedHomeworkId = "h-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业", documentId: "homework-1", rubricText: "旧标准", maxScore: 100)]
        model.homeworkRubricText = "新标准"
        model.homeworkMaxScoreText = "100"
        model.lastGradingTask = TaskItem(id: "grade-1", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", progress: 100)

        model.saveGradingConfig()
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == "评分配置已保存，请重新评分。")

        model.lastGradingTask = TaskItem(id: "grade-2", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", progress: 100)
        model.gradingDocuments = [LearningDocumentItem(id: "answer-1", workspaceId: "ws-1", originalFilename: "answer.pdf", fileType: "pdf", documentKind: "answer_key", status: "ready")]
        model.addHomeworkReference(documentId: "answer-1")
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.homeworkReferences.first?.documentId == "answer-1")
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == "评分依据已添加，请重新评分。")
    }

    @Test @MainActor func serverURLs_persistAcrossModelInstances() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        let model = NotePatchViewModel(settings: settings)
        model.apiBaseURLText = "https://api.example.test/"
        model.tusBaseURLText = "https://tus.example.test/files"
        model.saveServerURLs()

        let restored = NotePatchViewModel(settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)))
        #expect(restored.apiBaseURLText == "https://api.example.test/api/v1")
        #expect(restored.tusBaseURLText == "https://tus.example.test/files/")
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

    @Test @MainActor func uiTestEmail_entersEphemeralWorkbenchWithoutNetwork() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        var requestCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(settings: settings, backendSession: session, tusSession: session)
        model.emailText = "  UiTeSt  "
        model.passwordText = ""
        model.authenticate(register: false)

        #expect(model.isOfflineTestMode)
        #expect(model.session?.email == "uitest")
        #expect(model.selectedWorkspaceId == "ui-workspace")
        #expect(model.workspaces.first?.name == "My Workspace")
        #expect(model.statusMessage == "UI 离线测试模式")
        #expect(settings.loadSession() == nil)
        #expect(requestCount == 0)

        await model.restoreIfNeeded()
        model.handleScenePhase(.active)
        model.loadChatHistory()
        model.loadLearningDashboard()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(requestCount == 0)

        model.logout()
        #expect(model.session == nil)
        #expect(!model.isOfflineTestMode)
        #expect(settings.loadSession() == nil)
        #expect(requestCount == 0)

        model.emailText = "uitest"
        model.passwordText = ""
        model.authenticate(register: true)
        #expect(model.session == nil)
        #expect(model.errorMessage == "请输入邮箱和密码。")
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

    static func purgeTaskJSON(
        id: String,
        status: String,
        progress: Int,
        errorMessage: String? = nil
    ) -> String {
        let errorValue = errorMessage.map { "\"\($0)\"" } ?? "null"
        return
            """
            {
              "id": "\(id)",
              "workspace_id": "ws-1",
              "task_type": "purge_document",
              "status": "\(status)",
              "resource_type": "document",
              "resource_id": "doc-1",
              "payload": {"document_id":"doc-1"},
              "result": null,
              "error_message": \(errorValue),
              "progress": \(progress),
              "cancel_requested_at": null,
              "created_at": "",
              "updated_at": ""
            }
            """
    }

    static let completedDocumentJSON =
        """
        {
          "id": "doc-completed",
          "workspace_id": "ws-1",
          "uploaded_by": "user-1",
          "title": "Uploaded",
          "original_filename": "uploaded.pdf",
          "mime_type": "application/pdf",
          "file_size": 0,
          "file_type": "pdf",
          "document_kind": "other",
          "storage_backend": "s3",
          "bucket": "notepatch",
          "object_key": "workspaces/ws-1/documents/doc-completed/original/uploaded.pdf",
          "upload_id": null,
          "tus_upload_url": null,
          "sha256": null,
          "status": "uploaded",
          "created_at": "",
          "updated_at": "",
          "artifacts": []
        }
        """

    @MainActor
    static func waitUntil(
        attempts: Int = 200,
        condition: () -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw LearningBackendError("Timed out waiting for test condition")
    }

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
