import Foundation

final class SettingsStore {
    private static let legacyLearningBaseURL = "http://192.168.100.123:8001/api/v1"
    private static let legacyTUSBaseURL = "http://192.168.100.123:1080/files/"

    private enum Keys {
        static let learningBaseURL = "learning_base_url"
        static let tusBaseURL = "tusd_base_url"
        static let expiresAt = "learning_expires_at"
        static let userId = "learning_user_id"
        static let email = "learning_email"
        static let fullName = "learning_full_name"
        static let selectedWorkspaceId = "learning_selected_workspace_id"
        static let aiHistoryEnabled = "ai_history_enabled"
        static let accessToken = "learning_access_token"
        static let refreshToken = "learning_refresh_token"
        static let presenceClientId = "presence_client_id"
        static let appLanguage = "app_language"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func loadBaseURL() -> String {
        let stored = defaults.string(forKey: Keys.learningBaseURL)
        if stored == Self.legacyLearningBaseURL {
            saveBaseURL(defaultLearningBackendBaseURL)
            return defaultLearningBackendBaseURL
        }
        return normalizeLearningBackendBaseURL(stored ?? defaultLearningBackendBaseURL)
    }

    func loadTUSBaseURL() -> String {
        let stored = defaults.string(forKey: Keys.tusBaseURL)
        if stored == Self.legacyTUSBaseURL {
            saveTUSBaseURL(defaultTUSDBaseURL)
            return defaultTUSDBaseURL
        }
        return normalizeTUSBaseURL(stored ?? defaultTUSDBaseURL)
    }

    func saveBaseURL(_ baseURL: String) {
        defaults.set(normalizeLearningBackendBaseURL(baseURL), forKey: Keys.learningBaseURL)
    }

    func saveTUSBaseURL(_ baseURL: String) {
        defaults.set(normalizeTUSBaseURL(baseURL), forKey: Keys.tusBaseURL)
    }

    func loadAppLanguage() -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .system
    }

    func saveAppLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Keys.appLanguage)
    }

    func loadAIHistoryEnabled() -> Bool? {
        defaults.object(forKey: Keys.aiHistoryEnabled) as? Bool
    }

    func loadSession() -> SavedSession? {
        guard
            let accessToken = keychain.string(forKey: Keys.accessToken)?.nilIfBlank,
            let refreshToken = keychain.string(forKey: Keys.refreshToken)?.nilIfBlank,
            let userId = defaults.string(forKey: Keys.userId)?.nilIfBlank,
            let email = defaults.string(forKey: Keys.email)?.nilIfBlank,
            let expiresAt = defaults.string(forKey: Keys.expiresAt)?.nilIfBlank
        else {
            return nil
        }

        return SavedSession(
            baseURL: loadBaseURL(),
            tusBaseURL: loadTUSBaseURL(),
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            email: email,
            fullName: defaults.string(forKey: Keys.fullName)?.nilIfBlank,
            selectedWorkspaceId: defaults.string(forKey: Keys.selectedWorkspaceId)?.nilIfBlank,
            aiHistoryEnabled: defaults.object(forKey: Keys.aiHistoryEnabled) as? Bool ?? true
        )
    }

    func saveSession(_ session: SavedSession) {
        saveBaseURL(session.baseURL)
        saveTUSBaseURL(session.tusBaseURL)
        keychain.setString(session.accessToken, forKey: Keys.accessToken)
        keychain.setString(session.refreshToken, forKey: Keys.refreshToken)
        defaults.set(session.expiresAt, forKey: Keys.expiresAt)
        defaults.set(session.userId, forKey: Keys.userId)
        defaults.set(session.email, forKey: Keys.email)
        defaults.set(session.fullName ?? "", forKey: Keys.fullName)
        defaults.set(session.selectedWorkspaceId ?? "", forKey: Keys.selectedWorkspaceId)
        defaults.set(session.aiHistoryEnabled, forKey: Keys.aiHistoryEnabled)
    }

    func saveSelectedWorkspaceId(_ workspaceId: String?) {
        defaults.set(workspaceId ?? "", forKey: Keys.selectedWorkspaceId)
    }

    func loadPresenceClientId() -> String? {
        keychain.string(forKey: Keys.presenceClientId)?.nilIfBlank
    }

    func savePresenceClientId(_ clientId: String) {
        keychain.setString(clientId, forKey: Keys.presenceClientId)
    }

    func clearPresenceClientId() {
        keychain.removeString(forKey: Keys.presenceClientId)
    }

    func clearSession() {
        keychain.removeString(forKey: Keys.accessToken)
        keychain.removeString(forKey: Keys.refreshToken)
        keychain.removeString(forKey: Keys.presenceClientId)
        [
            Keys.expiresAt,
            Keys.userId,
            Keys.email,
            Keys.fullName,
            Keys.selectedWorkspaceId,
            Keys.aiHistoryEnabled
        ].forEach(defaults.removeObject(forKey:))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
