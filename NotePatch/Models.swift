import Foundation

let defaultLearningBackendBaseURL = "http://192.168.100.123:8001/api/v1"
let defaultTUSDBaseURL = "http://192.168.100.123:1080/files/"

func normalizeLearningBackendBaseURL(_ rawBaseURL: String) -> String {
    let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let withScheme: String
    if trimmed.isEmpty {
        withScheme = defaultLearningBackendBaseURL
    } else if trimmed.contains("://") {
        withScheme = trimmed
    } else {
        withScheme = "http://\(trimmed)"
    }
    let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard var components = URLComponents(string: normalized) else {
        return normalized
    }
    if components.path.isEmpty || components.path == "/" {
        components.path = "/api/v1"
    }
    return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? normalized
}

func normalizeTUSBaseURL(_ rawBaseURL: String) -> String {
    let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let withScheme: String
    if trimmed.isEmpty {
        withScheme = defaultTUSDBaseURL
    } else if trimmed.contains("://") {
        withScheme = trimmed
    } else {
        withScheme = "http://\(trimmed)"
    }
    return withScheme.hasSuffix("/") ? withScheme : "\(withScheme)/"
}

struct LearningBackendError: Error, LocalizedError {
    let message: String
    let statusCode: Int?
    let shouldClearSession: Bool
    let refreshTokenAttempt: String?
    let cause: Error?

    init(
        _ message: String,
        statusCode: Int? = nil,
        shouldClearSession: Bool = false,
        refreshTokenAttempt: String? = nil,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.shouldClearSession = shouldClearSession
        self.refreshTokenAttempt = refreshTokenAttempt
        self.cause = cause
    }

    var errorDescription: String? {
        message
    }
}

func shouldClearPersistedSession(
    for error: LearningBackendError,
    currentRefreshToken: String?
) -> Bool {
    guard error.shouldClearSession else {
        return false
    }
    guard let attemptedRefreshToken = error.refreshTokenAttempt else {
        return true
    }
    return currentRefreshToken == attemptedRefreshToken
}

struct BackendUser: Decodable, Equatable {
    let id: String
    let email: String
    let fullName: String?
    let isActive: Bool
    let createdAt: String
    let aiHistoryEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case isActive = "is_active"
        case createdAt = "created_at"
        case aiHistoryEnabled = "ai_history_enabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        aiHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiHistoryEnabled) ?? true
    }
}

struct TokenResponse: Decodable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: String
    let user: BackendUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case user
    }
}

struct AIHistoryPreferenceResponse: Decodable, Equatable {
    let aiHistoryEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case aiHistoryEnabled = "ai_history_enabled"
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Bool.self, forKey: .aiHistoryEnabled) {
            aiHistoryEnabled = value
        } else if let user = try container.decodeIfPresent(BackendUser.self, forKey: .user) {
            aiHistoryEnabled = user.aiHistoryEnabled
        } else {
            aiHistoryEnabled = true
        }
    }
}

struct PresenceHeartbeatResponse: Decodable, Equatable {
    let clientId: String
    let onlineUntil: String
    let heartbeatIntervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case onlineUntil = "online_until"
        case heartbeatIntervalSeconds = "heartbeat_interval_seconds"
    }
}

struct WorkspaceItem: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let type: String
    let ownerUserId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case ownerUserId = "owner_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        name: String,
        type: String = "personal",
        ownerUserId: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.ownerUserId = ownerUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "personal"
        ownerUserId = try container.decodeIfPresent(String.self, forKey: .ownerUserId) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct DocumentArtifactItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let documentId: String
    let artifactType: String
    let bucket: String
    let objectKey: String
    let mimeType: String?
    let fileSize: Int64?
    let metadataText: String?
    let metadataProcessor: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case documentId = "document_id"
        case artifactType = "artifact_type"
        case bucket
        case objectKey = "object_key"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case metadata
        case createdAt = "created_at"
    }

    init(
        id: String,
        workspaceId: String,
        documentId: String,
        artifactType: String,
        bucket: String,
        objectKey: String,
        mimeType: String?,
        fileSize: Int64?,
        metadataText: String?,
        metadataProcessor: String?,
        createdAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.documentId = documentId
        self.artifactType = artifactType
        self.bucket = bucket
        self.objectKey = objectKey
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.metadataText = metadataText
        self.metadataProcessor = metadataProcessor
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        documentId = try container.decode(String.self, forKey: .documentId)
        artifactType = try container.decodeIfPresent(String.self, forKey: .artifactType) ?? ""
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        objectKey = try container.decodeIfPresent(String.self, forKey: .objectKey) ?? ""
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""

        if let metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata),
           metadata.isNonEmptyObject {
            metadataText = metadata.displayString
            metadataProcessor = metadata.objectStringValue(for: "processor")
        } else {
            metadataText = nil
            metadataProcessor = nil
        }
    }
}

struct LearningDocumentItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let uploadedBy: String
    let title: String?
    let originalFilename: String
    let mimeType: String?
    let fileSize: Int64?
    let fileType: String
    let documentKind: String
    let storageBackend: String
    let bucket: String
    let objectKey: String
    let uploadId: String?
    let tusUploadURL: String?
    let sha256: String?
    let status: String
    let purgeStatus: String?
    let purgeTaskId: String?
    let purgedAt: String?
    let createdAt: String
    let updatedAt: String
    let artifacts: [DocumentArtifactItem]

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case uploadedBy = "uploaded_by"
        case title
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case fileType = "file_type"
        case documentKind = "document_kind"
        case storageBackend = "storage_backend"
        case bucket
        case objectKey = "object_key"
        case uploadId = "upload_id"
        case tusUploadURL = "tus_upload_url"
        case sha256
        case status
        case purgeStatus = "purge_status"
        case purgeTaskId = "purge_task_id"
        case purgedAt = "purged_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case artifacts
    }

    init(
        id: String,
        workspaceId: String,
        uploadedBy: String = "",
        title: String? = nil,
        originalFilename: String,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        fileType: String = "other",
        documentKind: String,
        storageBackend: String = "",
        bucket: String = "",
        objectKey: String = "",
        uploadId: String? = nil,
        tusUploadURL: String? = nil,
        sha256: String? = nil,
        status: String,
        purgeStatus: String? = nil,
        purgeTaskId: String? = nil,
        purgedAt: String? = nil,
        createdAt: String = "",
        updatedAt: String = "",
        artifacts: [DocumentArtifactItem] = []
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.uploadedBy = uploadedBy
        self.title = title
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.fileType = fileType
        self.documentKind = documentKind
        self.storageBackend = storageBackend
        self.bucket = bucket
        self.objectKey = objectKey
        self.uploadId = uploadId
        self.tusUploadURL = tusUploadURL
        self.sha256 = sha256
        self.status = status
        self.purgeStatus = purgeStatus
        self.purgeTaskId = purgeTaskId
        self.purgedAt = purgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.artifacts = artifacts
    }
}

struct DocumentDeleteResponse: Decodable, Equatable {
    let ok: Bool?
    let documentId: String
    let status: String
    let purgeStatus: String
    let purgeTaskId: String

    enum CodingKeys: String, CodingKey {
        case ok
        case documentId = "document_id"
        case status
        case purgeStatus = "purge_status"
        case purgeTaskId = "purge_task_id"
    }
}

struct UploadSessionItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let userId: String
    let documentId: String
    let tusUploadId: String?
    let tusUploadURL: String?
    let bucket: String
    let objectKey: String
    let status: String
    let expiresAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case documentId = "document_id"
        case tusUploadId = "tus_upload_id"
        case tusUploadURL = "tus_upload_url"
        case bucket
        case objectKey = "object_key"
        case status
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct UploadSessionResponse: Decodable, Equatable {
    let document: LearningDocumentItem
    let uploadSession: UploadSessionItem
    let tusEndpoint: String
    let tusMetadata: [String: String]
    let tusMetadataHeader: String
    let bucket: String
    let objectKey: String

    enum CodingKeys: String, CodingKey {
        case document
        case uploadSession = "upload_session"
        case tusEndpoint = "tus_endpoint"
        case tusMetadata = "tus_metadata"
        case tusMetadataHeader = "tus_metadata_header"
        case bucket
        case objectKey = "object_key"
    }
}

struct DownloadURLResponse: Decodable, Equatable {
    let downloadURL: String
    let expiresSeconds: Int

    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case expiresSeconds = "expires_seconds"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
        expiresSeconds = try container.decodeIfPresent(Int.self, forKey: .expiresSeconds)
            ?? container.decodeIfPresent(Int.self, forKey: .expiresIn)
            ?? 0
    }
}

struct ArtifactDownloadURLResponse: Decodable, Equatable {
    let artifactId: String
    let documentId: String
    let artifactType: String
    let filename: String
    let mimeType: String?
    let expiresSeconds: Int
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case documentId = "document_id"
        case artifactType = "artifact_type"
        case filename
        case mimeType = "mime_type"
        case expiresSeconds = "expires_seconds"
        case expiresIn = "expires_in"
        case downloadURL = "download_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artifactId = try container.decode(String.self, forKey: .artifactId)
        documentId = try container.decode(String.self, forKey: .documentId)
        artifactType = try container.decodeIfPresent(String.self, forKey: .artifactType) ?? ""
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? artifactId
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        expiresSeconds = try container.decodeIfPresent(Int.self, forKey: .expiresSeconds)
            ?? container.decodeIfPresent(Int.self, forKey: .expiresIn)
            ?? 0
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
    }
}

struct OcrArtifactItem: Decodable, Equatable, Identifiable {
    let id: String
    let artifactType: String
    let mimeType: String?
    let fileSize: Int64?
    let createdAt: String
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case artifactType = "artifact_type"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case createdAt = "created_at"
        case downloadURL = "download_url"
    }
}

struct OcrArtifactsResponse: Decodable, Equatable {
    let documentId: String
    let artifacts: [OcrArtifactItem]

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case artifacts
    }
}

struct ChatConversation: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let title: String
    let lastMessageAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChatMessage: Decodable, Equatable, Identifiable {
    let id: String
    let conversationId: String
    let role: String
    let content: String
    let taskId: String?
    let status: String
    let errorMessage: String?
    let citations: [ChatCitation]?
    let sourceStatus: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case taskId = "task_id"
        case status
        case errorMessage = "error_message"
        case citations
        case sourceStatus = "source_status"
        case createdAt = "created_at"
    }
}

struct ChatCitation: Decodable, Equatable {
    let chunkId: String?
    let documentId: String?
    let score: Double?
    let metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case documentId = "document_id"
        case score
        case metadata
    }
}

struct ChatConversationsResponse: Decodable, Equatable {
    let items: [ChatConversation]
    let page: Int
    let pageSize: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case pageSize = "page_size"
        case total
    }
}

struct ChatMessagesResponse: Decodable, Equatable {
    let items: [ChatMessage]
    let page: Int
    let pageSize: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case pageSize = "page_size"
        case total
    }
}

struct LearningUnit: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let subject: String?
    let gradeLevel: String?
    let topic: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subject
        case gradeLevel = "grade_level"
        case topic
    }
}

struct StudyNoteVersion: Decodable, Equatable, Identifiable {
    let id: String
    let learningUnitId: String
    let versionNo: Int
    let title: String
    let markdownObjectKey: String
    let jsonObjectKey: String
    let highlightedObjectKey: String?
    let highlightMapObjectKey: String?
    let sourceVersionId: String?
    let editOrigin: String?
    let editSummary: String?
    let downloadURLs: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case learningUnitId = "learning_unit_id"
        case versionNo = "version_no"
        case title
        case markdownObjectKey = "markdown_object_key"
        case jsonObjectKey = "json_object_key"
        case highlightedObjectKey = "highlighted_object_key"
        case highlightMapObjectKey = "highlight_map_object_key"
        case sourceVersionId = "source_version_id"
        case editOrigin = "edit_origin"
        case editSummary = "edit_summary"
        case downloadURLs = "download_urls"
    }

    init(
        id: String,
        learningUnitId: String,
        versionNo: Int,
        title: String,
        markdownObjectKey: String,
        jsonObjectKey: String,
        highlightedObjectKey: String? = nil,
        highlightMapObjectKey: String? = nil,
        sourceVersionId: String? = nil,
        editOrigin: String? = nil,
        editSummary: String? = nil,
        downloadURLs: [String: String] = [:]
    ) {
        self.id = id
        self.learningUnitId = learningUnitId
        self.versionNo = versionNo
        self.title = title
        self.markdownObjectKey = markdownObjectKey
        self.jsonObjectKey = jsonObjectKey
        self.highlightedObjectKey = highlightedObjectKey
        self.highlightMapObjectKey = highlightMapObjectKey
        self.sourceVersionId = sourceVersionId
        self.editOrigin = editOrigin
        self.editSummary = editSummary
        self.downloadURLs = downloadURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        learningUnitId = try container.decode(String.self, forKey: .learningUnitId)
        versionNo = try container.decode(Int.self, forKey: .versionNo)
        title = try container.decode(String.self, forKey: .title)
        markdownObjectKey = try container.decode(String.self, forKey: .markdownObjectKey)
        jsonObjectKey = try container.decode(String.self, forKey: .jsonObjectKey)
        highlightedObjectKey = try container.decodeIfPresent(String.self, forKey: .highlightedObjectKey)
        highlightMapObjectKey = try container.decodeIfPresent(String.self, forKey: .highlightMapObjectKey)
        sourceVersionId = try container.decodeIfPresent(String.self, forKey: .sourceVersionId)
        editOrigin = try container.decodeIfPresent(String.self, forKey: .editOrigin)
        editSummary = try container.decodeIfPresent(String.self, forKey: .editSummary)
        downloadURLs = try container.decodeIfPresent([String: String].self, forKey: .downloadURLs) ?? [:]
    }

    var preferredDownloadURL: String? {
        downloadURLs["highlighted"] ?? downloadURLs["markdown"] ?? downloadURLs["json"]
    }

    var preferredMarkdownDownloadURL: String? {
        downloadURLs["highlighted"] ?? downloadURLs["markdown"]
    }

    var jsonDownloadURL: String? {
        downloadURLs["json"]
    }

    var revisionOriginLabel: String {
        switch editOrigin {
        case "user": return "User Revision"
        case "admin": return "Admin Revision"
        case "skill": return "Auto-generated"
        default: return versionNo > 1 ? "Revised" : "Auto-generated"
        }
    }
}

struct StudyNoteRevisionInput: Equatable {
    let markdown: String
    let title: String?
    let editSummary: String?

    var payload: [String: Any] {
        var values: [String: Any] = ["markdown": markdown]
        if let title { values["title"] = title }
        if let editSummary { values["edit_summary"] = editSummary }
        return values
    }
}

struct StudyNoteRevisionResponse: Decodable, Equatable {
    let note: StudyNoteVersion
    let downstreamTasks: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case note
        case downstreamTasks = "downstream_tasks"
    }
}

struct StudyNoteListItem: Equatable, Identifiable {
    let learningUnit: LearningUnit
    let note: StudyNoteVersion

    var id: String { "\(learningUnit.id)-\(note.id)" }
}

struct StudyNoteGroup: Equatable, Identifiable {
    let learningUnit: LearningUnit
    let notes: [StudyNoteListItem]

    var id: String { learningUnit.id }
}

struct LearningMetadata: Equatable {
    var learningUnitId = ""
    var learningUnitTitle = ""
    var subject = ""
    var gradeLevel = ""
    var topic = ""

    var payload: [String: String] {
        var values: [String: String] = [:]
        if !learningUnitId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["learning_unit_id"] = learningUnitId.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if !learningUnitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["learning_unit_title"] = learningUnitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        ["subject": subject, "grade_level": gradeLevel, "topic": topic].forEach { key, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values[key] = trimmed
            }
        }
        return values
    }
}

struct KnowledgeSearchItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let documentId: String?
    let subject: String?
    let gradeLevel: String?
    let sourceType: String?
    let content: String
    let metadata: JSONValue
    let score: Double
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case documentId = "document_id"
        case subject
        case gradeLevel = "grade_level"
        case sourceType = "source_type"
        case content
        case metadata
        case score
        case createdAt = "created_at"
    }

    var metadataTitle: String? { metadata.objectStringValue(for: "title") }
    var pageReferences: String? {
        guard case .object(let values) = metadata, case .array(let pages)? = values["page_refs"] else { return nil }
        let labels = pages.compactMap { value -> String? in
            switch value {
            case .number(let number): return number.rounded() == number ? String(Int(number)) : String(number)
            case .string(let string): return string
            default: return nil
            }
        }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }
}

struct KnowledgeSearchResponse: Decodable, Equatable {
    let items: [KnowledgeSearchItem]
}

struct HomeworkItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let title: String
    let description: String?
    let documentId: String?
    let dueAt: String?
    let status: String
    let rubricText: String?
    let maxScore: Double
    let metadata: JSONValue
    let createdByUserId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title
        case description
        case documentId = "document_id"
        case dueAt = "due_at"
        case status
        case rubricText = "rubric_text"
        case maxScore = "max_score"
        case metadata
        case createdByUserId = "created_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        workspaceId: String,
        title: String,
        description: String? = nil,
        documentId: String? = nil,
        dueAt: String? = nil,
        status: String = "draft",
        rubricText: String? = nil,
        maxScore: Double = 100,
        metadata: JSONValue = .object([:]),
        createdByUserId: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.description = description
        self.documentId = documentId
        self.dueAt = dueAt
        self.status = status
        self.rubricText = rubricText
        self.maxScore = maxScore
        self.metadata = metadata
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        rubricText = try container.decodeIfPresent(String.self, forKey: .rubricText)
        maxScore = try container.decodeIfPresent(Double.self, forKey: .maxScore) ?? 100
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata) ?? .object([:])
        createdByUserId = try container.decodeIfPresent(String.self, forKey: .createdByUserId) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct HomeworkCreateInput: Equatable {
    let title: String
    let description: String?
    let documentId: String
    let dueAt: String?
    let rubricText: String?
    let maxScore: Double

    var payload: [String: Any] {
        var values: [String: Any] = [
            "title": title,
            "document_id": documentId,
            "max_score": maxScore,
            "metadata": [:]
        ]
        if let description, !description.isEmpty { values["description"] = description }
        if let dueAt { values["due_at"] = dueAt }
        if let rubricText { values["rubric_text"] = rubricText }
        return values
    }

    static func == (lhs: HomeworkCreateInput, rhs: HomeworkCreateInput) -> Bool {
        lhs.title == rhs.title && lhs.description == rhs.description && lhs.documentId == rhs.documentId && lhs.dueAt == rhs.dueAt && lhs.rubricText == rhs.rubricText && lhs.maxScore == rhs.maxScore
    }
}

struct GradingConfigInput: Equatable {
    let rubricText: String?
    let maxScore: Double

    var payload: [String: Any] {
        ["rubric_text": rubricText ?? NSNull(), "max_score": maxScore]
    }
}

struct HomeworkReferenceItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let homeworkId: String
    let documentId: String
    let referenceType: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case homeworkId = "homework_id"
        case documentId = "document_id"
        case referenceType = "reference_type"
        case createdAt = "created_at"
    }
}

struct TaskItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let taskType: String
    let status: String
    let resourceType: String?
    let resourceId: String?
    let payload: JSONValue?
    let result: JSONValue?
    let resultText: String?
    let errorMessage: String?
    let progress: Int
    let cancelRequestedAt: String?
    let createdAt: String
    let updatedAt: String
    let startedAt: String?
    let finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case taskType = "task_type"
        case status
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case payload
        case result
        case errorMessage = "error_message"
        case progress
        case cancelRequestedAt = "cancel_requested_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    init(
        id: String,
        workspaceId: String,
        taskType: String,
        status: String,
        resourceType: String? = nil,
        resourceId: String? = nil,
        payload: JSONValue? = nil,
        result: JSONValue? = nil,
        errorMessage: String? = nil,
        progress: Int = 0,
        cancelRequestedAt: String? = nil,
        createdAt: String = "",
        updatedAt: String = "",
        startedAt: String? = nil,
        finishedAt: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.taskType = taskType
        self.status = status
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.payload = payload
        self.result = result
        self.resultText = result?.displayString
        self.errorMessage = errorMessage
        self.progress = progress
        self.cancelRequestedAt = cancelRequestedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        taskType = try container.decodeIfPresent(String.self, forKey: .taskType) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        resourceType = try container.decodeIfPresent(String.self, forKey: .resourceType)
        resourceId = try container.decodeIfPresent(String.self, forKey: .resourceId)
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        resultText = result?.displayString
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        cancelRequestedAt = try container.decodeIfPresent(String.self, forKey: .cancelRequestedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
    }
}

struct TaskEventItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let taskId: String
    let eventType: String
    let level: String
    let message: String
    let progress: Int?
    let dataText: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case taskId = "task_id"
        case eventType = "event_type"
        case level
        case message
        case progress
        case data
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        taskId = try container.decode(String.self, forKey: .taskId)
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        dataText = try container.decodeIfPresent(JSONValue.self, forKey: .data)?.displayString
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

struct SavedSession: Equatable {
    let baseURL: String
    let tusBaseURL: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: String
    let userId: String
    let email: String
    let fullName: String?
    let selectedWorkspaceId: String?
    let aiHistoryEnabled: Bool

    func withTokenResponse(_ tokenResponse: TokenResponse) -> SavedSession {
        SavedSession(
            baseURL: baseURL,
            tusBaseURL: tusBaseURL,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: tokenResponse.expiresAt,
            userId: tokenResponse.user.id,
            email: tokenResponse.user.email,
            fullName: tokenResponse.user.fullName,
            selectedWorkspaceId: selectedWorkspaceId,
            aiHistoryEnabled: tokenResponse.user.aiHistoryEnabled
        )
    }

    func withAIHistoryEnabled(_ enabled: Bool) -> SavedSession {
        SavedSession(
            baseURL: baseURL,
            tusBaseURL: tusBaseURL,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            email: email,
            fullName: fullName,
            selectedWorkspaceId: selectedWorkspaceId,
            aiHistoryEnabled: enabled
        )
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int64(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array:
            guard let data = try? JSONEncoder.notepatch.encode(self),
                  let string = String(data: data, encoding: .utf8) else {
                return ""
            }
            return string
        case .null:
            return ""
        }
    }

    var isNonEmptyObject: Bool {
        if case .object(let object) = self {
            return !object.isEmpty
        }
        return false
    }

    func objectStringValue(for key: String) -> String? {
        guard case .object(let object) = self, case .string(let value)? = object[key], !value.isEmpty else {
            return nil
        }
        return value
    }

    func objectDoubleValue(for key: String) -> Double? {
        guard case .object(let object) = self else { return nil }
        switch object[key] {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }
}

extension JSONDecoder {
    static let notepatch: JSONDecoder = {
        JSONDecoder()
    }()
}

extension JSONEncoder {
    static let notepatch: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
