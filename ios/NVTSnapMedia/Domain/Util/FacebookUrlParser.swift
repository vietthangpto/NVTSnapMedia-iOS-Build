import Foundation

public enum FacebookUrlParser {

    private static let httpUrlPattern = #"https?://[^\s<>"'()\[\]]+"#
    private static let bareFbUrlPattern = #"(?<![A-Za-z0-9./:-])(?:(?:www|m|web|mbasic|touch)\.facebook\.com|facebook\.com|fb\.watch|fb\.gg|fb\.com)/[^\s<>"'()\[\]]+"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}!?'\"")

    public static func extractUrl(_ rawInput: String?) -> String? {
        guard let rawInput, !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for groups in RegexUtils.allMatches(in: rawInput, pattern: httpUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let cleaned = cleanMatchedUrl(rawMatch)
            if isSupportedFacebookHost(cleaned) {
                let unwrapped = unwrapLinkShim(cleaned)
                if isSupportedFacebookHost(unwrapped), hasNonEmptyPathOrQuery(unwrapped) {
                    return unwrapped
                }
            }
        }

        for groups in RegexUtils.allMatches(in: rawInput, pattern: bareFbUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let candidate = cleanMatchedUrl("https://\(rawMatch)")
            if isSupportedFacebookHost(candidate), hasNonEmptyPathOrQuery(candidate) {
                return unwrapLinkShim(candidate)
            }
        }

        return nil
    }

    public static func unwrapIfLinkShim(_ rawUrl: String) -> String {
        unwrapLinkShim(rawUrl)
    }

    public static func toDesktopFacebookUrl(_ url: String) -> String {
        RegexUtils.replacingMatches(
            in: url,
            pattern: #"^https?://(?:m|mbasic|web|touch|business)\.facebook\.com/"#,
            options: [.caseInsensitive]
        ) { _ in
            "https://www.facebook.com/"
        }
    }

    public static func extractVideoId(_ url: String) -> String? {
        let patterns = [
            #"/reel/(\d+)"#,
            #"/videos/(?:[^/]+/)?(\d+)"#,
            #"[?&]v=(\d+)"#,
            #"story_fbid=(\d+)"#
        ]
        for pattern in patterns {
            if let groups = RegexUtils.firstMatch(in: url, pattern: pattern, options: [.caseInsensitive]),
               groups.count > 1, !groups[1].isEmpty {
                return groups[1]
            }
        }
        return nil
    }

    public static func isSupportedFacebookHost(_ url: String) -> Bool {
        guard let comps = RegexUtils.safeURLComponents(url),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased() else {
            return false
        }
        return host == "facebook.com" ||
            host.hasSuffix(".facebook.com") ||
            host == "fb.watch" ||
            host.hasSuffix(".fb.watch") ||
            host == "fb.gg" ||
            host.hasSuffix(".fb.gg") ||
            host == "fb.com" ||
            host.hasSuffix(".fb.com")
    }

    private static func unwrapLinkShim(_ url: String) -> String {
        let lower = url.lowercased()
        guard lower.contains("l.facebook.com/l.php") || lower.contains("lm.facebook.com/l.php") else {
            return url
        }
        guard let groups = RegexUtils.firstMatch(in: url, pattern: #"[?&]u=([^&]+)"#),
              groups.count > 1, !groups[1].isEmpty else {
            return url
        }
        return groups[1].removingPercentEncoding ?? url
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

    private static func hasNonEmptyPathOrQuery(_ url: String) -> Bool {
        guard let comps = RegexUtils.safeURLComponents(url) else { return false }
        let trimmedPath = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasQuery = !(comps.percentEncodedQuery ?? "").isEmpty
        return !trimmedPath.isEmpty || hasQuery
    }
}
