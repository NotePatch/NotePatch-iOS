import Foundation

struct WorkflowSSECompletion: Decodable, Equatable {
    let workflowRunId: String
    let status: String
    let lastSequenceNo: Int

    enum CodingKeys: String, CodingKey {
        case workflowRunId = "workflow_run_id"
        case status
        case lastSequenceNo = "last_sequence_no"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflowRunId = try container.decodeIfPresent(String.self, forKey: .workflowRunId) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        lastSequenceNo = try container.decodeIfPresent(Int.self, forKey: .lastSequenceNo) ?? 0
    }
}

enum WorkflowSSEFrame: Equatable {
    case workflowEvent(WorkflowEvent)
    case done(WorkflowSSECompletion)
}

struct WorkflowSSEParser {
    private var eventName = "message"
    private var eventID: String?
    private var dataLines: [String] = []
    private var partialLine = ""

    mutating func append(_ chunk: String, workspaceId: String, workflowRunId: String) throws -> [WorkflowSSEFrame] {
        partialLine += chunk
        var frames: [WorkflowSSEFrame] = []
        while let newline = partialLine.firstIndex(of: "\n") {
            var line = String(partialLine[..<newline])
            partialLine.removeSubrange(...newline)
            if line.last == "\r" { line.removeLast() }
            if let frame = try consumeLine(line, workspaceId: workspaceId, workflowRunId: workflowRunId) {
                frames.append(frame)
            }
        }
        return frames
    }

    mutating func finish(workspaceId: String, workflowRunId: String) throws -> [WorkflowSSEFrame] {
        var frames: [WorkflowSSEFrame] = []
        if !partialLine.isEmpty {
            if let frame = try consumeLine(partialLine, workspaceId: workspaceId, workflowRunId: workflowRunId) {
                frames.append(frame)
            }
            partialLine = ""
        }
        if let frame = try dispatch(workspaceId: workspaceId, workflowRunId: workflowRunId) {
            frames.append(frame)
        }
        return frames
    }

    private mutating func consumeLine(
        _ line: String,
        workspaceId: String,
        workflowRunId: String
    ) throws -> WorkflowSSEFrame? {
        if line.isEmpty { return try dispatch(workspaceId: workspaceId, workflowRunId: workflowRunId) }
        if line.hasPrefix(":") { return nil }
        let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(pieces[0])
        var value = pieces.count > 1 ? String(pieces[1]) : ""
        if value.first == " " { value.removeFirst() }
        switch field {
        case "event": eventName = value
        case "id": eventID = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    private mutating func dispatch(workspaceId: String, workflowRunId: String) throws -> WorkflowSSEFrame? {
        guard !dataLines.isEmpty else {
            resetFrame()
            return nil
        }
        let name = eventName
        let id = eventID
        let data = Data(dataLines.joined(separator: "\n").utf8)
        resetFrame()
        switch name {
        case "workflow_event":
            let decoded = try JSONDecoder.notepatch.decode(WorkflowEvent.self, from: data)
            return .workflowEvent(decoded.withContext(
                workspaceId: decoded.workspaceId.isEmpty ? workspaceId : decoded.workspaceId,
                workflowRunId: decoded.workflowRunId.isEmpty ? workflowRunId : decoded.workflowRunId,
                sequenceNo: decoded.sequenceNo > 0 ? decoded.sequenceNo : (Int(id ?? "") ?? 0)
            ))
        case "done":
            return .done(try JSONDecoder.notepatch.decode(WorkflowSSECompletion.self, from: data))
        default:
            return nil
        }
    }

    private mutating func resetFrame() {
        eventName = "message"
        eventID = nil
        dataLines = []
    }
}

struct WorkflowSSEByteDecoder {
    private var parser = WorkflowSSEParser()
    private var pendingLine = Data()

    mutating func append(_ byte: UInt8, workspaceId: String, workflowRunId: String) throws -> [WorkflowSSEFrame] {
        pendingLine.append(byte)
        guard byte == 0x0A else { return [] }
        let chunk = String(decoding: pendingLine, as: UTF8.self)
        pendingLine.removeAll(keepingCapacity: true)
        return try parser.append(chunk, workspaceId: workspaceId, workflowRunId: workflowRunId)
    }

    mutating func finish(workspaceId: String, workflowRunId: String) throws -> [WorkflowSSEFrame] {
        var frames: [WorkflowSSEFrame] = []
        if !pendingLine.isEmpty {
            frames.append(contentsOf: try parser.append(
                String(decoding: pendingLine, as: UTF8.self),
                workspaceId: workspaceId,
                workflowRunId: workflowRunId
            ))
            pendingLine.removeAll(keepingCapacity: false)
        }
        frames.append(contentsOf: try parser.finish(workspaceId: workspaceId, workflowRunId: workflowRunId))
        return frames
    }
}

private extension WorkflowEvent {
    func withContext(workspaceId: String, workflowRunId: String, sequenceNo: Int) -> WorkflowEvent {
        WorkflowEvent(
            id: id,
            workspaceId: workspaceId,
            workflowRunId: workflowRunId,
            taskId: taskId,
            taskEventId: taskEventId,
            sequenceNo: sequenceNo,
            stage: stage,
            eventType: eventType,
            level: level,
            message: message,
            progress: progress,
            data: data,
            createdAt: createdAt
        )
    }
}
