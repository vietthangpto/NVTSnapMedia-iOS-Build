import AVFoundation
import SwiftUI
import UIKit

public final class MediaThumbnailCache: @unchecked Sendable {
    public static let shared = MediaThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    public func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    public func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Loads remote cover thumbnails (with browser User-Agent / Referer headers so Facebook & TikTok CDNs succeed)
/// or generates local file / video frame thumbnails with in-memory caching.
public struct RemoteMediaImage: View {
    public let urlString: String
    public var localFileURL: URL?
    public var contentMode: ContentMode
    public var placeholderSystemIcon: String
    public var referer: String
    public var cookie: String

    @Environment(\.appPalette) private var palette
    @State private var loadedImage: UIImage?
    @State private var didFail: Bool = false

    private static let browserUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    public init(
        urlString: String,
        localFileURL: URL? = nil,
        contentMode: ContentMode = .fill,
        placeholderSystemIcon: String = "play.rectangle.fill",
        referer: String = "",
        cookie: String = ""
    ) {
        self.urlString = urlString
        self.localFileURL = localFileURL
        self.contentMode = contentMode
        self.placeholderSystemIcon = placeholderSystemIcon
        self.referer = referer
        self.cookie = cookie
    }

    private var cacheKey: String {
        if let local = localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return "local::\(local.lastPathComponent)"
        }
        return "remote::\(urlString)"
    }

    public var body: some View {
        ZStack {
            palette.surfaceVariant

            if let image = loadedImage ?? MediaThumbnailCache.shared.image(for: cacheKey) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: placeholderSystemIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant.opacity(didFail ? 0.45 : 0.7))
            }
        }
        .task(id: cacheKey) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        let key = cacheKey
        if let cached = MediaThumbnailCache.shared.image(for: key) {
            loadedImage = cached
            return
        }

        // 1. Try local file first if present on disk
        if let local = localFileURL, FileManager.default.fileExists(atPath: local.path) {
            if let localImg = await Self.generateLocalPreview(at: local) {
                MediaThumbnailCache.shared.store(localImg, for: key)
                loadedImage = localImg
                return
            }
        }

        // 2. Load remote cover URL
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            didFail = true
            return
        }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 18
            req.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
            req.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            if !referer.isEmpty {
                req.setValue(referer, forHTTPHeaderField: "Referer")
            }
            if !cookie.isEmpty {
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let uiImage = UIImage(data: data) {
                MediaThumbnailCache.shared.store(uiImage, for: key)
                loadedImage = uiImage
                didFail = false
            } else {
                didFail = true
            }
        } catch {
            didFail = true
        }
    }

    private nonisolated static func generateLocalPreview(at fileURL: URL) async -> UIImage? {
        let ext = fileURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic"].contains(ext) {
            if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                return img
            }
        }
        if ["mp4", "mov", "m4v"].contains(ext) {
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let sampleTime = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
