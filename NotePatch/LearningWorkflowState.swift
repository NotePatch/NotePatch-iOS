import Foundation
import Combine

@MainActor
final class LearningWorkflowState: ObservableObject {
    @Published var workflows: [WorkflowRun] = []
    @Published var activeDetail: WorkflowDetail?
    @Published var events: [WorkflowEvent] = []
    @Published var isLoading = false

    func reset() {
        workflows = []
        activeDetail = nil
        events = []
        isLoading = false
    }
}
