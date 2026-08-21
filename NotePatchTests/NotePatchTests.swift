import Combine
import CryptoKit
import Foundation
import JavaScriptCore
import QuickLookThumbnailing
import SwiftUI
import Testing
import UIKit
import WebKit
@testable import NotePatch

private actor ThumbnailTestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Suite(.serialized)
@MainActor
struct NotePatchTests {
    // Hosted tests share the app container, so force the shared localization to
    // simplified Chinese instead of depending on the simulator's ambient defaults.
    init() {
        // The shared AppLocalization singleton reads this on first access.
        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: "app_language")
    }

    @Test func backendIntegrationDocument_matchesCurrentContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let documentURL = repositoryRoot.appendingPathComponent("docs/backend-frontend-integration.md")
        let data = try Data(contentsOf: documentURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(data.split(separator: 0x0A, omittingEmptySubsequences: false).count == 1_338)
        #expect(digest == "0f71d6bb6f56f145457c02a84850fc0b6ccf9b9bbe0918e240e0a65f6bbc1eb5")
    }

    @MainActor
    private static func makeComposerTextView() -> UITextView {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 8, bottom: 9, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        return textView
    }

    @Test func normalizeBaseURLs_defaultAndAddScheme() {
        #expect(normalizeLearningBackendBaseURL("") == defaultLearningBackendBaseURL)
        #expect(normalizeLearningBackendBaseURL("192.168.100.123:8001/") == "http://192.168.100.123:8001")
        #expect(normalizeLearningBackendBaseURL("\(defaultServiceRootURL)/") == defaultLearningBackendBaseURL)
        #expect(normalizeLearningBackendBaseURL("https://example.test/api/v1/") == "https://example.test/api/v1")
        #expect(normalizeLearningBackendBaseURL("https://example.test/api/") == "https://example.test/api")

        #expect(normalizeTUSBaseURL("") == defaultTUSDBaseURL)
        #expect(normalizeTUSBaseURL("192.168.100.123:1080/files") == "http://192.168.100.123:1080/files/")
        #expect(normalizeTUSBaseURL(defaultTUSDServiceRootURL) == defaultTUSDBaseURL)
        #expect(normalizeTUSBaseURL("https://example.test/files/") == "https://example.test/files/")
    }

    @Test @MainActor func backendClient_appendsHealthAndAPIPrefixToServiceBaseURL() async throws {
        var requestedURLs: [String] = []
        let session = Self.mockSession { request in
            requestedURLs.append(request.url?.absoluteString ?? "")
            switch request.url?.path {
            case "/np-b9a6aede5d0fbb05229d9541144a6067/health":
                return Self.response(request, status: 200, body: #"{"status":"ok"}"#)
            case "/np-b9a6aede5d0fbb05229d9541144a6067/api/v1/auth/me":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"id":"u-1","email":"user@example.test","is_active":true,"created_at":""}"#
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected path"}"#)
            }
        }
        let client = LearningBackendClient(
            baseURL: defaultLearningBackendBaseURL,
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        _ = try await client.healthCheck()
        _ = try await client.me()

        #expect(requestedURLs == [
            "\(defaultServiceRootURL)/health",
            "\(defaultServiceRootURL)/api/v1/auth/me"
        ])
    }

    @Test func settingsStore_migratesLegacyDefaultServerURLs() throws {
        let suiteName = "NotePatchURLMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("http://192.168.100.123:8001/api/v1", forKey: "learning_base_url")
        defaults.set("http://192.168.100.123:1080/files/", forKey: "tusd_base_url")

        let store = SettingsStore(
            defaults: defaults,
            keychain: KeychainStore(service: "\(suiteName).keychain")
        )

        #expect(store.loadBaseURL() == defaultLearningBackendBaseURL)
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)
        #expect(defaults.string(forKey: "learning_base_url") == defaultLearningBackendBaseURL)
        #expect(defaults.string(forKey: "tusd_base_url") == defaultTUSDBaseURL)

        defaults.set("https://5mbps.me:8443/notepatch/1/files/", forKey: "tusd_base_url")
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)
        #expect(defaults.string(forKey: "tusd_base_url") == defaultTUSDBaseURL)

        defaults.set("https://5mbps.me:8443/notepatch/1", forKey: "learning_base_url")
        defaults.set(2, forKey: "api_base_url_contract_version")
        defaults.set("https://5mbps.me:8443/notepatch/2/files/", forKey: "tusd_base_url")
        #expect(store.loadBaseURL() == defaultLearningBackendBaseURL)
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)
        #expect(defaults.string(forKey: "learning_base_url") == defaultLearningBackendBaseURL)
        #expect(defaults.string(forKey: "tusd_base_url") == defaultTUSDBaseURL)

        defaults.set("https://api.ls-jl.cn:8443/notepatch/1", forKey: "learning_base_url")
        defaults.set(3, forKey: "api_base_url_contract_version")
        defaults.set("https://api.ls-jl.cn:8443/notepatch/2/files/", forKey: "tusd_base_url")
        #expect(store.loadBaseURL() == defaultLearningBackendBaseURL)
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)
        #expect(store.loadBaseURL() == defaultLearningBackendBaseURL)
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)

        defaults.set("https://api.ls-jl.cn:8443/notepatch/1", forKey: "learning_base_url")
        defaults.set(4, forKey: "api_base_url_contract_version")
        defaults.set("https://api.ls-jl.cn:8443/notepatch/1/files/", forKey: "tusd_base_url")
        #expect(store.loadBaseURL() == defaultLearningBackendBaseURL)
        #expect(store.loadTUSBaseURL() == defaultTUSDBaseURL)
        #expect(defaults.string(forKey: "learning_base_url") == defaultLearningBackendBaseURL)

        defaults.set("https://custom.example.test/root", forKey: "learning_base_url")
        defaults.set(3, forKey: "api_base_url_contract_version")
        defaults.set("https://uploads.example.test/custom/", forKey: "tusd_base_url")
        #expect(store.loadBaseURL() == "https://custom.example.test/root")
        #expect(store.loadTUSBaseURL() == "https://uploads.example.test/custom/")
        #expect(defaults.integer(forKey: "api_base_url_contract_version") == 5)

        defaults.set("https://api.example.test/notepatch/api/v1", forKey: "learning_base_url")
        defaults.removeObject(forKey: "api_base_url_contract_version")
        #expect(store.loadBaseURL() == "https://api.example.test/notepatch/api/v1")

        store.saveBaseURL("https://api.example.test/notepatch/api/v1")
        #expect(store.loadBaseURL() == "https://api.example.test/notepatch/api/v1")
    }

    @Test func settingsStore_migratesOfficialSessionWithoutClearingCredentials() throws {
        let suiteName = "NotePatchSessionURLMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "\(suiteName).keychain")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            keychain.removeString(forKey: "learning_access_token")
            keychain.removeString(forKey: "learning_refresh_token")
        }
        defaults.set("https://api.ls-jl.cn:8443/notepatch/1", forKey: "learning_base_url")
        defaults.set("https://api.ls-jl.cn:8443/notepatch/2/files/", forKey: "tusd_base_url")
        defaults.set(3, forKey: "api_base_url_contract_version")
        defaults.set("2099-01-01T00:00:00Z", forKey: "learning_expires_at")
        defaults.set("user-1", forKey: "learning_user_id")
        defaults.set("user@example.test", forKey: "learning_email")
        defaults.set("workspace-1", forKey: "learning_selected_workspace_id")
        defaults.set(true, forKey: "ai_history_enabled")
        keychain.setString("access-token", forKey: "learning_access_token")
        keychain.setString("refresh-token", forKey: "learning_refresh_token")

        let session = try #require(SettingsStore(defaults: defaults, keychain: keychain).loadSession())

        #expect(session.baseURL == defaultLearningBackendBaseURL)
        #expect(session.tusBaseURL == defaultTUSDBaseURL)
        #expect(session.accessToken == "access-token")
        #expect(session.refreshToken == "refresh-token")
        #expect(session.userId == "user-1")
        #expect(session.selectedWorkspaceId == "workspace-1")
    }

    @Test func appLanguage_resolvesSupportedSystemLanguagesAndPersistsChoice() throws {
        #expect(AppLanguage.resolvedSystemLanguage(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolvedSystemLanguage(preferredLanguages: ["zh-Hant-TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolvedSystemLanguage(preferredLanguages: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolvedSystemLanguage(preferredLanguages: ["fr-FR"]) == .english)

        let suiteName = "NotePatchLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "\(suiteName).keychain"))
        #expect(store.loadAppLanguage() == .system)

        store.saveAppLanguage(.traditionalChinese)
        #expect(store.loadAppLanguage() == .traditionalChinese)
    }

    @Test @MainActor func globalFeedbackPreferenceDefaultsOnPersistsAndClearsCurrentMessage() throws {
        let suiteName = "NotePatchFeedbackPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = KeychainStore(service: "\(suiteName).keychain")
        let store = SettingsStore(defaults: defaults, keychain: keychain)

        #expect(store.loadGlobalFeedbackEnabled())
        let model = NotePatchViewModel(settings: store)
        model.presentStatus("operation.api_connected")
        model.updateGlobalFeedbackEnabled(false)

        #expect(!model.isGlobalFeedbackEnabled)
        #expect(model.statusMessage.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!store.loadGlobalFeedbackEnabled())

        let restored = NotePatchViewModel(settings: SettingsStore(defaults: defaults, keychain: keychain))
        #expect(!restored.isGlobalFeedbackEnabled)
    }

    @Test func globalFeedbackPrioritizesErrorsAndUsesExclusiveActivityStates() {
        #expect(appFeedbackItem(statusMessage: "Saved", errorMessage: nil, isBusy: false) == .init(kind: .success, text: "Saved"))
        #expect(appFeedbackItem(statusMessage: "Saving", errorMessage: nil, isBusy: true) == nil)
        #expect(appFeedbackItem(statusMessage: "Saving", errorMessage: "Failed", isBusy: true) == .init(kind: .error, text: "Failed"))
        #expect(appActivityPresentation(isBusy: false, progressPercent: 42, label: "Upload") == .hidden)
        #expect(appActivityPresentation(isBusy: true, progressPercent: nil, label: "Saving") == .indeterminate("Saving"))
        #expect(appActivityPresentation(isBusy: true, progressPercent: 142, label: "Upload") == .determinate(100, "Upload"))
    }

    @Test @MainActor func globalFeedbackAutoDismissesAndReplacementRestartsTimer() async throws {
        let state = AppFeedbackPresentationState(autoDismissNanoseconds: 60_000_000)
        var dismissed: [String] = []
        state.present(identity: "first") { dismissed.append("first") }
        try await Task.sleep(nanoseconds: 20_000_000)
        state.present(identity: "second") { dismissed.append("second") }
        try await Task.sleep(nanoseconds: 45_000_000)
        #expect(state.isVisible)
        #expect(dismissed.isEmpty)
        try await Task.sleep(nanoseconds: 35_000_000)
        #expect(!state.isVisible)
        #expect(dismissed == ["second"])
    }

    @Test @MainActor func pinnedFeedbackIgnoresTimerAndOutsideTapDismissesIt() async throws {
        let state = AppFeedbackPresentationState(autoDismissNanoseconds: 20_000_000)
        var dismissCount = 0
        state.present(identity: "pinned") { dismissCount += 1 }
        state.pin()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(state.isVisible)
        #expect(state.isPinned)
        #expect(dismissCount == 0)

        state.dismissFromOutsideTap()
        #expect(!state.isVisible)
        #expect(!state.isPinned)
        #expect(dismissCount == 1)
    }

    @Test @MainActor func appLocalization_updatesImmediatelyAndKeepsNetworkSettingsUntouched() throws {
        let suiteName = "NotePatchLocalizationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "\(suiteName).keychain"))
        store.saveBaseURL("https://api.example.test")
        let localization = AppLocalization(settings: store)

        localization.select(.simplifiedChinese)
        #expect(localization.language == .simplifiedChinese)
        #expect(localization.locale.identifier.lowercased().contains("zh-hans"))
        #expect(localization.string("Notes") == "笔记")
        #expect(store.loadAppLanguage() == .simplifiedChinese)
        #expect(store.loadBaseURL() == "https://api.example.test")
    }

    @Test @MainActor func semanticLocalizationKeysExistInEverySupportedLanguage() throws {
        let suiteName = "NotePatchLocalizationCompletenessTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "\(suiteName).keychain"))
        let localization = AppLocalization(settings: store)

        for language in [AppLanguage.english, .simplifiedChinese, .traditionalChinese] {
            localization.select(language)
            for key in AppLocalization.requiredSemanticKeys {
                #expect(localization.hasLocalizedValue(for: key), "Missing \(key) for \(language.rawValue)")
            }
        }

        let status = AppDisplayText.localized("task.progress", ["42", "75"])
        localization.select(.simplifiedChinese)
        #expect(status.resolved(using: localization) == "任务 42：75%")
        localization.select(.english)
        #expect(status.resolved(using: localization) == "Task 42: 75%")
        #expect(AppDisplayText.raw("backend detail").resolved(using: localization) == "backend detail")

        func keys(in resource: String) throws -> Set<String> {
            let url = try #require(Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: resource
            ))
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            let values = try #require(
                try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
                    as? [String: String]
            )
            return Set(values.keys)
        }

        let englishKeys = try keys(in: "en")
        let simplifiedChineseKeys = try keys(in: "zh-Hans")
        let traditionalChineseKeys = try keys(in: "zh-Hant")
        #expect(englishKeys == simplifiedChineseKeys)
        #expect(englishKeys == traditionalChineseKeys)
    }

    @Test @MainActor func sourceLocalizationKeysAndFormatArgumentsAreComplete() throws {
        func values(in resource: String) throws -> [String: String] {
            let url = try #require(Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: resource
            ))
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            return try #require(
                try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
                    as? [String: String]
            )
        }

        let localizedValues = try [
            "en": values(in: "en"),
            "zh-Hans": values(in: "zh-Hans"),
            "zh-Hant": values(in: "zh-Hant")
        ]
        let englishValues = try #require(localizedValues["en"])
        for key in englishValues.keys {
            let expectedArgumentCount = englishValues[key]?.components(separatedBy: "%@").count ?? 1
            for (language, table) in localizedValues {
                let value = try #require(table[key], "Missing \(key) for \(language)")
                #expect(
                    value.components(separatedBy: "%@").count == expectedArgumentCount,
                    "Format argument mismatch for \(key) in \(language)"
                )
            }
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NotePatch", isDirectory: true)
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let keyPatterns = [
            #"(?:localized|localizedFormat|setStatus|setError|setUploadProgress)\s*\(\s*\"([^\"]+)\""#,
            #"localizedKey:\s*\"([^\"]+)\""#,
            #"\.localized\(\s*\"([^\"]+)\""#
        ].map { try! NSRegularExpression(pattern: $0) }
        let visibleLiteralPattern = try NSRegularExpression(
            pattern: #"(?<![A-Za-z])(?:Text|Label|Button|DisclosureGroup|Stepper|navigationTitle|accessibilityLabel)\s*\(\s*\"([^\"]+)\""#
        )

        var sourceKeys = Set(AppLocalization.requiredSemanticKeys)
        var visibleLiterals = Set<String>()
        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for pattern in keyPatterns {
                for match in pattern.matches(in: source, range: range) {
                    guard let captureRange = Range(match.range(at: 1), in: source) else { continue }
                    let key = String(source[captureRange])
                    if !key.contains(#"\("#) {
                        sourceKeys.insert(key)
                    }
                }
            }
            for match in visibleLiteralPattern.matches(in: source, range: range) {
                guard let captureRange = Range(match.range(at: 1), in: source) else { continue }
                visibleLiterals.insert(String(source[captureRange]))
            }
        }

        for key in sourceKeys {
            for (language, table) in localizedValues {
                #expect(table[key]?.isEmpty == false, "Missing source key \(key) for \(language)")
            }
        }
        let permittedVisibleLiterals: Set<String> = ["NotePatch"]
        let untranslatedVisibleLiterals = visibleLiterals.filter { literal in
            literal.range(of: "[A-Za-z]", options: .regularExpression) != nil
                && !literal.contains(#"\("#)
                && !permittedVisibleLiterals.contains(literal)
        }
        #expect(untranslatedVisibleLiterals.isEmpty, "Unlocalized UI literals: \(untranslatedVisibleLiterals.sorted())")
    }

    @Test @MainActor func darkModeColorTokensResolveToDistinctReadableSurfaces() throws {
        func resolved(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
            UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        }

        func components(_ color: UIColor) throws -> (CGFloat, CGFloat, CGFloat) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            #expect((0...1).contains(red))
            #expect((0...1).contains(green))
            #expect((0...1).contains(blue))
            #expect((0...1).contains(alpha))
            return (red, green, blue)
        }

        func luminance(_ rgb: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.03928
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
        }

        func contrast(_ first: UIColor, _ second: UIColor) throws -> CGFloat {
            let firstLuminance = luminance(try components(first))
            let secondLuminance = luminance(try components(second))
            return (max(firstLuminance, secondLuminance) + 0.05)
                / (min(firstLuminance, secondLuminance) + 0.05)
        }

        let lightBackground = resolved(NPColors.background, style: .light)
        let darkBackground = resolved(NPColors.background, style: .dark)
        #expect(lightBackground != darkBackground)
        #expect(try contrast(resolved(NPColors.textPrimary, style: .light), lightBackground) >= 4.5)
        #expect(try contrast(resolved(NPColors.textPrimary, style: .dark), darkBackground) >= 4.5)
        #expect(resolved(NPColors.surfaceCard, style: .light) != resolved(NPColors.surfaceCard, style: .dark))
        #expect(resolved(NPColors.brand, style: .light) != resolved(NPColors.brand, style: .dark))
    }

    @Test func infoPlistPermissionDescriptionsExistInEverySupportedLanguage() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NotePatch", isDirectory: true)
        let requiredKeys = [
            "CFBundleDisplayName",
            "NSCameraUsageDescription",
            "NSPhotoLibraryAddUsageDescription",
            "NSPhotoLibraryUsageDescription"
        ]
        for resource in ["en", "zh-Hans", "zh-Hant"] {
            let url = sourceRoot
                .appendingPathComponent("\(resource).lproj", isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            let values = try #require(
                try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
                    as? [String: String]
            )
            for key in requiredKeys {
                #expect(values[key]?.isEmpty == false, "Missing \(key) for \(resource)")
            }
        }
    }

    @Test @MainActor func composerTextLayout_usesProvidedWidthAndWrapsText() throws {
        let textView = Self.makeComposerTextView()
        textView.text = String(repeating: "automatic wrapping ", count: 3)

        let wide = try #require(
            ComposerTextLayout.measure(textView: textView, availableWidth: 320, maximumLines: 7)
        )
        let narrow = try #require(
            ComposerTextLayout.measure(textView: textView, availableWidth: 140, maximumLines: 7)
        )

        #expect(narrow.height > wide.height)
        #expect(!wide.requiresScrolling)
        #expect(!narrow.requiresScrolling)
        #expect(ComposerTextLayout.measure(textView: textView, availableWidth: 1, maximumLines: 7) == nil)
    }

    @Test @MainActor func composerTextLayout_preservesNewlinesAndCapsAtSevenLines() throws {
        let textView = Self.makeComposerTextView()
        textView.text = "first line\nsecond line"
        let twoLines = try #require(
            ComposerTextLayout.measure(textView: textView, availableWidth: 300, maximumLines: 7)
        )
        #expect(twoLines.height > 44)
        #expect(!twoLines.requiresScrolling)

        textView.text = (1...9).map { "line \($0)" }.joined(separator: "\n")
        let overflow = try #require(
            ComposerTextLayout.measure(textView: textView, availableWidth: 300, maximumLines: 7)
        )
        let lineHeight = try #require(textView.font?.lineHeight)
        let insets = textView.textContainerInset.top + textView.textContainerInset.bottom

        #expect(overflow.height == ceil(lineHeight * 7 + insets))
        #expect(overflow.requiresScrolling)
    }

    @Test func keyboardAvoidance_movesComposerButNotWorkbenchBottomBar() {
        let chatFrame = CGRect(x: 0, y: 0, width: 390, height: 760)
        let dockedKeyboard = CGRect(x: 0, y: 510, width: 390, height: 334)
        #expect(keyboardAvoidanceOffset(contentFrame: chatFrame, keyboardFrame: dockedKeyboard) == 250)

        let hiddenKeyboard = CGRect(x: 0, y: 844, width: 390, height: 334)
        #expect(keyboardAvoidanceOffset(contentFrame: chatFrame, keyboardFrame: hiddenKeyboard) == 0)

        let nonOverlappingFloatingKeyboard = CGRect(x: 420, y: 500, width: 300, height: 250)
        #expect(keyboardAvoidanceOffset(contentFrame: chatFrame, keyboardFrame: nonOverlappingFloatingKeyboard) == 0)
        #expect(keyboardAvoidanceOffset(contentFrame: chatFrame, keyboardFrame: .null) == 0)
    }

    @Test func bottomNavigationUsesSystemHomeIndicatorSpacingOnce() {
        #expect(workbenchBottomBarAdditionalPadding(safeAreaBottom: 34) == 0)
        #expect(workbenchBottomBarAdditionalPadding(safeAreaBottom: 21) == 0)
        #expect(workbenchBottomBarAdditionalPadding(safeAreaBottom: 0) == 8)
    }

    @Test func bottomNavigationObstructionUsesMeasuredFrameAndVisibility() {
        let bar = CGRect(x: 16, y: 722, width: 358, height: 66)
        #expect(workbenchBottomObstruction(containerHeight: 844, bottomBarFrame: bar, isVisible: true) == 122)
        #expect(workbenchBottomObstruction(containerHeight: 844, bottomBarFrame: bar, isVisible: false) == 0)
        #expect(workbenchBottomObstruction(containerHeight: 844, bottomBarFrame: .null, isVisible: true) == 0)
        #expect(workbenchBottomObstruction(containerHeight: 700, bottomBarFrame: bar, isVisible: true) == 0)
    }

    @Test func feedbackToastUsesBottomBarOrSafeAreaAsItsBoundary() {
        let fullScreenBar = CGRect(x: 16, y: 722, width: 358, height: 66)
        #expect(appFeedbackBottomOffset(
            containerHeight: 844,
            bottomBarFrame: fullScreenBar,
            isAuthenticated: true,
            isUploadPresented: false,
            isBottomBarVisible: true,
            safeAreaBottom: 34
        ) == 136)

        #expect(appFeedbackBottomOffset(
            containerHeight: 844,
            bottomBarFrame: fullScreenBar,
            isAuthenticated: true,
            isUploadPresented: true,
            isBottomBarVisible: true,
            safeAreaBottom: 34
        ) == 54)

        #expect(appFeedbackBottomOffset(
            containerHeight: 667,
            bottomBarFrame: .null,
            isAuthenticated: false,
            isUploadPresented: false,
            isBottomBarVisible: false,
            safeAreaBottom: 0
        ) == 20)
    }

    @Test @MainActor func workbenchTabsHaveExpectedOrderAndDefault() throws {
        #expect(WorkbenchTab.allCases == [.home, .notes, .openClaw, .profile])
        let model = NotePatchViewModel()
        #expect(model.selectedTab == .home)
        #expect(model.selectedLearningSection == .notes)
        #expect(LearningSection.allCases == [.notes, .units, .search, .homework, .flashcards])

        var rootPublicationCount = 0
        let rootPublication = model.objectWillChange.sink { rootPublicationCount += 1 }
        model.selectedTab = .notes
        #expect(model.workbenchNavigationState.selectedTab == .notes)
        #expect(rootPublicationCount == 0)
        withExtendedLifetime(rootPublication) {}
    }

    @Test @MainActor func homeDashboardKeepsDocumentCountAndFiveMostRecentRows() {
        let state = HomeDashboardState()
        let documents = (1...6).map { index in
            LearningDocumentItem(
                id: "document-\(index)",
                workspaceId: "workspace",
                title: "Document \(index)",
                originalFilename: "document-\(index).pdf",
                fileType: "pdf",
                documentKind: "courseware",
                status: "ready",
                updatedAt: "2026-08-\(String(format: "%02d", index))T12:00:00Z"
            )
        }

        state.updateDocuments(documents)

        #expect(state.documentCount == 6)
        #expect(state.recentDocuments.map(\.id) == [
            "document-6", "document-5", "document-4", "document-3", "document-2"
        ])
    }

    @Test func fileHelpers_sanitizeMimeAndByteFormatting() {
        #expect(sanitizeFileName("a/b:c?.pdf") == "a_b_c_.pdf")
        #expect(contentTypeForFilename("photo.jpg") == "image/jpeg")
        #expect(contentTypeForFilename("slides.pptx") == "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        #expect(replacingFilenameExtension("exam.pdf", with: "jpg") == "exam.jpg")
        #expect(formatBytes(512) == "512 B")
        #expect(formatBytes(2048) == "2.0 KB")
    }

    @Test @MainActor func startupLoadsOnlyDocumentsAndDefersOtherTabs() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var paths: [String] = []
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            switch path {
            case "/api/v1/auth/me":
                return Self.response(request, status: 200, body: #"{"id":"u-1","email":"user@example.com","full_name":"User","is_active":true,"created_at":""}"#)
            case "/api/v1/workspaces":
                return Self.response(request, status: 200, body: #"[{"id":"ws-1","name":"My Workspace","type":"personal","owner_user_id":"u-1","created_at":"","updated_at":""}]"#)
            case "/api/v1/workspaces/ws-1/documents":
                return Self.response(request, status: 200, body: "[]")
            case "/api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[]")
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"unit-1","title":"比例","subject":"数学","grade_level":"七年级","topic":""}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/unit-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"note-1","learning_unit_id":"unit-1","version_no":1,"title":"笔记","html_object_key":"h","json_object_key":"j","download_urls":{}}]"#)
            case "/api/v1/workspaces/ws-1/ai/models":
                return Self.response(request, status: 200, body: #"{"provider":"openai","default_model":"model-default","selected_model":"model-default","items":[],"fetched_at":"","stale":false}"#)
            case "/api/v1/user/profile":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"code":"ok","message":"Profile loaded","data":{"id":"u-1","name":"User","email":"user@example.com","avatar_url":null,"profile_version":1,"reauthentication_required":false}}"#
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u-1",
            email: "user@example.com",
            fullName: "User",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"

        await model.restoreIfNeeded()

        #expect(paths == [
            "/api/v1/auth/me",
            "/api/v1/workspaces",
            "/api/v1/workspaces/ws-1/documents"
        ])

        model.selectedTab = .home
        model.ensureContentForSelectedTabLoaded()
        try await Self.waitUntil {
            !model.homeDashboardState.isLoadingSupplementaryContent
                && model.studyNoteGroups.count == 1
        }
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units/unit-1/notes" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/homeworks" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/documents" }.count == 1)
        #expect(model.homeDashboardState.learningUnitCount == 1)
        #expect(model.homeDashboardState.recentNotes.count == 1)

        model.ensureContentForSelectedTabLoaded()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units" }.count == 1)

        model.selectedTab = .notes
        model.ensureContentForSelectedTabLoaded()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units/unit-1/notes" }.count == 1)

        let requestsBeforeProfile = paths.count
        model.selectedTab = .profile
        model.ensureContentForSelectedTabLoaded()
        try await Self.waitUntil { model.aiModelCatalog != nil && !model.isAIModelsLoading }
        #expect(paths.count == requestsBeforeProfile + 2)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/ai/models" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/user/profile" }.count == 1)
        model.ensureContentForSelectedTabLoaded()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/ai/models" }.count == 1)

        model.selectedTab = .notes
        model.selectedLearningSection = .units
        model.ensureContentForSelectedTabLoaded()
        try await Self.waitUntil { !model.isLearningLoading && !model.isHomeworkLoading }
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/learning-units" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/homeworks" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/documents" }.count == 1)

        model.ensureContentForSelectedTabLoaded()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(paths.filter { $0 == "/api/v1/workspaces/ws-1/homeworks" }.count == 1)
    }

    @Test @MainActor func notesOverviewKeepsSuccessfulGroupsWhenOneUnitFails() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            switch request.url?.path ?? "" {
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"unit-1","title":"成功","subject":null,"grade_level":null,"topic":null},{"id":"unit-2","title":"失败","subject":null,"grade_level":null,"topic":null}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/unit-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"note-1","learning_unit_id":"unit-1","version_no":1,"title":"笔记","html_object_key":"h","json_object_key":"j","download_urls":{}}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/unit-2/notes":
                return Self.response(request, status: 500, body: #"{"detail":"worker unavailable"}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        model.loadNotesOverview()
        try await Self.waitUntil { !model.isNotesLoading }

        #expect(model.studyNoteGroups.map(\.learningUnit.id) == ["unit-1"])
        #expect(model.statusMessage == localizedFormat("notes.partial_load", "1", "1"))
    }

    @Test @MainActor func markdownRenderingCachesStableBlocks() async throws {
        clearMarkdownRenderCache()
        let markdown = "# 标题\n\n正文 **加粗**"
        let first = parseMarkdownBlocks(markdown)
        let second = parseMarkdownBlocks(markdown)
        #expect(first.map(\.id) == second.map(\.id))

        let renderer = MarkdownRenderState()
        renderer.load(markdown)
        #expect(renderer.blocks == first)
        #expect(cachedMarkdownInlineTokens("正文 **加粗**") == cachedMarkdownInlineTokens("正文 **加粗**"))

        let flashcardBlocks = parseMarkdownBlocks(
            "What does a **ratio** compare?\n\n1. First step\n2. Use `x`"
        )
        #expect(flashcardBlocks[0].inlineTokens.contains { $0.type == .bold && $0.text == "ratio" })
        #expect(flashcardBlocks[1].type == .ordered)
        #expect(flashcardBlocks[1].level == 1)
        #expect(flashcardBlocks[2].level == 2)
        #expect(flashcardBlocks[2].inlineTokens.contains { $0.type == .code && $0.text == "x" })

        let tableBlocks = parseMarkdownBlocks(
            """
            | Name | Score | Note |
            | :--- | ---: | :---: |
            | Alice | 98 | **Great** |
            | Bob | 87 | A \\| B |
            """
        )
        let tableBlock = try #require(tableBlocks.first)
        #expect(tableBlock.type == .table)
        let table = try #require(tableBlock.table)
        #expect(table.headers == ["Name", "Score", "Note"])
        #expect(table.alignments == [.leading, .trailing, .center])
        #expect(table.rows[0] == ["Alice", "98", "**Great**"])
        #expect(table.rows[1] == ["Bob", "87", "A | B"])

        let longMarkdown = String(repeating: "段落内容\n\n", count: 1_000)
        renderer.load(longMarkdown)
        try await Self.waitUntil { !renderer.blocks.isEmpty }
        #expect(renderer.blocks.first?.id == "block-0")
        #expect(renderer.blocks.first?.inlineTokens.isEmpty == false)
    }

    @Test @MainActor func openClawComposerState_doesNotPublishRootViewModelChanges() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        )
        var rootChangeCount = 0
        let cancellable = model.objectWillChange.sink { rootChangeCount += 1 }

        model.openClawComposerState.text = String(repeating: "a", count: 200)
        model.openClawComposerState.measuredTextHeight = 120

        #expect(model.openClawInput.count == 200)
        #expect(rootChangeCount == 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test @MainActor func openClawMessageState_onlyPublishesActualChanges() {
        let message = OpenClawChatMessage(
            id: "message-1",
            role: .assistant,
            content: "Thinking...",
            status: .sending,
            taskId: "task-1",
            progress: 10,
            events: []
        )
        let state = OpenClawViewState(messages: [message])
        var publishCount = 0
        let cancellable = state.objectWillChange.sink { publishCount += 1 }

        let unchanged = state.updateMessage(id: message.id) { $0.progress = 10 }
        #expect(!unchanged)
        #expect(publishCount == 0)

        let changed = state.updateMessage(id: message.id) { $0.progress = 20 }
        #expect(changed)
        #expect(state.messages.first?.progress == 20)
        #expect(publishCount == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test @MainActor func openClawViewModel_usesExplicitPromptAndLeavesComposerOwnershipToView() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var capturedPrompt: String?
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "POST /api/v1/workspaces/ws-1/ai/chat":
                if let body = Self.requestBodyData(request),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    capturedPrompt = object["prompt"] as? String
                }
                return Self.response(request, status: 201, body: Self.taskJSON)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"id":"task-1","workspace_id":"ws-1","task_type":"chat","status":"succeeded","resource_type":"conversation","resource_id":null,"payload":{},"result":{"answer":"Explicit reply"},"error_message":null,"progress":100,"created_at":"","updated_at":""}"#
                )
            case "GET /api/v1/workspaces/ws-1/tasks/task-1/events":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.openClawComposerState.text = "Local draft remains view-owned"

        #expect(model.startOpenClawChat(prompt: "  Explicit prompt  "))
        #expect(model.openClawComposerState.text == "Local draft remains view-owned")
        try await Self.waitUntil { !model.isOpenClawSending }

        #expect(capturedPrompt == "Explicit prompt")
        let sentUserMessages = model.openClawMessages.filter { $0.role == .user }
        #expect(sentUserMessages.map(\.content).contains("Explicit prompt"))
        #expect(model.openClawMessages.last?.content == "Explicit reply")
    }

    @Test @MainActor func fileImportService_copiesLargeFilesOffTheCallingActor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepatch-import-tests-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.txt")
        let sourceData = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        try sourceData.write(to: sourceURL)

        let outcomes = await FileImportService.shared.importFiles(
            [sourceURL],
            fallbackPrefix: "test",
            cacheDirectory: cache
        )
        let imported = try #require(outcomes.first?.file)
        #expect(imported.url != sourceURL)
        #expect(imported.filename == "source.txt")
        #expect(try Data(contentsOf: imported.url) == sourceData)
    }

    @Test @MainActor func uploadThumbnail_classificationCacheKeyAndImageDownsampling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepatch-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600))
        let sourceImage = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        let imageURL = root.appendingPathComponent("large.png")
        try #require(sourceImage.pngData()).write(to: imageURL)
        let imageFile = LocalUploadFile(url: imageURL, filename: "large.png", mimeType: "image/png")

        #expect(uploadThumbnailKind(for: imageFile, canQuickLookPreview: false) == .image)
        let thumbnail = try #require(downsampleUploadImage(at: imageURL, maxPixelSize: 160))
        #expect(max(thumbnail.size.width * thumbnail.scale, thumbnail.size.height * thumbnail.scale) <= 160)
        #expect(thumbnail.size.width < sourceImage.size.width)

        let firstKey = uploadThumbnailCacheKey(for: imageFile)
        var changedData = try Data(contentsOf: imageURL)
        changedData.append(0)
        try changedData.write(to: imageURL, options: .atomic)
        let secondKey = uploadThumbnailCacheKey(for: imageFile)
        #expect(firstKey != secondKey)

        let pdfURL = root.appendingPathComponent("notes.pdf")
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try pdfRenderer.pdfData { context in
            context.beginPage()
            NSString(string: "NotePatch PDF").draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }.write(to: pdfURL)
        let pdfFile = LocalUploadFile(url: pdfURL, filename: "notes.pdf", mimeType: "application/pdf")
        let unknownFile = LocalUploadFile(url: root.appendingPathComponent("blob.unknown"), filename: "blob.unknown", mimeType: nil)
        #expect(uploadThumbnailKind(for: pdfFile, canQuickLookPreview: true) == .quickLook)
        #expect(uploadThumbnailKind(for: unknownFile, canQuickLookPreview: false) == .unsupported)

        let request = QLThumbnailGenerator.Request(
            fileAt: pdfURL,
            size: CGSize(width: 56, height: 64),
            scale: 2,
            representationTypes: .thumbnail
        )
        let pdfThumbnail = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
        #expect(pdfThumbnail != nil)

        let cache = UploadThumbnailCache.shared
        cache.insert(thumbnail, forKey: uploadThumbnailCacheKey(for: imageFile))
        #expect(cache.image(forKey: uploadThumbnailCacheKey(for: imageFile)) != nil)
        cache.remove(file: imageFile)
        #expect(cache.image(forKey: uploadThumbnailCacheKey(for: imageFile)) == nil)
    }

    @Test @MainActor func documentThumbnail_downloadsOnceDownsamplesAndUsesIsolatedDiskCache() async throws {
        let suiteName = "NotePatchDocumentThumbnailTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notepatch-document-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 1200)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1200))
        }
        let sourceData = try #require(sourceImage.pngData())
        var downloadURLRequests = 0
        var imageRequests = 0
        let networkSession = Self.mockSession { request in
            switch request.url?.path {
            case "/api/v1/workspaces/ws-1/documents/image-1/download-url":
                downloadURLRequests += 1
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"document_id":"image-1","filename":"same.png","mime_type":"image/png","download_url":"https://files.test/image-1"}"#
                )
            case "/image-1":
                imageRequests += 1
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
                return (response, sourceData)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: networkSession,
            tusSession: networkSession,
            cacheDirectory: root,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u-1",
            email: "u@test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        let first = LearningDocumentItem(
            id: "image-1",
            workspaceId: "ws-1",
            originalFilename: "same.png",
            mimeType: "image/png",
            fileType: "image",
            documentKind: "note",
            status: "ready",
            updatedAt: "2026-08-17T12:00:00Z"
        )
        let second = LearningDocumentItem(
            id: "image-2",
            workspaceId: "ws-1",
            originalFilename: "same.png",
            mimeType: "image/png",
            fileType: "image",
            documentKind: "note",
            status: "ready",
            updatedAt: "2026-08-17T12:00:00Z"
        )
        let pdf = LearningDocumentItem(
            id: "pdf-1",
            workspaceId: "ws-1",
            originalFilename: "notes.pdf",
            mimeType: "application/pdf",
            fileType: "pdf",
            documentKind: "note",
            status: "ready"
        )

        #expect(documentSupportsImageThumbnail(first))
        #expect(!documentSupportsImageThumbnail(pdf))
        let firstCacheURL = documentThumbnailCacheURL(
            cacheDirectory: root,
            baseURL: "https://api.test",
            userId: "u-1",
            workspaceId: "ws-1",
            document: first
        )
        let secondCacheURL = documentThumbnailCacheURL(
            cacheDirectory: root,
            baseURL: "https://api.test",
            userId: "u-1",
            workspaceId: "ws-1",
            document: second
        )
        #expect(firstCacheURL != secondCacheURL)

        let firstResult = try #require(await model.generateDocumentThumbnail(for: first, maxPixelSize: 160))
        #expect(max(firstResult.size.width * firstResult.scale, firstResult.size.height * firstResult.scale) <= 160)
        #expect(FileManager.default.fileExists(atPath: firstCacheURL.path))
        let cachedResult = try #require(await model.generateDocumentThumbnail(for: first, maxPixelSize: 160))
        #expect(cachedResult.size == firstResult.size)
        #expect(downloadURLRequests == 1)
        #expect(imageRequests == 1)
    }

    @Test @MainActor func documentThumbnailPipeline_deduplicatesConcurrentConsumers() async throws {
        DocumentThumbnailPipeline.shared.removeAll()
        let key = "thumbnail-dedupe-\(UUID().uuidString)"
        let counter = ThumbnailTestCounter()
        let expected = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemMint.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let load: () async -> UIImage? = {
            await counter.increment()
            try? await Task.sleep(nanoseconds: 80_000_000)
            return Task.isCancelled ? nil : expected
        }

        let first = Task { await DocumentThumbnailPipeline.shared.image(forKey: key, loader: load) }
        let second = Task { await DocumentThumbnailPipeline.shared.image(forKey: key, loader: load) }
        let firstResult = await first.value
        let secondResult = await second.value

        #expect(firstResult != nil)
        #expect(secondResult != nil)
        #expect(await counter.value == 1)
        DocumentThumbnailPipeline.shared.removeAll()
    }

    @Test @MainActor func pendingUpload_previewClassificationAndCacheCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepatch-preview-tests-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = cache.appendingPathComponent("selected.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        let imageFile = LocalUploadFile(url: imageURL, filename: "selected.jpg", mimeType: "image/jpeg")
        #expect(imageFile.previewKind(canQuickLookPreview: false) == .image)

        let pdfURL = cache.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.7".utf8).write(to: pdfURL)
        let pdfFile = LocalUploadFile(url: pdfURL, filename: "notes.pdf", mimeType: "application/pdf")
        #expect(pdfFile.previewKind(canQuickLookPreview: true) == .quickLook)
        #expect(pdfFile.previewKind(canQuickLookPreview: false) == .unsupported)

        let imagePreview = DownloadedPreview(
            url: imageURL,
            mimeType: "image/jpeg",
            filename: "selected.jpg",
            fileSize: 3
        )
        #expect(imagePreview.previewKind(canQuickLookPreview: false) == .image)
        let documentPreview = DownloadedPreview(url: pdfURL, mimeType: "application/pdf")
        #expect(documentPreview.previewKind(canQuickLookPreview: true) == .quickLook)
        #expect(documentPreview.previewKind(canQuickLookPreview: false) == .unsupported)

        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var networkRequestCount = 0
        let session = Self.mockSession { request in
            networkRequestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cache
        )

        model.stageUploadFileForPreview(pdfFile)
        #expect(model.queuedUploadItems.count == 1)
        #expect(model.queuedUploadItems.first?.file.filename == "notes.pdf")
        #expect(model.queuedUploadItems.first?.documentKind == "homework")
        #expect(networkRequestCount == 0)
        let pdfId = try #require(model.queuedUploadItems.first?.id)
        model.removeQueuedUpload(pdfId)
        #expect(model.queuedUploadItems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pdfURL.path))

        let externalURL = root.appendingPathComponent("external.bin")
        try Data([0x00, 0x01]).write(to: externalURL)
        model.stageUploadFileForPreview(LocalUploadFile(url: externalURL, filename: "external.bin", mimeType: nil))
        let externalId = try #require(model.queuedUploadItems.first?.id)
        model.removeQueuedUpload(externalId)
        #expect(FileManager.default.fileExists(atPath: externalURL.path))

        let confirmURL = cache.appendingPathComponent("confirm.pdf")
        try Data("%PDF-1.7".utf8).write(to: confirmURL)
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: "2026-07-10T12:00:00Z",
            userId: "user-1",
            email: "user@example.com",
            fullName: "Test User",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.uploadDocumentKind = "homework"
        model.stageUploadFileForPreview(LocalUploadFile(url: confirmURL, filename: "confirm.pdf", mimeType: "application/pdf"))
        #expect(model.queuedUploadItems.first?.documentKind == "homework")
        model.uploadDocumentKind = "note"
        model.uploadSelectedQueuedFiles()

        for _ in 0..<50 where networkRequestCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        for _ in 0..<50 where model.isBusy {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(networkRequestCount == 1)
        #expect(model.queuedUploadItems.count == 1)
        if case .failed = model.queuedUploadItems[0].state {
            // Expected: the mocked backend rejects the upload session request.
        } else {
            Issue.record("Failed queue items must remain available for retry")
        }
    }

    @Test func tusHelpers_resolveURLAndUploadId() throws {
        let relative = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "abc")
        let absolutePath = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "/files/abc")
        let proxiedPath = try TusUploader.resolveUploadURL(
            endpoint: defaultTUSDBaseURL,
            location: "/files/abc"
        )
        let insecureSameOrigin = try TusUploader.resolveUploadURL(
            endpoint: defaultTUSDBaseURL,
            location: "http://8.137.78.255/files/abc"
        )
        let otherHost = try TusUploader.resolveUploadURL(endpoint: "http://192.168.100.123:1080/files/", location: "http://other.test/upload/xyz")
        #expect(relative == "http://192.168.100.123:1080/files/abc")
        #expect(absolutePath == "http://192.168.100.123:1080/files/abc")
        #expect(proxiedPath == "\(defaultTUSDBaseURL)abc")
        #expect(insecureSameOrigin == "\(defaultTUSDBaseURL)abc")
        #expect(otherHost == "http://other.test/upload/xyz")
        #expect(
            TusUploader.preferredEndpoint(
                configuredEndpoint: defaultTUSDBaseURL,
                serverEndpoint: "http://192.168.100.123:1080/files/"
            ) == "http://192.168.100.123:1080/files/"
        )
        #expect(
            TusUploader.preferredEndpoint(
                configuredEndpoint: "https://stale.example.test/files/",
                serverEndpoint: defaultTUSDBaseURL
            ) == defaultTUSDBaseURL
        )
        #expect(
            TusUploader.preferredEndpoint(
                configuredEndpoint: defaultTUSDBaseURL,
                serverEndpoint: nil
            ) == defaultTUSDBaseURL
        )
        #expect(TusUploader.extractTusUploadId("http://192.168.100.123:1080/files/abc") == "abc")
    }

    @Test @MainActor func uploadQueue_preservesKindsUploadsInOrderAndRemovesSuccesses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotePatchQueueTests-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = cache.appendingPathComponent("first.pdf")
        let secondURL = cache.appendingPathComponent("second.pdf")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        var kinds: [String] = []
        var tusCreateCount = 0
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path == "/api/v1/workspaces/ws-1/documents/upload-session" {
                let body = try #require(Self.requestBodyData(request))
                let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                kinds.append(try #require(object["document_kind"] as? String))
                return Self.response(request, status: 201, body: Self.uploadSessionJSON)
            }
            if request.httpMethod == "POST", request.url?.host == "192.168.100.123", path.hasPrefix("/files") {
                tusCreateCount += 1
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Location": "upload-\(tusCreateCount)", "Tus-Resumable": "1.0.0"]
                )!
                return (response, Data())
            }
            if request.httpMethod == "POST", path == "/api/v1/workspaces/ws-1/documents/complete-upload" {
                return Self.response(request, status: 200, body: Self.completedDocumentJSON)
            }
            if request.httpMethod == "GET", path == "/api/v1/workspaces/ws-1/documents" {
                return Self.response(request, status: 200, body: "[]")
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let suiteName = "NotePatchQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cache
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "http://192.168.100.123:1080/files/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.uploadDocumentKind = "homework"
        model.stageUploadFileForPreview(LocalUploadFile(url: firstURL, filename: "first.pdf", mimeType: "application/pdf"))
        model.uploadDocumentKind = "note"
        model.stageUploadFileForPreview(LocalUploadFile(url: secondURL, filename: "second.pdf", mimeType: "application/pdf"))

        model.uploadSelectedQueuedFiles()
        try await Self.waitUntil(attempts: 500) {
            model.statusMessage == localized("upload.selected_completed") || model.errorMessage != nil
        }

        #expect(kinds == ["homework", "note"])
        #expect(tusCreateCount == 2)
        #expect(model.queuedUploadItems.isEmpty)
        #expect(model.statusMessage == localized("upload.selected_completed"))
    }

    @Test @MainActor func uploadUsesServerTusEndpointAndAcceptsWebhookCompletionAfterConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchUploadRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("recovery.pdf")
        try Data().write(to: fileURL)

        var tusHosts: [String] = []
        var completeCount = 0
        var documentReadCount = 0
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("POST", "/api/v1/workspaces/ws-1/documents/upload-session"):
                return Self.response(request, status: 201, body: Self.uploadSessionJSON)
            case ("POST", let path) where path.hasPrefix("/files"):
                tusHosts.append(request.url?.host ?? "")
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Location": "upload-recovery", "Tus-Resumable": "1.0.0"]
                )!
                return (response, Data())
            case ("POST", "/api/v1/workspaces/ws-1/documents/complete-upload"):
                completeCount += 1
                return Self.response(request, status: 409, body: #"{"detail":"Upload is still being synchronized"}"#)
            case ("GET", "/api/v1/workspaces/ws-1/documents/doc-1"):
                documentReadCount += 1
                return Self.response(
                    request,
                    status: 200,
                    body: Self.completedDocumentJSON.replacingOccurrences(of: "doc-completed", with: "doc-1")
                )
            case ("GET", "/api/v1/workspaces/ws-1/documents"):
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let suiteName = "NotePatchUploadRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: root
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://stale.example.test/files/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u",
            email: "u@test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.stageUploadFileForPreview(
            LocalUploadFile(url: fileURL, filename: "recovery.pdf", mimeType: "application/pdf")
        )

        model.uploadSelectedQueuedFiles()
        try await Self.waitUntil(attempts: 500) {
            model.statusMessage == localized("upload.selected_completed") || model.errorMessage != nil
        }

        #expect(tusHosts == ["192.168.100.123"])
        #expect(completeCount == 1)
        #expect(documentReadCount == 1)
        #expect(model.queuedUploadItems.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func liveUploadSmokeTestWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NOTEPATCH_LIVE_UPLOAD"] == "1" else { return }
        let settings = SettingsStore()
        let activeSession = try #require(settings.loadSession())
        let workspaceId = try #require(activeSession.selectedWorkspaceId)
        let client = LearningBackendClient(
            baseURL: activeSession.baseURL,
            accessToken: activeSession.accessToken,
            refreshToken: activeSession.refreshToken
        )
        let staleSmokeDocuments = try await client.listDocuments(
            workspaceId: workspaceId,
            pageSize: 100,
            documentKind: "other"
        ).filter { $0.originalFilename.hasPrefix("notepatch-upload-smoke-") }
        for document in staleSmokeDocuments {
            _ = try? await client.deleteDocument(workspaceId: workspaceId, documentId: document.id)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchLiveUploadSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let filename = "notepatch-upload-smoke-\(UUID().uuidString).txt"
        let fileURL = root.appendingPathComponent(filename)
        let fileData = Data("NotePatch live upload smoke test".utf8)
        try fileData.write(to: fileURL, options: .atomic)

        let uploadSession = try await client.createUploadSession(
            workspaceId: workspaceId,
            filename: filename,
            mimeType: "text/plain",
            fileSize: Int64(fileData.count),
            documentKind: "other"
        )
        var completedDocument: LearningDocumentItem?
        do {
            let endpoint = TusUploader.preferredEndpoint(
                configuredEndpoint: activeSession.tusBaseURL,
                serverEndpoint: uploadSession.tusEndpoint
            )
            let tusResult = try await TusUploader().upload(
                fileURL: fileURL,
                endpoint: endpoint,
                metadataHeader: uploadSession.tusMetadataHeader
            ) { _, _ in }
            for attempt in 0..<20 {
                do {
                    completedDocument = try await client.completeUpload(
                        workspaceId: workspaceId,
                        uploadSessionId: uploadSession.uploadSession.id,
                        tusUploadURL: tusResult.uploadURL,
                        tusUploadId: tusResult.uploadId,
                        fileSize: Int64(fileData.count),
                        mimeType: "text/plain"
                    )
                    break
                } catch let error as LearningBackendError where error.statusCode == 409 {
                    if let document = try? await client.getDocument(
                        workspaceId: workspaceId,
                        documentId: uploadSession.document.id
                    ), ["uploaded", "processing", "ready", "scanning"].contains(document.status) {
                        completedDocument = document
                        break
                    }
                    try await Task.sleep(nanoseconds: UInt64(min(3, 1 + attempt / 5)) * 1_000_000_000)
                }
            }
            let document = try #require(completedDocument)
            #expect(document.id == uploadSession.document.id)
            #expect(["uploaded", "processing", "ready", "scanning"].contains(document.status))
        } catch {
            _ = try? await client.deleteDocument(workspaceId: workspaceId, documentId: uploadSession.document.id)
            throw error
        }
        _ = try await client.deleteDocument(workspaceId: workspaceId, documentId: uploadSession.document.id)
    }

    @Test func decodeTokenWorkspaceUploadArtifactAndTaskJSON() throws {
        let token = try JSONDecoder.notepatch.decode(
            TokenResponse.self,
            from: Data(
                """
                {
                  "access_token": "access",
                  "refresh_token": "refresh",
                  "token_type": "bearer",
                  "expires_at": "2026-07-09T12:00:00Z",
                  "user": {
                    "id": "user-1",
                    "email": "alice@example.com",
                    "full_name": "Alice",
                    "is_active": true,
                    "created_at": "2026-07-09T11:00:00Z"
                  }
                }
                """.utf8
            )
        )
        #expect(token.accessToken == "access")
        #expect(token.user.fullName == "Alice")

        let workspace = try JSONDecoder.notepatch.decode(
            WorkspaceItem.self,
            from: Data(
                """
                {
                  "id": "ws-1",
                  "name": "My Workspace",
                  "owner_user_id": "user-1",
                  "created_at": "2026-07-09T10:00:00Z",
                  "updated_at": "2026-07-09T10:00:00Z"
                }
                """.utf8
            )
        )
        #expect(workspace.type == "personal")

        let uploadSession = try JSONDecoder.notepatch.decode(UploadSessionResponse.self, from: Data(Self.uploadSessionJSON.utf8))
        #expect(uploadSession.document.id == "doc-1")
        #expect(uploadSession.uploadSession.id == "upload-1")
        #expect(uploadSession.tusMetadataHeader == "workspace_id d3MtMQ==,document_id ZG9jLTE=")
        #expect(uploadSession.tusMetadata["document_id"] == "doc-1")

        let artifacts = try JSONDecoder.notepatch.decode(
            [DocumentArtifactItem].self,
            from: Data(
                """
                [
                  {
                    "id": "artifact-1",
                    "workspace_id": "ws-1",
                    "document_id": "doc-1",
                    "artifact_type": "ocr_json",
                    "bucket": "notepatch",
                    "object_key": "workspaces/ws-1/documents/doc-1/artifacts/ocr.json",
                    "mime_type": "application/json",
                    "file_size": 12,
                    "metadata": {"processor":"doctr"},
                    "created_at": "2026-07-09T10:01:00Z"
                  }
                ]
                """.utf8
            )
        )
        #expect(artifacts.first?.metadataProcessor == "doctr")

        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(
                """
                {
                  "id": "task-1",
                  "workspace_id": "ws-1",
                  "task_type": "openclaw",
                  "status": "succeeded",
                  "resource_type": "document",
                  "resource_id": "doc-1",
                  "payload": {"conversation_id":"conversation-1"},
                  "result": {"runner":"mock","answer":"ok"},
                  "error_message": null,
                  "progress": 100,
                  "created_at": "2026-07-09T10:00:00Z",
                  "updated_at": "2026-07-09T10:00:30Z",
                  "started_at": "2026-07-09T10:00:01Z",
                  "finished_at": "2026-07-09T10:00:30Z"
                }
                """.utf8
            )
        )
        #expect(task.progress == 100)
        #expect(task.payload?.objectStringValue(for: "conversation_id") == "conversation-1")
        #expect(task.result == .object(["runner": .string("mock"), "answer": .string("ok")]))
        #expect(formatOpenClawTaskResult(task.resultText) == "ok")

        let deletion = try JSONDecoder.notepatch.decode(
            DocumentDeleteResponse.self,
            from: Data(#"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#.utf8)
        )
        #expect(deletion.purgeTaskId == "purge-1")

        let cancellingTask = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"task-cancel","workspace_id":"ws-1","status":"running","progress":20,"cancel_requested_at":"2026-07-11T00:00:00Z"}"#.utf8)
        )
        #expect(cancellingTask.cancelRequestedAt != nil)

        let documentDownload = try JSONDecoder.notepatch.decode(
            DownloadURLResponse.self,
            from: Data(#"{"download_url":"https://download.test/original","expires_in":900}"#.utf8)
        )
        #expect(documentDownload.downloadURL == "https://download.test/original")
        #expect(documentDownload.expiresSeconds == 900)

        let artifactDownload = try JSONDecoder.notepatch.decode(
            ArtifactDownloadURLResponse.self,
            from: Data(
                """
                {
                  "artifact_id": "artifact-1",
                  "document_id": "doc-1",
                  "artifact_type": "ocr_markdown",
                  "filename": "ocr.md",
                  "mime_type": "text/markdown",
                  "expires_in": 900,
                  "download_url": "https://download.test/ocr.md"
                }
                """.utf8
            )
        )
        #expect(artifactDownload.filename == "ocr.md")
        #expect(artifactDownload.expiresSeconds == 900)

        let ocrArtifacts = try JSONDecoder.notepatch.decode(
            OcrArtifactsResponse.self,
            from: Data(
                """
                {
                  "document_id": "doc-1",
                  "artifacts": [
                    {
                      "id": "ocr-md",
                      "artifact_type": "ocr_markdown",
                      "mime_type": "text/markdown",
                      "file_size": 99,
                      "created_at": "2026-07-09T10:02:00Z",
                      "download_url": "https://download.test/ocr.md"
                    }
                  ]
                }
                """.utf8
            )
        )
        #expect(ocrArtifacts.artifacts.first?.artifactType == "ocr_markdown")
        #expect(ocrArtifacts.artifacts.first?.downloadURL == "https://download.test/ocr.md")
    }

    @Test @MainActor func parseErrorMessage_handlesCommonDetailShapes() {
        #expect(LearningBackendClient.parseErrorMessage(#"{"detail":"Invalid token"}"#, status: 401) == "Invalid token")
        #expect(
            LearningBackendClient.parseErrorMessage(#"{"detail":[{"msg":"Field required"},{"msg":"Too short"}]}"#, status: 422)
            == "Field required；Too short"
        )
        #expect(LearningBackendClient.parseErrorMessage("", status: 409) == localized("error.http.conflict"))
        #expect(LearningBackendClient.parseErrorMessage("", status: 410) == localized("error.http.gone"))
        #expect(
            LearningBackendClient.parseErrorMessage(
                #"{"code":"profile_version_mismatch","message":"Profile changed elsewhere"}"#,
                status: 412
            ) == "Profile changed elsewhere"
        )
    }

    @Test func openClawAndMarkdownHelpers_matchAndroidBehavior() {
        #expect(formatOpenClawTaskResult(#"{"runner":"mock","answer":"hello"}"#) == "hello")
        let openClawResult = formatOpenClawTaskResult(
                """
                {
                  "runner": "gateway",
                  "output_key": "workspaces/ws-1/openclaw/output.md",
                  "output_keys": [
                    "workspaces/ws-1/openclaw/a.md",
                    "workspaces/ws-1/openclaw/b.json"
                  ],
                  "gateway_container": "openclaw-user-1",
                  "user_workspace_dir": "/srv/openclaw/users/user-1"
                }
                """
            )
        #expect(
            openClawResult
            ==
            """
            runner: gateway
            output_key: workspaces/ws-1/openclaw/output.md
            output_keys: workspaces/ws-1/openclaw/a.md, workspaces/ws-1/openclaw/b.json
            """
        )
        #expect(!openClawResult.contains("gateway_container"))
        #expect(!openClawResult.contains("user_workspace_dir"))
        #expect(formatOpenClawTaskResult("plain text") == "plain text")
        #expect(formatOpenClawTaskResult(nil) == "")

        let blocks = parseMarkdownBlocks(
            """
            # Title

            Paragraph with **bold** and `code`.
            - one
            1. two
            > quote
            ```
            val x = 1
            ```
            """
        )
        #expect(blocks[0].type == .heading)
        #expect(blocks[0].level == 1)
        #expect(blocks[2].type == .bullet)
        #expect(blocks[2].text == "one")
        #expect(blocks[3].type == .ordered)
        #expect(blocks[3].level == 1)
        #expect(blocks[3].text == "two")
        #expect(blocks[5].type == .code)
        #expect(blocks[5].text == "val x = 1")

        let tokens = parseMarkdownInline("A **bold** `code` [link](https://example.com)")
        #expect(tokens[1].type == .bold)
        #expect(tokens[1].text == "bold")
        #expect(tokens[3].type == .code)
        #expect(tokens[5].type == .link)
        #expect(tokens[5].text == "link (https://example.com)")
    }

    @Test func authedRequest_refreshesTokenOnUnauthorized() async throws {
        let session = Self.mockSession { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired":
                return Self.response(request, status: 401, body: #"{"detail":"expired"}"#)
            case ("POST", "/api/v1/auth/refresh"):
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "access_token": "new-access",
                      "refresh_token": "new-refresh",
                      "token_type": "bearer",
                      "expires_at": "2026-07-09T12:00:00Z",
                      "user": {
                        "id": "user-1",
                        "email": "alice@example.com",
                        "full_name": "Alice",
                        "is_active": true,
                        "created_at": "2026-07-09T11:00:00Z"
                      }
                    }
                    """
                )
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "id": "user-1",
                      "email": "alice@example.com",
                      "full_name": "Alice",
                      "is_active": true,
                      "created_at": "2026-07-09T11:00:00Z"
                    }
                    """
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }

        var refreshed: TokenResponse?
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "expired",
            refreshToken: "refresh",
            session: session
        ) { token, _ in
            refreshed = token
        }

        let user = try await client.me()
        #expect(user.email == "alice@example.com")
        #expect(refreshed?.accessToken == "new-access")
    }

    @Test @MainActor func concurrentUnauthorizedRequests_shareOneTokenRefresh() async throws {
        var refreshRequestCount = 0
        var retriedRequestCount = 0
        let session = Self.mockSession { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer expired":
                return Self.response(request, status: 401, body: #"{"detail":"expired"}"#)
            case ("POST", "/api/v1/auth/refresh"):
                refreshRequestCount += 1
                Thread.sleep(forTimeInterval: 0.05)
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "access_token": "new-access",
                      "refresh_token": "new-refresh",
                      "token_type": "bearer",
                      "expires_at": "2026-07-09T12:00:00Z",
                      "user": {
                        "id": "user-1",
                        "email": "alice@example.com",
                        "full_name": "Alice",
                        "is_active": true,
                        "created_at": "2026-07-09T11:00:00Z"
                      }
                    }
                    """
                )
            case ("GET", "/api/v1/auth/me") where request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access":
                retriedRequestCount += 1
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "id": "user-1",
                      "email": "alice@example.com",
                      "full_name": "Alice",
                      "is_active": true,
                      "created_at": "2026-07-09T11:00:00Z"
                    }
                    """
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }

        let firstClient = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "expired",
            refreshToken: "refresh",
            session: session
        )
        let secondClient = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "expired",
            refreshToken: "refresh",
            session: session
        )

        async let firstUser = firstClient.me()
        async let secondUser = secondClient.me()
        let (first, second) = try await (firstUser, secondUser)

        #expect(first.email == "alice@example.com")
        #expect(second.email == "alice@example.com")
        #expect(refreshRequestCount == 1)
        #expect(retriedRequestCount == 2)
    }

    @Test func staleRefreshFailure_doesNotClearNewerSession() {
        let staleRefreshFailure = LearningBackendError(
            "refresh token expired",
            statusCode: 401,
            shouldClearSession: true,
            refreshTokenAttempt: "old-refresh"
        )

        #expect(!shouldClearPersistedSession(for: staleRefreshFailure, currentRefreshToken: "new-refresh"))
        #expect(shouldClearPersistedSession(for: staleRefreshFailure, currentRefreshToken: "old-refresh"))
        #expect(
            shouldClearPersistedSession(
                for: LearningBackendError("unauthorized", statusCode: 401, shouldClearSession: true),
                currentRefreshToken: "new-refresh"
            )
        )
        #expect(
            !shouldClearPersistedSession(
                for: LearningBackendError("forbidden", statusCode: 403),
                currentRefreshToken: "new-refresh"
            )
        )
    }

    @Test func createUploadSession_sendsExpectedRequestShape() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.uploadSessionJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        let upload = try await client.createUploadSession(
            workspaceId: "ws 1",
            filename: "exam.pdf",
            mimeType: "application/pdf",
            fileSize: 12345,
            documentKind: "homework",
            learningMetadata: LearningMetadata(learningUnitTitle: "分数", subject: "数学", gradeLevel: "七年级", topic: "比例")
        )

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.absoluteString == "https://api.test/api/v1/workspaces/ws%201/documents/upload-session")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        #expect(capturedBody?["filename"] as? String == "exam.pdf")
        #expect(capturedBody?["document_kind"] as? String == "homework")
        let metadata = capturedBody?["metadata"] as? [String: String]
        #expect(metadata?["learning_unit_title"] == "分数")
        #expect(metadata?["subject"] == "数学")
        #expect(upload.document.originalFilename == "exam.pdf")
    }

    @Test func processDocument_sendsForceReprocessOption() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let task = try await client.processDocument(workspaceId: "ws-1", documentId: "doc-1", forceReprocess: true)

        let options = capturedBody?["options"] as? [String: Any]
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/api/v1/workspaces/ws-1/documents/doc-1/process")
        #expect(options?["force_reprocess"] as? Bool == true)
        #expect(task.id == "task-1")
    }

    @Test func openClawChat_usesChatEndpointAndPromptPayload() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let task = try await client.openClawChat(
            workspaceId: "ws-1",
            prompt: "总结本周错题",
            conversationId: "conversation-1",
            input: [
                "attachments": [[
                    "document_id": "document-1",
                    "filename": "question.png",
                    "mime_type": "image/png",
                    "file_type": "image"
                ]]
            ]
        )

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/api/v1/workspaces/ws-1/ai/chat")
        #expect(capturedBody?["prompt"] as? String == "总结本周错题")
        #expect(capturedBody?["conversation_id"] as? String == "conversation-1")
        let input = capturedBody?["input"] as? [String: Any]
        let attachments = input?["attachments"] as? [[String: Any]]
        #expect(attachments?.count == 1)
        #expect(attachments?.first?["document_id"] as? String == "document-1")
        #expect(attachments?.first?["filename"] as? String == "question.png")
        #expect(attachments?.first?["mime_type"] as? String == "image/png")
        #expect(capturedBody?["options"] as? [String: Any] != nil)
        #expect(task.id == "task-1")
    }

    @Test func openClawChat_sendsThinkingOptions() async throws {
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(request, status: 200, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        _ = try await client.openClawChat(
            workspaceId: "ws-1",
            prompt: "解释这道题",
            conversationId: nil,
            input: [:],
            options: ["thinking": ["enabled": true, "effort": "adaptive"]]
        )

        let options = capturedBody?["options"] as? [String: Any]
        let thinking = options?["thinking"] as? [String: Any]
        #expect(thinking?["enabled"] as? Bool == true)
        #expect(thinking?["effort"] as? String == "adaptive")
    }

    @Test func cancelTask_usesDocumentedEndpoint() async throws {
        var capturedRequest: URLRequest?
        let session = Self.mockSession { request in
            capturedRequest = request
            return Self.response(request, status: 202, body: Self.taskJSON)
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let task = try await client.cancelTask(workspaceId: "ws-1", taskId: "task-1")

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/api/v1/workspaces/ws-1/tasks/task-1/cancel")
        #expect(task.id == "task-1")
    }

    @Test @MainActor func reviseChatMessage_usesRevisionEndpointAndInheritsAttachments() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        let session = Self.mockSession { request in
            capturedRequest = request
            if let body = Self.requestBodyData(request) {
                capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            return Self.response(
                request,
                status: 202,
                body: #"{"code":"ok","message":"Chat message revised","data":{"id":"task-1","workspace_id":"ws-1","task_type":"openclaw_agent_run","status":"queued","payload":{"conversation_id":"c-1","revised_message_id":"m-1"},"progress":0}}"#
            )
        }
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        let task = try await client.reviseChatMessage(
            workspaceId: "ws/1",
            conversationId: "conversation/1",
            messageId: "message/1",
            prompt: "修改后的问题",
            options: ["thinking": ["enabled": true, "effort": "adaptive"]]
        )

        #expect(capturedRequest?.httpMethod == "POST")
        let encodedPath = capturedRequest?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
        }
        #expect(encodedPath == "/api/v1/workspaces/ws%2F1/ai/conversations/conversation%2F1/messages/message%2F1/revisions")
        #expect(capturedBody?["prompt"] as? String == "修改后的问题")
        #expect(capturedBody?["input"] is NSNull)
        let options = capturedBody?["options"] as? [String: Any]
        let thinking = options?["thinking"] as? [String: Any]
        #expect(thinking?["enabled"] as? Bool == true)
        #expect(task.id == "task-1")
    }

    @Test @MainActor func userProfileRequestsUseETagIdempotencyAndMultipart() async throws {
        var requests: [URLRequest] = []
        let profileOne = #"{"code":"ok","message":"Profile loaded","data":{"id":"u-1","name":"Alice","email":"alice@example.com","avatar_url":null,"profile_version":3,"reauthentication_required":false}}"#
        let profileTwo = #"{"code":"ok","message":"Profile saved","data":{"id":"u-1","name":"Alice Chen","email":"alice@example.com","avatar_url":"/api/v1/user/avatar/content?v=2","profile_version":4,"reauthentication_required":false}}"#
        let session = Self.mockSession { request in
            requests.append(request)
            let body = request.httpMethod == "GET" ? profileOne : profileTwo
            let etag = request.httpMethod == "GET" ? "\"profile-3\"" : "\"profile-4\""
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: request.httpMethod == "GET" ? 200 : 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "ETag": etag]
            )!
            return (response, Data(body.utf8))
        }
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        let loaded = try await client.getUserProfile()
        let updated = try await client.updateUserProfile(
            etag: loaded.etag,
            idempotencyKey: "profile-key",
            fields: ["name": "Alice Chen"]
        )
        _ = try await client.uploadUserAvatar(
            data: Data([0xff, 0xd8, 0xff, 0xd9]),
            mimeType: "image/jpeg",
            filename: "avatar.jpg",
            etag: updated.etag,
            idempotencyKey: "avatar-key"
        )

        #expect(loaded.etag == "\"profile-3\"")
        #expect(updated.profile.name == "Alice Chen")
        #expect(requests.count == 3)
        #expect(requests[1].value(forHTTPHeaderField: "If-Match") == "\"profile-3\"")
        #expect(requests[1].value(forHTTPHeaderField: "Idempotency-Key") == "profile-key")
        #expect(requests[2].value(forHTTPHeaderField: "If-Match") == "\"profile-4\"")
        #expect(requests[2].value(forHTTPHeaderField: "Idempotency-Key") == "avatar-key")
        #expect(requests[2].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let multipart = try #require(Self.requestBodyData(requests[2]))
        #expect(String(data: multipart, encoding: .isoLatin1)?.contains("name=\"file\"; filename=\"avatar.jpg\"") == true)
    }

    @Test @MainActor func profileValidationRequiresValidEmailAndPasswordForEmailChanges() {
        let model = NotePatchViewModel()
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u-1",
            email: "alice@example.com",
            fullName: "Alice",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.userProfileState.apply(UserProfileSnapshot(
            profile: UserProfile(
                id: "u-1",
                name: "Alice",
                email: "alice@example.com",
                avatarURL: nil,
                profileVersion: 1,
                reauthenticationRequired: false
            ),
            etag: "\"profile-1\""
        ))

        model.userProfileState.emailDraft = "not-an-email"
        model.saveUserProfile()
        #expect(model.errorMessage == localized("profile.validation.email_invalid"))

        model.userProfileState.emailDraft = "new@example.com"
        model.userProfileState.currentPassword = ""
        model.saveUserProfile()
        #expect(model.errorMessage == localized("profile.validation.password_required"))
    }

    @Test @MainActor func avatarRetryReusesIdempotencyKeyForSamePreparedImage() async throws {
        let suiteName = "NotePatchAvatarRetryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var uploadKeys: [String] = []
        let responseBody = #"{"code":"ok","message":"Avatar saved","data":{"id":"u-1","name":"Alice","email":"alice@example.com","avatar_url":"/api/v1/user/avatar/content?v=2","profile_version":2,"reauthentication_required":false}}"#
        let session = Self.mockSession { request in
            uploadKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            if uploadKeys.count == 1 {
                return Self.response(request, status: 503, body: #"{"code":"storage_unavailable","message":"Storage unavailable"}"#)
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "ETag": "\"profile-2\""]
            )!
            return (response, Data(responseBody.utf8))
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchAvatarRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let file = try writeImageToUploadCache(image, cacheDirectory: root)
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: root
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u-1",
            email: "alice@example.com",
            fullName: "Alice",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.userProfileState.apply(UserProfileSnapshot(
            profile: UserProfile(
                id: "u-1",
                name: "Alice",
                email: "alice@example.com",
                avatarURL: nil,
                profileVersion: 1,
                reauthenticationRequired: false
            ),
            etag: "\"profile-1\""
        ))

        model.uploadUserAvatar(file)
        try await Self.waitUntil { !model.userProfileState.isAvatarUploading }
        #expect(model.userProfileState.hasPendingAvatarRetry)
        model.retryPendingAvatarUpload()
        try await Self.waitUntil { !model.userProfileState.isAvatarUploading }

        #expect(uploadKeys.count == 2)
        #expect(uploadKeys[0] == uploadKeys[1])
        #expect(!model.userProfileState.hasPendingAvatarRetry)
    }

    @Test @MainActor func profileConflictReloadsLatestAndPreservesDraft() async throws {
        let suiteName = "NotePatchProfileConflictTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            if request.httpMethod == "PUT" {
                return Self.response(
                    request,
                    status: 412,
                    body: #"{"code":"profile_version_mismatch","message":"Profile changed elsewhere"}"#
                )
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "ETag": "\"profile-2\""]
            )!
            return (
                response,
                Data(#"{"code":"ok","message":"Profile loaded","data":{"id":"u-1","name":"Server Name","email":"alice@example.com","avatar_url":null,"profile_version":2,"reauthentication_required":false}}"#.utf8)
            )
        }
        let model = Self.profileModelForTests(defaults: defaults, session: session, service: suiteName)
        model.userProfileState.nameDraft = "Local Name"
        model.saveUserProfile()
        try await Self.waitUntil { !model.userProfileState.isSaving }

        #expect(model.userProfileState.hasConflict)
        #expect(model.userProfileState.snapshot?.etag == "\"profile-2\"")
        #expect(model.userProfileState.snapshot?.profile.name == "Server Name")
        #expect(model.userProfileState.nameDraft == "Local Name")
    }

    @Test @MainActor func emailProfileUpdateClearsTokensWhenReauthenticationIsRequired() async throws {
        let suiteName = "NotePatchProfileReauthenticationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var body: [String: Any]?
        let session = Self.mockSession { request in
            if let data = Self.requestBodyData(request) {
                body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "ETag": "\"profile-2\""]
            )!
            return (
                response,
                Data(#"{"code":"ok","message":"Profile saved","data":{"id":"u-1","name":"Alice","email":"new@example.com","avatar_url":null,"profile_version":2,"reauthentication_required":true}}"#.utf8)
            )
        }
        let model = Self.profileModelForTests(defaults: defaults, session: session, service: suiteName)
        model.userProfileState.emailDraft = "new@example.com"
        model.userProfileState.currentPassword = "secret"
        model.saveUserProfile()
        try await Self.waitUntil { model.session == nil }

        #expect(body?["email"] as? String == "new@example.com")
        #expect(body?["current_password"] as? String == "secret")
        #expect(model.statusMessage == localized("profile.reauthentication_required"))
        #expect(
            SettingsStore(
                defaults: defaults,
                keychain: KeychainStore(service: suiteName)
            ).loadSession() == nil
        )
    }

    @Test func taskEventItem_preservesStructuredDataForStreaming() throws {
        let json = #"{"id":"event-1","workspace_id":"ws-1","task_id":"task-1","sequence_no":3,"event_type":"chat_answer_delta","level":"info","message":"chunk","progress":null,"data":{"stream":"answer","delta":"你好","chunk_index":1,"attempt":1,"characters":2},"created_at":""}"#
        let event = try JSONDecoder.notepatch.decode(TaskEventItem.self, from: Data(json.utf8))

        #expect(event.eventType == "chat_answer_delta")
        #expect(event.data?.objectStringValue(for: "stream") == "answer")
        #expect(event.data?.objectStringValue(for: "delta") == "你好")
        #expect(event.dataText != nil)
    }

    @Test @MainActor func chatStreamReducer_appendsDeltasAndHandlesControlEvents() {
        func event(_ type: String, _ sequence: Int, delta: String? = nil, stream: String? = nil) -> TaskEventItem {
            var data: [String: JSONValue] = [:]
            if let delta { data["delta"] = .string(delta) }
            if let stream { data["stream"] = .string(stream) }
            return TaskEventItem(
                id: "event-\(sequence)",
                workspaceId: "ws-1",
                taskId: "task-1",
                sequenceNo: sequence,
                eventType: type,
                level: "info",
                message: "",
                progress: nil,
                data: data.isEmpty ? nil : .object(data),
                dataText: nil,
                createdAt: ""
            )
        }

        let events = [
            event("chat_stream_started", 1),
            event("chat_reasoning_delta", 2, delta: "先审题"),
            event("chat_answer_delta", 3, delta: "答案是"),
            event("chat_answer_delta", 4, delta: " 42"),
            event("chat_stream_started", 5),
            event("chat_answer_delta", 6, delta: "重新回答"),
            event("chat_stream_truncated", 7),
            event("chat_reasoning_unavailable", 8)
        ]

        let state = NotePatchViewModel.reduceChatStreamEvents(events)

        #expect(state.answer == "重新回答")
        #expect(state.reasoning == "")
        #expect(state.truncated)
        #expect(state.reasoningUnavailable)
    }

    @Test @MainActor func chatStreamReducer_usesDeclaredStreamAndDoesNotExposeReasoningAsAnswer() {
        func event(_ type: String, _ sequence: Int, stream: String, delta: String) -> TaskEventItem {
            TaskEventItem(
                id: "event-\(sequence)",
                workspaceId: "ws-1",
                taskId: "task-1",
                sequenceNo: sequence,
                eventType: type,
                level: "info",
                message: "",
                progress: nil,
                data: .object(["stream": .string(stream), "delta": .string(delta)]),
                dataText: nil,
                createdAt: ""
            )
        }

        let state = NotePatchViewModel.reduceChatStreamEvents([
            event("chat_answer_delta", 1, stream: "reasoning", delta: "正在整理上下文"),
            event("chat_reasoning_delta", 2, stream: "answer", delta: "这是最终回答。"),
            TaskEventItem(
                id: "event-3",
                workspaceId: "ws-1",
                taskId: "task-1",
                sequenceNo: 3,
                eventType: "chat_reasoning_unavailable",
                level: "info",
                message: "",
                progress: nil,
                data: nil,
                dataText: nil,
                createdAt: ""
            )
        ])

        #expect(state.answer == "这是最终回答。")
        #expect(state.reasoning == "正在整理上下文")
        #expect(!state.reasoningUnavailable)
    }

    @Test @MainActor func chatStreamReducer_allowsAnswerWithoutAnyReasoningEvents() {
        let state = NotePatchViewModel.reduceChatStreamEvents([
            TaskEventItem(
                id: "event-1",
                workspaceId: "ws-1",
                taskId: "task-1",
                sequenceNo: 1,
                eventType: "chat_answer_delta",
                level: "info",
                message: "",
                progress: nil,
                data: .object(["stream": .string("answer"), "delta": .string("直接回答")]),
                dataText: nil,
                createdAt: ""
            )
        ])

        #expect(state.answer == "直接回答")
        #expect(state.reasoning.isEmpty)
        #expect(!state.reasoningUnavailable)
    }

    @Test func openClawResult_preservesAuthoritativeAnswerWithoutTagGuessing() {
        let answer = "<think>这是回答中需要原样展示的文本</think>"
        #expect(formatOpenClawTaskResult(answer) == answer)
        #expect(formatOpenClawTaskResult(#"{"answer":"<analysis>原样内容</analysis>"}"#) == "<analysis>原样内容</analysis>")
    }

    @Test @MainActor func openClawAttachmentUploadFailure_keepsComposerDraft() async throws {
        let suiteName = "NotePatchChatAttachmentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            #expect(request.url?.path == "/api/v1/workspaces/ws-1/documents/upload-session")
            return Self.response(request, status: 500, body: #"{"detail":"storage unavailable"}"#)
        }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchChatAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let imageURL = cacheDirectory.appendingPathComponent("question.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try #require(image.pngData()).write(to: imageURL)
        let file = LocalUploadFile(url: imageURL, filename: "question.png", mimeType: "image/png")

        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cacheDirectory,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: "x",
            userId: "user-1",
            email: "user@example.test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.openClawComposerState.text = "分析图片"
        model.openClawComposerState.attachments = [file]

        #expect(model.startOpenClawChat(prompt: model.openClawComposerState.text, attachments: [file]))
        try await Self.waitUntil { !model.isOpenClawSending }

        #expect(model.openClawComposerState.text == "分析图片")
        #expect(model.openClawComposerState.attachments == [file])
        #expect(model.openClawMessages.count == 1)
        #expect(model.errorMessage?.contains("storage unavailable") == true)
    }


    @Test func createUploadSession_includesSaveToDocumentsForChatAttachment() async throws {
        var capturedBodies: [[String: Any]] = []
        let session = Self.mockSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/workspaces/ws-1/documents/upload-session")
            if let body = Self.requestBodyData(request) {
                let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                if let object { capturedBodies.append(object) }
            }
            return Self.response(request, status: 200, body: Self.uploadSessionJSON)
        }
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        _ = try await client.createUploadSession(
            workspaceId: "ws-1",
            filename: "question.png",
            mimeType: "image/png",
            fileSize: 1024,
            documentKind: "chat_attachment",
            learningMetadata: nil,
            saveToDocuments: false
        )
        _ = try await client.createUploadSession(
            workspaceId: "ws-1",
            filename: "note.pdf",
            mimeType: "application/pdf",
            fileSize: 2048,
            documentKind: "note",
            learningMetadata: nil,
            saveToDocuments: nil
        )

        #expect(capturedBodies.count == 2)
        #expect(capturedBodies.first?["document_kind"] as? String == "chat_attachment")
        #expect(capturedBodies.first?["save_to_documents"] as? Bool == false)
        #expect(capturedBodies.last?["document_kind"] as? String == "note")
        #expect(capturedBodies.last?["save_to_documents"] == nil)
    }

    @Test func artifactAndOcrRequests_useDocumentScopedEndpoints() async throws {
        var paths: [String] = []
        let session = Self.mockSession { request in
            paths.append(request.url?.absoluteString ?? "")
            switch request.url?.path ?? "" {
            case "/api/v1/workspaces/ws-1/documents/doc-1/artifacts/artifact-1/download-url":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "artifact_id": "artifact-1",
                      "document_id": "doc-1",
                      "artifact_type": "ocr_text",
                      "filename": "ocr.txt",
                      "mime_type": "text/plain",
                      "expires_seconds": 600,
                      "download_url": "https://download.test/ocr.txt"
                    }
                    """
                )
            case "/api/v1/workspaces/ws-1/documents/doc-1/ocr":
                return Self.response(
                    request,
                    status: 200,
                    body:
                    """
                    {
                      "document_id": "doc-1",
                      "artifacts": [
                        {
                          "id": "ocr-text",
                          "artifact_type": "ocr_text",
                          "mime_type": "text/plain",
                          "file_size": 10,
                          "created_at": "2026-07-09T10:03:00Z",
                          "download_url": "https://download.test/ocr.txt"
                        }
                      ]
                    }
                    """
                )
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }

        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )
        let artifact = try await client.getArtifactDownloadURL(workspaceId: "ws-1", documentId: "doc-1", artifactId: "artifact-1")
        let ocr = try await client.getOcrArtifacts(workspaceId: "ws-1", documentId: "doc-1", includeDownloadURL: true)

        #expect(artifact.downloadURL == "https://download.test/ocr.txt")
        #expect(ocr.artifacts.first?.downloadURL == "https://download.test/ocr.txt")
        #expect(paths.contains("https://api.test/api/v1/workspaces/ws-1/documents/doc-1/ocr?include_download_url=true"))
    }

    @Test func aiHistoryConversationAndLearningRequests_useDocumentedPaths() async throws {
        var requests: [URLRequest] = []
        let session = Self.mockSession { request in
            requests.append(request)
            switch request.url?.path ?? "" {
            case "/api/v1/auth/preferences":
                return Self.response(request, status: 200, body: #"{"ai_history_enabled":false}"#)
            case "/api/v1/workspaces/ws-1/ai/conversations":
                if request.httpMethod == "GET" {
                    return Self.response(request, status: 200, body: #"{"items":[{"id":"c-1","workspace_id":"ws-1","title":"复习","created_at":"","updated_at":""}],"page":1,"page_size":20,"total":1}"#)
                }
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "/api/v1/workspaces/ws-1/ai/conversations/c-1/messages":
                return Self.response(request, status: 200, body: #"{"items":[{"id":"m-1","conversation_id":"c-1","role":"assistant","content":"完成","status":"succeeded","model_id":"openai/gpt-4.1-mini","created_at":"","attachments":[{"document_id":"image-1","filename":"question.png","title":"Question","mime_type":"image/png","file_type":"image","file_size":128,"status":"ready","availability":"available"}],"citations":[{"chunk_id":"chunk-1","document_id":"doc-1","score":0.72,"metadata":{"page":2}}],"source_status":"partially_unavailable"}],"page":1,"page_size":100,"total":1}"#)
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"u-1","title":"分数","subject":"数学","grade_level":"七年级","topic":"比例"}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"n-1","learning_unit_id":"u-1","version_no":2,"title":"笔记","html_object_key":"h","json_object_key":"j","highlighted_html_object_key":"hh","download_urls":{"highlighted_html":"https://download.test/highlighted.html"}}]"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)
        let preference = try await client.updateAIPreferences(aiHistoryEnabled: false)
        let conversations = try await client.listConversations(workspaceId: "ws-1")
        let messages = try await client.listChatMessages(workspaceId: "ws-1", conversationId: "c-1")
        let units = try await client.listLearningUnits(workspaceId: "ws-1")
        let notes = try await client.listStudyNotes(workspaceId: "ws-1", learningUnitId: "u-1")

        #expect(preference.aiHistoryEnabled == false)
        #expect(conversations.items.first?.title == "复习")
        #expect(messages.items.first?.status == "succeeded")
        #expect(messages.items.first?.citations?.first?.documentId == "doc-1")
        #expect(messages.items.first?.citations?.first?.metadata?["page"] == .number(2))
        #expect(messages.items.first?.sourceStatus == "partially_unavailable")
        #expect(messages.items.first?.modelId == "openai/gpt-4.1-mini")
        #expect(messages.items.first?.attachments?.first?.documentId == "image-1")
        #expect(messages.items.first?.attachments?.first?.isImage == true)
        #expect(units.first?.gradeLevel == "七年级")
        #expect(notes.first?.preferredDownloadURL == "https://download.test/highlighted.html")
        #expect(requests.contains { $0.url?.query == "include_download_url=true" })
    }

    @Test @MainActor func aiModelCatalogAndSelection_useDocumentedContract() async throws {
        var requests: [URLRequest] = []
        var selectedPayload: String?
        var resetWasNull = false
        let catalogJSON =
            """
            {
              "provider": "openai",
              "default_model": "openai/gpt-4.1-mini",
              "selected_model": "openai/gpt-4.1",
              "items": [
                {
                  "id": "openai/gpt-4.1-mini",
                  "upstream_id": "gpt-4.1-mini",
                  "owned_by": null,
                  "created": null
                },
                {
                  "id": "openai/gpt-4.1",
                  "upstream_id": "gpt-4.1",
                  "owned_by": "openai",
                  "created": 1
                }
              ],
              "fetched_at": "2026-07-28T08:00:00Z",
              "stale": true
            }
            """
        let session = Self.mockSession { request in
            requests.append(request)
            let absoluteURL = request.url?.absoluteString ?? ""
            if request.httpMethod == "GET",
               absoluteURL.contains("/api/v1/workspaces/ws%2F1/ai/models") {
                return Self.response(request, status: 200, body: catalogJSON)
            }
            if request.httpMethod == "PUT",
               absoluteURL.contains("/api/v1/workspaces/ws%2F1/ai/model") {
                let body = Self.requestBodyData(request).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                let preferred: String
                if let modelId = body?["model_id"], !(modelId is NSNull) {
                    selectedPayload = modelId as? String
                    preferred = #""openai/gpt-4.1""#
                } else {
                    resetWasNull = true
                    preferred = "null"
                }
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"selected_model":"openai/gpt-4.1","preferred_model":\#(preferred),"default_model":"openai/gpt-4.1-mini"}"#
                )
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        let catalog = try await client.listAIModels(workspaceId: "ws/1")
        let selection = try await client.selectAIModel(workspaceId: "ws/1", modelId: "openai/gpt-4.1")
        let reset = try await client.selectAIModel(
            workspaceId: "ws/1",
            modelId: Optional<String>.none
        )

        #expect(catalog.provider == "openai")
        #expect(catalog.items.count == 2)
        #expect(catalog.items.first?.ownedBy == nil)
        #expect(catalog.stale)
        #expect(selection.preferredModel == "openai/gpt-4.1")
        #expect(reset.preferredModel == nil)
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "PUT"])
        #expect(selectedPayload == "openai/gpt-4.1")
        #expect(resetWasNull)
    }

    @Test @MainActor func aiModels_loadOnceRefreshAndRollbackFailedSelection() async throws {
        let suiteName = "NotePatchAIModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var getCount = 0
        var putCount = 0
        let session = Self.mockSession { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/workspaces/ws-1/ai/models"):
                getCount += 1
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"provider":"openai","default_model":"model-default","selected_model":"model-default","items":[{"id":"model-default","upstream_id":"default","owned_by":null,"created":null},{"id":"model-alt","upstream_id":"alternate","owned_by":"openai","created":1}],"fetched_at":"","stale":false}"#
                )
            case ("PUT", "/api/v1/workspaces/ws-1/ai/model"):
                putCount += 1
                return Self.response(request, status: 500, body: #"{"detail":"selection failed"}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: "",
            userId: "user",
            email: "user@example.test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.selectedTab = .profile

        model.ensureContentForSelectedTabLoaded()
        model.ensureContentForSelectedTabLoaded()
        try await Self.waitUntil { model.aiModelCatalog != nil && !model.isAIModelsLoading }
        #expect(getCount == 1)
        #expect(model.selectedAIModelId == nil)

        model.loadAIModels(force: true)
        try await Self.waitUntil { getCount == 2 && !model.isAIModelsLoading }
        #expect(getCount == 2)

        model.selectAIModel("model-alt")
        try await Self.waitUntil { !model.isAIModelUpdating }
        #expect(putCount == 1)
        #expect(model.selectedAIModelId == nil)
        #expect(model.aiModelsError?.contains("selection failed") == true)
    }

    @Test @MainActor func notesOverview_groupsVersionsAndLoadsHTMLOnDemand() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            switch request.url?.path ?? "" {
            case "/api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: #"[{"id":"u-1","title":"比例","subject":"数学","grade_level":"七年级","topic":"比"},{"id":"u-2","title":"单元二","subject":null,"grade_level":null,"topic":null}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-1/notes":
                return Self.response(request, status: 200, body: #"[{"id":"n-1","learning_unit_id":"u-1","version_no":1,"title":"旧笔记","html_object_key":"h1","json_object_key":"j1","download_urls":{"html":"https://download.test/n-1.html"}},{"id":"n-2","learning_unit_id":"u-1","version_no":2,"title":"新笔记","html_object_key":"h2","json_object_key":"j2","highlighted_html_object_key":"hh2","download_urls":{"highlighted_html":"https://download.test/n-2.html"}}]"#)
            case "/api/v1/workspaces/ws-1/learning-units/u-2/notes":
                return Self.response(request, status: 200, body: "[]")
            case "/api/v1/workspaces/ws-1/learning-units/u-1/notes/n-2/download-url":
                return Self.response(request, status: 404, body: #"{"detail":"rendered note unavailable"}"#)
            default:
                if request.url?.host == "download.test" {
                    return Self.response(request, status: 200, body: "<h1>比例</h1><ul><li>外项积等于内项积</li></ul>")
                }
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        model.loadNotesOverview()
        try await Self.waitUntil { !model.isNotesLoading }
        let group = try #require(model.studyNoteGroups.first)
        #expect(model.studyNoteGroups.count == 2)
        #expect(group.learningUnit.title == "比例")
        #expect(group.notes.map(\.note.versionNo) == [2, 1])

        let latest = try #require(group.notes.first)
        model.openStudyNote(latest)
        try await Self.waitUntil { !model.isStudyNoteLoading }
        #expect(model.studyNoteHTML?.contains("外项积等于内项积") == true)
        #expect(model.studyNoteReaderError == nil)
    }

    @Test @MainActor func studyNoteRevision_decodesSavesRefreshesAndPreservesConflictDraft() async throws {
        let decoded = try JSONDecoder.notepatch.decode(
            StudyNoteVersion.self,
            from: Data(#"{"id":"n-1","workspace_id":"ws-1","learning_unit_id":"u-1","version_no":2,"title":"用户笔记","html_object_key":"h","json_object_key":"j","knowledge_point_ids":["kp-1"],"source_version_id":"n-0","edit_origin":"user","edit_summary":"补充例题","download_urls":null}"#.utf8)
        )
        #expect(decoded.downloadURLs.isEmpty)
        #expect(decoded.sourceVersionId == "n-0")
        #expect(decoded.revisionOriginLabel == localized("note.origin.user"))

        var revisionBodies: [[String: Any]] = []
        var phase = 0
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            let encodedPath = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            } ?? ""
            if request.httpMethod == "POST", let data = Self.requestBodyData(request) {
                revisionBodies.append(try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:])
            }
            if request.url?.host == "download.test" {
                return Self.response(request, status: 200, body: "<h1>服务端最新版本</h1>")
            }
            switch encodedPath {
            case "/api/v1/workspaces/ws%2F1/learning-units/unit%2F1/notes/note%2F1/revisions":
                return Self.response(request, status: 201, body: #"{"note":{"id":"new-1","learning_unit_id":"unit/1","version_no":3,"title":"新标题","html_object_key":"h3","json_object_key":"j3","source_version_id":"note/1","edit_origin":"user","edit_summary":"补充例题","download_urls":null},"downstream_tasks":[]}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let escapedClient = LearningBackendClient(baseURL: "https://api.test", accessToken: "a", refreshToken: "r", session: session)
        let response = try await escapedClient.createStudyNoteRevision(
            workspaceId: "ws/1",
            learningUnitId: "unit/1",
            baseVersionId: "note/1",
            input: StudyNoteRevisionInput(html: "<h1>新内容</h1>", title: "新标题", editSummary: "补充例题")
        )
        #expect(response.note.id == "new-1")
        #expect(response.note.downloadURLs.isEmpty)
        #expect(revisionBodies.first?["html"] as? String == "<h1>新内容</h1>")
        #expect(revisionBodies.first?["markdown"] == nil)
        #expect(revisionBodies.first?["title"] as? String == "新标题")
        #expect(revisionBodies.first?["edit_summary"] as? String == "补充例题")

        phase = 1
        let modelSession = Self.mockSession { request in
            let path = request.url?.path ?? ""
            if request.url?.host == "download.test" {
                return Self.response(request, status: 200, body: "<h1>服务端最新版本</h1>")
            }
            switch (phase, request.httpMethod ?? "", path) {
            case (1, "POST", "/api/v1/workspaces/ws-1/learning-units/u-1/notes/n-2/revisions"):
                return Self.response(request, status: 201, body: #"{"note":{"id":"n-3","learning_unit_id":"u-1","version_no":3,"title":"新标题","html_object_key":"h3","json_object_key":"j3","source_version_id":"n-2","edit_origin":"user","edit_summary":"补充例题","download_urls":null}}"#)
            case (1, "GET", "/api/v1/workspaces/ws-1/learning-units/u-1/notes"):
                return Self.response(request, status: 200, body: #"[{"id":"n-3","learning_unit_id":"u-1","version_no":3,"title":"新标题","html_object_key":"h3","json_object_key":"j3","source_version_id":"n-2","edit_origin":"user","edit_summary":"补充例题","download_urls":{"html":"https://download.test/n-3.html"}},{"id":"n-2","learning_unit_id":"u-1","version_no":2,"title":"当前笔记","html_object_key":"h2","json_object_key":"j2","download_urls":{"html":"https://download.test/n-2.html"}},{"id":"n-1","learning_unit_id":"u-1","version_no":1,"title":"历史笔记","html_object_key":"h1","json_object_key":"j1","download_urls":{"html":"https://download.test/n-1.html"}}]"#)
            case (1, "GET", "/api/v1/workspaces/ws-1/learning-units/u-1/notes/n-3/download-url"):
                return Self.response(request, status: 404, body: #"{"detail":"rendered note unavailable"}"#)
            case (2, "POST", "/api/v1/workspaces/ws-1/learning-units/u-1/notes/n-3/revisions"):
                return Self.response(request, status: 409, body: #"{"detail":"base version is stale"}"#)
            case (2, "GET", "/api/v1/workspaces/ws-1/learning-units/u-1/notes"):
                return Self.response(request, status: 200, body: #"[{"id":"n-4","learning_unit_id":"u-1","version_no":4,"title":"服务端笔记","html_object_key":"h4","json_object_key":"j4","source_version_id":"n-3","edit_origin":"skill","edit_summary":null,"download_urls":{"html":"https://download.test/n-4.html"}},{"id":"n-3","learning_unit_id":"u-1","version_no":3,"title":"新标题","html_object_key":"h3","json_object_key":"j3","download_urls":{"html":"https://download.test/n-3.html"}}]"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: modelSession,
            tusSession: modelSession
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let unit = LearningUnit(id: "u-1", title: "比例", subject: "数学", gradeLevel: nil, topic: nil)
        let old = StudyNoteListItem(learningUnit: unit, note: StudyNoteVersion(id: "n-1", learningUnitId: "u-1", versionNo: 1, title: "历史笔记", htmlObjectKey: "h1", jsonObjectKey: "j1", downloadURLs: ["html": "https://download.test/n-1.html"]))
        let current = StudyNoteListItem(learningUnit: unit, note: StudyNoteVersion(id: "n-2", learningUnitId: "u-1", versionNo: 2, title: "当前笔记", htmlObjectKey: "h2", jsonObjectKey: "j2", downloadURLs: ["html": "https://download.test/n-2.html"]))
        model.studyNoteGroups = [StudyNoteGroup(learningUnit: unit, notes: [current, old])]
        model.selectedStudyNoteItem = old
        model.studyNoteHTML = "<h1>历史</h1>"
        #expect(!model.canEditSelectedStudyNote)

        model.selectedStudyNoteItem = current
        model.studyNoteHTML = "<h1>当前</h1>"
        model.beginStudyNoteEditing()
        try await Self.waitUntil { !model.isStudyNoteEditorLoading }
        model.studyNoteDraftTitle = "新标题"
        model.studyNoteDraftHTML = "<h1>本地新内容</h1>"
        model.studyNoteDraftSummary = "补充例题"
        model.saveStudyNoteRevision()
        try await Self.waitUntil { !model.isStudyNoteSaving }
        #expect(model.selectedStudyNoteItem?.note.id == "n-3")
        #expect(model.studyNoteGroups.first?.notes.first?.note.id == "n-3")
        #expect(model.studyNoteHTML == "<h1>本地新内容</h1>")
        #expect(!model.isStudyNoteEditorPresented)

        phase = 2
        model.beginStudyNoteEditing()
        try await Self.waitUntil { !model.isStudyNoteEditorLoading }
        model.studyNoteDraftHTML = "<h1>保留的本地草稿</h1>"
        model.saveStudyNoteRevision()
        try await Self.waitUntil { !model.isStudyNoteSaving }
        #expect(model.isStudyNoteConflictPending)
        #expect(model.selectedStudyNoteItem?.note.id == "n-4")
        #expect(model.studyNoteDraftHTML == "<h1>保留的本地草稿</h1>")
        #expect(model.studyNoteHTML == "<h1>服务端最新版本</h1>")
    }

    @Test func persistentMutationRequests_matchDocumentedContracts() async throws {
        var requests: [URLRequest] = []
        var bodies: [String: [String: Any]] = [:]
        let session = Self.mockSession { request in
            requests.append(request)
            let encodedPath = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            } ?? ""
            let key = "\(request.httpMethod ?? "") \(encodedPath)"
            if let data = Self.requestBodyData(request) {
                bodies[key] = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc%2F1":
                return Self.response(request, status: 202, body: #"{"ok":true,"document_id":"doc/1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#)
            case "PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1":
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "DELETE /api/v1/workspaces/ws-1/ai/conversations/c-1",
                 "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                return Self.response(request, status: 204, body: "")
            case "PATCH /api/v1/auth/preferences":
                return Self.response(request, status: 200, body: #"{"id":"u-1","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)

        let deleted = try await client.deleteDocument(workspaceId: "ws-1", documentId: "doc/1")
        let renamed = try await client.updateConversation(workspaceId: "ws-1", conversationId: "c-1", title: "新标题")
        try await client.deleteConversation(workspaceId: "ws-1", conversationId: "c-1")
        let preference = try await client.updateAIPreferences(aiHistoryEnabled: false)
        try await client.deleteHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", referenceId: "r-1")

        #expect(renamed.title == "新标题")
        #expect(deleted.purgeStatus == "queued")
        #expect(deleted.purgeTaskId == "purge-1")
        #expect(preference.aiHistoryEnabled == false)
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1"]?["title"] as? String == "新标题")
        #expect(bodies["PATCH /api/v1/auth/preferences"]?["ai_history_enabled"] as? Bool == false)
        #expect(requests.filter { $0.httpMethod == "DELETE" }.count == 3)
    }

    @Test func decodeDocumentPurgeAndTaskCancellationFields() throws {
        let document = try JSONDecoder.notepatch.decode(
            LearningDocumentItem.self,
            from: Data(
                #"{"id":"doc-1","workspace_id":"ws-1","uploaded_by":"u-1","original_filename":"homework.pdf","file_type":"pdf","document_kind":"homework","storage_backend":"seaweedfs","bucket":"b","object_key":"documents/doc-1","status":"deleted","purge_status":"running","purge_task_id":"purge-1","purged_at":null,"created_at":"","updated_at":"","artifacts":[]}"#.utf8
            )
        )
        let deletion = try JSONDecoder.notepatch.decode(
            DocumentDeleteResponse.self,
            from: Data(#"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#.utf8)
        )
        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"task-1","workspace_id":"ws-1","task_type":"purge_document","status":"running","payload":{},"progress":40,"cancel_requested_at":"2026-07-11T01:00:00Z","created_at":"","updated_at":""}"#.utf8)
        )

        #expect(document.purgeStatus == "running")
        #expect(document.purgeTaskId == "purge-1")
        #expect(deletion.documentId == "doc-1")
        #expect(deletion.purgeTaskId == "purge-1")
        #expect(task.cancelRequestedAt == "2026-07-11T01:00:00Z")
    }

    @Test func decodeKnowledgeHomeworkReferenceAndGradingResult() throws {
        let search = try JSONDecoder.notepatch.decode(
            KnowledgeSearchResponse.self,
            from: Data(#"{"items":[{"id":"k-1","workspace_id":"ws-1","document_id":null,"subject":null,"grade_level":"IGCSE","source_type":"courseware","content":"斜率表示变化率","metadata":{"title":"一次函数","page_refs":[2,3]},"score":0.8731,"created_at":""}]}"#.utf8)
        )
        #expect(search.items.first?.metadataTitle == "一次函数")
        #expect(search.items.first?.pageReferences == "2, 3")
        #expect(search.items.first?.documentId == nil)
        #expect(search.items.first?.score == 0.8731)

        let homework = try JSONDecoder.notepatch.decode(
            HomeworkItem.self,
            from: Data(#"{"id":"h-1","workspace_id":"ws-1","title":"代数作业","description":null,"document_id":"doc-1","due_at":null,"status":"draft","rubric_text":"过程 4 分","max_score":100.0,"metadata":{},"created_by_user_id":"u-1","created_at":"","updated_at":"","latest_grading_result":{"id":"g-1","workspace_id":"ws-1","homework_id":"h-1","question_id":null,"student_user_id":null,"score":86.5,"max_score":100.0,"grading_mode":"official","confidence":0.91,"feedback":"步骤完整","created_at":"2026-08-21T01:00:00Z"}}"#.utf8)
        )
        let gradingResults = try JSONDecoder.notepatch.decode(
            [GradingResult].self,
            from: Data(#"[{"id":"g-2","workspace_id":"ws-1","homework_id":"h-1","question_id":"q-1","student_user_id":null,"score":null,"max_score":null,"grading_mode":"provisional","confidence":null,"feedback":null,"created_at":"2026-08-20T01:00:00Z"}]"#.utf8)
        )
        let homeworkWithoutResult = try JSONDecoder.notepatch.decode(
            HomeworkItem.self,
            from: Data(#"{"id":"h-2","workspace_id":"ws-1","title":"旧响应","status":"draft","max_score":100,"created_by_user_id":"u-1","created_at":"","updated_at":""}"#.utf8)
        )
        let homeworkWithNullResult = try JSONDecoder.notepatch.decode(
            HomeworkItem.self,
            from: Data(#"{"id":"h-3","workspace_id":"ws-1","title":"未评分","status":"draft","max_score":100,"created_by_user_id":"u-1","created_at":"","updated_at":"","latest_grading_result":null}"#.utf8)
        )
        let references = try JSONDecoder.notepatch.decode(
            [HomeworkReferenceItem].self,
            from: Data(#"[{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}]"#.utf8)
        )
        let task = try JSONDecoder.notepatch.decode(
            TaskItem.self,
            from: Data(#"{"id":"t-1","workspace_id":"ws-1","status":"succeeded","payload":{},"result":{"grading_mode":"provisional","confidence":0.82},"progress":100}"#.utf8)
        )
        #expect(homework.maxScore == 100)
        #expect(homework.latestGradingResult?.score == 86.5)
        #expect(homework.latestGradingResult?.gradingMode == "official")
        #expect(gradingResults.first?.questionId == "q-1")
        #expect(gradingResults.first?.score == nil)
        #expect(homeworkWithoutResult.latestGradingResult == nil)
        #expect(homeworkWithNullResult.latestGradingResult == nil)
        #expect(references.first?.referenceType == "answer_key")
        #expect(task.result?.objectStringValue(for: "grading_mode") == "provisional")
        #expect(task.result?.objectDoubleValue(for: "confidence") == 0.82)
    }

    @Test func knowledgeAndHomeworkRequests_matchOpenAPI() async throws {
        var bodies: [String: [String: Any]] = [:]
        let homeworkJSON = #"{"id":"h-1","workspace_id":"ws-1","title":"代数作业","document_id":"doc-1","status":"draft","rubric_text":"过程 4 分","max_score":100.0,"metadata":{},"created_by_user_id":"u-1","created_at":"","updated_at":"","latest_grading_result":{"id":"g-1","workspace_id":"ws-1","homework_id":"h-1","score":86.5,"max_score":100.0,"grading_mode":"official","confidence":0.91,"feedback":"步骤完整","created_at":"2026-08-21T01:00:00Z"}}"#
        let gradingResultJSON = #"{"id":"g-1","workspace_id":"ws-1","homework_id":"h-1","question_id":null,"student_user_id":null,"score":86.5,"max_score":100.0,"grading_mode":"official","confidence":0.91,"feedback":"步骤完整","created_at":"2026-08-21T01:00:00Z"}"#
        let referenceJSON = #"{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}"#
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            if let data = Self.requestBodyData(request) {
                bodies[key] = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            switch key {
            case "POST /api/v1/workspaces/ws-1/knowledge/search":
                return Self.response(request, status: 200, body: #"{"items":[]}"#)
            case "GET /api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[\(homeworkJSON)]")
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1", "POST /api/v1/workspaces/ws-1/homeworks", "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: request.httpMethod == "POST" ? 201 : 200, body: homeworkJSON)
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 200, body: "[\(referenceJSON)]")
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/grading-results":
                return Self.response(request, status: 200, body: "[\(gradingResultJSON)]")
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 201, body: referenceJSON)
            case "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                return Self.response(request, status: 204, body: "")
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/grade":
                return Self.response(request, status: 201, body: Self.taskJSON)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "access", refreshToken: "refresh", session: session)
        _ = try await client.searchKnowledge(workspaceId: "ws-1", query: "斜率", learningUnitId: "unit-1", subject: "math", limit: 6)
        _ = try await client.listHomeworks(workspaceId: "ws-1")
        _ = try await client.getHomework(workspaceId: "ws-1", homeworkId: "h-1")
        _ = try await client.createHomework(workspaceId: "ws-1", input: HomeworkCreateInput(title: "代数作业", description: nil, documentId: "doc-1", dueAt: nil, rubricText: nil, maxScore: 100))
        _ = try await client.updateGradingConfig(workspaceId: "ws-1", homeworkId: "h-1", input: GradingConfigInput(rubricText: nil, maxScore: 80))
        let gradingResults = try await client.listGradingResults(workspaceId: "ws-1", homeworkId: "h-1")
        _ = try await client.listHomeworkReferences(workspaceId: "ws-1", homeworkId: "h-1")
        _ = try await client.addHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key")
        try await client.deleteHomeworkReference(workspaceId: "ws-1", homeworkId: "h-1", referenceId: "r-1")
        _ = try await client.gradeHomework(workspaceId: "ws-1", homeworkId: "h-1")

        #expect(bodies["POST /api/v1/workspaces/ws-1/knowledge/search"]?["learning_unit_id"] as? String == "unit-1")
        #expect(bodies["POST /api/v1/workspaces/ws-1/knowledge/search"]?["limit"] as? Int == 6)
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks"]?["document_id"] as? String == "doc-1")
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config"]?["max_score"] as? Double == 80)
        #expect(bodies["PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config"]?["rubric_text"] is NSNull)
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks/h-1/references"]?["reference_type"] as? String == "answer_key")
        #expect(bodies["POST /api/v1/workspaces/ws-1/homeworks/h-1/grade"]?["student_user_id"] is NSNull)
        #expect(gradingResults.first?.feedback == "步骤完整")
    }

    @Test func gradingResultsRequest_escapesWorkspaceAndHomeworkPaths() async throws {
        var capturedRequest: URLRequest?
        let session = Self.mockSession { request in
            capturedRequest = request
            return Self.response(request, status: 200, body: "[]")
        }
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access",
            refreshToken: "refresh",
            session: session
        )

        _ = try await client.listGradingResults(workspaceId: "ws/1", homeworkId: "homework/1")

        let encodedPath = capturedRequest?.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
        }
        #expect(capturedRequest?.httpMethod == "GET")
        #expect(encodedPath == "/api/v1/workspaces/ws%2F1/homeworks/homework%2F1/grading-results")
    }

    @Test @MainActor func conversationMutations_waitForServerAndDeduplicateRequests() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var renameCount = 0
        var deleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/ai/conversations/c-1":
                renameCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 200, body: #"{"id":"c-1","workspace_id":"ws-1","title":"新标题","created_at":"","updated_at":""}"#)
            case "DELETE /api/v1/workspaces/ws-1/ai/conversations/c-1":
                deleteCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 204, body: "")
            case "GET /api/v1/workspaces/ws-1/ai/conversations":
                return Self.response(request, status: 200, body: #"{"items":[],"page":1,"page_size":20,"total":0}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedConversationId = "c-1"
        model.conversations = [ChatConversation(id: "c-1", workspaceId: "ws-1", title: "旧标题", lastMessageAt: nil, createdAt: "", updatedAt: "")]

        model.renameCurrentConversation(to: "新标题")
        model.renameCurrentConversation(to: "重复请求")
        #expect(model.isConversationMutating)
        #expect(model.selectedConversation?.title == "旧标题")
        try await Self.waitUntil { !model.isConversationMutating }
        #expect(renameCount == 1)
        #expect(model.selectedConversation?.title == "新标题")
        #expect(model.statusMessage == localized("chat.title_saved"))

        model.renameCurrentConversation(to: String(repeating: "a", count: 161))
        #expect(model.errorMessage == localized("chat.error.title_length"))
        #expect(renameCount == 1)

        model.deleteCurrentConversation()
        model.deleteCurrentConversation()
        #expect(model.isConversationMutating)
        #expect(model.conversations.count == 1)
        try await Self.waitUntil { !model.isConversationMutating }
        #expect(deleteCount == 1)
        #expect(model.conversations.isEmpty)
        #expect(model.selectedConversationId == nil)
        #expect(model.statusMessage == localized("chat.conversation_deleted"))
    }

    @Test @MainActor func conversationSelection_ignoresLateResponseFromPreviousSelection() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            switch request.url?.path {
            case "/api/v1/workspaces/ws-1/ai/conversations/c-1/messages":
                Thread.sleep(forTimeInterval: 0.12)
                return Self.response(request, status: 200, body: #"{"items":[{"id":"m-1","conversation_id":"c-1","role":"assistant","content":"old","status":"succeeded","created_at":""}],"page":1,"page_size":100,"total":1}"#)
            case "/api/v1/workspaces/ws-1/ai/conversations/c-2/messages":
                return Self.response(request, status: 200, body: #"{"items":[{"id":"m-2","conversation_id":"c-2","role":"assistant","content":"current","status":"succeeded","created_at":""}],"page":1,"page_size":100,"total":1}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        model.selectConversation("c-1")
        model.selectConversation("c-2")
        try await Self.waitUntil { !model.isChatHistoryLoading && model.openClawMessages.first?.content == "current" }
        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(model.selectedConversationId == "c-2")
        #expect(model.openClawMessages.map(\.content) == ["current"])
    }

    @Test @MainActor func restoredConversationDownloadsPersistedImageAttachments() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchRestoredChatAttachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let imageData = try #require(image.pngData())
        var requestedPaths: [String] = []
        let backendSession = Self.mockSession { request in
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/workspaces/ws-1/ai/conversations/c-1/messages":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"items":[{"id":"message-1","conversation_id":"c-1","role":"user","content":"这是什么图片？","status":"succeeded","created_at":"","attachments":[{"document_id":"089c9496-df42-4e92-bc4f-a493a3b711f8","filename":"question.png","mime_type":"image/png","file_type":"image","file_size":128,"status":"ready","availability":"available"}]}],"page":1,"page_size":100,"total":1}"#
                )
            case "/api/v1/workspaces/ws-1/documents/089c9496-df42-4e92-bc4f-a493a3b711f8/download-url":
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"document_id":"089c9496-df42-4e92-bc4f-a493a3b711f8","filename":"question.png","expires_in":900,"download_url":"https://download.test/question.png"}"#
                )
            case "/question.png":
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
                return (response, imageData)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: backendSession,
            tusSession: backendSession,
            cacheDirectory: cacheDirectory,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        model.selectConversation("c-1")
        try await Self.waitUntil {
            !model.isChatHistoryLoading && model.openClawMessages.first?.attachments.first?.status == .ready
        }

        let restored = try #require(model.openClawMessages.first?.attachments.first)
        #expect(restored.documentId == "089c9496-df42-4e92-bc4f-a493a3b711f8")
        #expect(restored.file.filename == "question.png")
        #expect(FileManager.default.fileExists(atPath: restored.file.url.path))
        #expect((try Data(contentsOf: restored.file.url)) == imageData)
        #expect(requestedPaths.contains("/api/v1/workspaces/ws-1/documents/089c9496-df42-4e92-bc4f-a493a3b711f8/download-url"))
        #expect(requestedPaths.contains("/question.png"))
    }

    @Test @MainActor func documentPreviewRetriesExpiredURLOnceAndIsolatesSameNamedFiles() async throws {
        let suiteName = "NotePatchDocumentPreview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchDocumentPreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        var downloadURLRequests: [String: Int] = [:]
        var expiredDownloadCount = 0
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/download-url") {
                let documentId = path.components(separatedBy: "/documents/").last?
                    .components(separatedBy: "/").first ?? ""
                downloadURLRequests[documentId, default: 0] += 1
                let url = documentId == "doc-1" && downloadURLRequests[documentId] == 1
                    ? "https://download.test/expired"
                    : "https://download.test/\(documentId)"
                return Self.response(request, status: 200, body: #"{"download_url":"\#(url)","expires_in":900}"#)
            }
            if path == "/expired" {
                expiredDownloadCount += 1
                return Self.response(request, status: 403, body: #"{"detail":"expired"}"#)
            }
            if path == "/doc-1" || path == "/doc-2" {
                let data = Data("preview-\(path)".utf8)
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/pdf"]
                )!
                return (response, data)
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: cacheDirectory,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u",
            email: "u@test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        let first = LearningDocumentItem(
            id: "doc-1", workspaceId: "ws-1", originalFilename: "same.pdf",
            mimeType: "application/pdf", fileType: "pdf", documentKind: "courseware", status: "scanning"
        )
        let second = LearningDocumentItem(
            id: "doc-2", workspaceId: "ws-1", originalFilename: "same.pdf",
            mimeType: "application/pdf", fileType: "pdf", documentKind: "courseware", status: "ready"
        )

        model.downloadAndPreview(first)
        model.downloadAndPreview(first)
        try await Self.waitUntil { model.downloadedPreview?.url.path.contains("/doc-1/") == true }
        let firstURL = try #require(model.downloadedPreview?.url)
        model.downloadedPreview = nil
        model.downloadAndPreview(second)
        try await Self.waitUntil { model.downloadedPreview?.url.path.contains("/doc-2/") == true }
        let secondURL = try #require(model.downloadedPreview?.url)

        #expect(expiredDownloadCount == 1)
        #expect(downloadURLRequests["doc-1"] == 2)
        #expect(downloadURLRequests["doc-2"] == 1)
        #expect(firstURL != secondURL)
        #expect(firstURL.lastPathComponent == secondURL.lastPathComponent)
        #expect(!model.isDocumentPreviewLoading("doc-1"))
        #expect(!model.isDocumentPreviewLoading("doc-2"))
    }

    @Test @MainActor func homeworkSelection_ignoresLateReferencesFromPreviousHomework() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            switch request.url?.path {
            case "/api/v1/workspaces/ws-1/homeworks/h-1/references":
                Thread.sleep(forTimeInterval: 0.12)
                return Self.response(request, status: 200, body: #"[{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"d-1","reference_type":"answer_key","created_at":""}]"#)
            case "/api/v1/workspaces/ws-1/homeworks/h-2/references":
                return Self.response(request, status: 200, body: #"[{"id":"r-2","workspace_id":"ws-1","homework_id":"h-2","document_id":"d-2","reference_type":"rubric","created_at":""}]"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.homeworks = [
            HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "One", maxScore: 100),
            HomeworkItem(id: "h-2", workspaceId: "ws-1", title: "Two", maxScore: 100)
        ]

        model.selectHomework("h-1")
        model.selectHomework("h-2")
        try await Self.waitUntil { !model.isHomeworkLoading && model.homeworkReferences.first?.id == "r-2" }
        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(model.selectedHomeworkId == "h-2")
        #expect(model.homeworkReferences.map(\.id) == ["r-2"])
    }

    @Test @MainActor func documentDeletion_keepsServerCommitWhenRefreshFails() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            if request.httpMethod == "DELETE" {
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 500, body: #"{"detail":"delete rejected"}"#)
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let document = LearningDocumentItem(id: "doc-1", workspaceId: "ws-1", title: "作业", originalFilename: "homework.pdf", fileType: "pdf", documentKind: "homework", status: "ready")
        let reference = HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "doc-1", referenceType: "answer_key", createdAt: "")
        model.documents = [document]
        model.gradingDocuments = [document]
        model.homeworkReferences = [reference]

        model.deleteDocument(document)
        #expect(model.isBusy)
        #expect(model.documents == [document])
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents == [document])
        #expect(model.gradingDocuments == [document])
        #expect(model.homeworkReferences == [reference])
        #expect(model.errorMessage == "delete rejected")

        MockURLProtocol.handler = { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc-1":
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 202, body: #"{"ok":true,"document_id":"doc-1","status":"deleted","purge_status":"queued","purge_task_id":"purge-1"}"#)
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-1", status: "succeeded", progress: 100))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1/events":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"refresh unavailable"}"#)
            }
        }
        model.errorMessage = nil
        model.deleteDocument(document)
        #expect(model.documents == [document])
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents.isEmpty)
        #expect(model.gradingDocuments.isEmpty)
        #expect(model.homeworkReferences.isEmpty)
        #expect(model.selectedTab == .home)
        #expect(model.selectedDocumentsSection == .tasks)
        #expect(model.selectedHomeDestination == .tasks)
        #expect(model.activeTask?.taskType == "purge_document")
        #expect(model.activeTask?.status == "succeeded")
        #expect(model.errorMessage == nil)
        #expect(model.statusMessage.contains(localized("operation.document_cleanup_completed")))
        #expect(model.statusMessage.contains("refresh unavailable"))
    }

    @Test @MainActor func failedDocumentPurge_canBeRetriedWithoutRestoringDocument() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var deleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "DELETE /api/v1/workspaces/ws-1/documents/doc-1":
                deleteCount += 1
                let taskId = deleteCount == 1 ? "purge-1" : "purge-2"
                return Self.response(request, status: 202, body: "{\"ok\":true,\"document_id\":\"doc-1\",\"status\":\"deleted\",\"purge_status\":\"queued\",\"purge_task_id\":\"\(taskId)\"}")
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-1", status: "failed", progress: 45, errorMessage: "purge failed"))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-1/events":
                return Self.response(request, status: 200, body: "[]")
            case "GET /api/v1/workspaces/ws-1/tasks/purge-2":
                return Self.response(request, status: 200, body: Self.purgeTaskJSON(id: "purge-2", status: "succeeded", progress: 100))
            case "GET /api/v1/workspaces/ws-1/tasks/purge-2/events":
                return Self.response(request, status: 200, body: "[]")
            case "GET /api/v1/workspaces/ws-1/documents",
                 "GET /api/v1/workspaces/ws-1/learning-units",
                 "GET /api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let document = LearningDocumentItem(id: "doc-1", workspaceId: "ws-1", title: "作业", originalFilename: "homework.pdf", fileType: "pdf", documentKind: "homework", status: "ready")
        model.documents = [document]

        model.deleteDocument(document)
        try await Self.waitUntil { !model.isBusy }
        #expect(model.documents.isEmpty)
        #expect(model.activeTask?.status == "failed")
        #expect(model.canRetryDocumentPurge)
        #expect(model.errorMessage == "purge failed")

        model.retryDocumentPurge()
        try await Self.waitUntil { !model.isBusy }
        #expect(deleteCount == 2)
        #expect(model.documents.isEmpty)
        #expect(model.activeTask?.id == "purge-2")
        #expect(model.activeTask?.status == "succeeded")
        #expect(!model.canRetryDocumentPurge)
        #expect(model.statusMessage == localized("document.cleanup_complete"))
    }

    @Test @MainActor func processingValidationAndCancellation_stopResultReads() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var requestCount = 0
        var resultReadCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "POST /api/v1/workspaces/ws-1/documents/doc-ready/process":
                return Self.response(request, status: 201, body: Self.taskJSON)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1":
                return Self.response(request, status: 200, body: #"{"id":"task-1","workspace_id":"ws-1","task_type":"process_document","status":"cancelled","resource_type":"document","resource_id":"doc-ready","payload":{},"result":null,"error_message":null,"progress":25,"cancel_requested_at":"2026-07-11T01:00:00Z","created_at":"","updated_at":""}"#)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1/events":
                return Self.response(request, status: 200, body: #"[{"id":"event-1","workspace_id":"ws-1","task_id":"task-1","event_type":"task_cancelled","level":"warning","message":"Source document was deleted","progress":25,"data":{},"created_at":""}]"#)
            case "GET /api/v1/workspaces/ws-1/tasks/task-1/events/stream":
                return Self.response(request, status: 404, body: #"{"detail":"stream unavailable"}"#)
            default:
                resultReadCount += 1
                return Self.response(request, status: 500, body: #"{"detail":"unexpected result read"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"

        let invalidDocument = LearningDocumentItem(id: "doc-created", workspaceId: "ws-1", originalFilename: "created.pdf", fileType: "pdf", documentKind: "homework", status: "created")
        model.startProcessing(invalidDocument)
        #expect(requestCount == 0)
        #expect(model.errorMessage == localized("Only uploaded, ready, or failed documents can be processed."))

        let readyDocument = LearningDocumentItem(id: "doc-ready", workspaceId: "ws-1", originalFilename: "ready.pdf", fileType: "pdf", documentKind: "homework", status: "uploaded")
        model.startProcessing(readyDocument)
        try await Self.waitUntil { !model.isBusy }
        #expect(model.activeTask?.status == "cancelled")
        #expect(model.activeTask?.cancelRequestedAt != nil)
        #expect(model.taskEvents.last?.message == "Source document was deleted")
        #expect(model.errorMessage == "Source document was deleted")
        #expect(resultReadCount == 0)
    }

    @Test @MainActor func aiPreference_isSerializedPersistedAndRolledBackOnFailure() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        defer {
            settings.clearSession()
            defaults.removePersistentDomain(forName: suiteName)
        }
        var requestCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            Thread.sleep(forTimeInterval: 0.08)
            return Self.response(request, status: 200, body: #"{"id":"u","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#)
        }
        let model = NotePatchViewModel(settings: settings, backendSession: session, tusSession: session)
        let activeSession = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.session = activeSession
        model.selectedWorkspaceId = "ws-1"
        model.aiHistoryEnabled = true

        model.updateAIHistoryEnabled(false)
        model.updateAIHistoryEnabled(true)
        #expect(model.isAIPreferenceUpdating)
        #expect(model.aiHistoryEnabled == false)
        try await Self.waitUntil { !model.isAIPreferenceUpdating }
        #expect(requestCount == 1)
        #expect(settings.loadAIHistoryEnabled() == false)
        #expect(model.statusMessage == localized("AI history setting saved."))

        MockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"preference rejected"}"#)
        }
        model.updateAIHistoryEnabled(true)
        try await Self.waitUntil { !model.isAIPreferenceUpdating }
        #expect(model.aiHistoryEnabled == false)
        #expect(settings.loadAIHistoryEnabled() == false)
        #expect(model.errorMessage == "preference rejected")
    }

    @Test @MainActor func aiPreferenceResponse_doesNotRestoreLoggedOutSession() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        defer {
            settings.clearSession()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let session = Self.mockSession { request in
            if request.url?.path == "/api/v1/auth/preferences" {
                Thread.sleep(forTimeInterval: 0.12)
                return Self.response(request, status: 200, body: #"{"id":"u","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#)
            }
            return Self.response(request, status: 204, body: "")
        }
        let model = NotePatchViewModel(settings: settings, backendSession: session, tusSession: session)
        let activeSession = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        settings.saveSession(activeSession)
        model.session = activeSession
        model.selectedWorkspaceId = "ws-1"

        model.updateAIHistoryEnabled(false)
        model.logout()
        try await Task.sleep(nanoseconds: 220_000_000)

        #expect(model.session == nil)
        #expect(settings.loadSession() == nil)
        #expect(!model.isAIPreferenceUpdating)
    }

    @Test @MainActor func staleAttachmentImport_isDiscardedAfterWorkspaceChange() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-2", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-2"
        let fileURL = model.uploadCacheDirectory.appendingPathComponent("stale-attachment.txt")
        try Data("stale".utf8).write(to: fileURL)
        let file = LocalUploadFile(url: fileURL, filename: "stale-attachment.txt", mimeType: "text/plain")

        let accepted = model.stageOpenClawDraftAttachments(
            [file],
            expectedUserId: "u",
            expectedWorkspaceId: "ws-1"
        )

        #expect(!accepted)
        #expect(model.openClawComposerState.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test @MainActor func gradingDraftAndReferenceDeletion_reflectServerState() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var referenceDeleteCount = 0
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: 500, body: #"{"detail":"grading rejected"}"#)
            case "DELETE /api/v1/workspaces/ws-1/homeworks/h-1/references/r-1":
                referenceDeleteCount += 1
                Thread.sleep(forTimeInterval: 0.08)
                return Self.response(request, status: 204, body: "")
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业", rubricText: "旧标准", maxScore: 100)]
        model.selectedHomeworkId = "h-1"
        model.homeworkRubricText = "旧标准"
        model.homeworkMaxScoreText = "100"
        #expect(!model.isGradingConfigDirty)

        model.homeworkRubricText = "新标准"
        #expect(model.isGradingConfigDirty)
        model.saveGradingConfig()
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.homeworkRubricText == "新标准")
        #expect(model.selectedHomework?.rubricText == "旧标准")
        #expect(model.isGradingConfigDirty)
        #expect(model.errorMessage == "grading rejected")
        #expect(!model.statusMessage.contains("已保存"))

        let reference = HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key", createdAt: "")
        model.homeworkReferences = [reference]
        model.lastGradingTask = TaskItem(id: "grade-1", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", result: .object(["grading_mode": .string("official")]), progress: 100)
        model.deleteHomeworkReference(reference)
        model.deleteHomeworkReference(reference)
        #expect(model.homeworkReferences == [reference])
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(referenceDeleteCount == 1)
        #expect(model.homeworkReferences.isEmpty)
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == localized("Reference removed. Please re-grade."))
    }

    @Test @MainActor func successfulGradingMutations_clearStaleResult() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "PATCH /api/v1/workspaces/ws-1/homeworks/h-1/grading-config":
                return Self.response(request, status: 200, body: #"{"id":"h-1","workspace_id":"ws-1","title":"作业","document_id":"homework-1","status":"draft","rubric_text":"新标准","max_score":100,"metadata":{},"created_by_user_id":"u","created_at":"","updated_at":""}"#)
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/references":
                return Self.response(request, status: 201, body: #"{"id":"r-1","workspace_id":"ws-1","homework_id":"h-1","document_id":"answer-1","reference_type":"answer_key","created_at":""}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedHomeworkId = "h-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业", documentId: "homework-1", rubricText: "旧标准", maxScore: 100)]
        model.homeworkRubricText = "新标准"
        model.homeworkMaxScoreText = "100"
        model.lastGradingTask = TaskItem(id: "grade-1", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", progress: 100)

        model.saveGradingConfig()
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == localized("Grading configuration saved. Please re-grade."))

        model.lastGradingTask = TaskItem(id: "grade-2", workspaceId: "ws-1", taskType: "grade_homework", status: "succeeded", progress: 100)
        model.gradingDocuments = [LearningDocumentItem(id: "answer-1", workspaceId: "ws-1", originalFilename: "answer.pdf", fileType: "pdf", documentKind: "answer_key", status: "ready")]
        model.addHomeworkReference(documentId: "answer-1")
        try await Self.waitUntil { !model.isHomeworkLoading }
        #expect(model.homeworkReferences.first?.documentId == "answer-1")
        #expect(model.lastGradingTask == nil)
        #expect(model.statusMessage == localized("Reference added. Please re-grade."))
    }

    @Test @MainActor func gradingHistory_usesHomeworkLatestResultAndLoadsOnDemandOnce() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var historyRequestCount = 0
        let historyJSON = #"""
        [
          {"id":"g-old","workspace_id":"ws-1","homework_id":"h-1","score":70,"max_score":100,"grading_mode":"provisional","confidence":0.6,"feedback":null,"created_at":"2026-08-19T00:00:00Z"},
          {"id":"g-new","workspace_id":"ws-1","homework_id":"h-1","score":92,"max_score":100,"grading_mode":"official","confidence":0.94,"feedback":"很好","created_at":"2026-08-21T00:00:00Z"}
        ]
        """#
        let session = Self.mockSession { request in
            guard request.url?.path == "/api/v1/workspaces/ws-1/homeworks/h-1/grading-results" else {
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
            historyRequestCount += 1
            Thread.sleep(forTimeInterval: 0.03)
            return Self.response(request, status: 200, body: historyJSON)
        }
        let latest = GradingResult(
            id: "g-new",
            workspaceId: "ws-1",
            homeworkId: "h-1",
            questionId: nil,
            studentUserId: nil,
            score: 92,
            maxScore: 100,
            gradingMode: "official",
            confidence: 0.94,
            feedback: "很好",
            createdAt: "2026-08-21T00:00:00Z"
        )
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedHomeworkId = "h-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业", latestGradingResult: latest)]
        model.lastGradingTask = TaskItem(
            id: "old-task",
            workspaceId: "ws-1",
            taskType: "grade_homework",
            status: "succeeded",
            result: .object(["grading_mode": .string("provisional"), "confidence": .number(0.1)]),
            progress: 100
        )

        #expect(model.gradingModeLabel == localized("grading.mode.official"))
        #expect(model.gradingConfidence == 0.94)
        #expect(model.gradingResults.isEmpty)

        model.loadGradingHistory()
        model.loadGradingHistory()
        try await Self.waitUntil { !model.isGradingHistoryLoading && model.gradingResults.count == 2 }
        #expect(historyRequestCount == 1)
        #expect(model.gradingResults.map(\.id) == ["g-new", "g-old"])

        model.loadGradingHistory()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(historyRequestCount == 1)

        model.loadGradingHistory(force: true)
        try await Self.waitUntil { !model.isGradingHistoryLoading && historyRequestCount == 2 }
    }

    @Test @MainActor func gradingCompletion_refreshesHomeworkLatestResultAndLoadedHistory() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var historyRequestCount = 0
        let oldResult = #"{"id":"g-old","workspace_id":"ws-1","homework_id":"h-1","score":70,"max_score":100,"grading_mode":"provisional","created_at":"2026-08-19T00:00:00Z"}"#
        let newResult = #"{"id":"g-new","workspace_id":"ws-1","homework_id":"h-1","score":95,"max_score":100,"grading_mode":"official","confidence":0.96,"feedback":"优秀","created_at":"2026-08-21T00:00:00Z"}"#
        let homeworkJSON = "{\"id\":\"h-1\",\"workspace_id\":\"ws-1\",\"title\":\"作业\",\"status\":\"graded\",\"max_score\":100,\"metadata\":{},\"created_by_user_id\":\"u\",\"created_at\":\"\",\"updated_at\":\"\",\"latest_grading_result\":\(newResult)}"
        let session = Self.mockSession { request in
            let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
            switch key {
            case "GET /api/v1/workspaces/ws-1/homeworks/h-1/grading-results":
                historyRequestCount += 1
                return Self.response(
                    request,
                    status: 200,
                    body: historyRequestCount == 1 ? "[\(oldResult)]" : "[\(newResult),\(oldResult)]"
                )
            case "POST /api/v1/workspaces/ws-1/homeworks/h-1/grade":
                return Self.response(
                    request,
                    status: 202,
                    body: #"{"id":"grade-task","workspace_id":"ws-1","task_type":"grade_homework","status":"succeeded","payload":{},"result":{},"progress":100,"created_at":"","updated_at":""}"#
                )
            case "GET /api/v1/workspaces/ws-1/homeworks":
                return Self.response(request, status: 200, body: "[\(homeworkJSON)]")
            case "GET /api/v1/workspaces/ws-1/documents",
                 "GET /api/v1/workspaces/ws-1/homeworks/h-1/references",
                 "GET /api/v1/workspaces/ws-1/learning-units":
                return Self.response(request, status: 200, body: "[]")
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.selectedHomeworkId = "h-1"
        model.homeworks = [HomeworkItem(id: "h-1", workspaceId: "ws-1", title: "作业")]

        model.loadGradingHistory()
        try await Self.waitUntil { !model.isGradingHistoryLoading && model.gradingResults.first?.id == "g-old" }
        model.gradeSelectedHomework()
        try await Self.waitUntil {
            !model.isHomeworkLoading
                && !model.isGradingHistoryLoading
                && model.latestGradingResult?.id == "g-new"
                && model.gradingResults.first?.id == "g-new"
        }

        #expect(historyRequestCount == 2)
        #expect(model.gradingModeLabel == localized("grading.mode.official"))
        #expect(model.gradingConfidence == 0.96)
    }

    @Test @MainActor func serverURLs_persistAcrossModelInstances() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        let model = NotePatchViewModel(settings: settings)
        model.apiBaseURLText = "https://api.example.test/"
        model.tusBaseURLText = "https://tus.example.test/files"
        model.saveServerURLs()

        let restored = NotePatchViewModel(settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)))
        #expect(restored.apiBaseURLText == "https://api.example.test")
        #expect(restored.tusBaseURLText == "https://tus.example.test/files/")
    }

    @Test @MainActor func serverURLDraft_survivesUnrelatedSessionUpdates() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        defer {
            settings.clearSession()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let activeSession = SavedSession(
            baseURL: "https://api.old.test",
            tusBaseURL: "https://files.old.test/files/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u",
            email: "u@test",
            fullName: nil,
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        settings.saveSession(activeSession)
        let networkSession = Self.mockSession { request in
            #expect(request.url?.path == "/api/v1/auth/preferences")
            return Self.response(
                request,
                status: 200,
                body: #"{"id":"u","email":"u@test","is_active":true,"ai_history_enabled":false,"created_at":""}"#
            )
        }
        let model = NotePatchViewModel(settings: settings, backendSession: networkSession, tusSession: networkSession)
        model.apiBaseURLText = "https://api.draft.test/custom"
        model.tusBaseURLText = "https://files.draft.test/uploads"

        model.updateAIHistoryEnabled(false)
        try await Self.waitUntil { !model.isAIPreferenceUpdating }

        #expect(model.apiBaseURLText == "https://api.draft.test/custom")
        #expect(model.tusBaseURLText == "https://files.draft.test/uploads")
        #expect(model.session?.aiHistoryEnabled == false)
    }

    @Test @MainActor func authenticatedServerURLs_saveAndRestoreFromNewModel() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        defer {
            settings.clearSession()
            defaults.removePersistentDomain(forName: suiteName)
        }
        settings.saveSession(
            SavedSession(
                baseURL: "https://api.old.test",
                tusBaseURL: "https://files.old.test/files/",
                accessToken: "a",
                refreshToken: "r",
                expiresAt: "x",
                userId: "u",
                email: "u@test",
                fullName: nil,
                selectedWorkspaceId: "ws-1",
                aiHistoryEnabled: true
            )
        )
        let model = NotePatchViewModel(settings: settings)
        model.apiBaseURLText = "https://api.new.test/root/"
        model.tusBaseURLText = "https://files.new.test/uploads"
        model.saveServerURLs()

        let restored = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        )
        #expect(restored.apiBaseURLText == "https://api.new.test/root")
        #expect(restored.tusBaseURLText == "https://files.new.test/uploads/")
        #expect(restored.session?.baseURL == "https://api.new.test/root")
        #expect(restored.session?.tusBaseURL == "https://files.new.test/uploads/")
    }

    @Test @MainActor func gradingViewModel_validatesAndFiltersCandidates() throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)))
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.searchKnowledge()
        #expect(model.errorMessage == localized("knowledge.error.query_required"))

        let documents = try JSONDecoder.notepatch.decode(
            [LearningDocumentItem].self,
            from: Data(Self.gradingDocumentsJSON.utf8)
        )
        model.gradingDocuments = documents
        model.homeworkReferences = [HomeworkReferenceItem(id: "r-1", workspaceId: "ws-1", homeworkId: "h-1", documentId: "answer-1", referenceType: "answer_key", createdAt: "")]
        #expect(model.homeworkDocumentCandidates.map(\.id) == ["homework-1"])
        #expect(model.referenceDocumentCandidates.map(\.id) == ["rubric-1"])

        model.selectedHomeworkId = "h-1"
        model.homeworkMaxScoreText = "0"
        model.saveGradingConfig()
        #expect(model.errorMessage == localized("Maximum score must be greater than 0."))
    }

    @Test @MainActor func uiTestEmail_entersEphemeralWorkbenchWithoutNetwork() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        var requestCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(settings: settings, backendSession: session, tusSession: session)
        model.emailText = "  UiTeSt  "
        model.passwordText = ""
        model.authenticate(register: false)

        #expect(model.isOfflineTestMode)
        #expect(model.session?.email == "uitest")
        #expect(model.selectedWorkspaceId == "ui-workspace")
        #expect(model.workspaces.first?.name == "My Workspace")
        #expect(model.statusMessage == localized("operation.offline_test_mode"))
        #expect(settings.loadSession() == nil)
        #expect(requestCount == 0)

        await model.restoreIfNeeded()
        model.handleScenePhase(.active)
        model.loadChatHistory()
        model.loadLearningDashboard()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(requestCount == 0)

        model.logout()
        #expect(model.session == nil)
        #expect(!model.isOfflineTestMode)
        #expect(settings.loadSession() == nil)
        #expect(requestCount == 0)

        model.emailText = "uitest"
        model.passwordText = ""
        model.authenticate(register: true)
        #expect(model.session == nil)
        #expect(model.errorMessage == localized("auth.error.credentials_required"))
    }

    @Test @MainActor func htmlNotesAndFlashcards_decodeLatestContractAndGenerationStates() throws {
        let unit = try JSONDecoder.notepatch.decode(
            LearningUnit.self,
            from: Data(#"{"id":"unit-1","workspace_id":"ws-1","title":"代数","subject":"数学","grade_level":"七年级","topic":"方程","metadata":{"term":"fall"},"knowledge_revision":4,"attempt_revision":2,"notes_generated_revision":3,"note_generation_due_at":"2026-07-14T01:00:00Z","created_at":"","updated_at":""}"#.utf8)
        )
        let note = try JSONDecoder.notepatch.decode(
            StudyNoteVersion.self,
            from: Data(#"{"id":"note-1","workspace_id":"ws-1","learning_unit_id":"unit-1","task_id":"task-1","version_no":3,"title":"代数笔记","html_object_key":"notes/note.html","json_object_key":"notes/note.json","highlighted_html_object_key":"notes/highlighted.html","highlight_map_object_key":null,"knowledge_point_ids":["kp-1"],"source_document_ids":["doc-1"],"source_mistake_ids":[],"source_version_id":"note-0","edited_by_user_id":"u-1","edit_origin":"user","edit_summary":"补充例题","metadata":{"theme":"blue"},"created_at":"","download_urls":{"highlighted_html":"https://download.test/highlighted.html","html":"https://download.test/note.html"}}"#.utf8)
        )
        let detail = try JSONDecoder.notepatch.decode(
            FlashcardDeckDetail.self,
            from: Data(#"{"deck":{"id":"deck-1","workspace_id":"ws-1","learning_unit_id":"unit-1","study_note_version_id":"note-1","task_id":"task-2","version_no":2,"attempt_revision":2,"weighting_config":{"error_multiplier":1.5},"metadata":{},"created_at":"2026-07-14T01:00:00Z"},"cards":[{"id":"card-1","knowledge_point_id":"kp-1","front":"什么是一元一次方程？","back":"只含一个未知数且最高次数为 1 的方程。","priority_score":1.75,"priority_factors":{"base":1,"error_pressure":0.5,"recent_correct_streak":2},"source_refs":[{"document_id":"doc-1"}],"difficulty":"medium","rank":1,"created_at":"2026-07-14T01:00:00Z"}]}"#.utf8)
        )

        #expect(unit.knowledgeRevision == 4)
        #expect(unit.notesGeneratedRevision == 3)
        #expect(StudyNoteGroup(learningUnit: unit, notes: [StudyNoteListItem(learningUnit: unit, note: note)]).generationState == .generating)
        #expect(note.preferredHTMLDownloadURL == "https://download.test/highlighted.html")
        #expect(note.knowledgePointIds == ["kp-1"])
        #expect(detail.deck.attemptRevision == 2)
        #expect(detail.cards.first?.priorityFactors["recent_correct_streak"] == .number(2))

        let noKnowledge = LearningUnit(id: "u0", title: "空", knowledgeRevision: 0, notesGeneratedRevision: 0)
        let ready = LearningUnit(id: "u1", title: "完成", knowledgeRevision: 2, notesGeneratedRevision: 2)
        #expect(StudyNoteGroup(learningUnit: noKnowledge, notes: []).generationState == .noKnowledge)
        #expect(StudyNoteGroup(learningUnit: ready, notes: []).generationState == .unavailable)
        #expect(StudyNoteGroup(learningUnit: ready, notes: [StudyNoteListItem(learningUnit: ready, note: note)]).generationState == .ready)
    }

    @Test @MainActor func noteDownloadAndFlashcardRequests_matchLatestOpenAPI() async throws {
        var requests: [URLRequest] = []
        let session = Self.mockSession { request in
            requests.append(request)
            let path = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            } ?? ""
            switch path {
            case "/api/v1/workspaces/ws%2F1/learning-units/unit%2F1/notes/note%2F1/download-url":
                return Self.response(request, status: 200, body: #"{"note_version_id":"note/1","learning_unit_id":"unit/1","kind":"highlighted_html","filename":"note.html","expires_in":900,"download_url":"https://download.test/note.html"}"#)
            case "/api/v1/workspaces/ws%2F1/learning-units/unit%2F1/flashcard-decks":
                return Self.response(request, status: 200, body: #"[{"id":"deck/1","workspace_id":"ws/1","learning_unit_id":"unit/1","study_note_version_id":"note/1","version_no":1,"attempt_revision":0,"weighting_config":{},"metadata":{},"created_at":""}]"#)
            case "/api/v1/workspaces/ws%2F1/learning-units/unit%2F1/flashcard-decks/latest",
                 "/api/v1/workspaces/ws%2F1/learning-units/unit%2F1/flashcard-decks/deck%2F1":
                return Self.response(request, status: 200, body: #"{"deck":{"id":"deck/1","workspace_id":"ws/1","learning_unit_id":"unit/1","study_note_version_id":"note/1","version_no":1,"attempt_revision":0,"weighting_config":{},"metadata":{},"created_at":""},"cards":[]}"#)
            default:
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "a", refreshToken: "r", session: session)
        let download = try await client.getStudyNoteDownloadURL(
            workspaceId: "ws/1",
            learningUnitId: "unit/1",
            noteVersionId: "note/1",
            kind: .highlightedHTML
        )
        let decks = try await client.listFlashcardDecks(workspaceId: "ws/1", learningUnitId: "unit/1")
        _ = try await client.getLatestFlashcardDeck(workspaceId: "ws/1", learningUnitId: "unit/1")
        _ = try await client.getFlashcardDeck(workspaceId: "ws/1", learningUnitId: "unit/1", deckId: "deck/1")

        #expect(download.kind == "highlighted_html")
        #expect(decks.first?.id == "deck/1")
        #expect(requests.first?.url?.query == "kind=highlighted_html&expires_seconds=900")
        #expect(requests[1].url?.query == "page=1&page_size=100")
    }

    @Test @MainActor func noteReaderRequestsRenderedHTMLAndKeepsRawHTMLForEditing() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var requestedHosts: [String] = []
        let session = Self.mockSession { request in
            requestedHosts.append(request.url?.host ?? "")
            if request.url?.path == "/api/v1/workspaces/ws-1/learning-units/u-1/notes/n-1/download-url" {
                return Self.response(request, status: 200, body: #"{"note_version_id":"n-1","learning_unit_id":"u-1","kind":"rendered_html","filename":"note.html","expires_in":900,"download_url":"/api/v1/assets/study-notes/render?token=fresh"}"#)
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "https://tus.test", accessToken: "a", refreshToken: "r", expiresAt: "", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        let unit = LearningUnit(id: "u-1", title: "Unit", knowledgeRevision: 1, notesGeneratedRevision: 1)
        let note = StudyNoteVersion(id: "n-1", learningUnitId: "u-1", versionNo: 1, title: "Note", htmlObjectKey: "h", jsonObjectKey: "j", highlightedHTMLObjectKey: "hh", downloadURLs: ["highlighted_html": "https://expired.test/note.html"])
        let item = StudyNoteListItem(learningUnit: unit, note: note)
        model.studyNoteGroups = [StudyNoteGroup(learningUnit: unit, notes: [item])]

        model.openStudyNote(item)
        try await Self.waitUntil { !model.isStudyNoteLoading }

        #expect(model.studyNoteHTML == nil)
        #expect(model.studyNoteRenderedURL?.absoluteString == "https://api.test/api/v1/assets/study-notes/render?token=fresh")
        #expect(requestedHosts == ["api.test"])
    }

    @Test @MainActor func htmlSecurityShellBlocksExecutableAndExternalContent() {
        let document = HTMLNoteSecurity.readerDocument(bodyHTML: "<script>alert(1)</script><img src='https://tracker.test/a.png'><p>Safe</p>")
        #expect(document.contains("default-src 'none'"))
        #expect(document.contains("script-src 'none'"))
        #expect(document.contains("img-src data:"))
        #expect(HTMLNoteSecurity.editorUserScript.contains("name.startsWith('on')"))
        #expect(HTMLNoteSecurity.editorUserScript.contains("blockedTags"))
        #expect(HTMLNoteSecurity.hasVisibleContent("<p><br></p>") == false)
        #expect(HTMLNoteSecurity.hasVisibleContent("<p>Visible</p>"))
    }

    @Test func latexMathRendererConvertsCommonNoteFormulasToMathML() throws {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            Issue.record("LaTeX renderer JavaScript failed: \(exception?.toString() ?? "unknown error")")
        }
        context.evaluateScript(LatexMathSupport.renderingScript)
        let renderer = try #require(context.objectForKeyedSubscript("__notePatchLatexToMathMLString"))

        let inline = try #require(renderer.call(withArguments: [#"\frac{a_1}{b^2}=\sqrt{x}+\alpha"#, false])?.toString())
        #expect(inline.contains("<math"))
        #expect(inline.contains("display=\"inline\""))
        #expect(inline.contains("<mfrac>"))
        #expect(inline.contains("<msub>"))
        #expect(inline.contains("<msup>"))
        #expect(inline.contains("<msqrt>"))
        #expect(inline.contains("&#x03B1;"))

        let display = try #require(renderer.call(withArguments: [#"\sum_{i=1}^{n} i"#, true])?.toString())
        #expect(display.contains("display=\"block\""))
        #expect(display.contains("<munderover>"))

        let matrix = try #require(renderer.call(withArguments: [#"\begin{pmatrix}a & b \\ c & d\end{pmatrix}"#, true])?.toString())
        #expect(matrix.contains("<mtable>"))
        #expect(matrix.contains("<mtr>"))
        #expect(matrix.contains("<mtd>"))

        #expect(!LatexMathSupport.renderingScript.contains("https://"))
        #expect(!LatexMathSupport.renderingScript.contains("fetch("))
        #expect(!LatexMathSupport.renderingScript.contains("XMLHttpRequest"))
        #expect(!LatexMathSupport.renderingScript.contains("script.src"))
    }

    @Test @MainActor func noteWebViewRendersLatexWithPageJavaScriptDisabled() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        LatexMathSupport.install(into: configuration)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        let probe = TestWebViewNavigationProbe()
        let document = HTMLNoteSecurity.readerDocument(
            bodyHTML: #"<p>Inline: \(\frac{a}{b}=x^2\)</p><p>$$\sum_{i=1}^{n} i$$</p>"#
        )
        try await probe.load(document, in: webView)

        let mathCount = try #require(try await evaluateJavaScript("document.querySelectorAll('math').length", in: webView) as? Int)
        let fractionCount = try #require(try await evaluateJavaScript("document.querySelectorAll('mfrac').length", in: webView) as? Int)
        let displayCount = try #require(try await evaluateJavaScript("document.querySelectorAll('math[display=block]').length", in: webView) as? Int)
        let externalResourceCount = try #require(try await evaluateJavaScript("performance.getEntriesByType('resource').length", in: webView) as? Int)

        #expect(mathCount == 2)
        #expect(fractionCount == 1)
        #expect(displayCount == 1)
        #expect(externalResourceCount == 0)
    }

    @Test @MainActor func noteWebViewRendersBackendFormulaContainersAsMathML() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        LatexMathSupport.install(into: configuration)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        let probe = TestWebViewNavigationProbe()
        let document = HTMLNoteSecurity.readerDocument(
            bodyHTML: #"""
            <p class="np-formula">V = π(1.5)<sup>2</sup>(4) + (1/3)π(1.5)<sup>2</sup>(2) = 10.5π m<sup>3</sup></p>
            <p class="np-formula">l = sqrt(1.5² + 2²) = 2.5 m</p>
            """#
        )
        try await probe.load(document, in: webView)

        let mathCount = try #require(try await evaluateJavaScript("document.querySelectorAll('.np-formula > math').length", in: webView) as? Int)
        let superscriptCount = try #require(try await evaluateJavaScript("document.querySelectorAll('.np-formula msup').length", in: webView) as? Int)
        let squareRootCount = try #require(try await evaluateJavaScript("document.querySelectorAll('.np-formula msqrt').length", in: webView) as? Int)
        let rawSuperscriptCount = try #require(try await evaluateJavaScript("document.querySelectorAll('.np-formula sup').length", in: webView) as? Int)

        #expect(mathCount == 2)
        #expect(superscriptCount >= 4)
        #expect(squareRootCount == 1)
        #expect(rawSuperscriptCount == 0)
    }

    @Test @MainActor func offlineFlashcardsFlipAndNavigateWithoutNetwork() async throws {
        let suiteName = "NotePatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var requestCount = 0
        let session = Self.mockSession { request in
            requestCount += 1
            return Self.response(request, status: 500, body: #"{"detail":"unexpected"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session
        )
        model.emailText = "uitest"
        model.authenticate(register: false)
        model.selectedTab = .notes
        model.selectedLearningSection = .flashcards
        model.ensureContentForSelectedTabLoaded()

        #expect(model.currentFlashcard?.id == "card-1")
        model.flipCurrentFlashcard()
        #expect(model.isFlashcardShowingBack)
        model.showNextFlashcard()
        #expect(model.currentFlashcard?.id == "card-2")
        #expect(!model.isFlashcardShowingBack)
        #expect(requestCount == 0)
    }

    @Test func productionModelsIgnoreScanningMetadataAndDecodeCurrentFields() throws {
        let document = try JSONDecoder.notepatch.decode(
            LearningDocumentItem.self,
            from: Data(#"{"id":"doc-1","workspace_id":"ws-1","uploaded_by":"user-1","original_filename":"a.docx","file_type":"docx","document_kind":"courseware","storage_backend":"s3","bucket":"notepatch","object_key":"documents/a.docx","status":"scanning","scan_status":"pending","scan_message":"queued","scanned_at":null,"detected_mime_type":"application/vnd.openxmlformats-officedocument.wordprocessingml.document","created_at":"","updated_at":"","artifacts":[]}"#.utf8)
        )
        let unit = try JSONDecoder.notepatch.decode(
            LearningUnit.self,
            from: Data(#"{"id":"unit-1","workspace_id":"ws-1","title":"Unit","merge_status":"rebuilding","merged_into_id":null}"#.utf8)
        )
        let note = try JSONDecoder.notepatch.decode(
            StudyNoteVersion.self,
            from: Data(#"{"id":"note-1","learning_unit_id":"unit-1","version_no":1,"title":"Note","html_object_key":"n.html","json_object_key":"n.json","download_urls":{"rendered_html":"/api/v1/assets/study-notes/render?token=x","html":"https://download.test/raw.html"}}"#.utf8)
        )
        let event = try JSONDecoder.notepatch.decode(
            TaskEventItem.self,
            from: Data(#"{"id":"event-1","task_id":"task-1","sequence_no":7,"event_type":"progress","level":"info","message":"running","progress":40,"created_at":""}"#.utf8)
        )

        #expect(document.status == "scanning")
        #expect(unit.mergeStatus == "rebuilding")
        #expect(note.preferredDownloadURL == "/api/v1/assets/study-notes/render?token=x")
        #expect(event.sequenceNo == 7)
        #expect(event.workspaceId.isEmpty)
    }

    @Test func taskSSEParserHandlesChunksHeartbeatMultilineAndDone() throws {
        var parser = TaskSSEParser()
        let first = ": heartbeat\n\nid: 9\nevent: task_event\ndata: {\"id\":\"event-9\",\"task_id\":\"task-1\",\"sequence_no\":9,"
        let second = "\"event_type\":\"progress\",\"level\":\"info\",\"message\":\"Working\",\"progress\":75,\"data\":{},\"created_at\":\"\"}\n\nevent: done\ndata: {\"task_id\":\"task-1\",\"status\":\"succeeded\",\"last_sequence_no\":9}\n\n"
        #expect(try parser.append(first, workspaceId: "ws-1").isEmpty)
        let frames = try parser.append(second, workspaceId: "ws-1")

        #expect(frames.count == 2)
        guard case .taskEvent(let event) = frames[0] else {
            Issue.record("Expected task event")
            return
        }
        #expect(event.workspaceId == "ws-1")
        #expect(event.sequenceNo == 9)
        #expect(event.progress == 75)
        guard case .done(let completion) = frames[1] else {
            Issue.record("Expected done frame")
            return
        }
        #expect(completion.status == "succeeded")
        #expect(completion.lastSequenceNo == 9)
    }

    @Test func taskSSEByteDecoderEmitsFramesBeforeConnectionFinishes() throws {
        var decoder = TaskSSEByteDecoder()
        let event = "id: 1\nevent: task_event\ndata: {\"id\":\"event-1\",\"task_id\":\"task-1\",\"sequence_no\":1,\"event_type\":\"chat_answer_delta\",\"level\":\"info\",\"message\":\"chunk\",\"progress\":null,\"data\":{\"delta\":\"Hello\"},\"created_at\":\"\"}\n\n"
        var eventFrames: [TaskSSEFrame] = []
        for byte in event.utf8 {
            eventFrames.append(contentsOf: try decoder.append(byte, workspaceId: "ws-1"))
        }

        #expect(eventFrames.count == 1)
        guard case .taskEvent(let taskEvent) = eventFrames[0] else {
            Issue.record("Expected an event before the stream finishes")
            return
        }
        #expect(taskEvent.eventType == "chat_answer_delta")
        #expect(taskEvent.data?.objectStringValue(for: "delta") == "Hello")

        let done = "event: done\ndata: {\"task_id\":\"task-1\",\"status\":\"succeeded\",\"last_sequence_no\":1}\n\n"
        var doneFrames: [TaskSSEFrame] = []
        for byte in done.utf8 {
            doneFrames.append(contentsOf: try decoder.append(byte, workspaceId: "ws-1"))
        }

        #expect(doneFrames.count == 1)
        guard case .done(let completion) = doneFrames[0] else {
            Issue.record("Expected done before the stream finishes")
            return
        }
        #expect(completion.status == "succeeded")
        #expect(try decoder.finish(workspaceId: "ws-1").isEmpty)
    }

    @Test @MainActor func taskSSERequestUsesBearerAcceptAndLastEventID() throws {
        let client = LearningBackendClient(
            baseURL: "https://api.test",
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )
        let request = try client.taskEventStreamRequest(
            workspaceId: "ws/1",
            taskId: "task/1",
            lastEventID: 42
        )

        let encodedPath = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
        }
        #expect(request.httpMethod == "GET")
        #expect(encodedPath == "/api/v1/workspaces/ws%2F1/tasks/task%2F1/events/stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Last-Event-ID") == "42")
    }

    @Test @MainActor func mergeLearningUnitsRequestEscapesPathAndUsesFixedBody() async throws {
        var capturedRequest: URLRequest?
        let session = Self.mockSession { request in
            capturedRequest = request
            return Self.response(request, status: 202, body: Self.taskJSON)
        }
        let client = LearningBackendClient(baseURL: "https://api.test", accessToken: "a", refreshToken: "r", session: session)
        _ = try await client.mergeLearningUnits(
            workspaceId: "ws/1",
            targetLearningUnitId: "target/1",
            sourceLearningUnitIds: ["source-1", "source-2"]
        )

        #expect(capturedRequest?.httpMethod == "POST")
        let request = try #require(capturedRequest)
        let encodedPath = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath }
        #expect(encodedPath == "/api/v1/workspaces/ws%2F1/learning-units/target%2F1/merge")
        let body = try #require(Self.requestBodyData(request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["source_learning_unit_ids"] as? [String] == ["source-1", "source-2"])
    }

    @Test @MainActor func legacyScanMetadataDoesNotGateFrontendActions() throws {
        let suiteName = "NotePatchScanRules.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        )
        let legacyDocument = try JSONDecoder.notepatch.decode(
            LearningDocumentItem.self,
            from: Data(#"{"id":"legacy","workspace_id":"ws","uploaded_by":"u","original_filename":"bad.pdf","file_type":"pdf","document_kind":"homework","storage_backend":"s3","bucket":"files","object_key":"bad.pdf","status":"failed","scan_status":"infected","scan_message":"malware","created_at":"","updated_at":"","artifacts":[]}"#.utf8)
        )

        #expect(model.canProcessDocument(legacyDocument))
        #expect(model.canDownloadDocument(legacyDocument))
    }

    @Test @MainActor func learningUnitMergeValidatesSourcesAndPreservesSelectionOnFailure() async throws {
        let suiteName = "NotePatchMergeState.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var mergeRequestCount = 0
        let session = Self.mockSession { request in
            if request.httpMethod == "POST", request.url?.path.hasSuffix("/learning-units/unit-0/merge") == true {
                mergeRequestCount += 1
                return Self.response(request, status: 500, body: #"{"detail":"merge unavailable"}"#)
            }
            return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
        }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(
            baseURL: "https://api.test", tusBaseURL: "https://tus.test/", accessToken: "a",
            refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test",
            fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true
        )
        model.selectedWorkspaceId = "ws-1"
        model.learningUnits = (0...51).map {
            LearningUnit(id: "unit-\($0)", workspaceId: "ws-1", title: "Unit \($0)")
        }

        model.beginLearningUnitMerge()
        model.setLearningUnitMergeTarget("unit-0")
        model.toggleLearningUnitMergeSource("unit-0")
        #expect(model.mergeSourceLearningUnitIds.isEmpty)
        for index in 1...51 {
            model.toggleLearningUnitMergeSource("unit-\(index)")
        }
        #expect(model.mergeSourceLearningUnitIds.count == 50)
        model.requestLearningUnitMergeConfirmation()
        #expect(model.isLearningUnitMergeConfirmationPresented)

        let selectedSources = model.mergeSourceLearningUnitIds
        model.confirmLearningUnitMerge()
        try await Self.waitUntil { !model.isLearningUnitMerging }
        #expect(mergeRequestCount == 1)
        #expect(model.mergeSourceLearningUnitIds == selectedSources)
        #expect(model.isLearningUnitMergePresented)
        #expect(model.errorMessage == "merge unavailable")
    }
}

private extension NotePatchTests {
    static let gradingDocumentsJSON =
        """
        [
          {"id":"homework-1","workspace_id":"ws-1","uploaded_by":"u","title":"作业","original_filename":"homework.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"homework","storage_backend":"seaweedfs","bucket":"b","object_key":"homework","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"answer-1","workspace_id":"ws-1","uploaded_by":"u","title":"答案","original_filename":"answer.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"answer_key","storage_backend":"seaweedfs","bucket":"b","object_key":"answer","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"rubric-1","workspace_id":"ws-1","uploaded_by":"u","title":"标准","original_filename":"rubric.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"rubric","storage_backend":"seaweedfs","bucket":"b","object_key":"rubric","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"ready","created_at":"","updated_at":"","artifacts":[]},
          {"id":"pending-1","workspace_id":"ws-1","uploaded_by":"u","title":"未处理答案","original_filename":"pending.pdf","mime_type":"application/pdf","file_size":10,"file_type":"pdf","document_kind":"answer_key","storage_backend":"seaweedfs","bucket":"b","object_key":"pending","upload_id":null,"tus_upload_url":null,"sha256":null,"status":"uploaded","created_at":"","updated_at":"","artifacts":[]}
        ]
        """

    static let uploadSessionJSON =
        """
        {
          "document": {
            "id": "doc-1",
            "workspace_id": "ws-1",
            "uploaded_by": "user-1",
            "title": "exam.pdf",
            "original_filename": "exam.pdf",
            "mime_type": "application/pdf",
            "file_size": 12345,
            "file_type": "pdf",
            "document_kind": "homework",
            "storage_backend": "seaweedfs",
            "bucket": "notepatch",
            "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf",
            "upload_id": null,
            "tus_upload_url": null,
            "sha256": null,
            "status": "created",
            "metadata": {},
            "created_at": "2026-07-09T10:00:00Z",
            "updated_at": "2026-07-09T10:00:00Z",
            "artifacts": []
          },
          "upload_session": {
            "id": "upload-1",
            "workspace_id": "ws-1",
            "user_id": "user-1",
            "document_id": "doc-1",
            "tus_upload_id": null,
            "tus_upload_url": null,
            "bucket": "notepatch",
            "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf",
            "status": "created",
            "expires_at": null,
            "created_at": "2026-07-09T10:00:00Z",
            "updated_at": "2026-07-09T10:00:00Z"
          },
          "tus_endpoint": "http://192.168.100.123:1080/files/",
          "tus_metadata": {
            "workspace_id": "ws-1",
            "document_id": "doc-1"
          },
          "tus_metadata_header": "workspace_id d3MtMQ==,document_id ZG9jLTE=",
          "bucket": "notepatch",
          "object_key": "workspaces/ws-1/documents/doc-1/original/exam.pdf"
        }
        """

    static let taskJSON =
        """
        {
          "id": "task-1",
          "workspace_id": "ws-1",
          "task_type": "document_processing_pipeline",
          "status": "queued",
          "resource_type": "document",
          "resource_id": "doc-1",
          "payload": {},
          "result": null,
          "error_message": null,
          "progress": 0,
          "created_at": "2026-07-09T10:00:00Z",
          "updated_at": "2026-07-09T10:00:00Z",
          "started_at": null,
          "finished_at": null
        }
        """

    static func purgeTaskJSON(
        id: String,
        status: String,
        progress: Int,
        errorMessage: String? = nil
    ) -> String {
        let errorValue = errorMessage.map { "\"\($0)\"" } ?? "null"
        return
            """
            {
              "id": "\(id)",
              "workspace_id": "ws-1",
              "task_type": "purge_document",
              "status": "\(status)",
              "resource_type": "document",
              "resource_id": "doc-1",
              "payload": {"document_id":"doc-1"},
              "result": null,
              "error_message": \(errorValue),
              "progress": \(progress),
              "cancel_requested_at": null,
              "created_at": "",
              "updated_at": ""
            }
            """
    }

    static let completedDocumentJSON =
        """
        {
          "id": "doc-completed",
          "workspace_id": "ws-1",
          "uploaded_by": "user-1",
          "title": "Uploaded",
          "original_filename": "uploaded.pdf",
          "mime_type": "application/pdf",
          "file_size": 0,
          "file_type": "pdf",
          "document_kind": "other",
          "storage_backend": "s3",
          "bucket": "notepatch",
          "object_key": "workspaces/ws-1/documents/doc-completed/original/uploaded.pdf",
          "upload_id": null,
          "tus_upload_url": null,
          "sha256": null,
          "status": "uploaded",
          "created_at": "",
          "updated_at": "",
          "artifacts": []
        }
        """

    @MainActor
    static func waitUntil(
        attempts: Int = 200,
        condition: () -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw LearningBackendError("Timed out waiting for test condition")
    }

    static func mockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(_ request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.test")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    @MainActor
    static func profileModelForTests(
        defaults: UserDefaults,
        session: URLSession,
        service: String
    ) -> NotePatchViewModel {
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: service))
        let savedSession = SavedSession(
            baseURL: "https://api.test",
            tusBaseURL: "https://tus.test/files/",
            accessToken: "a",
            refreshToken: "r",
            expiresAt: "x",
            userId: "u-1",
            email: "alice@example.com",
            fullName: "Alice",
            selectedWorkspaceId: "ws-1",
            aiHistoryEnabled: true
        )
        settings.saveSession(savedSession)
        let model = NotePatchViewModel(
            settings: settings,
            backendSession: session,
            tusSession: session
        )
        model.session = savedSession
        model.userProfileState.apply(UserProfileSnapshot(
            profile: UserProfile(
                id: "u-1",
                name: "Alice",
                email: "alice@example.com",
                avatarURL: nil,
                profileVersion: 1,
                reauthenticationRequired: false
            ),
            etag: "\"profile-1\""
        ))
        return model
    }

    static func requestBodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer {
            stream.close()
        }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }

    @MainActor
    private func evaluateJavaScript(_ source: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
    @Test @MainActor func openClawChatAttachment_saveToWorkspaceToggleIsSent() async throws {
        for expectedSaveToWorkspace in [true, false] {
            let suiteName = "NotePatchChatAttachmentSaveTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            var capturedBody: [String: Any]?
            let session = Self.mockSession { request in
                let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
                switch key {
                case "POST /api/v1/workspaces/ws-1/documents/upload-session":
                    if let body = Self.requestBodyData(request) {
                        capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                    }
                    return Self.response(request, status: 500, body: #"{"detail":"storage unavailable"}"#)
                default:
                    return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
                }
            }
            let cacheDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NotePatchChatAttachmentSaveTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cacheDirectory) }
            let imageURL = cacheDirectory.appendingPathComponent("question.png")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            try #require(image.pngData()).write(to: imageURL)
            let file = LocalUploadFile(url: imageURL, filename: "question.png", mimeType: "image/png")

            let model = NotePatchViewModel(
                settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
                backendSession: session,
                tusSession: session,
                cacheDirectory: cacheDirectory,
                taskEventStreamingEnabled: false
            )
            model.session = SavedSession(
                baseURL: "https://api.test",
                tusBaseURL: "https://tus.test/files/",
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: "x",
                userId: "user-1",
                email: "user@example.test",
                fullName: nil,
                selectedWorkspaceId: "ws-1",
                aiHistoryEnabled: true
            )
            model.selectedWorkspaceId = "ws-1"
            model.openClawComposerState.text = "分析图片"
            model.openClawComposerState.attachments = [file]
            model.openClawComposerState.saveAttachmentsToWorkspace = expectedSaveToWorkspace

            #expect(model.startOpenClawChat(prompt: model.openClawComposerState.text, attachments: [file]))
            try await Self.waitUntil { !model.isOpenClawSending }

            #expect(capturedBody?["document_kind"] as? String == "chat_attachment")
            #expect(capturedBody?["save_to_documents"] as? Bool == expectedSaveToWorkspace)
        }
    }

@MainActor
private final class TestWebViewNavigationProbe: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

    @Test @MainActor func openClawChatAttachment_sendsDocumentIdOnly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotePatchChatAttachmentContractTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("question.png")
        try Data().write(to: fileURL)
        let file = LocalUploadFile(url: fileURL, filename: "question.png", mimeType: "image/png")

        var chatBody: [String: Any]?
        let session = Self.mockSession { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("POST", "/api/v1/workspaces/ws-1/documents/upload-session"):
                return Self.response(request, status: 201, body: Self.uploadSessionJSON)
            case ("POST", "/api/v1/workspaces/ws-1/documents/complete-upload"):
                return Self.response(request, status: 200, body: Self.completedDocumentJSON)
            case ("POST", "/api/v1/workspaces/ws-1/ai/chat"):
                if let body = Self.requestBodyData(request) {
                    chatBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                }
                return Self.response(request, status: 201, body: Self.taskJSON)
            case ("GET", "/api/v1/workspaces/ws-1/tasks/task-1"):
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"id":"task-1","workspace_id":"ws-1","task_type":"chat","status":"succeeded","resource_type":"conversation","resource_id":null,"payload":{},"result":{"answer":"done"},"error_message":null,"progress":100,"created_at":"","updated_at":""}"#
                )
            case ("GET", "/api/v1/workspaces/ws-1/tasks/task-1/events"):
                return Self.response(request, status: 200, body: "[]")
            default:
                if request.httpMethod == "POST", request.url?.host == "192.168.100.123", path.hasPrefix("/files") {
                    let response = HTTPURLResponse(
                        url: try #require(request.url),
                        statusCode: 201,
                        httpVersion: nil,
                        headerFields: ["Location": "upload-1", "Tus-Resumable": "1.0.0"]
                    )!
                    return (response, Data())
                }
                return Self.response(request, status: 500, body: #"{"detail":"unexpected request"}"#)
            }
        }
        let suiteName = "NotePatchChatAttachmentContractTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = NotePatchViewModel(
            settings: SettingsStore(defaults: defaults, keychain: KeychainStore(service: suiteName)),
            backendSession: session,
            tusSession: session,
            cacheDirectory: root,
            taskEventStreamingEnabled: false
        )
        model.session = SavedSession(baseURL: "https://api.test", tusBaseURL: "http://192.168.100.123:1080/files/", accessToken: "a", refreshToken: "r", expiresAt: "x", userId: "u", email: "u@test", fullName: nil, selectedWorkspaceId: "ws-1", aiHistoryEnabled: true)
        model.selectedWorkspaceId = "ws-1"
        model.openClawComposerState.attachments = [file]

        #expect(model.startOpenClawChat(prompt: "这是什么？", attachments: [file]))
        try await Self.waitUntil { !model.isOpenClawSending }

        let input = try #require(chatBody?["input"] as? [String: Any])
        let attachments = try #require(input["attachments"] as? [[String: Any]])
        #expect(attachments.count == 1)
        #expect(attachments.first?["document_id"] as? String == "doc-completed")
        #expect(attachments.first?.count == 1)
    }

}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: LearningBackendError("Missing mock handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
