import Foundation
import Combine

public enum ThemeMode: String, CaseIterable, Codable, Sendable {
    case dark = "DARK"
    case light = "LIGHT"
    case system = "SYSTEM"
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case vi = "VI"
    case en = "EN"
}

public enum PreferredQuality: String, CaseIterable, Codable, Sendable {
    case ultraHdMax = "ULTRA_HD_MAX"
    case fhd1080p = "FHD_1080P"
    case hdVideo = "HD_VIDEO"
    case sdVideo = "SD_VIDEO"
    case audioOnly = "AUDIO_ONLY"
}

public struct UserSettings: Equatable, Sendable {
    public var autoCheckClipboard: Bool
    public var autoDownloadOnShare: Bool
    public var preferredQuality: PreferredQuality
    public var themeMode: ThemeMode
    public var language: AppLanguage
    public var customEndpoint: String
    public var lastHandledClipboardUrl: String

    public init(
        autoCheckClipboard: Bool = true,
        autoDownloadOnShare: Bool = false,
        preferredQuality: PreferredQuality = .ultraHdMax,
        themeMode: ThemeMode = .dark,
        language: AppLanguage = .vi,
        customEndpoint: String = "",
        lastHandledClipboardUrl: String = ""
    ) {
        self.autoCheckClipboard = autoCheckClipboard
        self.autoDownloadOnShare = autoDownloadOnShare
        self.preferredQuality = preferredQuality
        self.themeMode = themeMode
        self.language = language
        self.customEndpoint = customEndpoint
        self.lastHandledClipboardUrl = lastHandledClipboardUrl
    }
}

@MainActor
public final class AppPreferences: ObservableObject {

    public static let appGroupIdentifier = "group.com.nvtsnapmedia.app"
    public static let pendingSharedTextKey = "nvtsnapmedia_pending_shared_text"

    private enum Keys {
        static let autoCheckClipboard = "auto_check_clipboard"
        static let autoDownloadOnShare = "auto_download_on_share"
        static let preferredQuality = "preferred_quality"
        static let themeMode = "theme_mode"
        static let language = "language"
        static let customEndpoint = "custom_endpoint"
        static let lastClipboardUrl = "last_clipboard_url"
    }

    @Published public private(set) var settings: UserSettings

    private let defaults: UserDefaults
    private let groupDefaults: UserDefaults?

    public init() {
        let std = UserDefaults.standard
        let grp = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.defaults = std
        self.groupDefaults = grp
        self.settings = Self.loadSettings(from: std)
    }

    private static func loadSettings(from store: UserDefaults) -> UserSettings {
        let autoClip = store.object(forKey: Keys.autoCheckClipboard) as? Bool ?? true
        let autoShare = store.object(forKey: Keys.autoDownloadOnShare) as? Bool ?? false
        let quality = store.string(forKey: Keys.preferredQuality)
            .flatMap(PreferredQuality.init(rawValue:)) ?? .ultraHdMax
        let theme = store.string(forKey: Keys.themeMode)
            .flatMap(ThemeMode.init(rawValue:)) ?? .dark
        let lang = store.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .vi
        let endpoint = store.string(forKey: Keys.customEndpoint) ?? ""
        let lastClip = store.string(forKey: Keys.lastClipboardUrl) ?? ""

        return UserSettings(
            autoCheckClipboard: autoClip,
            autoDownloadOnShare: autoShare,
            preferredQuality: quality,
            themeMode: theme,
            language: lang,
            customEndpoint: endpoint,
            lastHandledClipboardUrl: lastClip
        )
    }

    public func setAutoCheckClipboard(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.autoCheckClipboard)
        settings.autoCheckClipboard = enabled
    }

    public func setAutoDownloadOnShare(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.autoDownloadOnShare)
        groupDefaults?.set(enabled, forKey: Keys.autoDownloadOnShare)
        settings.autoDownloadOnShare = enabled
    }

    public func setPreferredQuality(_ quality: PreferredQuality) {
        defaults.set(quality.rawValue, forKey: Keys.preferredQuality)
        settings.preferredQuality = quality
    }

    public func setThemeMode(_ mode: ThemeMode) {
        defaults.set(mode.rawValue, forKey: Keys.themeMode)
        settings.themeMode = mode
    }

    public func setLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Keys.language)
        groupDefaults?.set(language.rawValue, forKey: Keys.language)
        settings.language = language
    }

    public func setCustomEndpoint(_ endpoint: String) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed, forKey: Keys.customEndpoint)
        settings.customEndpoint = trimmed
    }

    public func setLastHandledClipboardUrl(_ url: String) {
        defaults.set(url, forKey: Keys.lastClipboardUrl)
        settings.lastHandledClipboardUrl = url
    }

    /// Consumes any URL/text queued by the iOS Share Extension via App Group UserDefaults.
    public func consumePendingSharedTextFromAppGroup() -> String? {
        guard let grp = groupDefaults,
              let pending = grp.string(forKey: Self.pendingSharedTextKey),
              !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        grp.removeObject(forKey: Self.pendingSharedTextKey)
        grp.synchronize()
        return pending
    }
}
