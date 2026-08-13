import Foundation

let defaultServiceRootURL = "https://api.ls-jl.cn:8443/notepatch/1"
let defaultTUSDServiceRootURL = "https://api.ls-jl.cn:8443/notepatch/2"
let defaultLearningBackendBaseURL = defaultServiceRootURL
let defaultTUSDBaseURL = "\(defaultTUSDServiceRootURL)/files/"

func normalizeLearningBackendBaseURL(_ rawBaseURL: String) -> String {
    let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = path.isEmpty ? "" : "/\(path)"
    components.query = nil
    components.fragment = nil
    return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? normalized
}

func migrateLegacyLearningBackendBaseURL(_ rawBaseURL: String) -> String {
    let normalized = normalizeLearningBackendBaseURL(rawBaseURL)
    guard var components = URLComponents(string: normalized) else { return normalized }
    var segments = components.path.split(separator: "/").map(String.init)
    if segments.count >= 2, Array(segments.suffix(2)) == ["api", "v1"] {
        segments.removeLast(2)
        components.path = segments.isEmpty ? "" : "/\(segments.joined(separator: "/"))"
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
    let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard var components = URLComponents(string: normalized) else {
        return "\(normalized)/"
    }
    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let defaultRootPath = URLComponents(string: defaultTUSDServiceRootURL)?.path
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if path.isEmpty || path == defaultRootPath {
        components.path = path.isEmpty ? "/files" : "/\(path)/files"
    }
    let resolved = components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? normalized
    return "\(resolved)/"
}

struct LearningBackendError: Error, LocalizedError {
    let message: String
    let statusCode: Int?
    let shouldClearSession: Bool
    let refreshTokenAttempt: String?
    let cause: Error?

    nonisolated init(
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

    nonisolated var errorDescription: String? {
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
    let scanStatus: String?
    let scanMessage: String?
    let scannedAt: String?
    let detectedMimeType: String?
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
        case scanStatus = "scan_status"
        case scanMessage = "scan_message"
        case scannedAt = "scanned_at"
        case detectedMimeType = "detected_mime_type"
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
        scanStatus: String? = nil,
        scanMessage: String? = nil,
        scannedAt: String? = nil,
        detectedMimeType: String? = nil,
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
        self.scanStatus = scanStatus
        self.scanMessage = scanMessage
        self.scannedAt = scannedAt
        self.detectedMimeType = detectedMimeType
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

struct AiModel: Decodable, Equatable, Identifiable {
    let id: String
    let upstreamId: String
    let ownedBy: String?
    let created: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case upstreamId = "upstream_id"
        case ownedBy = "owned_by"
        case created
    }
}

struct AiModelCatalog: Decodable, Equatable {
    let provider: String
    let defaultModel: String
    let selectedModel: String
    let items: [AiModel]
    let fetchedAt: String
    let stale: Bool

    enum CodingKeys: String, CodingKey {
        case provider
        case defaultModel = "default_model"
        case selectedModel = "selected_model"
        case items
        case fetchedAt = "fetched_at"
        case stale
    }

    func applying(_ selection: AiModelSelectionResponse) -> AiModelCatalog {
        AiModelCatalog(
            provider: provider,
            defaultModel: selection.defaultModel,
            selectedModel: selection.selectedModel,
            items: items,
            fetchedAt: fetchedAt,
            stale: stale
        )
    }
}

struct AiModelSelectionResponse: Decodable, Equatable {
    let selectedModel: String
    let preferredModel: String?
    let defaultModel: String

    enum CodingKeys: String, CodingKey {
        case selectedModel = "selected_model"
        case preferredModel = "preferred_model"
        case defaultModel = "default_model"
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
    let modelId: String?
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
        case modelId = "model_id"
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
    let workspaceId: String?
    let title: String
    let subject: String?
    let gradeLevel: String?
    let topic: String?
    let metadata: [String: JSONValue]
    let knowledgeRevision: Int
    let attemptRevision: Int
    let notesGeneratedRevision: Int
    let noteGenerationDueAt: String?
    let mergeStatus: String?
    let mergedIntoId: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title
        case subject
        case gradeLevel = "grade_level"
        case topic
        case metadata
        case knowledgeRevision = "knowledge_revision"
        case attemptRevision = "attempt_revision"
        case notesGeneratedRevision = "notes_generated_revision"
        case noteGenerationDueAt = "note_generation_due_at"
        case mergeStatus = "merge_status"
        case mergedIntoId = "merged_into_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        workspaceId: String? = nil,
        title: String,
        subject: String? = nil,
        gradeLevel: String? = nil,
        topic: String? = nil,
        metadata: [String: JSONValue] = [:],
        knowledgeRevision: Int = 0,
        attemptRevision: Int = 0,
        notesGeneratedRevision: Int = 0,
        noteGenerationDueAt: String? = nil,
        mergeStatus: String? = nil,
        mergedIntoId: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.subject = subject
        self.gradeLevel = gradeLevel
        self.topic = topic
        self.metadata = metadata
        self.knowledgeRevision = knowledgeRevision
        self.attemptRevision = attemptRevision
        self.notesGeneratedRevision = notesGeneratedRevision
        self.noteGenerationDueAt = noteGenerationDueAt
        self.mergeStatus = mergeStatus
        self.mergedIntoId = mergedIntoId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        title = try container.decode(String.self, forKey: .title)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        gradeLevel = try container.decodeIfPresent(String.self, forKey: .gradeLevel)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        knowledgeRevision = try container.decodeIfPresent(Int.self, forKey: .knowledgeRevision) ?? 0
        attemptRevision = try container.decodeIfPresent(Int.self, forKey: .attemptRevision) ?? 0
        notesGeneratedRevision = try container.decodeIfPresent(Int.self, forKey: .notesGeneratedRevision) ?? 0
        noteGenerationDueAt = try container.decodeIfPresent(String.self, forKey: .noteGenerationDueAt)
        mergeStatus = try container.decodeIfPresent(String.self, forKey: .mergeStatus)
        mergedIntoId = try container.decodeIfPresent(String.self, forKey: .mergedIntoId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct StudyNoteVersion: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String?
    let learningUnitId: String
    let taskId: String?
    let versionNo: Int
    let title: String
    let htmlObjectKey: String
    let jsonObjectKey: String
    let highlightedHTMLObjectKey: String?
    let highlightMapObjectKey: String?
    let knowledgePointIds: [String]
    let sourceDocumentIds: [String]
    let sourceMistakeIds: [String]
    let sourceVersionId: String?
    let editedByUserId: String?
    let editOrigin: String?
    let editSummary: String?
    let metadata: [String: JSONValue]
    let createdAt: String?
    let downloadURLs: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case learningUnitId = "learning_unit_id"
        case taskId = "task_id"
        case versionNo = "version_no"
        case title
        case htmlObjectKey = "html_object_key"
        case legacyMarkdownObjectKey = "markdown_object_key"
        case jsonObjectKey = "json_object_key"
        case highlightedHTMLObjectKey = "highlighted_html_object_key"
        case legacyHighlightedObjectKey = "highlighted_object_key"
        case highlightMapObjectKey = "highlight_map_object_key"
        case knowledgePointIds = "knowledge_point_ids"
        case sourceDocumentIds = "source_document_ids"
        case sourceMistakeIds = "source_mistake_ids"
        case sourceVersionId = "source_version_id"
        case editedByUserId = "edited_by_user_id"
        case editOrigin = "edit_origin"
        case editSummary = "edit_summary"
        case metadata
        case createdAt = "created_at"
        case downloadURLs = "download_urls"
    }

    init(
        id: String,
        workspaceId: String? = nil,
        learningUnitId: String,
        taskId: String? = nil,
        versionNo: Int,
        title: String,
        htmlObjectKey: String,
        jsonObjectKey: String,
        highlightedHTMLObjectKey: String? = nil,
        highlightMapObjectKey: String? = nil,
        knowledgePointIds: [String] = [],
        sourceDocumentIds: [String] = [],
        sourceMistakeIds: [String] = [],
        sourceVersionId: String? = nil,
        editedByUserId: String? = nil,
        editOrigin: String? = nil,
        editSummary: String? = nil,
        metadata: [String: JSONValue] = [:],
        createdAt: String? = nil,
        downloadURLs: [String: String] = [:]
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.learningUnitId = learningUnitId
        self.taskId = taskId
        self.versionNo = versionNo
        self.title = title
        self.htmlObjectKey = htmlObjectKey
        self.jsonObjectKey = jsonObjectKey
        self.highlightedHTMLObjectKey = highlightedHTMLObjectKey
        self.highlightMapObjectKey = highlightMapObjectKey
        self.knowledgePointIds = knowledgePointIds
        self.sourceDocumentIds = sourceDocumentIds
        self.sourceMistakeIds = sourceMistakeIds
        self.sourceVersionId = sourceVersionId
        self.editedByUserId = editedByUserId
        self.editOrigin = editOrigin
        self.editSummary = editSummary
        self.metadata = metadata
        self.createdAt = createdAt
        self.downloadURLs = downloadURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        learningUnitId = try container.decode(String.self, forKey: .learningUnitId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        versionNo = try container.decode(Int.self, forKey: .versionNo)
        title = try container.decode(String.self, forKey: .title)
        htmlObjectKey = try container.decodeIfPresent(String.self, forKey: .htmlObjectKey)
            ?? container.decodeIfPresent(String.self, forKey: .legacyMarkdownObjectKey)
            ?? ""
        jsonObjectKey = try container.decode(String.self, forKey: .jsonObjectKey)
        highlightedHTMLObjectKey = try container.decodeIfPresent(String.self, forKey: .highlightedHTMLObjectKey)
            ?? container.decodeIfPresent(String.self, forKey: .legacyHighlightedObjectKey)
        highlightMapObjectKey = try container.decodeIfPresent(String.self, forKey: .highlightMapObjectKey)
        knowledgePointIds = try container.decodeIfPresent([String].self, forKey: .knowledgePointIds) ?? []
        sourceDocumentIds = try container.decodeIfPresent([String].self, forKey: .sourceDocumentIds) ?? []
        sourceMistakeIds = try container.decodeIfPresent([String].self, forKey: .sourceMistakeIds) ?? []
        sourceVersionId = try container.decodeIfPresent(String.self, forKey: .sourceVersionId)
        editedByUserId = try container.decodeIfPresent(String.self, forKey: .editedByUserId)
        editOrigin = try container.decodeIfPresent(String.self, forKey: .editOrigin)
        editSummary = try container.decodeIfPresent(String.self, forKey: .editSummary)
        metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        downloadURLs = try container.decodeIfPresent([String: String].self, forKey: .downloadURLs) ?? [:]
    }

    var preferredDownloadURL: String? {
        renderedHTMLDownloadURL ?? preferredHTMLDownloadURL ?? downloadURLs["json"]
    }

    var renderedHTMLDownloadURL: String? {
        downloadURLs["rendered_html"]
    }

    var preferredHTMLDownloadURL: String? {
        downloadURLs["highlighted_html"]
            ?? downloadURLs["html"]
            ?? downloadURLs["highlighted"]
            ?? downloadURLs["markdown"]
    }

    var jsonDownloadURL: String? {
        downloadURLs["json"]
    }

    var revisionOriginLabel: String {
        switch editOrigin {
        case "user": return localized("note.origin.user")
        case "admin": return localized("note.origin.admin")
        case "skill": return localized("note.origin.generated")
        default: return versionNo > 1 ? localized("note.origin.revised") : localized("note.origin.generated")
        }
    }
}

struct StudyNoteRevisionInput: Equatable {
    let html: String
    let title: String?
    let editSummary: String?

    var payload: [String: Any] {
        var values: [String: Any] = ["html": html]
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

    var generationState: StudyNoteGenerationState {
        if ["merging", "rebuilding"].contains(learningUnit.mergeStatus ?? "") { return .generating }
        if learningUnit.mergeStatus == "failed" { return .unavailable }
        if learningUnit.knowledgeRevision == 0 { return .noKnowledge }
        if learningUnit.notesGeneratedRevision < learningUnit.knowledgeRevision { return .generating }
        return notes.isEmpty ? .unavailable : .ready
    }

    var isLatestNoteStale: Bool {
        !notes.isEmpty && learningUnit.notesGeneratedRevision < learningUnit.knowledgeRevision
    }
}

enum StudyNoteGenerationState: String, Equatable {
    case noKnowledge
    case generating
    case ready
    case unavailable
}

enum StudyNoteDownloadKind: String {
    case html
    case json
    case highlightedHTML = "highlighted_html"
    case highlightMap = "highlight_map"
    case renderedHTML = "rendered_html"
}

struct StudyNoteDownloadURLResponse: Decodable, Equatable {
    let noteVersionId: String
    let learningUnitId: String
    let kind: String
    let filename: String
    let expiresIn: Int
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case noteVersionId = "note_version_id"
        case learningUnitId = "learning_unit_id"
        case kind
        case filename
        case expiresIn = "expires_in"
        case downloadURL = "download_url"
    }
}

struct FlashcardDeck: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let learningUnitId: String
    let studyNoteVersionId: String
    let taskId: String?
    let versionNo: Int
    let attemptRevision: Int
    let weightingConfig: [String: JSONValue]
    let metadata: [String: JSONValue]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case learningUnitId = "learning_unit_id"
        case studyNoteVersionId = "study_note_version_id"
        case taskId = "task_id"
        case versionNo = "version_no"
        case attemptRevision = "attempt_revision"
        case weightingConfig = "weighting_config"
        case metadata
        case createdAt = "created_at"
    }

    init(
        id: String,
        workspaceId: String,
        learningUnitId: String,
        studyNoteVersionId: String,
        taskId: String? = nil,
        versionNo: Int,
        attemptRevision: Int,
        weightingConfig: [String: JSONValue] = [:],
        metadata: [String: JSONValue] = [:],
        createdAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.learningUnitId = learningUnitId
        self.studyNoteVersionId = studyNoteVersionId
        self.taskId = taskId
        self.versionNo = versionNo
        self.attemptRevision = attemptRevision
        self.weightingConfig = weightingConfig
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

struct Flashcard: Decodable, Equatable, Identifiable {
    let id: String
    let knowledgePointId: String
    let front: String
    let back: String
    let priorityScore: Double
    let priorityFactors: [String: JSONValue]
    let sourceRefs: [JSONValue]
    let difficulty: String?
    let rank: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case knowledgePointId = "knowledge_point_id"
        case front
        case back
        case priorityScore = "priority_score"
        case priorityFactors = "priority_factors"
        case sourceRefs = "source_refs"
        case difficulty
        case rank
        case createdAt = "created_at"
    }

    init(
        id: String,
        knowledgePointId: String,
        front: String,
        back: String,
        priorityScore: Double,
        priorityFactors: [String: JSONValue] = [:],
        sourceRefs: [JSONValue] = [],
        difficulty: String? = nil,
        rank: Int,
        createdAt: String
    ) {
        self.id = id
        self.knowledgePointId = knowledgePointId
        self.front = front
        self.back = back
        self.priorityScore = priorityScore
        self.priorityFactors = priorityFactors
        self.sourceRefs = sourceRefs
        self.difficulty = difficulty
        self.rank = rank
        self.createdAt = createdAt
    }
}

struct FlashcardDeckDetail: Decodable, Equatable {
    let deck: FlashcardDeck
    let cards: [Flashcard]
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

    func applyingLiveEvent(_ event: TaskEventItem) -> TaskItem {
        let inferredStatus = event.eventType == "queued" ? "queued" : (status == "queued" ? "running" : status)
        return TaskItem(
            id: id,
            workspaceId: workspaceId,
            taskType: taskType,
            status: inferredStatus,
            resourceType: resourceType,
            resourceId: resourceId,
            payload: payload,
            result: result,
            errorMessage: errorMessage,
            progress: event.progress ?? progress,
            cancelRequestedAt: cancelRequestedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    var isTerminal: Bool {
        ["succeeded", "failed", "cancelled"].contains(status)
    }
}

struct TaskEventItem: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let taskId: String
    let sequenceNo: Int
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
        case sequenceNo = "sequence_no"
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
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        taskId = try container.decode(String.self, forKey: .taskId)
        sequenceNo = try container.decodeIfPresent(Int.self, forKey: .sequenceNo) ?? 0
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        dataText = try container.decodeIfPresent(JSONValue.self, forKey: .data)?.displayString
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    init(
        id: String,
        workspaceId: String,
        taskId: String,
        sequenceNo: Int,
        eventType: String,
        level: String,
        message: String,
        progress: Int?,
        dataText: String?,
        createdAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.taskId = taskId
        self.sequenceNo = sequenceNo
        self.eventType = eventType
        self.level = level
        self.message = message
        self.progress = progress
        self.dataText = dataText
        self.createdAt = createdAt
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
