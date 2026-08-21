import Combine
import Foundation
import UIKit

@MainActor
final class UserProfileState: ObservableObject {
    @Published var snapshot: UserProfileSnapshot?
    @Published var avatarImage: UIImage?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isAvatarUploading = false
    @Published var nameDraft = ""
    @Published var emailDraft = ""
    @Published var currentPassword = ""
    @Published var hasConflict = false
    @Published var hasAvatarConflict = false
    @Published var hasPendingAvatarRetry = false

    func apply(_ snapshot: UserProfileSnapshot) {
        self.snapshot = snapshot
        nameDraft = snapshot.profile.name
        emailDraft = snapshot.profile.email
        currentPassword = ""
        hasConflict = false
        hasAvatarConflict = false
    }

    func clear() {
        snapshot = nil
        avatarImage = nil
        isLoading = false
        isSaving = false
        isAvatarUploading = false
        nameDraft = ""
        emailDraft = ""
        currentPassword = ""
        hasConflict = false
        hasAvatarConflict = false
        hasPendingAvatarRetry = false
    }
}
