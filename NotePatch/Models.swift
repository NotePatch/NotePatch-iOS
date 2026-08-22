import Foundation

let defaultServiceRootURL = "https://8.137.78.255/np-b9a6aede5d0fbb05229d9541144a6067"
let defaultTUSDServiceRootURL = defaultServiceRootURL
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
    let localizationKey: String?
    let localizationArguments: [String]
    let statusCode: Int?
    let shouldClearSession: Bool
    let refreshTokenAttempt: String?
    let cause: Error?
    let backendCode: String?
    let backendDetails: [String: JSONValue]?

    nonisolated init(
        _ message: String,
        statusCode: Int? = nil,
        shouldClearSession: Bool = false,
        refreshTokenAttempt: String? = nil,
        cause: Error? = nil,
        backendCode: String? = nil,
        backendDetails: [String: JSONValue]? = nil
    ) {
        self.message = message
        self.localizationKey = nil
        self.localizationArguments = []
        self.statusCode = statusCode
        self.shouldClearSession = shouldClearSession
        self.refreshTokenAttempt = refreshTokenAttempt
        self.cause = cause
        self.backendCode = backendCode
        self.backendDetails = backendDetails
    }

    nonisolated init(
        localizedKey: String,
        arguments: [String] = [],
        statusCode: Int? = nil,
        shouldClearSession: Bool = false,
        refreshTokenAttempt: String? = nil,
        cause: Error? = nil,
        backendCode: String? = nil,
        backendDetails: [String: JSONValue]? = nil
    ) {
        self.message = localizedKey
        self.localizationKey = localizedKey
        self.localizationArguments = arguments
        self.statusCode = statusCode
        self.shouldClearSession = shouldClearSession
        self.refreshTokenAttempt = refreshTokenAttempt
        self.cause = cause
        self.backendCode = backendCode
        self.backendDetails = backendDetails
    }

    nonisolated var errorDescription: String? {
        message
    }

    nonisolated func withContext(
        statusCode: Int?,
        shouldClearSession: Bool,
        refreshTokenAttempt: String? = nil,
        cause: Error? = nil
    ) -> LearningBackendError {
        if let localizationKey {
            return LearningBackendError(
                localizedKey: localizationKey,
                arguments: localizationArguments,
                statusCode: statusCode,
                shouldClearSession: shouldClearSession,
                refreshTokenAttempt: refreshTokenAttempt,
                cause: cause ?? self,
                backendCode: backendCode,
                backendDetails: backendDetails
            )
        }
        return LearningBackendError(
            message,
            statusCode: statusCode,
            shouldClearSession: shouldClearSession,
            refreshTokenAttempt: refreshTokenAttempt,
            cause: cause ?? self,
            backendCode: backendCode,
            backendDetails: backendDetails
        )
    }
}

struct AIPreferences: Codable, Equatable {
    var responseLanguage: String
    var collaborationStyle: String
    var responseDepth: String
    var responseStructure: String
    var clarificationPolicy: String
    var feedbackTone: String
    var learningGuidance: String
    var customInstructions: String?

    static let defaults = AIPreferences(
        responseLanguage: "match_user",
        collaborationStyle: "collaborative",
        responseDepth: "balanced",
        responseStructure: "adaptive",
        clarificationPolicy: "ask_when_ambiguous",
        feedbackTone: "neutral",
        learningGuidance: "explain_then_answer",
        customInstructions: nil
    )

    enum CodingKeys: String, CodingKey {
        case responseLanguage = "response_language"
        case collaborationStyle = "collaboration_style"
        case responseDepth = "response_depth"
        case responseStructure = "response_structure"
        case clarificationPolicy = "clarification_policy"
        case feedbackTone = "feedback_tone"
        case learningGuidance = "learning_guidance"
        case customInstructions = "custom_instructions"
    }

    init(
        responseLanguage: String,
        collaborationStyle: String,
        responseDepth: String,
        responseStructure: String,
        clarificationPolicy: String,
        feedbackTone: String,
        learningGuidance: String,
        customInstructions: String?
    ) {
        self.responseLanguage = responseLanguage
        self.collaborationStyle = collaborationStyle
        self.responseDepth = responseDepth
        self.responseStructure = responseStructure
        self.clarificationPolicy = clarificationPolicy
        self.feedbackTone = feedbackTone
        self.learningGuidance = learningGuidance
        self.customInstructions = customInstructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        responseLanguage = try c.decodeIfPresent(String.self, forKey: .responseLanguage) ?? d.responseLanguage
        collaborationStyle = try c.decodeIfPresent(String.self, forKey: .collaborationStyle) ?? d.collaborationStyle
        responseDepth = try c.decodeIfPresent(String.self, forKey: .responseDepth) ?? d.responseDepth
        responseStructure = try c.decodeIfPresent(String.self, forKey: .responseStructure) ?? d.responseStructure
        clarificationPolicy = try c.decodeIfPresent(String.self, forKey: .clarificationPolicy) ?? d.clarificationPolicy
        feedbackTone = try c.decodeIfPresent(String.self, forKey: .feedbackTone) ?? d.feedbackTone
        learningGuidance = try c.decodeIfPresent(String.self, forKey: .learningGuidance) ?? d.learningGuidance
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions)
    }

    var payload: [String: Any] {
        [
            "response_language": responseLanguage,
            "collaboration_style": collaborationStyle,
            "response_depth": responseDepth,
            "response_structure": responseStructure,
            "clarification_policy": clarificationPolicy,
            "feedback_tone": feedbackTone,
            "learning_guidance": learningGuidance,
            "custom_instructions": customInstructions ?? NSNull()
        ]
    }

    func patch(comparedTo previous: AIPreferences) -> [String: Any] {
        var result: [String: Any] = [:]
        if responseLanguage != previous.responseLanguage { result["response_language"] = responseLanguage }
        if collaborationStyle != previous.collaborationStyle { result["collaboration_style"] = collaborationStyle }
        if responseDepth != previous.responseDepth { result["response_depth"] = responseDepth }
        if responseStructure != previous.responseStructure { result["response_structure"] = responseStructure }
        if clarificationPolicy != previous.clarificationPolicy { result["clarification_policy"] = clarificationPolicy }
        if feedbackTone != previous.feedbackTone { result["feedback_tone"] = feedbackTone }
        if learningGuidance != previous.learningGuidance { result["learning_guidance"] = learningGuidance }
        if customInstructions != previous.customInstructions {
            result["custom_instructions"] = customInstructions ?? NSNull()
        }
        return result
    }
}

struct AIOnboardingOption: Codable, Equatable, Identifiable {
    let value: String
    let labelKey: String
    var id: String { value }
    enum CodingKeys: String, CodingKey { case value; case labelKey = "label_key" }
}

struct AIOnboardingQuestion: Codable, Equatable, Identifiable {
    let id: String
    let messageKey: String
    let required: Bool
    let options: [AIOnboardingOption]
    enum CodingKeys: String, CodingKey { case id; case messageKey = "message_key"; case required; case options }
}

struct AIOnboardingResponse: Codable, Equatable {
    let version: Int
    let completed: Bool
    let completedAt: String?
    let answers: AIPreferences
    let questions: [AIOnboardingQuestion]
    enum CodingKeys: String, CodingKey { case version; case completed; case completedAt = "completed_at"; case answers; case questions }
}

struct ChatGreeting: Decodable, Equatable {
    let assistantName: String
    let message: String
    let messageKey: String
    let format: String
    let locale: String
    let onboardingRequired: Bool
    let onboardingVersion: Int
    let questions: [AIOnboardingQuestion]
    enum CodingKeys: String, CodingKey {
        case assistantName = "assistant_name"; case message; case messageKey = "message_key"; case format; case locale
        case onboardingRequired = "onboarding_required"; case onboardingVersion = "onboarding_version"; case questions
    }
    init(
        assistantName: String,
        message: String,
        messageKey: String = "ai.chat.initial_greeting",
        format: String = "markdown",
        locale: String,
        onboardingRequired: Bool,
        onboardingVersion: Int,
        questions: [AIOnboardingQuestion] = []
    ) {
        self.assistantName = assistantName
        self.message = message
        self.messageKey = messageKey
        self.format = format
        self.locale = locale
        self.onboardingRequired = onboardingRequired
        self.onboardingVersion = onboardingVersion
        self.questions = questions
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assistantName = try c.decodeIfPresent(String.self, forKey: .assistantName) ?? "NotePatch AI"
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        messageKey = try c.decodeIfPresent(String.self, forKey: .messageKey) ?? "ai.chat.initial_greeting"
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "markdown"
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "en-US"
        onboardingRequired = try c.decodeIfPresent(Bool.self, forKey: .onboardingRequired) ?? false
        onboardingVersion = try c.decodeIfPresent(Int.self, forKey: .onboardingVersion) ?? 0
        questions = try c.decodeIfPresent([AIOnboardingQuestion].self, forKey: .questions) ?? []
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

struct NoteContentEditLevel: RawRepresentable, Codable, Equatable, Hashable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    static let verbatim = Self(rawValue: "verbatim")
    static let spelling = Self(rawValue: "spelling")
    static let conceptual = Self(rawValue: "conceptual")
    static let rewrite = Self(rawValue: "rewrite")
    static let supportedValues: [Self] = [.verbatim, .spelling, .conceptual, .rewrite]

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct NoteLayoutEditLevel: RawRepresentable, Codable, Equatable, Hashable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    static let preserve = Self(rawValue: "preserve")
    static let minor = Self(rawValue: "minor")
    static let reorder = Self(rawValue: "reorder")
    static let reflow = Self(rawValue: "reflow")
    static let supportedValues: [Self] = [.preserve, .minor, .reorder, .reflow]

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct BackendUser: Decodable, Equatable {
    let id: String
    let email: String
    let fullName: String?
    let isActive: Bool
    let createdAt: String
    let aiHistoryEnabled: Bool
    let autoImageRemarkEnabled: Bool
    let noteContentEditLevel: NoteContentEditLevel
    let noteLayoutEditLevel: NoteLayoutEditLevel
    let noteHistoryLimit: Int
    let aiOnboardingVersion: Int
    let aiOnboardingCompletedAt: String?
    let aiOnboardingCompleted: Bool
    let aiPreferences: AIPreferences

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case isActive = "is_active"
        case createdAt = "created_at"
        case aiHistoryEnabled = "ai_history_enabled"
        case autoImageRemarkEnabled = "auto_image_remark_enabled"
        case noteContentEditLevel = "note_content_edit_level"
        case noteLayoutEditLevel = "note_layout_edit_level"
        case noteHistoryLimit = "note_history_limit"
        case aiOnboardingVersion = "ai_onboarding_version"
        case aiOnboardingCompletedAt = "ai_onboarding_completed_at"
        case aiOnboardingCompleted = "ai_onboarding_completed"
        case aiPreferences = "ai_preferences"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        aiHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiHistoryEnabled) ?? true
        autoImageRemarkEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoImageRemarkEnabled) ?? true
        noteContentEditLevel = try container.decodeIfPresent(NoteContentEditLevel.self, forKey: .noteContentEditLevel) ?? .conceptual
        noteLayoutEditLevel = try container.decodeIfPresent(NoteLayoutEditLevel.self, forKey: .noteLayoutEditLevel) ?? .minor
        noteHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .noteHistoryLimit) ?? 3
        aiOnboardingVersion = try container.decodeIfPresent(Int.self, forKey: .aiOnboardingVersion) ?? 0
        aiOnboardingCompletedAt = try container.decodeIfPresent(String.self, forKey: .aiOnboardingCompletedAt)
        aiOnboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .aiOnboardingCompleted) ?? false
        aiPreferences = (try? container.decode(AIPreferences.self, forKey: .aiPreferences)) ?? .defaults
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
    let remark: String?
    let remarkSource: String?
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
    let retentionScope: String?
    let chatConversationId: String?
    let saveToDocuments: Bool?
    let latestWorkflowRunId: String?
    let imageRemarkStatus: String?
    let imageRemarkTaskId: String?
    let createdAt: String
    let updatedAt: String
    let artifacts: [DocumentArtifactItem]

    var displayRemark: String {
        let value = remark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? originalFilename : value
    }

    var isImageRemarkActive: Bool {
        ["waiting_upload", "waiting_ocr", "queued", "running"].contains(imageRemarkStatus ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case uploadedBy = "uploaded_by"
        case title
        case remark
        case remarkSource = "remark_source"
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
        case retentionScope = "retention_scope"
        case chatConversationId = "chat_conversation_id"
        case saveToDocuments = "save_to_documents"
        case latestWorkflowRunId = "latest_workflow_run_id"
        case imageRemarkStatus = "image_remark_status"
        case imageRemarkTaskId = "image_remark_task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case artifacts
    }

    init(
        id: String,
        workspaceId: String,
        uploadedBy: String = "",
        title: String? = nil,
        remark: String? = nil,
        remarkSource: String? = nil,
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
        retentionScope: String? = nil,
        chatConversationId: String? = nil,
        saveToDocuments: Bool? = nil,
        latestWorkflowRunId: String? = nil,
        imageRemarkStatus: String? = nil,
        imageRemarkTaskId: String? = nil,
        createdAt: String = "",
        updatedAt: String = "",
        artifacts: [DocumentArtifactItem] = []
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.uploadedBy = uploadedBy
        self.title = title
        self.remark = remark
        self.remarkSource = remarkSource
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
        self.retentionScope = retentionScope
        self.chatConversationId = chatConversationId
        self.saveToDocuments = saveToDocuments
        self.latestWorkflowRunId = latestWorkflowRunId
        self.imageRemarkStatus = imageRemarkStatus
        self.imageRemarkTaskId = imageRemarkTaskId
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
    let workflowRunId: String?

    enum CodingKeys: String, CodingKey {
        case document
        case uploadSession = "upload_session"
        case tusEndpoint = "tus_endpoint"
        case tusMetadata = "tus_metadata"
        case tusMetadataHeader = "tus_metadata_header"
        case bucket
        case objectKey = "object_key"
        case workflowRunId = "workflow_run_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        document = try container.decode(LearningDocumentItem.self, forKey: .document)
        uploadSession = try container.decode(UploadSessionItem.self, forKey: .uploadSession)
        tusEndpoint = try container.decode(String.self, forKey: .tusEndpoint)
        tusMetadata = try container.decodeIfPresent([String: String].self, forKey: .tusMetadata) ?? [:]
        tusMetadataHeader = try container.decodeIfPresent(String.self, forKey: .tusMetadataHeader) ?? ""
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        objectKey = try container.decodeIfPresent(String.self, forKey: .objectKey) ?? ""
        workflowRunId = try container.decodeIfPresent(String.self, forKey: .workflowRunId)
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
    let titleSource: String?
    let titleGeneratedAt: String?
    let lastMessageAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case title
        case titleSource = "title_source"
        case titleGeneratedAt = "title_generated_at"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        workspaceId: String,
        title: String,
        titleSource: String? = nil,
        titleGeneratedAt: String? = nil,
        lastMessageAt: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.titleSource = titleSource
        self.titleGeneratedAt = titleGeneratedAt
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatMessageAttachment: Decodable, Equatable, Identifiable {
    let documentId: String
    let filename: String
    let title: String?
    let mimeType: String?
    let fileType: String?
    let fileSize: Int64?
    let status: String?
    let availability: String?
    let retentionScope: String?
    let saveToDocuments: Bool?

    var id: String { documentId }
    var isImage: Bool {
        mimeType?.hasPrefix("image/") == true
            || fileType == "image"
            || ["jpg", "jpeg", "png", "webp", "heic"].contains((filename as NSString).pathExtension.lowercased())
    }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case filename
        case title
        case mimeType = "mime_type"
        case fileType = "file_type"
        case fileSize = "file_size"
        case status
        case availability
        case retentionScope = "retention_scope"
        case saveToDocuments = "save_to_documents"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId) ?? ""
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        availability = try container.decodeIfPresent(String.self, forKey: .availability)
        retentionScope = try container.decodeIfPresent(String.self, forKey: .retentionScope)
        saveToDocuments = try container.decodeIfPresent(Bool.self, forKey: .saveToDocuments)
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
    let attachments: [ChatMessageAttachment]?
    let revisionOfMessageId: String?
    let supersededByMessageId: String?
    let supersededAt: String?
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
        case attachments
        case revisionOfMessageId = "revision_of_message_id"
        case supersededByMessageId = "superseded_by_message_id"
        case supersededAt = "superseded_at"
        case createdAt = "created_at"
    }
}

struct APIResponseEnvelope<Value: Decodable>: Decodable {
    let code: String
    let message: String
    let data: Value
}

struct UserProfile: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let email: String
    let avatarURL: String?
    let profileVersion: Int
    let reauthenticationRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatarURL = "avatar_url"
        case profileVersion = "profile_version"
        case reauthenticationRequired = "reauthentication_required"
    }
}

struct UserProfileSnapshot: Equatable {
    let profile: UserProfile
    let etag: String
}

struct AvatarDownloadURL: Decodable, Equatable {
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case url
        case avatarURL = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            ?? container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decode(String.self, forKey: .avatarURL)
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
    let noteIRObjectKey: String?
    let contentEditLevel: NoteContentEditLevel
    let layoutEditLevel: NoteLayoutEditLevel
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
    let rendering: StudyNoteRendering?

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
        case noteIRObjectKey = "note_ir_object_key"
        case contentEditLevel = "content_edit_level"
        case layoutEditLevel = "layout_edit_level"
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
        case rendering
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
        noteIRObjectKey: String? = nil,
        contentEditLevel: NoteContentEditLevel = .conceptual,
        layoutEditLevel: NoteLayoutEditLevel = .minor,
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
        downloadURLs: [String: String] = [:],
        rendering: StudyNoteRendering? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.learningUnitId = learningUnitId
        self.taskId = taskId
        self.versionNo = versionNo
        self.title = title
        self.htmlObjectKey = htmlObjectKey
        self.jsonObjectKey = jsonObjectKey
        self.noteIRObjectKey = noteIRObjectKey
        self.contentEditLevel = contentEditLevel
        self.layoutEditLevel = layoutEditLevel
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
        self.rendering = rendering
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
        jsonObjectKey = try container.decodeIfPresent(String.self, forKey: .jsonObjectKey) ?? ""
        noteIRObjectKey = try container.decodeIfPresent(String.self, forKey: .noteIRObjectKey)
        contentEditLevel = try container.decodeIfPresent(NoteContentEditLevel.self, forKey: .contentEditLevel) ?? .conceptual
        layoutEditLevel = try container.decodeIfPresent(NoteLayoutEditLevel.self, forKey: .layoutEditLevel) ?? .minor
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
        rendering = try container.decodeIfPresent(StudyNoteRendering.self, forKey: .rendering)
    }

    var preferredDownloadURL: String? {
        renderedHTMLDownloadURL ?? preferredHTMLDownloadURL ?? downloadURLs["json"]
    }

    var completionCount: Int? {
        metadata["completion_count"]?.intValue
    }

    var completionSourceDocumentIds: [String] {
        metadata["completion_source_document_ids"]?.stringArrayValue ?? []
    }

    var completionEvidenceRevision: Int? {
        metadata["completion_evidence_revision"]?.intValue
    }

    var completionStrategy: String? {
        metadata["completion_strategy"]?.stringValue
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

struct StudyNoteRendering: Decodable, Equatable {
    let themeId: String
    let cssURL: String?
    let wrapperClass: String

    enum CodingKeys: String, CodingKey {
        case themeId = "theme_id"
        case cssURL = "css_url"
        case wrapperClass = "wrapper_class"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeId = try container.decodeIfPresent(String.self, forKey: .themeId) ?? "notepatch-paper-v1"
        cssURL = try container.decodeIfPresent(String.self, forKey: .cssURL)
        wrapperClass = try container.decodeIfPresent(String.self, forKey: .wrapperClass) ?? "np-note-theme"
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

struct FlashcardHintItem: Decodable, Equatable {
    let code: String
    let messageKey: String
    let tone: String
    let params: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case code
        case messageKey = "message_key"
        case tone
        case params
    }

    init(code: String, messageKey: String, tone: String, params: [String: JSONValue] = [:]) {
        self.code = code
        self.messageKey = messageKey
        self.tone = tone
        self.params = params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "general_review"
        messageKey = try container.decodeIfPresent(String.self, forKey: .messageKey)
            ?? "flashcards.hints.general_review"
        tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? "neutral"
        params = try container.decodeIfPresent([String: JSONValue].self, forKey: .params) ?? [:]
    }
}

struct FlashcardReviewHint: Decodable, Equatable {
    let primary: FlashcardHintItem
    let badges: [FlashcardHintItem]
    let dataQuality: String

    enum CodingKeys: String, CodingKey {
        case primary
        case badges
        case dataQuality = "data_quality"
    }

    init(primary: FlashcardHintItem, badges: [FlashcardHintItem] = [], dataQuality: String = "complete") {
        self.primary = primary
        self.badges = Array(badges.prefix(3))
        self.dataQuality = dataQuality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decodeIfPresent(FlashcardHintItem.self, forKey: .primary)
            ?? FlashcardHintItem(
                code: "general_review",
                messageKey: "flashcards.hints.general_review",
                tone: "neutral"
            )
        badges = Array((try container.decodeIfPresent([FlashcardHintItem].self, forKey: .badges) ?? []).prefix(3))
        dataQuality = try container.decodeIfPresent(String.self, forKey: .dataQuality) ?? "legacy"
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
    let reviewHint: FlashcardReviewHint?
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
        case reviewHint = "review_hint"
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
        reviewHint: FlashcardReviewHint? = nil,
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
        self.reviewHint = reviewHint
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
    var autoGroupLearningUnit = true
    var noteSetId: String?
    var pageIndex: Int?
    var noteContentEditLevel: NoteContentEditLevel?
    var noteLayoutEditLevel: NoteLayoutEditLevel?

    var topLevelPayload: [String: Any] {
        var values: [String: Any] = ["auto_group_learning_unit": autoGroupLearningUnit]
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
        if let noteSetId, !noteSetId.isEmpty { values["note_set_id"] = noteSetId }
        if let pageIndex { values["page_index"] = pageIndex }
        if let noteContentEditLevel { values["note_content_edit_level"] = noteContentEditLevel.rawValue }
        if let noteLayoutEditLevel { values["note_layout_edit_level"] = noteLayoutEditLevel.rawValue }
        return values
    }

    var payload: [String: String] {
        topLevelPayload.reduce(into: [:]) { result, pair in
            if let value = pair.value as? String { result[pair.key] = value }
        }
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

struct GradingResult: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let homeworkId: String
    let questionId: String?
    let studentUserId: String?
    let score: Double?
    let maxScore: Double?
    let gradingMode: String
    let confidence: Double?
    let feedback: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case homeworkId = "homework_id"
        case questionId = "question_id"
        case studentUserId = "student_user_id"
        case score
        case maxScore = "max_score"
        case gradingMode = "grading_mode"
        case confidence
        case feedback
        case createdAt = "created_at"
    }
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
    let latestGradingResult: GradingResult?

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
        case latestGradingResult = "latest_grading_result"
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
        updatedAt: String = "",
        latestGradingResult: GradingResult? = nil
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
        self.latestGradingResult = latestGradingResult
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
        latestGradingResult = try container.decodeIfPresent(GradingResult.self, forKey: .latestGradingResult)
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
    let data: JSONValue?
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
        data = try container.decodeIfPresent(JSONValue.self, forKey: .data)
        dataText = data?.displayString
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
        data: JSONValue? = nil,
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
        self.data = data
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
    var autoImageRemarkEnabled: Bool = true
    var noteContentEditLevel: NoteContentEditLevel = .conceptual
    var noteLayoutEditLevel: NoteLayoutEditLevel = .minor
    var noteHistoryLimit: Int = 3
    var aiOnboardingVersion: Int = 0
    var aiOnboardingCompletedAt: String? = nil
    var aiOnboardingCompleted: Bool = true
    var aiPreferences: AIPreferences = .defaults

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
            aiHistoryEnabled: tokenResponse.user.aiHistoryEnabled,
            autoImageRemarkEnabled: tokenResponse.user.autoImageRemarkEnabled,
            noteContentEditLevel: tokenResponse.user.noteContentEditLevel,
            noteLayoutEditLevel: tokenResponse.user.noteLayoutEditLevel,
            noteHistoryLimit: tokenResponse.user.noteHistoryLimit,
            aiOnboardingVersion: tokenResponse.user.aiOnboardingVersion,
            aiOnboardingCompletedAt: tokenResponse.user.aiOnboardingCompletedAt,
            aiOnboardingCompleted: tokenResponse.user.aiOnboardingCompleted,
            aiPreferences: tokenResponse.user.aiPreferences
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
            aiHistoryEnabled: enabled,
            autoImageRemarkEnabled: autoImageRemarkEnabled,
            noteContentEditLevel: noteContentEditLevel,
            noteLayoutEditLevel: noteLayoutEditLevel,
            noteHistoryLimit: noteHistoryLimit,
            aiOnboardingVersion: aiOnboardingVersion,
            aiOnboardingCompletedAt: aiOnboardingCompletedAt,
            aiOnboardingCompleted: aiOnboardingCompleted,
            aiPreferences: aiPreferences
        )
    }

    func withUser(_ user: BackendUser) -> SavedSession {
        SavedSession(
            baseURL: baseURL,
            tusBaseURL: tusBaseURL,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: user.id,
            email: user.email,
            fullName: user.fullName,
            selectedWorkspaceId: selectedWorkspaceId,
            aiHistoryEnabled: user.aiHistoryEnabled,
            autoImageRemarkEnabled: user.autoImageRemarkEnabled,
            noteContentEditLevel: user.noteContentEditLevel,
            noteLayoutEditLevel: user.noteLayoutEditLevel,
            noteHistoryLimit: user.noteHistoryLimit,
            aiOnboardingVersion: user.aiOnboardingVersion,
            aiOnboardingCompletedAt: user.aiOnboardingCompletedAt,
            aiOnboardingCompleted: user.aiOnboardingCompleted,
            aiPreferences: user.aiPreferences
        )
    }

    func withProfile(_ profile: UserProfile) -> SavedSession {
        SavedSession(
            baseURL: baseURL,
            tusBaseURL: tusBaseURL,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: profile.id,
            email: profile.email,
            fullName: profile.name,
            selectedWorkspaceId: selectedWorkspaceId,
            aiHistoryEnabled: aiHistoryEnabled,
            autoImageRemarkEnabled: autoImageRemarkEnabled,
            noteContentEditLevel: noteContentEditLevel,
            noteLayoutEditLevel: noteLayoutEditLevel,
            noteHistoryLimit: noteHistoryLimit,
            aiOnboardingVersion: aiOnboardingVersion,
            aiOnboardingCompletedAt: aiOnboardingCompletedAt,
            aiOnboardingCompleted: aiOnboardingCompleted,
            aiPreferences: aiPreferences
        )
    }

    func withAIOnboarding(_ onboarding: AIOnboardingResponse) -> SavedSession {
        var updated = self
        updated.aiOnboardingVersion = onboarding.version
        updated.aiOnboardingCompletedAt = onboarding.completedAt
        updated.aiOnboardingCompleted = onboarding.completed
        updated.aiPreferences = onboarding.answers
        return updated
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

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var stringArrayValue: [String]? {
        guard case .array(let values) = self else { return nil }
        return values.compactMap(\.stringValue)
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
