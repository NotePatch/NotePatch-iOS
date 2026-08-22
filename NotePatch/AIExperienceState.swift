import Combine
import Foundation

struct PendingAIChatSubmission: Equatable {
    let prompt: String
    let attachments: [LocalUploadFile]
    let userId: String
    let workspaceId: String
    var didAutoRetry: Bool
}

@MainActor
final class AIExperienceState: ObservableObject {
    @Published var greeting: ChatGreeting?
    @Published var greetingError: String?
    @Published var isGreetingLoading = false
    @Published var onboarding: AIOnboardingResponse?
    @Published var draftPreferences: AIPreferences = .defaults
    @Published var currentQuestionIndex = 0
    @Published var isOnboardingPresented = false
    @Published var isSettingsPresented = false
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    var pendingSubmission: PendingAIChatSubmission?

    func apply(_ onboarding: AIOnboardingResponse, presentIfRequired: Bool) {
        self.onboarding = onboarding
        draftPreferences = onboarding.answers
        currentQuestionIndex = min(currentQuestionIndex, max(0, onboarding.questions.count - 1))
        if onboarding.completed {
            isOnboardingPresented = false
        } else if presentIfRequired {
            isOnboardingPresented = true
        }
        errorMessage = nil
    }

    func beginSettings(with preferences: AIPreferences) {
        draftPreferences = preferences
        errorMessage = nil
        isSettingsPresented = true
    }

    func answer(for questionId: String) -> String {
        switch questionId {
        case "response_language": return draftPreferences.responseLanguage
        case "collaboration_style": return draftPreferences.collaborationStyle
        case "response_depth": return draftPreferences.responseDepth
        case "response_structure": return draftPreferences.responseStructure
        case "clarification_policy": return draftPreferences.clarificationPolicy
        case "feedback_tone": return draftPreferences.feedbackTone
        case "learning_guidance": return draftPreferences.learningGuidance
        default: return ""
        }
    }

    func setAnswer(_ value: String, for questionId: String) {
        switch questionId {
        case "response_language": draftPreferences.responseLanguage = value
        case "collaboration_style": draftPreferences.collaborationStyle = value
        case "response_depth": draftPreferences.responseDepth = value
        case "response_structure": draftPreferences.responseStructure = value
        case "clarification_policy": draftPreferences.clarificationPolicy = value
        case "feedback_tone": draftPreferences.feedbackTone = value
        case "learning_guidance": draftPreferences.learningGuidance = value
        default: break
        }
    }

    func reset() {
        greeting = nil
        greetingError = nil
        isGreetingLoading = false
        onboarding = nil
        draftPreferences = .defaults
        currentQuestionIndex = 0
        isOnboardingPresented = false
        isSettingsPresented = false
        isLoading = false
        isSaving = false
        errorMessage = nil
        pendingSubmission = nil
    }
}
