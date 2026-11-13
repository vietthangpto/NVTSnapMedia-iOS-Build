import AVFoundation
import Foundation

public struct MuxingError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Pure native `AVFoundation` lossless MP4 track muxer.
/// Combines a video-only DASH MP4 track (4K / 2K / 1080p60 H.264, HEVC, or AV1) with an M4A/MP4 audio track
/// into a single progressive `.mp4` container (`AVAssetExportPresetPassthrough`) with zero re-encoding.
public enum DashTrackMuxer {

    /// Losslessly muxes `videoFileURL` and `audioFileURL` into `destinationURL`.
    public static func muxVideoAndAudio(
        videoFileURL: URL,
        audioFileURL: URL,
        destinationURL: URL
    ) async throws {
        // Normalize `hev1` sample description entries to `hvc1` if needed so iOS AVFoundation & Photos accept HEVC tracks.
        normalizeHevcSampleEntryIfNeeded(at: videoFileURL)

        let videoAsset = AVURLAsset(
            url: videoFileURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let audioAsset = AVURLAsset(
            url: audioFileURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw MuxingError("Không tìm thấy luồng hình ảnh hợp lệ trong tệp video DASH.")
        }

        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            throw MuxingError("Không tìm thấy luồng âm thanh hợp lệ trong tệp M4A.")
        }

        let videoTimeRange = try await sourceVideoTrack.load(.timeRange)
        let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
        let videoTransform = try await sourceVideoTrack.load(.preferredTransform)

        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MuxingError("Không thể khởi tạo luồng video đích khi ghép tệp MP4.")
        }
        compVideoTrack.preferredTransform = videoTransform

        let effectiveVideoDuration = videoTimeRange.duration
        try compVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: effectiveVideoDuration),
            of: sourceVideoTrack,
            at: .zero
        )

        if let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
            let clampedAudioDuration = CMTimeMinimum(effectiveVideoDuration, audioTimeRange.duration)
            let finalAudioDuration = clampedAudioDuration.seconds > 0 ? clampedAudioDuration : audioTimeRange.duration
            try compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: finalAudioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MuxingError("Thiết bị không hỗ trợ AVAssetExportPresetPassthrough cho định dạng video này.")
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        try Task.checkCancellation()

        switch exportSession.status {
        case .completed:
            let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
            if size <= 0 {
                throw MuxingError("Tệp MP4 sau khi ghép không có dữ liệu.")
            }
        case .cancelled:
            throw CancellationError()
        default:
            let detail = exportSession.error?.localizedDescription ?? "Lỗi không xác định"
            throw MuxingError("Ghép luồng Video + Audio thất bại: \(detail)")
        }
    }

    // MARK: - ISO-BMFF Box Helpers & HEVC (`hev1` -> `hvc1`) Normalizer

    /// Extracts the payload bytes of the first top-level ISO-BMFF atom matching `boxType` (4-ASCII-char fourCC).
    public static func extractIsoBoxPayload(data: Data, boxType: String) -> Data? {
        guard boxType.utf8.count == 4 else { return nil }
        let targetBytes = Array(boxType.utf8)
        let bytes = [UInt8](data)
        var offset = 0

        while offset + 8 <= bytes.count {
            let rawSize = readUInt32BE(bytes, offset)
            let typeSlice = Array(bytes[(offset + 4)..<(offset + 8)])
            var headerLen = 8
            var boxSize = Int(rawSize)

            if rawSize == 1 {
                guard offset + 16 <= bytes.count else { break }
                boxSize = Int(readUInt64BE(bytes, offset + 8))
                headerLen = 16
            } else if rawSize == 0 {
                boxSize = bytes.count - offset
            }

            guard boxSize >= headerLen, offset + boxSize <= bytes.count else {
                break
            }

            if typeSlice == targetBytes {
                let payloadStart = offset + headerLen
                let payloadEnd = offset + boxSize
                return Data(bytes[payloadStart..<payloadEnd])
            }

            offset += boxSize
        }
        return nil
    }

    /// Walks the ISO-BMFF `moov -> trak -> mdia -> minf -> stbl -> stsd` hierarchy in place
    /// and rewrites `hev1` sample description fourCC tags to `hvc1` so iOS `AVFoundation` & `Photos` play them natively.
    public static func normalizeHevcSampleEntryIfNeeded(at fileURL: URL) {
        guard let handle = try? FileHandle(forUpdating: fileURL) else { return }
        defer { try? handle.close() }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSizeNum = attrs[.size] as? NSNumber else {
            return
        }
        let fileSize = fileSizeNum.uint64Value
        guard fileSize >= 16 else { return }

        var offset: UInt64 = 0
        while offset + 8 <= fileSize {
            guard let header = readBytes(handle: handle, offset: offset, count: 16), header.count >= 8 else {
                break
            }
            let rawSize = readUInt32BE(header, 0)
            let boxType = String(bytes: header[4..<8], encoding: .isoLatin1) ?? ""
            var headerLen: UInt64 = 8
            var boxSize = UInt64(rawSize)

            if rawSize == 1 {
                guard header.count >= 16 else { break }
                boxSize = readUInt64BE(header, 8)
                headerLen = 16
            } else if rawSize == 0 {
                boxSize = fileSize - offset
            }

            guard boxSize >= headerLen, offset + boxSize <= fileSize else { break }

            if boxType == "moov" && boxSize <= 16 * 1024 * 1024 {
                let payloadLen = Int(boxSize - headerLen)
                if let moovBytes = readBytes(handle: handle, offset: offset + headerLen, count: payloadLen) {
                    var mutableMoov = moovBytes
                    if patchHev1InContainer(&mutableMoov, range: 0..<mutableMoov.count) {
                        try? handle.seek(toOffset: offset + headerLen)
                        try? handle.write(contentsOf: Data(mutableMoov))
                    }
                }
                break
            }

            offset += boxSize
        }
    }

    private static let containerAtoms: Set<String> = ["trak", "mdia", "minf", "stbl"]

    private static func patchHev1InContainer(_ buffer: inout [UInt8], range: Range<Int>) -> Bool {
        var modified = false
        var pos = range.lowerBound

        while pos + 8 <= range.upperBound {
            let rawSize = Int(readUInt32BE(buffer, pos))
            guard rawSize >= 8, pos + rawSize <= range.upperBound else { break }
            let boxType = String(bytes: buffer[(pos + 4)..<(pos + 8)], encoding: .isoLatin1) ?? ""

            if containerAtoms.contains(boxType) {
                if patchHev1InContainer(&buffer, range: (pos + 8)..<(pos + rawSize)) {
                    modified = true
                }
            } else if boxType == "stsd" && rawSize >= 24 {
                // FullBox: 8-byte header + 4-byte version/flags + 4-byte entry_count = 16 bytes
                let entryCount = Int(readUInt32BE(buffer, pos + 12))
                var entryOffset = pos + 16
                for _ in 0..<entryCount {
                    guard entryOffset + 8 <= pos + rawSize else { break }
                    let entrySize = Int(readUInt32BE(buffer, entryOffset))
                    guard entrySize >= 8, entryOffset + entrySize <= pos + rawSize else { break }
                    let entryType = String(bytes: buffer[(entryOffset + 4)..<(entryOffset + 8)], encoding: .isoLatin1) ?? ""
                    if entryType == "hev1" {
                        let hvc1 = Array("hvc1".utf8)
                        buffer[entryOffset + 4] = hvc1[0]
                        buffer[entryOffset + 5] = hvc1[1]
                        buffer[entryOffset + 6] = hvc1[2]
                        buffer[entryOffset + 7] = hvc1[3]
                        modified = true
                    }
                    entryOffset += entrySize
                }
            }

            pos += rawSize
        }
        return modified
    }

    private static func readBytes(handle: FileHandle, offset: UInt64, count: Int) -> [UInt8]? {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count) else { return nil }
            return [UInt8](data)
        } catch {
            return nil
        }
    }

    private static func readUInt32BE(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        (UInt32(bytes[index]) << 24)
            | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8)
            | UInt32(bytes[index + 3])
    }

    private static func readUInt64BE(_ bytes: [UInt8], _ index: Int) -> UInt64 {
        let high = UInt64(readUInt32BE(bytes, index))
        let low = UInt64(readUInt32BE(bytes, index + 4))
        return (high << 32) | low
    }
}
