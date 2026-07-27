import Foundation
import SwiftUI
import Combine

enum AppDisplayText: Equatable {
    case localized(String, [String] = [])
    case raw(String)

    @MainActor
    func resolved(using localization: AppLocalization) -> String {
        switch self {
        case .localized(let key, let arguments):
            return localization.string(key, arguments: arguments)
        case .raw(let value):
            return value
        }
    }

    @MainActor
    func resolved() -> String {
        resolved(using: .shared)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return localized("language.system")
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return AppLanguage.resolvedSystemLanguage().localeIdentifier
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .english:
            return "en"
        }
    }

    var resourceIdentifier: String {
        switch self {
        case .system:
            return AppLanguage.resolvedSystemLanguage().resourceIdentifier
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .english:
            return "en"
        }
    }

    static func resolvedSystemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let identifier = preferredLanguages.first else { return .english }
        let locale = Locale(identifier: identifier)
        guard locale.language.languageCode?.identifier.lowercased() == "zh" else { return .english }

        let script = locale.language.script?.identifier.lowercased()
        let region = locale.region?.identifier.uppercased()
        if script == "hant" || ["TW", "HK", "MO"].contains(region ?? "") {
            return .traditionalChinese
        }
        return .simplifiedChinese
    }
}

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    static let requiredSemanticKeys = [
        "language.system",
        "tab.documents", "tab.notes", "tab.ai", "tab.me",
        "notes.section.notes", "notes.section.review", "notes.section.picker",
        "documents.section.documents", "documents.section.tasks",
        "review.section.units", "review.section.search", "review.section.grading",
        "filter.all", "filter.all_documents",
        "common.dismiss", "common.other",
        "file.unknown_size",
        "documents.count", "upload.items_count", "upload.selected_count",
        "accessibility.select_file", "accessibility.deselect_file",
        "accessibility.preview_file", "accessibility.remove_file", "accessibility.refresh_named",
        "accessibility.refresh_homework", "accessibility.remove_reference",
        "knowledge.results_count", "grading.confidence",
        "chat.error_event", "chat.citing_sources",
        "task.status.cancelling", "task.type.document_cleanup", "task.type.document_processing",
        "grading.mode.official", "grading.mode.diagnostic", "account.default_user",
        "note.version", "account.session_valid_until",
        "workspace.switched", "workspace.loaded",
        "upload.added_to_queue", "upload.batch_progress", "upload.some_failed",
        "upload.tus_progress", "upload.tusd_sync_retry",
        "task.progress", "knowledge.results_found", "grading.task_progress",
        "document.cleanup_progress", "operation.refresh_failed", "notes.partial_load",
        "operation.conversation_deleted", "operation.note_revision_saved",
        "operation.reference_removed", "operation.document_cleanup_completed",
        "error.http.unauthorized", "error.http.forbidden", "error.http.not_found",
        "error.http.conflict", "error.http.gone", "error.http.validation",
        "error.http.generic"
    ]

    @Published private(set) var language: AppLanguage
    private let settings: SettingsStore

    init(settings: SettingsStore? = nil) {
        let settings = settings ?? SettingsStore()
        self.settings = settings
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-NotePatchUITestLanguage"),
           arguments.indices.contains(flagIndex + 1),
           let override = AppLanguage(rawValue: arguments[flagIndex + 1]) {
            language = override
        } else {
            language = settings.loadAppLanguage()
        }
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func select(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        settings.saveAppLanguage(language)
    }

    func string(_ key: String) -> String {
        let bundle = localizationBundle
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func string(_ key: String, arguments: [CVarArg]) -> String {
        let format = string(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func string(_ key: String, arguments: [String]) -> String {
        let format = string(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func hasLocalizedValue(for key: String) -> Bool {
        let value = localizationBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return !value.isEmpty && value != key
    }

    private var localizationBundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.resourceIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main
        }
        return bundle
    }
}

@MainActor
func localized(_ key: String) -> String {
    AppLocalization.shared.string(key)
}

@MainActor
func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalization.shared.string(key, arguments: arguments)
}
