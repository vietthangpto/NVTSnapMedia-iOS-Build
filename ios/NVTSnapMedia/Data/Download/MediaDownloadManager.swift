import Foundation
import Photos
import UIKit
import UserNotifications

public enum AlbumOpenResult: Sendable {
    case opened
    case fileNotFound
    case noAppFound
}

private actor AsyncSemaphore {
    private let maxPermits: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.maxPermits = max(1, permits)
        self.available = max(1, permits)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            available = min(maxPermits, available + 1)
        }
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private struct StreamError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
public final class MediaDownloadManager: ObservableObject {

    public static let customPhotoAlbumTitle = "NVTSnapMedia"

    private static let defaultBrowserUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private static let googleChunkSize: Int64 = 9 * 1024 * 1024 // 9 MB chunks bypass YouTube CDN throttling
    private static let progressUpdateIntervalSec: TimeInterval = 0.22

    private let database: DownloadDatabase
    private let preferences: AppPreferences
    private let semaphore = AsyncSemaphore(permits: 3)
    private let urlSession: URLSession

    private var activeTasks: [Int64: Task<Void, Never>] = [:]

    public init(database: DownloadDatabase, preferences: AppPreferences) {
        self.database = database
        self.preferences = preferences

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 3600
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Public Queue Operations

    @discardableResult
    public func enqueueDownload(media: UnifiedMediaInfo, option: DownloadQualityOption) async -> Int64 {
        let fileName = Self.buildOutputFileName(media: media, option: option)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let record = DownloadRecord(
            id: 0,
            mediaId: media.id,
            platform: media.platform,
            title: media.title,
            authorName: media.authorName,
            thumbnailUrl: media.coverUrl,
            sourceUrl: media.originalUrl,
            downloadUrl: option.url,
            audioStreamUrl: option.audioStreamUrl,
            fallbackUrl: option.fallbackUrl,
            clientUserAgent: option.clientUserAgent,
            cookieHeader: option.cookieHeader,
            refererHeader: option.refererHeader,
            demuxAudioFromVideo: option.demuxAudioFromVideo,
            localRelativePath: "",
            photoAssetId: "",
            fileName: fileName,
            mimeType: option.mimeType,
            mediaCategory: option.mediaCategory,
            qualityTag: option.badge,
            totalBytes: max(0, option.sizeBytes),
            downloadedBytes: 0,
            speedBytesPerSec: 0,
            status: .queued,
            errorMessage: "",
            createdAt: nowMs
        )

        let insertedId = await database.insertRecord(record)
        requestNotificationPermissionIfNeeded()
        scheduleWorker(for: insertedId)
        return insertedId
    }

    public func cancelDownload(_ id: Int64) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        Task { @MainActor in
            await database.updateRecordState(
                id: id,
                status: .cancelled,
                errorMessage: currentIsVietnamese ? "Đã hủy tải xuống" : "Download cancelled"
            )
        }
    }

    public func retryDownload(_ id: Int64) {
        guard let existing = database.getById(id) else { return }
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)

        Task { @MainActor in
            await database.updateRecordState(
                id: id,
                status: .queued,
                downloadedBytes: 0,
                totalBytes: existing.totalBytes,
                errorMessage: ""
            )
            scheduleWorker(for: id)
        }
    }

    public func deleteDownload(_ record: DownloadRecord, deleteLocalFile: Bool) async {
        activeTasks[record.id]?.cancel()
        activeTasks.removeValue(forKey: record.id)

        if deleteLocalFile, let fileURL = record.resolvedFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        await database.deleteById(record.id)
    }

    public func clearFinishedHistoryKeepFiles() async {
        await database.clearHistoryKeepFiles()
    }

    /// Opens the downloaded media item inside the native iOS `Photos` app (for Video/Image)
    /// or iOS `Files` app (for Audio / fallback).
    public func openInSystemAlbum(_ record: DownloadRecord) async -> AlbumOpenResult {
        let localFileExists: Bool = {
            guard let url = record.resolvedFileURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }()

        let photoAssetExists: Bool = {
            guard !record.photoAssetId.isEmpty else { return false }
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else { return true }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [record.photoAssetId], options: nil)
            return result.count > 0
        }()

        guard localFileExists || photoAssetExists else {
            return .fileNotFound
        }

        if record.mediaCategory == .video || record.mediaCategory == .image {
            if let photosURL = URL(string: "photos-redirect://"),
               UIApplication.shared.canOpenURL(photosURL) {
                let opened = await UIApplication.shared.open(photosURL)
                if opened { return .opened }
            }
        }

        // Open the NVTSnapMedia folder inside iOS Files (`shareddocuments://`)
        if let fileURL = record.resolvedFileURL {
            let folderPath = fileURL.deletingLastPathComponent().path
            if let encoded = folderPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let filesURL = URL(string: "shareddocuments://\(encoded)"),
               UIApplication.shared.canOpenURL(filesURL) {
                let opened = await UIApplication.shared.open(filesURL)
                if opened { return .opened }
            }
        }

        if let photosURL = URL(string: "photos-redirect://"),
           UIApplication.shared.canOpenURL(photosURL) {
            let opened = await UIApplication.shared.open(photosURL)
            if opened { return .opened }
        }

        return .noAppFound
    }

    // MARK: - Worker Execution

    private var currentIsVietnamese: Bool {
        preferences.settings.language == .vi
    }

    private func scheduleWorker(for recordId: Int64) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runDownloadTask(recordId: recordId)
        }
        activeTasks[recordId] = task
    }

    private func runDownloadTask(recordId: Int64) async {
        await semaphore.acquire()
        defer {
            Task { await semaphore.release() }
            activeTasks.removeValue(forKey: recordId)
        }

        guard !Task.isCancelled, let record = database.getById(recordId) else { return }

        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "NVTSnapMediaDownload-\(recordId)") {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        defer {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }

        database.updateProgressInMemory(
            id: recordId,
            downloadedBytes: 0,
            totalBytes: record.totalBytes,
            speedBytesPerSec: 0,
            status: .downloading
        )
        await database.updateRecordState(id: recordId, status: .downloading, errorMessage: "")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NVTSnapMediaParts", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var tempFilesToCleanup: [URL] = []
        defer {
            for tmp in tempFilesToCleanup {
                try? FileManager.default.removeItem(at: tmp)
            }
        }

        do {
            let (finalURL, relativePath) = try Self.prepareDestinationURL(
                category: record.mediaCategory,
                preferredFileName: record.fileName
            )

            let session = self.urlSession

            if !record.audioStreamUrl.isEmpty && record.mediaCategory == .video {
                // Dual-track DASH download (4K / 2K / 1080p60 Video + M4A Audio -> Lossless MP4 Mux)
                let videoPart = tempDir.appendingPathComponent("dl_\(recordId)_video.mp4")
                let audioPart = tempDir.appendingPathComponent("dl_\(recordId)_audio.m4a")
                let muxedPart = tempDir.appendingPathComponent("dl_\(recordId)_muxed.mp4")
                tempFilesToCleanup.append(contentsOf: [videoPart, audioPart, muxedPart])

                let estimatedCombined = max(record.totalBytes, 0)

                let videoBytes = try await Self.downloadSingleResource(
                    session: session,
                    primaryUrl: record.downloadUrl,
                    fallbackUrl: record.fallbackUrl,
                    userAgent: record.clientUserAgent,
                    cookie: record.cookieHeader,
                    referer: record.refererHeader,
                    destination: videoPart
                ) { [weak self] downloaded, streamTotal, speed in
                    guard let self else { return }
                    let effectiveTotal: Int64
                    if estimatedCombined > 0 {
                        effectiveTotal = estimatedCombined
                    } else if streamTotal > 0 {
                        effectiveTotal = Int64(Double(streamTotal) * 1.15)
                    } else {
                        effectiveTotal = 0
                    }
                    Task { @MainActor in
                        self.database.updateProgressInMemory(
                            id: recordId,
                            downloadedBytes: downloaded,
                            totalBytes: effectiveTotal,
                            speedBytesPerSec: speed,
                            status: .downloading
                        )
                    }
                }

                try Task.checkCancellation()

                let audioBytes = try await Self.downloadSingleResource(
                    session: session,
                    primaryUrl: record.audioStreamUrl,
                    fallbackUrl: "",
                    userAgent: record.clientUserAgent,
                    cookie: record.cookieHeader,
                    referer: record.refererHeader,
                    destination: audioPart
                ) { [weak self] downloaded, streamTotal, speed in
                    guard let self else { return }
                    let combinedTotal = streamTotal > 0 ? (videoBytes + streamTotal) : max(estimatedCombined, videoBytes + downloaded)
                    Task { @MainActor in
                        self.database.updateProgressInMemory(
                            id: recordId,
                            downloadedBytes: videoBytes + downloaded,
                            totalBytes: combinedTotal,
                            speedBytesPerSec: speed,
                            status: .downloading
                        )
                    }
                }

                try Task.checkCancellation()

                try await DashTrackMuxer.muxVideoAndAudio(
                    videoFileURL: videoPart,
                    audioFileURL: audioPart,
                    destinationURL: muxedPart
                )

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try? FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: muxedPart, to: finalURL)
                let finalSize = Self.fileSize(at: finalURL) > 0 ? Self.fileSize(at: finalURL) : (videoBytes + audioBytes)

                let assetId = await Self.exportToPhotoLibraryIfApplicable(
                    fileURL: finalURL,
                    category: record.mediaCategory
                )

                await database.updateRecordState(
                    id: recordId,
                    status: .completed,
                    localRelativePath: relativePath,
                    photoAssetId: assetId ?? "",
                    downloadedBytes: finalSize,
                    totalBytes: finalSize,
                    errorMessage: ""
                )
                postCompletionNotification(record: record)

            } else if record.demuxAudioFromVideo && record.mediaCategory == .audio {
                // Download progressive MP4 then losslessly demux AAC track into clean `.m4a`
                let sourceVideoPart = tempDir.appendingPathComponent("dl_\(recordId)_src.mp4")
                let extractedM4aPart = tempDir.appendingPathComponent("dl_\(recordId)_out.m4a")
                tempFilesToCleanup.append(contentsOf: [sourceVideoPart, extractedM4aPart])

                _ = try await Self.downloadSingleResource(
                    session: session,
                    primaryUrl: record.downloadUrl,
                    fallbackUrl: record.fallbackUrl,
                    userAgent: record.clientUserAgent,
                    cookie: record.cookieHeader,
                    referer: record.refererHeader,
                    destination: sourceVideoPart
                ) { [weak self] downloaded, streamTotal, speed in
                    guard let self else { return }
                    let total = streamTotal > 0 ? streamTotal : record.totalBytes
                    Task { @MainActor in
                        self.database.updateProgressInMemory(
                            id: recordId,
                            downloadedBytes: downloaded,
                            totalBytes: total,
                            speedBytesPerSec: speed,
                            status: .downloading
                        )
                    }
                }

                try Task.checkCancellation()

                try await AudioTrackExtractor.extractAudioToM4a(
                    sourceVideoURL: sourceVideoPart,
                    destinationM4aURL: extractedM4aPart
                )

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try? FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: extractedM4aPart, to: finalURL)
                let finalSize = Self.fileSize(at: finalURL)

                await database.updateRecordState(
                    id: recordId,
                    status: .completed,
                    localRelativePath: relativePath,
                    photoAssetId: "",
                    downloadedBytes: finalSize,
                    totalBytes: finalSize,
                    errorMessage: ""
                )
                postCompletionNotification(record: record)

            } else {
                // Single progressive video, direct M4A/MP3 audio, or high-res JPG photo
                let partFile = tempDir.appendingPathComponent("dl_\(recordId)_single.part")
                tempFilesToCleanup.append(partFile)

                let writtenBytes = try await Self.downloadSingleResource(
                    session: session,
                    primaryUrl: record.downloadUrl,
                    fallbackUrl: record.fallbackUrl,
                    userAgent: record.clientUserAgent,
                    cookie: record.cookieHeader,
                    referer: record.refererHeader,
                    destination: partFile
                ) { [weak self] downloaded, streamTotal, speed in
                    guard let self else { return }
                    let total = streamTotal > 0 ? streamTotal : record.totalBytes
                    Task { @MainActor in
                        self.database.updateProgressInMemory(
                            id: recordId,
                            downloadedBytes: downloaded,
                            totalBytes: total,
                            speedBytesPerSec: speed,
                            status: .downloading
                        )
                    }
                }

                try Task.checkCancellation()

                if record.mediaCategory == .video {
                    DashTrackMuxer.normalizeHevcSampleEntryIfNeeded(at: partFile)
                }

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try? FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: partFile, to: finalURL)
                let finalSize = Self.fileSize(at: finalURL) > 0 ? Self.fileSize(at: finalURL) : writtenBytes

                let assetId = await Self.exportToPhotoLibraryIfApplicable(
                    fileURL: finalURL,
                    category: record.mediaCategory
                )

                await database.updateRecordState(
                    id: recordId,
                    status: .completed,
                    localRelativePath: relativePath,
                    photoAssetId: assetId ?? "",
                    downloadedBytes: finalSize,
                    totalBytes: finalSize,
                    errorMessage: ""
                )
                postCompletionNotification(record: record)
            }

        } catch is CancellationError {
            await database.updateRecordState(
                id: recordId,
                status: .cancelled,
                errorMessage: currentIsVietnamese ? "Đã hủy tải xuống" : "Download cancelled"
            )
        } catch {
            if Task.isCancelled {
                await database.updateRecordState(
                    id: recordId,
                    status: .cancelled,
                    errorMessage: currentIsVietnamese ? "Đã hủy tải xuống" : "Download cancelled"
                )
            } else {
                await database.updateRecordState(
                    id: recordId,
                    status: .failed,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    // MARK: - HTTP Streaming Engines (9 MB GoogleVideo Range Chunks + Standard Streaming)

    private nonisolated static func downloadSingleResource(
        session: URLSession,
        primaryUrl: String,
        fallbackUrl: String,
        userAgent: String,
        cookie: String,
        referer: String,
        destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64, Int64) -> Void
    ) async throws -> Int64 {
        do {
            return try await streamFromUrl(
                session: session,
                urlString: primaryUrl,
                userAgent: userAgent,
                cookie: cookie,
                referer: referer,
                destination: destination,
                onProgress: onProgress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let trimmedFallback = fallbackUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFallback.isEmpty, trimmedFallback != primaryUrl else {
                throw error
            }
            try? FileManager.default.removeItem(at: destination)
            return try await streamFromUrl(
                session: session,
                urlString: trimmedFallback,
                userAgent: userAgent,
                cookie: cookie,
                referer: referer,
                destination: destination,
                onProgress: onProgress
            )
        }
    }

    private nonisolated static func streamFromUrl(
        session: URLSession,
        urlString: String,
        userAgent: String,
        cookie: String,
        referer: String,
        destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64, Int64) -> Void
    ) async throws -> Int64 {
        guard let url = URL(string: urlString) else {
            throw StreamError("URL tải xuống không hợp lệ.")
        }

        let host = url.host?.lowercased() ?? ""
        if host.contains("googlevideo.com") {
            return try await streamGoogleVideoChunked(
                session: session,
                url: url,
                userAgent: userAgent,
                destination: destination,
                onProgress: onProgress
            )
        } else {
            return try await streamStandardSingle(
                session: session,
                url: url,
                userAgent: userAgent,
                cookie: cookie,
                referer: referer,
                destination: destination,
                onProgress: onProgress
            )
        }
    }

    /// Streams `googlevideo.com` URLs using 9 MB HTTP `Range` chunks to eliminate YouTube CDN bandwidth throttling.
    private nonisolated static func streamGoogleVideoChunked(
        session: URLSession,
        url: URL,
        userAgent: String,
        destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64, Int64) -> Void
    ) async throws -> Int64 {
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }

        var knownTotalBytes: Int64 = extractClenFromQuery(url: url)
        var currentOffset: Int64 = 0

        var lastReportTime = CFAbsoluteTimeGetCurrent()
        var bytesAtLastReport: Int64 = 0
        let effectiveUA = userAgent.isEmpty ? defaultBrowserUA : userAgent

        while true {
            try Task.checkCancellation()

            let chunkEnd: Int64
            if knownTotalBytes > 0 {
                if currentOffset >= knownTotalBytes { break }
                chunkEnd = min(currentOffset + googleChunkSize - 1, knownTotalBytes - 1)
            } else {
                chunkEnd = currentOffset + googleChunkSize - 1
            }

            var chunkCompleted = false
            var lastChunkError: Error?

            for attempt in 0..<3 {
                try Task.checkCancellation()
                let offsetBeforeAttempt = currentOffset

                do {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue(effectiveUA, forHTTPHeaderField: "User-Agent")
                    req.setValue("bytes=\(currentOffset)-\(chunkEnd)", forHTTPHeaderField: "Range")
                    req.setValue("*/*", forHTTPHeaderField: "Accept")

                    let (asyncBytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw StreamError("Phản hồi máy chủ YouTube CDN không hợp lệ.")
                    }

                    if http.statusCode == 416 {
                        // Requested range not satisfiable -> EOF reached
                        knownTotalBytes = currentOffset
                        chunkCompleted = true
                        break
                    }

                    guard (200...299).contains(http.statusCode) else {
                        throw StreamError("Máy chủ CDN trả mã lỗi HTTP \(http.statusCode).")
                    }

                    if knownTotalBytes <= 0 {
                        if let totalFromRange = parseTotalFromContentRange(http.value(forHTTPHeaderField: "Content-Range")) {
                            knownTotalBytes = totalFromRange
                        } else if http.statusCode == 200, http.expectedContentLength > 0 {
                            knownTotalBytes = http.expectedContentLength
                        }
                    }

                    let serverIgnoredRange = (http.statusCode == 200 && currentOffset == 0)

                    var buffer = Data()
                    buffer.reserveCapacity(65_536)
                    var chunkBytesRead: Int64 = 0

                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= 65_536 {
                            try Task.checkCancellation()
                            try fileHandle.write(contentsOf: buffer)
                            let count = Int64(buffer.count)
                            currentOffset += count
                            chunkBytesRead += count
                            buffer.removeAll(keepingCapacity: true)

                            let now = CFAbsoluteTimeGetCurrent()
                            let elapsed = now - lastReportTime
                            if elapsed >= progressUpdateIntervalSec {
                                let speed = Int64(Double(currentOffset - bytesAtLastReport) / elapsed)
                                lastReportTime = now
                                bytesAtLastReport = currentOffset
                                onProgress(currentOffset, knownTotalBytes, max(0, speed))
                            }
                        }
                    }

                    if !buffer.isEmpty {
                        try fileHandle.write(contentsOf: buffer)
                        let count = Int64(buffer.count)
                        currentOffset += count
                        chunkBytesRead += count
                    }

                    onProgress(currentOffset, knownTotalBytes, 0)

                    if serverIgnoredRange || chunkBytesRead == 0 {
                        knownTotalBytes = currentOffset
                    } else if knownTotalBytes <= 0 && chunkBytesRead < googleChunkSize {
                        knownTotalBytes = currentOffset
                    }

                    chunkCompleted = true
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastChunkError = error
                    // Rewind file handle to offset before failed chunk attempt
                    currentOffset = offsetBeforeAttempt
                    try? fileHandle.truncate(atOffset: UInt64(offsetBeforeAttempt))
                    try? fileHandle.seek(toOffset: UInt64(offsetBeforeAttempt))
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                    }
                }
            }

            if !chunkCompleted {
                throw lastChunkError ?? StreamError("Mất kết nối khi tải phân đoạn video.")
            }

            if knownTotalBytes > 0 && currentOffset >= knownTotalBytes {
                break
            }
        }

        guard currentOffset > 0 else {
            throw StreamError("Luồng dữ liệu tải về trống (0 bytes).")
        }
        return currentOffset
    }

    /// Streams standard CDN URLs (Facebook, TikTok, direct audio, photos) with custom headers.
    private nonisolated static func streamStandardSingle(
        session: URLSession,
        url: URL,
        userAgent: String,
        cookie: String,
        referer: String,
        destination: URL,
        onProgress: @Sendable @escaping (Int64, Int64, Int64) -> Void
    ) async throws -> Int64 {
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent.isEmpty ? defaultBrowserUA : userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        if !cookie.isEmpty {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if !referer.isEmpty {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let (asyncBytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StreamError("Không thể tải tệp từ máy chủ (HTTP \(status)).")
        }

        let totalExpected: Int64 = {
            if let rangeTotal = parseTotalFromContentRange(http.value(forHTTPHeaderField: "Content-Range")) {
                return rangeTotal
            }
            return http.expectedContentLength > 0 ? http.expectedContentLength : 0
        }()

        var downloaded: Int64 = 0
        var lastReportTime = CFAbsoluteTimeGetCurrent()
        var bytesAtLastReport: Int64 = 0

        var buffer = Data()
        buffer.reserveCapacity(65_536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try Task.checkCancellation()
                try fileHandle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - lastReportTime
                if elapsed >= progressUpdateIntervalSec {
                    let speed = Int64(Double(downloaded - bytesAtLastReport) / elapsed)
                    lastReportTime = now
                    bytesAtLastReport = downloaded
                    onProgress(downloaded, totalExpected, max(0, speed))
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }

        guard downloaded > 0 else {
            throw StreamError("Tệp tải về rỗng (0 bytes).")
        }

        onProgress(downloaded, max(totalExpected, downloaded), 0)
        return downloaded
    }

    private nonisolated static func extractClenFromQuery(url: URL) -> Int64 {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let clenItem = comps.queryItems?.first(where: { $0.name == "clen" })?.value,
              let val = Int64(clenItem), val > 0 else {
            return 0
        }
        return val
    }

    private nonisolated static func parseTotalFromContentRange(_ header: String?) -> Int64? {
        guard let header, let slashIdx = header.lastIndex(of: "/") else { return nil }
        let totalStr = header[header.index(after: slashIdx)...].trimmingCharacters(in: .whitespaces)
        if let val = Int64(totalStr), val > 0 {
            return val
        }
        return nil
    }

    // MARK: - File Naming, Sandbox Destination & iOS Photos Album Integration

    public nonisolated static func buildOutputFileName(
        media: UnifiedMediaInfo,
        option: DownloadQualityOption
    ) -> String {
        let authorSeg = MediaUrlDetector.sanitizeFileSegment(media.authorName, maxLen: 20)
        let idSeg = MediaUrlDetector.sanitizeFileSegment(media.id, maxLen: 16)
        let badgeSeg = MediaUrlDetector.sanitizeFileSegment(option.badge, maxLen: 12)
        let ext = option.extensionName
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let cleanExt = ext.isEmpty ? "mp4" : ext
        return "NVTSnapMedia_\(media.platform.filePrefix)_\(authorSeg)_\(idSeg)_\(badgeSeg).\(cleanExt)"
    }

    private nonisolated static func prepareDestinationURL(
        category: MediaCategory,
        preferredFileName: String
    ) throws -> (fileURL: URL, relativePath: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StreamError("Không thể truy cập thư mục Documents trên thiết bị.")
        }

        let subfolder: String
        switch category {
        case .video: subfolder = "NVTSnapMedia/Movies"
        case .audio: subfolder = "NVTSnapMedia/Music"
        case .image: subfolder = "NVTSnapMedia/Pictures"
        }

        let dirURL = docs.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let nsName = preferredFileName as NSString
        let baseName = nsName.deletingPathExtension
        let ext = nsName.pathExtension

        var candidateName = preferredFileName
        var counter = 1
        while FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(candidateName).path) {
            candidateName = ext.isEmpty ? "\(baseName)_(\(counter))" : "\(baseName)_(\(counter)).\(ext)"
            counter += 1
        }

        let finalURL = dirURL.appendingPathComponent(candidateName)
        let relPath = "\(subfolder)/\(candidateName)"
        return (finalURL, relPath)
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// Saves completed Video or Image files into the user's iOS `Photos` library under the custom `"NVTSnapMedia"` album.
    private nonisolated static func exportToPhotoLibraryIfApplicable(
        fileURL: URL,
        category: MediaCategory
    ) async -> String? {
        guard category == .video || category == .image else { return nil }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let finalStatus: PHAuthorizationStatus
        if currentStatus == .notDetermined {
            finalStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            finalStatus = currentStatus
        }

        guard finalStatus == .authorized || finalStatus == .limited else {
            return nil
        }

        let targetAlbum = await fetchOrCreateCustomAlbum(named: customPhotoAlbumTitle)
        let idBox = SendableBox<String?>(nil)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest: PHAssetChangeRequest?
                if category == .video {
                    creationRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                } else {
                    creationRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }

                if let placeholder = creationRequest?.placeholderForCreatedAsset {
                    idBox.value = placeholder.localIdentifier
                    if let targetAlbum,
                       let albumChange = PHAssetCollectionChangeRequest(for: targetAlbum) {
                        let fastEnumeration: NSArray = [placeholder]
                        albumChange.addAssets(fastEnumeration)
                    }
                }
            }
            return idBox.value
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchOrCreateCustomAlbum(named title: String) async -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )
        if let first = existing.firstObject {
            return first
        }

        let albumIdBox = SendableBox<String?>(nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                albumIdBox.value = req.placeholderForCreatedAssetCollection.localIdentifier
            }
            if let albumPlaceholderId = albumIdBox.value {
                let created = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumPlaceholderId],
                    options: nil
                )
                return created.firstObject
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Local Completion Notifications

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    private func postCompletionNotification(record: DownloadRecord) {
        let isVi = currentIsVietnamese
        let content = UNMutableNotificationContent()
        content.title = isVi
            ? "Đã tải xong • \(record.platform.displayName)"
            : "Download complete • \(record.platform.displayName)"
        content.body = "\(record.title) (\(record.qualityTag))"
        content.sound = .default
        content.userInfo = [
            "open_tab": "downloads",
            "record_id": record.id
        ]

        let req = UNNotificationRequest(
            identifier: "nvtsnapmedia_done_\(record.id)_\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
