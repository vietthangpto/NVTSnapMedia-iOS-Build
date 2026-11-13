import Foundation

public enum RegexUtils {

    public static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return extractGroups(from: match, in: nsText)
    }

    public static func allMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).map {
            extractGroups(from: $0, in: nsText)
        }
    }

    public static func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        with templateOrTransform: (([String]) -> String)
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let groups = extractGroups(from: match, in: nsText)
            let replacement = templateOrTransform(groups)
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    public static func matchesEntire(
        _ text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return false
        }
        return match.range.location == 0 && match.range.length == nsText.length
    }

    public static func safeURLComponents(_ raw: String) -> URLComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        if let direct = URLComponents(string: trimmed) {
            return direct
        }
        let allowed = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#%/:@?&=[]!$'()*+,;"))
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) {
            return URLComponents(string: encoded)
        }
        return nil
    }

    private static func extractGroups(from match: NSTextCheckingResult, in nsText: NSString) -> [String] {
        var groups: [String] = []
        groups.reserveCapacity(match.numberOfRanges)
        for idx in 0..<match.numberOfRanges {
            let r = match.range(at: idx)
            if r.location != NSNotFound {
                groups.append(nsText.substring(with: r))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}
