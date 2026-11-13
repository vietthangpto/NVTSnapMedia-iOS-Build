import Foundation

public enum DownloadStatus: String, Codable, Sendable {
    case queued = "QUEUED"
    case downloading = "DOWNLOADING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

public struct DownloadRecord: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var mediaId: String
    public var platform: MediaPlatform
    public var title: String
    public var authorName: String
    public var thumbnailUrl: String
    public var sourceUrl: String
    public var downloadUrl: String
    public var audioStreamUrl: String
    public var fallbackUrl: String
    public var clientUserAgent: String
    public var cookieHeader: String
    public var refererHeader: String
    public var demuxAudioFromVideo: Bool
    /// Relative path inside Documents (e.g. "NVTSnapMedia/Movies/file.mp4") or file URL string
    public var localRelativePath: String
    /// Optional PHAsset localIdentifier when saved into iOS Photos album "NVTSnapMedia"
    public var photoAssetId: String
    public var fileName: String
    public var mimeType: String
    public var mediaCategory: MediaCategory
    public var qualityTag: String
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var speedBytesPerSec: Int64
    public var status: DownloadStatus
    public var errorMessage: String
    public var createdAt: Int64

    public init(
        id: Int64,
        mediaId: String,
        platform: MediaPlatform,
        title: String,
        authorName: String,
        thumbnailUrl: String,
        sourceUrl: String,
        downloadUrl: String,
        audioStreamUrl: String = "",
        fallbackUrl: String = "",
        clientUserAgent: String = "",
        cookieHeader: String = "",
        refererHeader: String = "",
        demuxAudioFromVideo: Bool = false,
        localRelativePath: String = "",
        photoAssetId: String = "",
        fileName: String,
        mimeType: String,
        mediaCategory: MediaCategory,
        qualityTag: String,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        speedBytesPerSec: Int64 = 0,
        status: DownloadStatus,
        errorMessage: String = "",
        createdAt: Int64
    ) {
        self.id = id
        self.mediaId = mediaId
        self.platform = platform
        self.title = title
        self.authorName = authorName
        self.thumbnailUrl = thumbnailUrl
        self.sourceUrl = sourceUrl
        self.downloadUrl = downloadUrl
        self.audioStreamUrl = audioStreamUrl
        self.fallbackUrl = fallbackUrl
        self.clientUserAgent = clientUserAgent
        self.cookieHeader = cookieHeader
        self.refererHeader = refererHeader
        self.demuxAudioFromVideo = demuxAudioFromVideo
        self.localRelativePath = localRelativePath
        self.photoAssetId = photoAssetId
        self.fileName = fileName
        self.mimeType = mimeType
        self.mediaCategory = mediaCategory
        self.qualityTag = qualityTag
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0.0), 1.0)
    }

    /// Resolves `localRelativePath` against the current iOS app sandbox `Documents` directory.
    public var resolvedFileURL: URL? {
        guard !localRelativePath.isEmpty else { return nil }
        if localRelativePath.hasPrefix("file://"), let url = URL(string: localRelativePath) {
            return url
        }
        if localRelativePath.hasPrefix("/") {
            return URL(fileURLWithPath: localRelativePath)
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(localRelativePath)
    }
}
