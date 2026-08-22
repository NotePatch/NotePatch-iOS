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

    var aiClientLocale: String {
        let resolved = self == .system ? AppLanguage.resolvedSystemLanguage() : self
        switch resolved {
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .english, .system: return "en-US"
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
        "chat.copy.message", "chat.select_text.action", "chat.select_text.title", "chat.revision.action",
        "profile.edit", "profile.edit.title", "profile.avatar.choose",
        "profile.global_feedback", "profile.global_feedback_help",
        "feedback.accessibility.keep", "feedback.accessibility.pinned", "feedback.accessibility.dismiss_outside",
        "filter.all", "filter.all_documents",
        "common.dismiss", "common.other",
        "file.unknown_size",
        "documents.count", "upload.items_count", "upload.selected_count",
        "accessibility.select_file", "accessibility.deselect_file",
        "accessibility.preview_file", "accessibility.remove_file", "accessibility.refresh_named",
        "accessibility.refresh_homework", "accessibility.remove_reference",
        "knowledge.results_count", "grading.confidence", "grading.latest_result", "grading.history",
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
        "workspace.loaded",
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
        "common.collapse", "chat.ai.saved_session", "chat.ai.auto_saved_after_first_message",
        "chat.ai_name", "ai.greeting.load_failed", "ai.onboarding.title", "ai.onboarding.loading",
        "ai.onboarding.progress", "ai.onboarding.custom_instructions", "ai.onboarding.complete",
        "ai.onboarding.load_failed", "ai.onboarding.custom_too_long", "ai.onboarding.answer_required",
        "ai.onboarding.version_changed", "ai.preferences.title", "ai.preferences.summary", "ai.preferences.saved",
        "ai.onboarding.questions.response_language", "ai.onboarding.questions.collaboration_style",
        "ai.onboarding.questions.response_depth", "ai.onboarding.questions.response_structure",
        "ai.onboarding.questions.clarification_policy", "ai.onboarding.questions.feedback_tone",
        "ai.onboarding.questions.learning_guidance",
        "ai.onboarding.options.response_language.match_user", "ai.onboarding.options.response_language.client_locale",
        "ai.onboarding.options.response_language.zh-CN", "ai.onboarding.options.response_language.en-US",
        "ai.onboarding.options.response_language.pt-BR", "ai.onboarding.options.collaboration_style.direct",
        "ai.onboarding.options.collaboration_style.collaborative", "ai.onboarding.options.collaboration_style.coach",
        "ai.onboarding.options.collaboration_style.socratic", "ai.onboarding.options.response_depth.concise",
        "ai.onboarding.options.response_depth.balanced", "ai.onboarding.options.response_depth.detailed",
        "ai.onboarding.options.response_structure.adaptive", "ai.onboarding.options.response_structure.steps",
        "ai.onboarding.options.response_structure.bullets", "ai.onboarding.options.response_structure.prose",
        "ai.onboarding.options.clarification_policy.ask_when_ambiguous",
        "ai.onboarding.options.clarification_policy.assume_when_safe",
        "ai.onboarding.options.clarification_policy.confirm_before_actions",
        "ai.onboarding.options.feedback_tone.gentle", "ai.onboarding.options.feedback_tone.neutral",
        "ai.onboarding.options.feedback_tone.strict", "ai.onboarding.options.learning_guidance.answer_first",
        "ai.onboarding.options.learning_guidance.explain_then_answer", "ai.onboarding.options.learning_guidance.hint_first",
        "image_remark.preference.title", "image_remark.preference.toggle", "image_remark.preference.help",
        "image_remark.preference.saving", "image_remark.preference.saved",
        "image_remark.upload.title", "image_remark.upload.action", "image_remark.upload.help",
        "image_remark.edit.title", "image_remark.edit.action", "image_remark.edit.help",
        "image_remark.placeholder", "image_remark.restore_filename", "image_remark.saving", "image_remark.saved",
        "image_remark.error.required", "image_remark.error.too_long",
        "image_remark.status.processing", "image_remark.status.succeeded", "image_remark.status.failed",
        "image_remark.status.empty_ocr", "image_remark.status.disabled", "image_remark.status.user",
        "image_remark.status.unknown", "image_remark.source.user", "image_remark.source.ai_ocr",
        "image_remark.source.original_filename", "image_remark.source.unknown",
        "image_remark.detail.original_filename", "image_remark.detail.title",
        "image_remark.detail.source", "image_remark.detail.status", "note.completion.summary",
        "note.completion.strategy", "note.completion.evidence_revision"
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
