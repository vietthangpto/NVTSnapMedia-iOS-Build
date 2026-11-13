import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
public final class DownloadDatabase: ObservableObject {

    @Published public private(set) var downloads: [DownloadRecord] = []

    private nonisolated let dbQueue = DispatchQueue(label: "com.nvtsnapmedia.app.sqlite", qos: .userInitiated)
    private nonisolated(unsafe) var db: OpaquePointer?

    public init() {
        let dbPath = Self.databaseFileURL().path
        dbQueue.sync {
            if sqlite3_open_v2(
                dbPath,
                &self.db,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK {
                Self.createSchema(db: self.db)
                Self.recoverInterruptedTasks(db: self.db)
            }
        }
        let initialItems = dbQueue.sync { Self.fetchAllRecords(db: self.db) }
        self.downloads = initialItems
    }

    deinit {
        let handle = db
        dbQueue.async {
            if let handle {
                sqlite3_close(handle)
            }
        }
    }

    private nonisolated static func databaseFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NVTSnapMediaDB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nvtsnapmedia_downloads.sqlite3")
    }

    private nonisolated static func createSchema(db: OpaquePointer?) {
        guard let db else { return }
        let createSQL = """
        CREATE TABLE IF NOT EXISTS downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            media_id TEXT NOT NULL,
            platform TEXT NOT NULL,
            title TEXT NOT NULL,
            author_name TEXT NOT NULL,
            thumbnail_url TEXT NOT NULL,
            source_url TEXT NOT NULL,
            download_url TEXT NOT NULL,
            audio_stream_url TEXT NOT NULL DEFAULT '',
            fallback_url TEXT NOT NULL DEFAULT '',
            client_user_agent TEXT NOT NULL DEFAULT '',
            cookie_header TEXT NOT NULL DEFAULT '',
            referer_header TEXT NOT NULL DEFAULT '',
            demux_audio INTEGER NOT NULL DEFAULT 0,
            local_relative_path TEXT NOT NULL DEFAULT '',
            photo_asset_id TEXT NOT NULL DEFAULT '',
            file_name TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            media_category TEXT NOT NULL,
            quality_tag TEXT NOT NULL,
            downloaded_bytes INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            status TEXT NOT NULL,
            error_message TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_media_downloads_created_at ON downloads(created_at DESC);
        """
        sqlite3_exec(db, createSQL, nil, nil, nil)
    }

    private nonisolated static func recoverInterruptedTasks(db: OpaquePointer?) {
        guard let db else { return }
        let sql = """
        UPDATE downloads
        SET status = 'FAILED', error_message = 'Tải xuống bị gián đoạn khi đóng ứng dụng'
        WHERE status IN ('QUEUED', 'DOWNLOADING');
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private nonisolated static func fetchAllRecords(db: OpaquePointer?) -> [DownloadRecord] {
        guard let db else { return [] }
        let sql = """
        SELECT id, media_id, platform, title, author_name, thumbnail_url, source_url, download_url,
               audio_stream_url, fallback_url, client_user_agent, cookie_header, referer_header,
               demux_audio, local_relative_path, photo_asset_id, file_name, mime_type,
               media_category, quality_tag, downloaded_bytes, total_bytes, status,
               error_message, created_at
        FROM downloads
        ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var list: [DownloadRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let mediaId = colString(stmt, 1)
            let platRaw = colString(stmt, 2)
            let title = colString(stmt, 3)
            let authorName = colString(stmt, 4)
            let thumbnailUrl = colString(stmt, 5)
            let sourceUrl = colString(stmt, 6)
            let downloadUrl = colString(stmt, 7)
            let audioStreamUrl = colString(stmt, 8)
            let fallbackUrl = colString(stmt, 9)
            let clientUA = colString(stmt, 10)
            let cookieHeader = colString(stmt, 11)
            let refererHeader = colString(stmt, 12)
            let demuxAudio = sqlite3_column_int(stmt, 13) == 1
            let localRelPath = colString(stmt, 14)
            let photoAssetId = colString(stmt, 15)
            let fileName = colString(stmt, 16)
            let mimeType = colString(stmt, 17)
            let catRaw = colString(stmt, 18)
            let qualityTag = colString(stmt, 19)
            let downloadedBytes = sqlite3_column_int64(stmt, 20)
            let totalBytes = sqlite3_column_int64(stmt, 21)
            let statusRaw = colString(stmt, 22)
            let errorMessage = colString(stmt, 23)
            let createdAt = sqlite3_column_int64(stmt, 24)

            list.append(
                DownloadRecord(
                    id: id,
                    mediaId: mediaId,
                    platform: MediaPlatform(rawValue: platRaw) ?? .youtube,
                    title: title,
                    authorName: authorName,
                    thumbnailUrl: thumbnailUrl,
                    sourceUrl: sourceUrl,
                    downloadUrl: downloadUrl,
                    audioStreamUrl: audioStreamUrl,
                    fallbackUrl: fallbackUrl,
                    clientUserAgent: clientUA,
                    cookieHeader: cookieHeader,
                    refererHeader: refererHeader,
                    demuxAudioFromVideo: demuxAudio,
                    localRelativePath: localRelPath,
                    photoAssetId: photoAssetId,
                    fileName: fileName,
                    mimeType: mimeType,
                    mediaCategory: MediaCategory(rawValue: catRaw) ?? .video,
                    qualityTag: qualityTag,
                    totalBytes: totalBytes,
                    downloadedBytes: downloadedBytes,
                    speedBytesPerSec: 0,
                    status: DownloadStatus(rawValue: statusRaw) ?? .failed,
                    errorMessage: errorMessage,
                    createdAt: createdAt
                )
            )
        }
        return list
    }

    private nonisolated static func colString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private nonisolated static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    public func insertRecord(_ record: DownloadRecord) async -> Int64 {
        let dbHandle = self.db
        let newId: Int64 = await withCheckedContinuation { continuation in
            dbQueue.async {
                guard let dbHandle else {
                    continuation.resume(returning: Int64(Date().timeIntervalSince1970 * 1000))
                    return
                }
                let sql = """
                INSERT INTO downloads (
                    media_id, platform, title, author_name, thumbnail_url, source_url, download_url,
                    audio_stream_url, fallback_url, client_user_agent, cookie_header, referer_header,
                    demux_audio, local_relative_path, photo_asset_id, file_name, mime_type,
                    media_category, quality_tag, downloaded_bytes, total_bytes, status,
                    error_message, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(dbHandle, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: Int64(Date().timeIntervalSince1970 * 1000))
                    return
                }
                defer { sqlite3_finalize(stmt) }

                Self.bindText(stmt, 1, record.mediaId)
                Self.bindText(stmt, 2, record.platform.rawValue)
                Self.bindText(stmt, 3, record.title)
                Self.bindText(stmt, 4, record.authorName)
                Self.bindText(stmt, 5, record.thumbnailUrl)
                Self.bindText(stmt, 6, record.sourceUrl)
                Self.bindText(stmt, 7, record.downloadUrl)
                Self.bindText(stmt, 8, record.audioStreamUrl)
                Self.bindText(stmt, 9, record.fallbackUrl)
                Self.bindText(stmt, 10, record.clientUserAgent)
                Self.bindText(stmt, 11, record.cookieHeader)
                Self.bindText(stmt, 12, record.refererHeader)
                sqlite3_bind_int(stmt, 13, record.demuxAudioFromVideo ? 1 : 0)
                Self.bindText(stmt, 14, record.localRelativePath)
                Self.bindText(stmt, 15, record.photoAssetId)
                Self.bindText(stmt, 16, record.fileName)
                Self.bindText(stmt, 17, record.mimeType)
                Self.bindText(stmt, 18, record.mediaCategory.rawValue)
                Self.bindText(stmt, 19, record.qualityTag)
                sqlite3_bind_int64(stmt, 20, record.downloadedBytes)
                sqlite3_bind_int64(stmt, 21, record.totalBytes)
                Self.bindText(stmt, 22, record.status.rawValue)
                Self.bindText(stmt, 23, record.errorMessage)
                sqlite3_bind_int64(stmt, 24, record.createdAt)

                _ = sqlite3_step(stmt)
                let rowId = sqlite3_last_insert_rowid(dbHandle)
                continuation.resume(returning: rowId)
            }
        }

        var inserted = record
        inserted.id = newId
        downloads.insert(inserted, at: 0)
        return newId
    }

    public func updateProgressInMemory(
        id: Int64,
        downloadedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSec: Int64,
        status: DownloadStatus = .downloading
    ) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        var item = downloads[idx]
        item.downloadedBytes = downloadedBytes
        if totalBytes > 0 {
            item.totalBytes = totalBytes
        }
        item.speedBytesPerSec = speedBytesPerSec
        item.status = status
        downloads[idx] = item
    }

    public func updateRecordState(
        id: Int64,
        status: DownloadStatus,
        localRelativePath: String? = nil,
        photoAssetId: String? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        errorMessage: String = ""
    ) async {
        let current = downloads.first(where: { $0.id == id })
        let finalPath = localRelativePath ?? current?.localRelativePath ?? ""
        let finalAsset = photoAssetId ?? current?.photoAssetId ?? ""
        let finalDown = downloadedBytes ?? current?.downloadedBytes ?? 0
        let finalTotal = totalBytes ?? current?.totalBytes ?? 0

        let dbHandle = self.db
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async {
                if let dbHandle {
                    let sql = """
                    UPDATE downloads
                    SET status = ?, error_message = ?, local_relative_path = ?, photo_asset_id = ?,
                        downloaded_bytes = ?, total_bytes = ?
                    WHERE id = ?;
                    """
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(dbHandle, sql, -1, &stmt, nil) == SQLITE_OK {
                        Self.bindText(stmt, 1, status.rawValue)
                        Self.bindText(stmt, 2, errorMessage)
                        Self.bindText(stmt, 3, finalPath)
                        Self.bindText(stmt, 4, finalAsset)
                        sqlite3_bind_int64(stmt, 5, finalDown)
                        sqlite3_bind_int64(stmt, 6, finalTotal)
                        sqlite3_bind_int64(stmt, 7, id)
                        _ = sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                }
                continuation.resume()
            }
        }

        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            var item = downloads[idx]
            item.status = status
            item.localRelativePath = finalPath
            item.photoAssetId = finalAsset
            item.downloadedBytes = finalDown
            item.totalBytes = finalTotal
            item.speedBytesPerSec = 0
            item.errorMessage = errorMessage
            downloads[idx] = item
        }
    }

    public func getById(_ id: Int64) -> DownloadRecord? {
        downloads.first(where: { $0.id == id })
    }

    public func deleteById(_ id: Int64) async {
        let dbHandle = self.db
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async {
                if let dbHandle {
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(dbHandle, "DELETE FROM downloads WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_int64(stmt, 1, id)
                        _ = sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                }
                continuation.resume()
            }
        }
        downloads.removeAll { $0.id == id }
    }

    public func clearHistoryKeepFiles() async {
        let dbHandle = self.db
        let remaining: [DownloadRecord] = await withCheckedContinuation { continuation in
            dbQueue.async {
                if let dbHandle {
                    let sql = "DELETE FROM downloads WHERE status NOT IN ('QUEUED', 'DOWNLOADING');"
                    sqlite3_exec(dbHandle, sql, nil, nil, nil)
                }
                let list = Self.fetchAllRecords(db: dbHandle)
                continuation.resume(returning: list)
            }
        }
        downloads = remaining
    }
}
