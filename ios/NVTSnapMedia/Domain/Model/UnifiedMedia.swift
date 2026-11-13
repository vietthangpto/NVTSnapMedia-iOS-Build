import Foundation

public enum MediaPlatform: String, CaseIterable, Codable, Sendable, Identifiable {
    case youtube = "YOUTUBE"
    case facebook = "FACEBOOK"
    case tiktok = "TIKTOK"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .tiktok: return "TikTok"
        }
    }

    public var filePrefix: String {
        switch self {
        case .youtube: return "YTB"
        case .facebook: return "FB"
        case .tiktok: return "TIK"
        }
    }
}

public enum MediaCategory: String, CaseIterable, Codable, Sendable {
    case video = "VIDEO"
    case audio = "AUDIO"
    case image = "IMAGE"
}

public enum VideoResolutionTier: Int, CaseIterable, Comparable, Sendable {
    case sd = 0
    case sd480p = 1
    case hd720p = 2
    case fhd1080p = 3
    case qhd2k = 4
    case uhd4k = 5

    public var rank: Int { rawValue }

    public var isAboveHd: Bool {
        rank >= VideoResolutionTier.fhd1080p.rank
    }

    public static func < (lhs: VideoResolutionTier, rhs: VideoResolutionTier) -> Bool {
        lhs.rank < rhs.rank
    }

    public static func classify(width: Int, height: Int, qualityHint: String = "") -> VideoResolutionTier {
        let hint = qualityHint.lowercased()
        if hint.contains("2160") || hint.contains("4k") || hint.contains("uhd") {
            return .uhd4k
        }
        if hint.contains("1440") || hint.contains("2k") || hint.contains("qhd") {
            return .qhd2k
        }
        if hint.contains("1080") || hint.contains("fhd") {
            return .fhd1080p
        }
        if hint.contains("720") {
            return .hd720p
        }
        if hint.contains("480") {
            return .sd480p
        }
        if width > 0 && height > 0 {
            let longSide = max(width, height)
            let shortSide = min(width, height)
            if longSide >= 3200 || shortSide >= 2000 { return .uhd4k }
            if longSide >= 2400 || shortSide >= 1350 { return .qhd2k }
            if longSide >= 1800 || shortSide >= 1000 { return .fhd1080p }
            if longSide >= 1200 || shortSide >= 700 { return .hd720p }
            if longSide >= 800 || shortSide >= 460 { return .sd480p }
            return .sd
        }
        if hint.contains("hd") {
            return .hd720p
        }
        return .sd
    }
}

public struct DownloadQualityOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var labelVi: String
    public var labelEn: String
    public var subtitleVi: String
    public var subtitleEn: String
    public var badge: String
    public var url: String
    public var audioStreamUrl: String
    public var fallbackUrl: String
    public var clientUserAgent: String
    public var cookieHeader: String
    public var refererHeader: String
    public var mediaCategory: MediaCategory
    public var extensionName: String
    public var mimeType: String
    public var sizeBytes: Int64
    public var width: Int
    public var height: Int
    public var fps: Int
    public var codecLabel: String
    public var isUltraHd: Bool
    public var isPrimary: Bool
    public var isWatermark: Bool
    public var demuxAudioFromVideo: Bool
    public var imageIndex: Int?

    public init(
        id: String,
        labelVi: String,
        labelEn: String,
        subtitleVi: String = "",
        subtitleEn: String = "",
        badge: String,
        url: String,
        audioStreamUrl: String = "",
        fallbackUrl: String = "",
        clientUserAgent: String = "",
        cookieHeader: String = "",
        refererHeader: String = "",
        mediaCategory: MediaCategory,
        extensionName: String,
        mimeType: String,
        sizeBytes: Int64 = 0,
        width: Int = 0,
        height: Int = 0,
        fps: Int = 0,
        codecLabel: String = "",
        isUltraHd: Bool = false,
        isPrimary: Bool = false,
        isWatermark: Bool = false,
        demuxAudioFromVideo: Bool = false,
        imageIndex: Int? = nil
    ) {
        self.id = id
        self.labelVi = labelVi
        self.labelEn = labelEn
        self.subtitleVi = subtitleVi
        self.subtitleEn = subtitleEn
        self.badge = badge
        self.url = url
        self.audioStreamUrl = audioStreamUrl
        self.fallbackUrl = fallbackUrl
        self.clientUserAgent = clientUserAgent
        self.cookieHeader = cookieHeader
        self.refererHeader = refererHeader
        self.mediaCategory = mediaCategory
        self.extensionName = extensionName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.fps = fps
        self.codecLabel = codecLabel
        self.isUltraHd = isUltraHd
        self.isPrimary = isPrimary
        self.isWatermark = isWatermark
        self.demuxAudioFromVideo = demuxAudioFromVideo
        self.imageIndex = imageIndex
    }
}

public struct UnifiedMediaInfo: Equatable, Sendable {
    public var id: String
    public var platform: MediaPlatform
    public var originalUrl: String
    public var title: String
    public var authorName: String
    public var authorHandle: String
    public var authorAvatarUrl: String
    public var coverUrl: String
    public var durationSeconds: Int
    public var viewCountText: String
    public var likeCountText: String
    public var musicTitle: String
    public var isVerticalShort: Bool
    public var isImageGallery: Bool
    public var galleryImages: [String]
    public var previewStreamUrl: String
    public var previewUserAgent: String
    public var maxResolutionBadge: String
    public var downloadOptions: [DownloadQualityOption]
    public var providerName: String

    public init(
        id: String,
        platform: MediaPlatform,
        originalUrl: String,
        title: String,
        authorName: String,
        authorHandle: String = "",
        authorAvatarUrl: String = "",
        coverUrl: String,
        durationSeconds: Int = 0,
        viewCountText: String = "",
        likeCountText: String = "",
        musicTitle: String = "",
        isVerticalShort: Bool = false,
        isImageGallery: Bool = false,
        galleryImages: [String] = [],
        previewStreamUrl: String = "",
        previewUserAgent: String = "",
        maxResolutionBadge: String = "",
        downloadOptions: [DownloadQualityOption],
        providerName: String
    ) {
        self.id = id
        self.platform = platform
        self.originalUrl = originalUrl
        self.title = title
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorAvatarUrl = authorAvatarUrl
        self.coverUrl = coverUrl
        self.durationSeconds = durationSeconds
        self.viewCountText = viewCountText
        self.likeCountText = likeCountText
        self.musicTitle = musicTitle
        self.isVerticalShort = isVerticalShort
        self.isImageGallery = isImageGallery
        self.galleryImages = galleryImages
        self.previewStreamUrl = previewStreamUrl
        self.previewUserAgent = previewUserAgent
        self.maxResolutionBadge = maxResolutionBadge
        self.downloadOptions = downloadOptions
        self.providerName = providerName
    }
}
