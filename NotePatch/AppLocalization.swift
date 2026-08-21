import Foundation
import SwiftUI
import Combine

enum AppDisplayText: Equatable, Sendable {
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
        guard locale.languageCode?.lowercased() == "zh" else { return .english }

        let script = locale.scriptCode?.lowercased()
        let region = locale.regionCode?.uppercased()
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
        "tab.home", "tab.documents", "tab.notes", "tab.ai", "tab.me",
        "home.title", "home.refresh", "home.metric.documents", "home.metric.units",
        "home.metric.homeworks", "home.active_task", "home.recent_documents",
        "home.recent_notes", "home.review", "home.no_documents", "home.no_notes",
        "home.loading_learning", "home.learning_failed", "home.note_metadata", "common.view_all",
        "upload.title", "knowledge.snippet", "grading.set_due_date", "profile.ai_history",
        "notes.section.notes", "notes.section.review", "notes.section.picker",
        "documents.section.documents", "documents.section.tasks",
        "review.section.notes", "review.section.units", "review.section.search", "review.section.homework",
        "chat.copy.conversation", "chat.copy.message", "chat.revision.action",
        "profile.edit", "profile.edit.title", "profile.avatar.choose",
        "filter.all", "filter.all_documents",
        "common.dismiss", "common.other",
        "file.unknown_size",
        "documents.count", "upload.items_count", "upload.selected_count",
        "accessibility.select_file", "accessibility.deselect_file",
        "accessibility.preview_file", "accessibility.remove_file", "accessibility.refresh_named",
        "accessibility.refresh_homework", "accessibility.remove_reference",
        "knowledge.results_count", "grading.confidence",
        "chat.error_event", "chat.citing_sources", "chat.model_used",
        "ai.model.title", "ai.model.picker", "ai.model.deployment_default",
        "ai.model.current", "ai.model.default", "ai.model.cached_warning",
        "ai.model.fetched_at", "ai.model.empty", "ai.model.loading",
        "ai.model.refresh", "operation.ai_model_saved",
        "task.status.cancelling", "task.type.document_cleanup", "task.type.document_processing",
        "status.preparing", "upload.selected_completed", "document.error.not_available",
        "document.error.not_processable", "artifact.converted_pdf",
        "preview.unsupported.title", "preview.unsupported.message", "preview.file.name",
        "preview.file.type", "preview.file.size", "preview.open_external",
        "merge.action", "merge.title", "merge.help", "merge.target", "merge.sources_count", "merge.continue",
        "merge.confirm.title", "merge.confirm.action", "merge.confirm.message", "merge.view_task",
        "merge.error.target_required", "merge.error.sources_required", "merge.starting", "merge.in_progress",
        "merge.task_progress", "merge.rebuilding", "merge.completed", "merge.status.merging",
        "merge.status.rebuilding", "merge.status.completed", "merge.status.failed",
        "task.type.merge_learning_units", "note.reader.signed_url_expired", "note.reader.http_error",
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
        "error.http.generic",
        "common.expand", "upload.learning_info", "task.result", "task.cancelled_fallback",
        "task.type.ai_chat", "task.type.other", "knowledge.limit", "knowledge.page",
        "chat.composer_accessibility", "chat.system_help", "chat.no_content", "chat.recent_event",
        "operation.registering", "operation.signing_in", "operation.note_downloaded",
        "operation.image_downloaded", "operation.file_downloaded", "document.ocr_empty",
        "document.ocr_loaded", "document.artifact_downloaded", "status.unknown",
        "merge.status.unknown", "document_kind.unknown", "file_type.unknown", "artifact.unknown",
        "error.image.orientation", "error.server.invalid_response", "error.download.invalid_url",
        "error.session.expired", "error.session.refresh_cancelled", "error.auth.required",
        "error.server.invalid_address", "error.task.stream_disconnected", "error.task.stream_incomplete",
        "error.upload.confirmation_failed", "error.note.invalid_encoding", "error.upload.file_missing",
        "error.tus.location_missing", "error.tus.version_missing", "error.tus.location_invalid",
        "error.tus.chunk_failed", "error.photo.type_unknown", "error.photo.read_failed",
        "error.network.invalid_address", "error.network.dns", "error.network.unreachable",
        "error.network.timeout", "error.network.io", "note.error.conflict_refresh_failed_generic",
        "upload.some_failed_generic", "filter.summary.status", "filter.summary.type", "filter.summary.file",
        "status.pending", "status.rebuilding", "status.unavailable", "error.task.failed",
        "common.collapse", "chat.ai.saved_session", "chat.ai.auto_saved_after_first_message"
    ]

    @Published private(set) var language: AppLanguage
    private let settings: SettingsStore
    private var localizedValueCache: [String: String] = [:]
    private var localizationBundleCache: (identifier: String, bundle: Bundle)?

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
        localizedValueCache.removeAll(keepingCapacity: true)
        localizationBundleCache = nil
        settings.saveAppLanguage(language)
    }

    func string(_ key: String) -> String {
        if let cached = localizedValueCache[key] {
            return cached
        }
        let bundle = localizationBundle
        let value = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        localizedValueCache[key] = value
        return value
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
        let identifier = language.resourceIdentifier
        if let cached = localizationBundleCache, cached.identifier == identifier {
            return cached.bundle
        }
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main
        }
        localizationBundleCache = (identifier, bundle)
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
