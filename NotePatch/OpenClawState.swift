import Combine
import CoreGraphics
import Foundation

@MainActor
final class OpenClawViewState: ObservableObject {
    @Published var messages: [OpenClawChatMessage]
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: String?
    @Published var isSending = false
    @Published var isHistoryLoading = false
    @Published var isConversationMutating = false

    init(messages: [OpenClawChatMessage] = []) {
        self.messages = messages
    }

    var selectedConversation: ChatConversation? {
        conversations.first(where: { $0.id == selectedConversationId })
    }

    @discardableResult
    func updateMessage(
        id: String,
        transform: (inout OpenClawChatMessage) -> Void
    ) -> Bool {
        let trace = NPPerformanceTrace.begin("ChatMessageUpdate")
        defer { NPPerformanceTrace.end("ChatMessageUpdate", id: trace) }
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var updated = messages[index]
        transform(&updated)
        guard updated != messages[index] else {
            return false
        }
        messages[index] = updated
        return true
    }
}

@MainActor
final class OpenClawComposerState: ObservableObject {
    @Published var text = ""
    @Published var measuredTextHeight: CGFloat = 44
    @Published var attachments: [LocalUploadFile] = []
    @Published var saveAttachmentsToWorkspace = true

    func removeAttachment(_ file: LocalUploadFile) {
        attachments.removeAll { $0.id == file.id }
    }

    func clearDraft(removeAttachmentFiles: Bool) {
        let files = attachments
        text = ""
        measuredTextHeight = 44
        attachments = []
        guard removeAttachmentFiles else { return }
        files.forEach { UploadThumbnailCache.shared.remove(file: $0) }
        Task.detached(priority: .utility) {
            for file in files {
                try? FileManager.default.removeItem(at: file.url)
            }
        }
    }
}
