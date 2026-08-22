import Foundation

struct NoteSetCreateInput: Equatable {
    let title: String
    let expectedPageCount: Int
    let learningUnitId: String?
    let subject: String?
    let gradeLevel: String?
    let topic: String?
    let contentEditLevel: NoteContentEditLevel?
    let layoutEditLevel: NoteLayoutEditLevel?

    var payload: [String: Any] {
        var result: [String: Any] = [
            "title": title,
            "expected_page_count": expectedPageCount
        ]
        if let learningUnitId { result["learning_unit_id"] = learningUnitId }
        if let subject { result["subject"] = subject }
        if let gradeLevel { result["grade_level"] = gradeLevel }
        if let topic { result["topic"] = topic }
        if let contentEditLevel { result["content_edit_level"] = contentEditLevel.rawValue }
        if let layoutEditLevel { result["layout_edit_level"] = layoutEditLevel.rawValue }
        return result
    }
}

struct NoteSetDocument: Decodable, Equatable, Identifiable {
    let id: String
    let documentId: String
    let pageIndex: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case pageIndex = "page_index"
        case createdAt = "created_at"
    }
}

struct NoteSet: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let userId: String?
    let learningUnitId: String?
    let title: String
    let expectedPageCount: Int
    let status: String
    let contentEditLevel: NoteContentEditLevel
    let layoutEditLevel: NoteLayoutEditLevel
    let metadata: JSONValue
    let completedAt: String?
    let createdAt: String
    let updatedAt: String
    let documents: [NoteSetDocument]

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case learningUnitId = "learning_unit_id"
        case title
        case expectedPageCount = "expected_page_count"
        case status
        case contentEditLevel = "content_edit_level"
        case layoutEditLevel = "layout_edit_level"
        case metadata
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case documents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        learningUnitId = try container.decodeIfPresent(String.self, forKey: .learningUnitId)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        expectedPageCount = try container.decodeIfPresent(Int.self, forKey: .expectedPageCount) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        contentEditLevel = try container.decodeIfPresent(NoteContentEditLevel.self, forKey: .contentEditLevel) ?? .conceptual
        layoutEditLevel = try container.decodeIfPresent(NoteLayoutEditLevel.self, forKey: .layoutEditLevel) ?? .minor
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata) ?? .object([:])
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        documents = try container.decodeIfPresent([NoteSetDocument].self, forKey: .documents) ?? []
    }
}

struct NoteSourceReference: Codable, Equatable, Hashable {
    let documentId: String?
    let pageIndex: Int?
    let blockId: String?
    let bbox: [Double]?
    let excerpt: String

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case pageIndex = "page_index"
        case blockId = "block_id"
        case bbox
        case excerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
        blockId = try container.decodeIfPresent(String.self, forKey: .blockId)
        bbox = try container.decodeIfPresent([Double].self, forKey: .bbox)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
    }

    init(documentId: String?, pageIndex: Int?, blockId: String?, bbox: [Double]?, excerpt: String) {
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.blockId = blockId
        self.bbox = bbox
        self.excerpt = excerpt
    }

    var payload: [String: Any] {
        var result: [String: Any] = ["excerpt": excerpt]
        if let documentId { result["document_id"] = documentId }
        if let pageIndex { result["page_index"] = pageIndex }
        if let blockId { result["block_id"] = blockId }
        if let bbox { result["bbox"] = bbox }
        return result
    }
}

struct NoteGap: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let learningUnitId: String
    let knowledgePointId: String
    let noteVersionId: String?
    let acceptedVersionId: String?
    let status: String
    let coverageScore: Double
    let sourceRefs: [NoteSourceReference]
    let targetSectionId: String?
    let targetAnchor: String?
    let insertPosition: String
    let metadata: JSONValue
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case learningUnitId = "learning_unit_id"
        case knowledgePointId = "knowledge_point_id"
        case noteVersionId = "note_version_id"
        case acceptedVersionId = "accepted_version_id"
        case status
        case coverageScore = "coverage_score"
        case sourceRefs = "source_refs"
        case targetSectionId = "target_section_id"
        case targetAnchor = "target_anchor"
        case insertPosition = "insert_position"
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        learningUnitId = try container.decodeIfPresent(String.self, forKey: .learningUnitId) ?? ""
        knowledgePointId = try container.decodeIfPresent(String.self, forKey: .knowledgePointId) ?? ""
        noteVersionId = try container.decodeIfPresent(String.self, forKey: .noteVersionId)
        acceptedVersionId = try container.decodeIfPresent(String.self, forKey: .acceptedVersionId)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        coverageScore = try container.decodeIfPresent(Double.self, forKey: .coverageScore) ?? 0
        sourceRefs = try container.decodeIfPresent([NoteSourceReference].self, forKey: .sourceRefs) ?? []
        targetSectionId = try container.decodeIfPresent(String.self, forKey: .targetSectionId)
        targetAnchor = try container.decodeIfPresent(String.self, forKey: .targetAnchor)
        insertPosition = try container.decodeIfPresent(String.self, forKey: .insertPosition) ?? "after"
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata) ?? .object([:])
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct NoteSupplementDraft: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let learningUnitId: String
    let gapSuggestionId: String
    let baseNoteVersionId: String?
    let generatedByTaskId: String?
    let versionNo: Int
    let status: String
    let html: String
    let selectedSourceRefs: [NoteSourceReference]
    let targetSectionId: String?
    let targetAnchor: String?
    let insertPosition: String
    let instruction: String?
    let feedback: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case learningUnitId = "learning_unit_id"
        case gapSuggestionId = "gap_suggestion_id"
        case baseNoteVersionId = "base_note_version_id"
        case generatedByTaskId = "generated_by_task_id"
        case versionNo = "version_no"
        case status
        case html
        case selectedSourceRefs = "selected_source_refs"
        case targetSectionId = "target_section_id"
        case targetAnchor = "target_anchor"
        case insertPosition = "insert_position"
        case instruction
        case feedback
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        learningUnitId = try container.decodeIfPresent(String.self, forKey: .learningUnitId) ?? ""
        gapSuggestionId = try container.decodeIfPresent(String.self, forKey: .gapSuggestionId) ?? ""
        baseNoteVersionId = try container.decodeIfPresent(String.self, forKey: .baseNoteVersionId)
        generatedByTaskId = try container.decodeIfPresent(String.self, forKey: .generatedByTaskId)
        versionNo = try container.decodeIfPresent(Int.self, forKey: .versionNo) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        html = try container.decodeIfPresent(String.self, forKey: .html) ?? ""
        selectedSourceRefs = try container.decodeIfPresent([NoteSourceReference].self, forKey: .selectedSourceRefs) ?? []
        targetSectionId = try container.decodeIfPresent(String.self, forKey: .targetSectionId)
        targetAnchor = try container.decodeIfPresent(String.self, forKey: .targetAnchor)
        insertPosition = try container.decodeIfPresent(String.self, forKey: .insertPosition) ?? "after"
        instruction = try container.decodeIfPresent(String.self, forKey: .instruction)
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct NoteGapDetail: Decodable, Equatable {
    let suggestion: NoteGap
    let drafts: [NoteSupplementDraft]

    enum CodingKeys: String, CodingKey { case suggestion, drafts }

    init(suggestion: NoteGap, drafts: [NoteSupplementDraft]) {
        self.suggestion = suggestion
        self.drafts = drafts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        suggestion = try container.decode(NoteGap.self, forKey: .suggestion)
        drafts = try container.decodeIfPresent([NoteSupplementDraft].self, forKey: .drafts) ?? []
    }
}

struct StudyNoteCorrection: Decodable, Equatable, Identifiable {
    let id: String
    let sourceBlockId: String?
    let correctionType: String
    let originalText: String
    let correctedText: String
    let reason: String?
    let confidence: Double?
    let sourceRefs: [NoteSourceReference]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sourceBlockId = "source_block_id"
        case correctionType = "correction_type"
        case originalText = "original_text"
        case correctedText = "corrected_text"
        case reason
        case confidence
        case sourceRefs = "source_refs"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceBlockId = try container.decodeIfPresent(String.self, forKey: .sourceBlockId)
        correctionType = try container.decodeIfPresent(String.self, forKey: .correctionType) ?? ""
        originalText = try container.decodeIfPresent(String.self, forKey: .originalText) ?? ""
        correctedText = try container.decodeIfPresent(String.self, forKey: .correctedText) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        sourceRefs = try container.decodeIfPresent([NoteSourceReference].self, forKey: .sourceRefs) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

struct WorkflowRun: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let userId: String?
    let documentId: String?
    let learningUnitId: String?
    let triggerType: String
    let status: String
    let coreStatus: String
    let enrichmentStatus: String
    let currentStage: String?
    let progress: Int
    let waitingUntil: String?
    let errorMessage: String?
    let result: JSONValue
    let metadata: JSONValue
    let createdAt: String
    let updatedAt: String
    let startedAt: String?
    let finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case userId = "user_id"
        case documentId = "document_id"
        case learningUnitId = "learning_unit_id"
        case triggerType = "trigger_type"
        case status
        case coreStatus = "core_status"
        case enrichmentStatus = "enrichment_status"
        case currentStage = "current_stage"
        case progress
        case waitingUntil = "waiting_until"
        case errorMessage = "error_message"
        case result
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    init(
        id: String,
        workspaceId: String,
        userId: String?,
        documentId: String?,
        learningUnitId: String?,
        triggerType: String,
        status: String,
        coreStatus: String,
        enrichmentStatus: String,
        currentStage: String?,
        progress: Int,
        waitingUntil: String?,
        errorMessage: String?,
        result: JSONValue,
        metadata: JSONValue,
        createdAt: String,
        updatedAt: String,
        startedAt: String?,
        finishedAt: String?
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.userId = userId
        self.documentId = documentId
        self.learningUnitId = learningUnitId
        self.triggerType = triggerType
        self.status = status
        self.coreStatus = coreStatus
        self.enrichmentStatus = enrichmentStatus
        self.currentStage = currentStage
        self.progress = progress
        self.waitingUntil = waitingUntil
        self.errorMessage = errorMessage
        self.result = result
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var isTerminal: Bool {
        ["succeeded", "partially_succeeded", "failed", "cancelled"].contains(status)
    }

    func applying(event: WorkflowEvent) -> WorkflowRun {
        WorkflowRun(
            id: id,
            workspaceId: workspaceId,
            userId: userId,
            documentId: documentId,
            learningUnitId: learningUnitId,
            triggerType: triggerType,
            status: status,
            coreStatus: coreStatus,
            enrichmentStatus: enrichmentStatus,
            currentStage: event.stage ?? currentStage,
            progress: event.progress ?? progress,
            waitingUntil: waitingUntil,
            errorMessage: errorMessage,
            result: result,
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: event.createdAt.isEmpty ? updatedAt : event.createdAt,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}

struct WorkflowTask: Decodable, Equatable, Identifiable {
    let stage: String
    let phase: String
    let required: Bool
    let task: TaskItem

    var id: String { "\(stage)-\(phase)-\(task.id)" }
}

struct WorkflowDetail: Decodable, Equatable {
    let workflow: WorkflowRun
    let tasks: [WorkflowTask]

    enum CodingKeys: String, CodingKey { case workflow, tasks }

    init(workflow: WorkflowRun, tasks: [WorkflowTask]) {
        self.workflow = workflow
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflow = try container.decode(WorkflowRun.self, forKey: .workflow)
        tasks = try container.decodeIfPresent([WorkflowTask].self, forKey: .tasks) ?? []
    }
}

struct WorkflowEvent: Decodable, Equatable, Identifiable {
    let id: String
    let workspaceId: String
    let workflowRunId: String
    let taskId: String?
    let taskEventId: String?
    let sequenceNo: Int
    let stage: String?
    let eventType: String
    let level: String
    let message: String
    let progress: Int?
    let data: JSONValue
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case workflowRunId = "workflow_run_id"
        case taskId = "task_id"
        case taskEventId = "task_event_id"
        case sequenceNo = "sequence_no"
        case stage
        case eventType = "event_type"
        case level
        case message
        case progress
        case data
        case createdAt = "created_at"
    }

    init(
        id: String,
        workspaceId: String,
        workflowRunId: String,
        taskId: String?,
        taskEventId: String?,
        sequenceNo: Int,
        stage: String?,
        eventType: String,
        level: String,
        message: String,
        progress: Int?,
        data: JSONValue,
        createdAt: String
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.workflowRunId = workflowRunId
        self.taskId = taskId
        self.taskEventId = taskEventId
        self.sequenceNo = sequenceNo
        self.stage = stage
        self.eventType = eventType
        self.level = level
        self.message = message
        self.progress = progress
        self.data = data
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
        workflowRunId = try container.decodeIfPresent(String.self, forKey: .workflowRunId) ?? ""
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        taskEventId = try container.decodeIfPresent(String.self, forKey: .taskEventId)
        sequenceNo = try container.decodeIfPresent(Int.self, forKey: .sequenceNo) ?? 0
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType) ?? ""
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        data = try container.decodeIfPresent(JSONValue.self, forKey: .data) ?? .object([:])
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}
