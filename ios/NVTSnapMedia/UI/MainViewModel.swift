import Combine
import Foundation
import SwiftUI
import UIKit

public enum AppTab: Hashable, Sendable {
    case home
    case downloads
    case settings
}

public struct MediaViewerTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let platform: MediaPlatform
    public let category: MediaCategory
    public let streamOrFileURL: URL
    public let isLocalFile: Bool
    public let coverUrl: String
    public let userAgent: String
    public let referer: String
    public let cookie: String
    public let associatedRecord: DownloadRecord?

    public init(
        id: String,
        title: String,
        subtitle: String,
        platform: MediaPlatform,
        category: MediaCategory,
        streamOrFileURL: URL,
        isLocalFile: Bool,
        coverUrl: String = "",
        userAgent: String = "",
        referer: String = "",
        cookie: String = "",
        associatedRecord: DownloadRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.platform = platform
        self.category = category
        self.streamOrFileURL = streamOrFileURL
        self.isLocalFile = isLocalFile
        self.coverUrl = coverUrl
        self.userAgent = userAgent
        self.referer = referer
        self.cookie = cookie
        self.associatedRecord = associatedRecord
    }
}

@MainActor
public final class MainViewModel: ObservableObject {

    // MARK: - Published UI State

    @Published public var selectedTab: AppTab = .home
    @Published public var urlInput: String = ""
    @Published public private(set) var isExtracting: Bool = false
    @Published public private(set) var extractedMedia: UnifiedMediaInfo?
    @Published public private(set) var extractionError: String?
    @Published public private(set) var clipboardCandidate: DetectedMediaSource?

    // Library Filter & Search State
    @Published public var searchQuery: String = ""
    @Published public var platformFilter: MediaPlatform?
    @Published public var categoryFilter: MediaCategory?

    // Modals & Toasts
    @Published public var viewerTarget: MediaViewerTarget?
    @Published public var sharePayload: ShareSheetPayload?
    @Published public private(set) var toastMessage: String?

    // Dependencies
    public let preferences: AppPreferences
    public let database: DownloadDatabase
    public let downloadManager: MediaDownloadManager
    private let extractor: UnifiedMediaExtractor

    private var extractionTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastInspectedPasteboardCount: Int = -1
    private var cancellables = Set<AnyCancellable>()

    public init(
        preferences: AppPreferences,
        database: DownloadDatabase,
        downloadManager: MediaDownloadManager,
        extractor: UnifiedMediaExtractor = UnifiedMediaExtractor()
    ) {
        self.preferences = preferences
        self.database = database
        self.downloadManager = downloadManager
        self.extractor = extractor

        // Forward nested ObservableObject changes so SwiftUI views observing MainViewModel refresh immediately
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        database.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Derived Computed Properties

    public var currentStrings: AppStrings {
        stringsForLanguage(preferences.settings.language)
    }

    public var isVietnamese: Bool {
        preferences.settings.language == .vi
    }

    public var liveDetectedSource: DetectedMediaSource? {
        MediaUrlDetector.detect(urlInput)
    }

    public var activeDownloads: [DownloadRecord] {
        database.downloads.filter { $0.status == .downloading || $0.status == .queued }
    }

    public var activeDownloadsCount: Int {
        activeDownloads.count
    }

    public var filteredDownloads: [DownloadRecord] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return database.downloads.filter { item in
            if let pf = platformFilter, item.platform != pf {
                return false
            }
            if let cf = categoryFilter, item.mediaCategory != cf {
                return false
            }
            if !trimmedQuery.isEmpty {
                let haystack = "\(item.title) \(item.authorName) \(item.fileName) \(item.qualityTag)".lowercased()
                if !haystack.contains(trimmedQuery) {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Input, Clipboard & Share Handoff

    public func clearInputAndResult() {
        extractionTask?.cancel()
        isExtracting = false
        urlInput = ""
        extractedMedia = nil
        extractionError = nil
    }

    public func pasteFromClipboardAndAnalyze() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            showToast(currentStrings.emptyClipboardMsg)
            return
        }
        lastInspectedPasteboardCount = UIPasteboard.general.changeCount
        urlInput = raw
        if let detected = MediaUrlDetector.detect(raw) {
            preferences.setLastHandledClipboardUrl(detected.cleanUrl)
            clipboardCandidate = nil
            analyzeCurrentInput(autoDownloadPreferred: false)
        } else {
            showToast(currentStrings.invalidUrlMsg)
        }
    }

    public func useDetectedClipboardCandidate() {
        guard let candidate = clipboardCandidate else { return }
        urlInput = candidate.cleanUrl
        preferences.setLastHandledClipboardUrl(candidate.cleanUrl)
        clipboardCandidate = nil
        analyzeCurrentInput(autoDownloadPreferred: false)
    }

    public func dismissClipboardCandidate() {
        if let candidate = clipboardCandidate {
            preferences.setLastHandledClipboardUrl(candidate.cleanUrl)
        }
        clipboardCandidate = nil
    }

    /// Non-intrusively checks if iOS clipboard holds a probable URL before reading its text,
    /// avoiding unnecessary pasteboard prompts when regular non-URL text is copied.
    public func checkClipboardOnForeground() {
        // First consume any pending Share Extension payload from App Group
        if consumeAppGroupShareIfPresent() {
            return
        }

        guard preferences.settings.autoCheckClipboard else { return }
        let pb = UIPasteboard.general
        guard pb.hasStrings || pb.hasURLs else { return }
        guard pb.changeCount != lastInspectedPasteboardCount else { return }
        lastInspectedPasteboardCount = pb.changeCount

        Task { @MainActor in
            do {
                let patterns = try await pb.detectPatterns(for: [.probableWebURL])
                guard patterns.contains(.probableWebURL) else { return }
                guard let content = pb.string,
                      let detected = MediaUrlDetector.detect(content) else {
                    return
                }
                let currentClean = MediaUrlDetector.detect(self.urlInput)?.cleanUrl
                if detected.cleanUrl != self.preferences.settings.lastHandledClipboardUrl
                    && detected.cleanUrl != currentClean {
                    self.clipboardCandidate = detected
                }
            } catch {
                // Ignore pasteboard pattern detection failure
            }
        }
    }

    @discardableResult
    public func consumeAppGroupShareIfPresent() -> Bool {
        guard let pending = preferences.consumePendingSharedTextFromAppGroup() else {
            return false
        }
        handleIncomingSharedText(pending)
        return true
    }

    public func handleIncomingURL(_ url: URL) {
        // Check if Share Extension also wrote full text to App Group; discard duplicate so it won't fire twice
        _ = preferences.consumePendingSharedTextFromAppGroup()

        if url.scheme?.lowercased() == "nvtsnapmedia" {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if comps.host?.lowercased() == "downloads" {
                    selectedTab = .downloads
                    return
                }
                if let sharedParam = comps.queryItems?.first(where: { $0.name == "text" || $0.name == "url" })?.value,
                   !sharedParam.isEmpty {
                    handleIncomingSharedText(sharedParam)
                    return
                }
            }
        }
        handleIncomingSharedText(url.absoluteString)
    }

    public func handleIncomingSharedText(_ rawText: String) {
        selectedTab = .home
        if let detected = MediaUrlDetector.detect(rawText) {
            urlInput = detected.cleanUrl
            preferences.setLastHandledClipboardUrl(detected.cleanUrl)
            clipboardCandidate = nil
            analyzeCurrentInput(autoDownloadPreferred: preferences.settings.autoDownloadOnShare)
        } else {
            urlInput = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            showToast(currentStrings.invalidUrlMsg)
        }
    }

    // MARK: - Media Extraction & Download Dispatch

    public func analyzeCurrentInput(autoDownloadPreferred: Bool = false) {
        let raw = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detected = MediaUrlDetector.detect(raw) else {
            extractionError = currentStrings.invalidUrlMsg
            showToast(currentStrings.invalidUrlMsg)
            triggerNotificationHaptic(.warning)
            return
        }

        extractionTask?.cancel()
        isExtracting = true
        extractionError = nil
        extractedMedia = nil
        urlInput = detected.cleanUrl
        preferences.setLastHandledClipboardUrl(detected.cleanUrl)

        let customEndpoint = preferences.settings.customEndpoint
        let extractorRef = self.extractor

        extractionTask = Task { [weak self] in
            let result = await extractorRef.extractMedia(
                rawInput: detected.cleanUrl,
                customEndpoint: customEndpoint
            )
            guard !Task.isCancelled, let self else { return }

            self.isExtracting = false
            switch result {
            case .success(let info):
                self.extractedMedia = info
                self.extractionError = nil
                self.triggerImpactHaptic(.medium)

                if autoDownloadPreferred {
                    if info.isImageGallery && info.downloadOptions.contains(where: { $0.mediaCategory == .image }) {
                        self.downloadAllGalleryPhotos(media: info)
                    } else if let chosen = Self.pickPreferredOption(
                        from: info,
                        preferred: self.preferences.settings.preferredQuality
                    ) {
                        self.startSingleDownload(media: info, option: chosen)
                    }
                }

            case .failure(let err):
                self.extractedMedia = nil
                self.extractionError = err.localizedDescription
                self.triggerNotificationHaptic(.error)
            }
        }
    }

    public func startSingleDownload(media: UnifiedMediaInfo, option: DownloadQualityOption) {
        triggerImpactHaptic(.light)
        showToast(currentStrings.startedDownloadMsg)
        Task {
            await downloadManager.enqueueDownload(media: media, option: option)
        }
    }

    public func downloadAllGalleryPhotos(media: UnifiedMediaInfo) {
        let imageOptions = media.downloadOptions.filter { $0.mediaCategory == .image }
        guard !imageOptions.isEmpty else { return }
        triggerImpactHaptic(.medium)
        showToast(currentStrings.startedDownloadMsg)
        Task {
            for opt in imageOptions {
                await downloadManager.enqueueDownload(media: media, option: opt)
            }
        }
    }

    public static func pickPreferredOption(
        from media: UnifiedMediaInfo,
        preferred: PreferredQuality
    ) -> DownloadQualityOption? {
        let options = media.downloadOptions
        guard !options.isEmpty else { return nil }

        if preferred == .audioOnly {
            return options.first(where: { $0.mediaCategory == .audio }) ?? options.first
        }

        let cleanVideos = options.filter { $0.mediaCategory == .video && !$0.isWatermark }
        let videoPool = cleanVideos.isEmpty ? options.filter { $0.mediaCategory == .video } : cleanVideos
        guard !videoPool.isEmpty else {
            return options.first
        }

        switch preferred {
        case .ultraHdMax:
            return videoPool.first(where: { $0.isPrimary }) ?? videoPool.first
        case .fhd1080p:
            return videoPool.first(where: {
                VideoResolutionTier.classify(width: $0.width, height: $0.height, qualityHint: $0.badge) == .fhd1080p
            }) ?? videoPool.first(where: {
                VideoResolutionTier.classify(width: $0.width, height: $0.height, qualityHint: $0.badge) <= .fhd1080p
            }) ?? videoPool.first
        case .hdVideo:
            return videoPool.first(where: {
                VideoResolutionTier.classify(width: $0.width, height: $0.height, qualityHint: $0.badge) == .hd720p
            }) ?? videoPool.first(where: {
                VideoResolutionTier.classify(width: $0.width, height: $0.height, qualityHint: $0.badge) <= .hd720p
            }) ?? videoPool.last
        case .sdVideo:
            return videoPool.last(where: { !$0.isUltraHd }) ?? videoPool.last
        case .audioOnly:
            return options.first
        }
    }

    // MARK: - Preview, Share, Album & Platform Launchers

    public func openExtractedPreview(_ media: UnifiedMediaInfo, initialGalleryIndex: Int? = nil) {
        if media.isImageGallery, !media.galleryImages.isEmpty {
            let idx = min(max(initialGalleryIndex ?? 0, 0), media.galleryImages.count - 1)
            if let imgURL = URL(string: media.galleryImages[idx]) {
                viewerTarget = MediaViewerTarget(
                    id: "preview_img_\(media.id)_\(idx)",
                    title: media.title,
                    subtitle: "@\(media.authorName)",
                    platform: media.platform,
                    category: .image,
                    streamOrFileURL: imgURL,
                    isLocalFile: false,
                    coverUrl: media.coverUrl
                )
            }
            return
        }

        // Prefer a progressive MP4 (no separate audio stream) so remote preview plays with full sound
        let progressiveOption = media.downloadOptions.first(where: {
            $0.mediaCategory == .video && $0.audioStreamUrl.isEmpty && !$0.isWatermark
        }) ?? media.downloadOptions.first(where: {
            $0.mediaCategory == .video && $0.audioStreamUrl.isEmpty
        })

        let previewString = !media.previewStreamUrl.isEmpty
            ? media.previewStreamUrl
            : (progressiveOption?.url ?? media.downloadOptions.first?.url ?? "")

        guard let streamURL = URL(string: previewString) else { return }

        viewerTarget = MediaViewerTarget(
            id: "preview_\(media.id)",
            title: media.title,
            subtitle: media.authorName,
            platform: media.platform,
            category: progressiveOption?.mediaCategory ?? .video,
            streamOrFileURL: streamURL,
            isLocalFile: false,
            coverUrl: media.coverUrl,
            userAgent: !media.previewUserAgent.isEmpty
                ? media.previewUserAgent
                : (progressiveOption?.clientUserAgent ?? ""),
            referer: progressiveOption?.refererHeader ?? "",
            cookie: progressiveOption?.cookieHeader ?? ""
        )
    }

    public func openDownloadedRecordViewer(_ record: DownloadRecord) {
        guard let fileURL = record.resolvedFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            showToast(currentStrings.albumFileNotFoundMsg)
            return
        }

        viewerTarget = MediaViewerTarget(
            id: "local_\(record.id)",
            title: record.title,
            subtitle: "\(record.authorName) • \(record.qualityTag)",
            platform: record.platform,
            category: record.mediaCategory,
            streamOrFileURL: fileURL,
            isLocalFile: true,
            coverUrl: record.thumbnailUrl,
            associatedRecord: record
        )
    }

    public func openRecordInSystemAlbum(_ record: DownloadRecord) {
        Task {
            let result = await downloadManager.openInSystemAlbum(record)
            switch result {
            case .opened:
                break
            case .fileNotFound:
                showToast(currentStrings.albumFileNotFoundMsg)
            case .noAppFound:
                showToast(currentStrings.albumNoAppFoundMsg)
            }
        }
    }

    public func shareDownloadedRecord(_ record: DownloadRecord) {
        if let fileURL = record.resolvedFileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            sharePayload = ShareSheetPayload(items: [fileURL])
        } else if let src = URL(string: record.sourceUrl) {
            sharePayload = ShareSheetPayload(items: [src])
        } else {
            showToast(currentStrings.albumFileNotFoundMsg)
        }
    }

    public func openOriginalSourceURL(_ rawUrl: String) {
        guard let url = URL(string: rawUrl) else { return }
        UIApplication.shared.open(url)
    }

    public func copyCaptionToClipboard(_ caption: String) {
        UIPasteboard.general.string = caption
        lastInspectedPasteboardCount = UIPasteboard.general.changeCount
        triggerImpactHaptic(.light)
        showToast(currentStrings.captionCopied)
    }

    public func openSocialPlatform(_ platform: MediaPlatform) {
        let candidates: [String]
        switch platform {
        case .youtube:
            candidates = ["youtube://", "https://m.youtube.com"]
        case .facebook:
            candidates = ["fb://", "https://m.facebook.com"]
        case .tiktok:
            candidates = ["snssdk1233://", "tiktok://", "https://www.tiktok.com"]
        }

        for raw in candidates {
            if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        if let fallback = URL(string: candidates.last ?? "https://www.youtube.com") {
            UIApplication.shared.open(fallback)
        }
    }

    // MARK: - Toast & Haptics

    public func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.toastMessage = nil
            }
        }
    }

    private func triggerImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }

    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(type)
    }
}
