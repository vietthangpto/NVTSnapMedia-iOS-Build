import Foundation

public enum YouTubeUrlParser {

    private static let httpUrlPattern = #"https?://[^\s<>"'()\[\]]+"#
    private static let bareYtbUrlPattern = #"(?<![A-Za-z0-9./:-])(?:(?:www|m|music|gaming)\.)?(?:youtube\.com|youtu\.be|youtube-nocookie\.com)/[^\s<>"'()\[\]]+"#
    private static let validVideoIdPattern = #"^[A-Za-z0-9_-]{11}$"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;!?)]}\"'")

    private static let allowedExactHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "gaming.youtube.com",
        "youtu.be",
        "www.youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com"
    ]

    public static func extractUrl(_ rawText: String?) -> String? {
        guard let rawText, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for groups in RegexUtils.allMatches(in: rawText, pattern: httpUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let cleaned = cleanTrailingPunctuation(rawMatch)
            if isGenuineYouTubeUrl(cleaned), extractVideoIdFromCleanUrl(cleaned) != nil {
                return cleaned
            }
        }

        for groups in RegexUtils.allMatches(in: rawText, pattern: bareYtbUrlPattern, options: [.caseInsensitive]) {
            guard let rawMatch = groups.first else { continue }
            let candidate = "https://\(cleanTrailingPunctuation(rawMatch))"
            if isGenuineYouTubeUrl(candidate), extractVideoIdFromCleanUrl(candidate) != nil {
                return candidate
            }
        }

        return nil
    }

    public static func isGenuineYouTubeUrl(_ url: String) -> Bool {
        guard let comps = RegexUtils.safeURLComponents(url),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased() else {
            return false
        }
        return allowedExactHosts.contains(host)
    }

    public static func extractVideoId(_ url: String?) -> String? {
        guard let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = extractVideoIdFromCleanUrl(trimmed) {
            return id
        }
        guard let extractedUrl = extractUrl(trimmed) else { return nil }
        return extractVideoIdFromCleanUrl(extractedUrl)
    }

    public static func isShortsUrl(_ url: String?) -> Bool {
        guard let url, !url.isEmpty else { return false }
        return url.range(of: "/shorts/", options: .caseInsensitive) != nil
    }

    public static func toCanonicalWatchUrl(videoId: String, isShorts: Bool = false) -> String {
        if isShorts {
            return "https://www.youtube.com/shorts/\(videoId)"
        } else {
            return "https://www.youtube.com/watch?v=\(videoId)"
        }
    }

    private static func extractVideoIdFromCleanUrl(_ url: String) -> String? {
        guard !url.isEmpty, !url.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        let lower = url.lowercased()
        let normalized: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            normalized = url
        } else {
            normalized = "https://\(url)"
        }
        guard isGenuineYouTubeUrl(normalized),
              let comps = RegexUtils.safeURLComponents(normalized) else {
            return nil
        }

        let host = comps.host?.lowercased() ?? ""
        let pathSegments = comps.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }

        if host == "youtu.be" || host == "www.youtu.be" {
            if let candidate = pathSegments.first, isValidVideoId(candidate) {
                return candidate
            }
        }

        let queryMap = parseQueryParams(comps.percentEncodedQuery)
        if let vParam = queryMap["v"] ?? queryMap["vi"], isValidVideoId(vParam) {
            return vParam
        }

        if pathSegments.count >= 2 {
            let prefix = pathSegments[0].lowercased()
            let validPrefixes: Set<String> = ["shorts", "live", "embed", "v", "e", "watch", "clip"]
            if validPrefixes.contains(prefix) {
                let candidate = pathSegments[1]
                if isValidVideoId(candidate) {
                    return candidate
                }
            }
        }

        if let uParam = queryMap["u"], !uParam.isEmpty,
           let decodedU = uParam.removingPercentEncoding, !decodedU.isEmpty {
            if let groups = RegexUtils.firstMatch(in: decodedU, pattern: #"[?&]v=([A-Za-z0-9_-]{11})"#),
               groups.count > 1, isValidVideoId(groups[1]) {
                return groups[1]
            }
        }

        return nil
    }

    private static func isValidVideoId(_ candidate: String) -> Bool {
        RegexUtils.matchesEntire(candidate, pattern: validVideoIdPattern)
    }

    private static func parseQueryParams(_ rawQuery: String?) -> [String: String] {
        guard let rawQuery, !rawQuery.isEmpty else { return [:] }
        var out: [String: String] = [:]
        for pair in rawQuery.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = String(parts[0])
                let val = String(parts[1])
                if !key.isEmpty, out[key] == nil {
                    out[key] = val
                }
            }
        }
        return out
    }

    private static func cleanTrailingPunctuation(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.unicodeScalars.last, trailingPunctuation.contains(last) {
            result.unicodeScalars.removeLast()
        }
        return result
    }
}
