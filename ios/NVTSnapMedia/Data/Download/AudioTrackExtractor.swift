import AVFoundation
import Foundation

/// Pure native `AVFoundation` lossless audio track extractor.
/// Demuxes the AAC audio track from a downloaded `.mp4` container into a clean `.m4a` file
/// using `AVAssetExportPresetPassthrough` without re-encoding or quality loss.
public enum AudioTrackExtractor {

    public static func extractAudioToM4a(
        sourceVideoURL: URL,
        destinationM4aURL: URL
    ) async throws {
        let sourceAsset = AVURLAsset(
            url: sourceVideoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            throw MuxingError("Video này không có kênh âm thanh để tách riêng.")
        }

        let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
        let composition = AVMutableComposition()

        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MuxingError("Không thể khởi tạo luồng âm thanh M4A.")
        }

        try compAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: audioTimeRange.duration),
            of: sourceAudioTrack,
            at: .zero
        )

        if FileManager.default.fileExists(atPath: destinationM4aURL.path) {
            try? FileManager.default.removeItem(at: destinationM4aURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MuxingError("Thiết bị không hỗ trợ tách luồng âm thanh M4A gốc.")
        }

        exportSession.outputURL = destinationM4aURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        try Task.checkCancellation()

        switch exportSession.status {
        case .completed:
            let size = (try? FileManager.default.attributesOfItem(atPath: destinationM4aURL.path)[.size] as? Int64) ?? 0
            if size <= 0 {
                throw MuxingError("Tệp M4A sau khi tách không có dữ liệu.")
            }
        case .cancelled:
            throw CancellationError()
        default:
            let detail = exportSession.error?.localizedDescription ?? "Lỗi không xác định"
            throw MuxingError("Tách âm thanh M4A thất bại: \(detail)")
        }
    }
}
