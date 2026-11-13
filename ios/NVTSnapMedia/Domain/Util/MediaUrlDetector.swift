import Foundation

public struct DetectedMediaSource: Equatable, Sendable {
    public let platform: MediaPlatform
    public let cleanUrl: String

    public init(platform: MediaPlatform, cleanUrl: String) {
        self.platform = platform
        self.cleanUrl = cleanUrl
    }
}

public enum MediaUrlDetector {

    private static let httpTokenPattern = #"https?://[^\s<>"'()\[\]]+"#

    /// Automatically detects whether arbitrary user input (URL, clipboard text, or multi-line share caption)
    /// belongs to YouTube, Facebook, or TikTok, returning the normalized clean URL and exact platform.
    /// Also unwraps Facebook Messenger/Link-Shim (`l.facebook.com/l.php?u=...`) URLs so shared YouTube
    /// or TikTok links wrapped inside Facebook redirectors are routed to their true source engine.
    public static func detect(_ rawInput: String?) -> DetectedMediaSource? {
        guard let rawInput, !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // 1. Scan full http(s):// tokens in appearance order first
        let httpMatches = RegexUtils.allMatches(
            in: rawInput,
            pattern: httpTokenPattern,
            options: [.caseInsensitive]
        )
        for groups in httpMatches {
            guard let token = groups.first, !token.isEmpty else { continue }
            let rawCandidate = FacebookUrlParser.unwrapIfLinkShim(token)
            if let yt = YouTubeUrlParser.extractUrl(rawCandidate) {
                return DetectedMediaSource(platform: .youtube, cleanUrl: yt)
            }
            if let tik = TikTokUrlParser.extractUrl(rawCandidate) {
                return DetectedMediaSource(platform: .tiktok, cleanUrl: tik)
            }
            if let fb = FacebookUrlParser.extractUrl(rawCandidate) {
                return DetectedMediaSource(platform: .facebook, cleanUrl: fb)
            }
        }

        // 2. Fallback to bare domain links without scheme (e.g., youtu.be/..., fb.watch/..., vt.tiktok.com/...)
        if let yt = YouTubeUrlParser.extractUrl(rawInput) {
            return DetectedMediaSource(platform: .youtube, cleanUrl: yt)
        }
        if let tik = TikTokUrlParser.extractUrl(rawInput) {
            return DetectedMediaSource(platform: .tiktok, cleanUrl: tik)
        }
        if let fb = FacebookUrlParser.extractUrl(rawInput) {
            return DetectedMediaSource(platform: .facebook, cleanUrl: fb)
        }

        return nil
    }

    public static func isValidSupportedInput(_ rawInput: String?) -> Bool {
        detect(rawInput) != nil
    }

    public static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hrs > 0 {
            return String(format: Locale(identifier: "en_US_POSIX"), "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: Locale(identifier: "en_US_POSIX"), "%02d:%02d", mins, secs)
        }
    }

    public static func formatCompactCount(_ count: Int64) -> String {
        guard count > 0 else { return "" }
        let locale = Locale(identifier: "en_US_POSIX")
        if count >= 1_000_000_000 {
            return String(format: locale, "%.1fB", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: locale, "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: locale, "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    public static func formatCompactCountString(_ rawCount: String?) -> String {
        guard let trimmed = rawCount?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return ""
        }
        if let numeric = Int64(trimmed) {
            return formatCompactCount(numeric)
        }
        return trimmed
    }

    public static func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let locale = Locale(identifier: "en_US_POSIX")
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        if gb >= 1.0 {
            return String(format: locale, "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: locale, "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: locale, "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    public static func formatSpeed(_ bytesPerSec: Int64) -> String {
        guard bytesPerSec > 0 else { return "" }
        let locale = Locale(identifier: "en_US_POSIX")
        let mbPerSec = Double(bytesPerSec) / (1024.0 * 1024.0)
        if mbPerSec >= 1.0 {
            return String(format: locale, "%.1f MB/s", mbPerSec)
        } else {
            return String(format: locale, "%.0f KB/s", Double(bytesPerSec) / 1024.0)
        }
    }

    public static func sanitizeFileSegment(_ input: String, maxLen: Int = 26) -> String {
        let replaced = RegexUtils.replacingMatches(
            in: input,
            pattern: #"[^\p{L}\p{N}_-]+"#
        ) { _ in "_" }
        let cleaned = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !cleaned.isEmpty else { return "media" }
        if cleaned.count > maxLen {
            let prefix = String(cleaned.prefix(maxLen))
            let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return trimmed.isEmpty ? "media" : trimmed
        }
        return cleaned
    }
}
