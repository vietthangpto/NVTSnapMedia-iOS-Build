import Foundation

public struct ExtractionError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public final class UnifiedMediaExtractor: Sendable {
    public let youTubeService: YouTubeExtractorService
    public let facebookService: FacebookExtractorService
    public let tikTokService: TikTokExtractorService

    public init(
        youTubeService: YouTubeExtractorService = YouTubeExtractorService(),
        facebookService: FacebookExtractorService = FacebookExtractorService(),
        tikTokService: TikTokExtractorService = TikTokExtractorService()
    ) {
        self.youTubeService = youTubeService
        self.facebookService = facebookService
        self.tikTokService = tikTokService
    }

    /// Automatically detects whether `rawInput` belongs to YouTube, Facebook, or TikTok
    /// and dispatches extraction to the corresponding specialized Ultra-HD engine.
    public func extractMedia(
        rawInput: String,
        customEndpoint: String = ""
    ) async -> Result<UnifiedMediaInfo, Error> {
        guard let detected = MediaUrlDetector.detect(rawInput) else {
            return .failure(
                ExtractionError(
                    "Không nhận diện được liên kết hợp lệ. Hãy dán đường dẫn từ YouTube, Facebook hoặc TikTok."
                )
            )
        }

        switch detected.platform {
        case .youtube:
            return await youTubeService.extractMedia(rawUrl: detected.cleanUrl, customEndpoint: customEndpoint)
        case .facebook:
            return await facebookService.extractMedia(rawInput: detected.cleanUrl, customEndpoint: customEndpoint)
        case .tiktok:
            return await tikTokService.extractMedia(rawInput: detected.cleanUrl, customEndpoint: customEndpoint)
        }
    }
}
