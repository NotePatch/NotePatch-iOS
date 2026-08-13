import Foundation

struct TaskSSECompletion: Decodable, Equatable {
    let taskId: String
    let status: String
    let lastSequenceNo: Int

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case lastSequenceNo = "last_sequence_no"
    }
}

enum TaskSSEFrame: Equatable {
    case taskEvent(TaskEventItem)
    case done(TaskSSECompletion)
}

private struct TaskSSEEventPayload: Decodable {
    let id: String
    let taskId: String
    let sequenceNo: Int
    let eventType: String
    let level: String
    let message: String
    let progress: Int?
    let data: JSONValue?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case sequenceNo = "sequence_no"
        case eventType = "event_type"
        case level
        case message
        case progress
        case data
        case createdAt = "created_at"
    }
}

struct TaskSSEParser {
    private var eventName = "message"
    private var eventID: String?
    private var dataLines: [String] = []
    private var partialLine = ""

    mutating func append(_ chunk: String, workspaceId: String) throws -> [TaskSSEFrame] {
        partialLine += chunk
        var frames: [TaskSSEFrame] = []
        while let newline = partialLine.firstIndex(of: "\n") {
            var line = String(partialLine[..<newline])
            partialLine.removeSubrange(...newline)
            if line.last == "\r" { line.removeLast() }
            if let frame = try consumeLine(line, workspaceId: workspaceId) {
                frames.append(frame)
            }
        }
        return frames
    }

    mutating func finish(workspaceId: String) throws -> [TaskSSEFrame] {
        var frames: [TaskSSEFrame] = []
        if !partialLine.isEmpty {
            if let frame = try consumeLine(partialLine, workspaceId: workspaceId) {
                frames.append(frame)
            }
            partialLine = ""
        }
        if let frame = try dispatch(workspaceId: workspaceId) {
            frames.append(frame)
        }
        return frames
    }

    mutating func consumeLine(_ line: String, workspaceId: String) throws -> TaskSSEFrame? {
        if line.isEmpty {
            return try dispatch(workspaceId: workspaceId)
        }
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

    private mutating func dispatch(workspaceId: String) throws -> TaskSSEFrame? {
        guard !dataLines.isEmpty else {
            resetFrame()
            return nil
        }
        let name = eventName
        let id = eventID
        let data = Data(dataLines.joined(separator: "\n").utf8)
        resetFrame()

        switch name {
        case "task_event":
            let payload = try JSONDecoder.notepatch.decode(TaskSSEEventPayload.self, from: data)
            let sequence = payload.sequenceNo > 0 ? payload.sequenceNo : (Int(id ?? "") ?? 0)
            return .taskEvent(TaskEventItem(
                id: payload.id,
                workspaceId: workspaceId,
                taskId: payload.taskId,
                sequenceNo: sequence,
                eventType: payload.eventType,
                level: payload.level,
                message: payload.message,
                progress: payload.progress,
                dataText: payload.data?.displayString,
                createdAt: payload.createdAt
            ))
        case "done":
            return .done(try JSONDecoder.notepatch.decode(TaskSSECompletion.self, from: data))
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
