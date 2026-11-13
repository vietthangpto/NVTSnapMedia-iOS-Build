import Foundation

public enum TikTokUrlParser {

    private static let httpUrlPattern = #"https?://[^\s<>"'()\[\]]+"#
    private static let bareTikTokUrlPattern = #"(?<![A-Za-z0-9./:-])(?:(?:vt|vm|www|m)\.tiktok\.com|tiktok\.com|v\.douyin\.com)/[^\s<>"'()\[\]]+"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}!?'\"")

    public static func extractUrl(_ rawInput: String?) -> String? {
        guard let rawInput, !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for groups in RegexUtils.allMatches(in: rawInput, pattern: httpUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let cleaned = cleanMatchedUrl(rawMatch)
            if isSupportedTikTokHost(cleaned), hasNonEmptyPath(cleaned) {
                return cleaned
            }
        }

        for groups in RegexUtils.allMatches(in: rawInput, pattern: bareTikTokUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let cleaned = cleanMatchedUrl("https://\(rawMatch)")
            if isSupportedTikTokHost(cleaned), hasNonEmptyPath(cleaned) {
                return cleaned
            }
        }

        return nil
    }

    public static func isSupportedTikTokHost(_ url: String) -> Bool {
        guard let comps = RegexUtils.safeURLComponents(url),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased() else {
            return false
        }
        return host == "tiktok.com" ||
            host.hasSuffix(".tiktok.com") ||
            host == "tiktokv.com" ||
            host.hasSuffix(".tiktokv.com") ||
            host == "douyin.com" ||
            host.hasSuffix(".douyin.com")
    }

    private static func cleanMatchedUrl(_ rawUrl: String) -> String {
        var cleaned = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = cleaned.unicodeScalars.last, trailingPunctuation.contains(last) {
            cleaned.unicodeScalars.removeLast()
        }
        if cleaned.lowercased().hasPrefix("http://") {
            cleaned = "https://" + cleaned.dropFirst(7)
        }
        return cleaned
    }

    private static func hasNonEmptyPath(_ url: String) -> Bool {
        guard let comps = RegexUtils.safeURLComponents(url) else { return false }
        return !comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }
}
