import Foundation

public final class YouTubeExtractorService: @unchecked Sendable {

    public static let androidYouTubeUA =
        "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
    public static let iosYouTubeUA =
        "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
    public static let desktopChromeUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    private let session: URLSession
    private let lock = NSLock()
    private var cachedVisitorData: String = ""
    private var cachedVisitorTimestampMs: Int64 = 0

    private struct InnertubeClientProfile {
        let name: String
        let clientName: String
        let clientVersion: String
        let userAgent: String
        let extraFields: [String: Any]
    }

    private struct ParsedStreamFormat {
        let itag: Int
        let url: String
        let mimeType: String
        let codecs: String
        let qualityLabel: String
        let width: Int
        let height: Int
        let fps: Int
        let bitrate: Int64
        let contentLength: Int64
        let isProgressive: Bool
        let isAudioOnly: Bool
        let isAutoDubbed: Bool
        let isDefaultAudio: Bool

        var isMp4Container: Bool {
            let lower = mimeType.lowercased()
            return lower.hasPrefix("video/mp4") || lower.hasPrefix("audio/mp4")
        }

        var isWebmContainer: Bool {
            let lower = mimeType.lowercased()
            return lower.hasPrefix("video/webm") || lower.hasPrefix("audio/webm")
        }

        var isHdr: Bool {
            let ql = qualityLabel.lowercased()
            let c = codecs.lowercased()
            return ql.contains("hdr") || c.contains("vp9.2") || c.contains("vp09.02") || c.contains(".10.")
        }

        var codecShortLabel: String {
            let c = codecs.lowercased()
            if c.contains("av01") { return isHdr ? "AV1 HDR" : "AV1" }
            if c.contains("vp9") || c.contains("vp09") { return isHdr ? "VP9 HDR" : "VP9" }
            if c.contains("hev1") || c.contains("hvc1") { return isHdr ? "HEVC HDR" : "HEVC" }
            if c.contains("avc1") { return "H.264" }
            if c.contains("mp4a") { return "AAC" }
            if c.contains("opus") { return "Opus" }
            return "MP4"
        }

        var tier: VideoResolutionTier {
            VideoResolutionTier.classify(width: width, height: height, qualityHint: qualityLabel)
        }
    }

    private struct QuadOptionMeta {
        let id: String
        let vi: String
        let en: String
        let badge: String
    }

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: config)
        }
    }

    public func extractMedia(
        rawUrl: String,
        customEndpoint: String = ""
    ) async -> Result<UnifiedMediaInfo, Error> {
        do {
            guard let cleanUrl = YouTubeUrlParser.extractUrl(rawUrl) else {
                throw ExtractionError("Liên kết YouTube không hợp lệ")
            }
            guard let videoId = YouTubeUrlParser.extractVideoId(cleanUrl) else {
                throw ExtractionError("Không tìm thấy mã video YouTube (11 ký tự) trong liên kết")
            }
            let isShortsHint = YouTubeUrlParser.isShortsUrl(cleanUrl)
            var errors: [String] = []

            let trimmedEndpoint = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEndpoint.isEmpty {
                do {
                    let customInfo = try await extractViaCustomEndpoint(
                        endpoint: trimmedEndpoint,
                        cleanUrl: cleanUrl,
                        videoId: videoId,
                        isShortsHint: isShortsHint
                    )
                    return .success(customInfo)
                } catch {
                    errors.append("Custom API: \(error.localizedDescription)")
                }
            }

            let visitorData = await getOrFetchVisitorData(videoId: videoId)

            let profiles: [InnertubeClientProfile] = [
                InnertubeClientProfile(
                    name: "NVTSnapMedia YouTube iOS Engine",
                    clientName: "IOS",
                    clientVersion: "20.10.4",
                    userAgent: Self.iosYouTubeUA,
                    extraFields: [
                        "deviceMake": "Apple",
                        "deviceModel": "iPhone16,2",
                        "osName": "iPhone",
                        "osVersion": "18.3.2.22D82"
                    ]
                ),
                InnertubeClientProfile(
                    name: "NVTSnapMedia YouTube Ultra-HD Engine",
                    clientName: "ANDROID",
                    clientVersion: "20.10.38",
                    userAgent: Self.androidYouTubeUA,
                    extraFields: [
                        "androidSdkVersion": 34,
                        "osName": "Android",
                        "osVersion": "14"
                    ]
                )
            ]

            var bestCandidate: UnifiedMediaInfo?

            for profile in profiles {
                do {
                    let media = try await queryInnertubePlayer(
                        videoId: videoId,
                        originalUrl: cleanUrl,
                        isShortsHint: isShortsHint,
                        profile: profile,
                        visitorData: visitorData
                    )
                    let has4KOr2K = media.downloadOptions.contains {
                        $0.id == "ytb_video_4k" || $0.id == "ytb_video_2k"
                    }
                    if has4KOr2K {
                        let upgraded = await upgradeMaxResCoverIfAvailable(media: media, videoId: videoId)
                        return .success(upgraded)
                    }
                    if let currentBest = bestCandidate {
                        let currentUltraCount = currentBest.downloadOptions.filter(\.isUltraHd).count
                        let newUltraCount = media.downloadOptions.filter(\.isUltraHd).count
                        if newUltraCount > currentUltraCount ||
                            (newUltraCount == currentUltraCount && media.downloadOptions.count > currentBest.downloadOptions.count) {
                            bestCandidate = media
                        }
                    } else {
                        bestCandidate = media
                    }
                } catch {
                    errors.append("\(profile.clientName): \(error.localizedDescription)")
                    clearCachedVisitorData()
                }
            }

            if let bestCandidate {
                let upgraded = await upgradeMaxResCoverIfAvailable(media: bestCandidate, videoId: videoId)
                return .success(upgraded)
            }

            let detail = errors.first.map { " (\($0))" } ?? ""
            throw ExtractionError(
                "Không thể bóc tách video YouTube này. Hãy kiểm tra video đang ở chế độ Công khai và không giới hạn độ tuổi\(detail)"
            )
        } catch {
            return .failure(error)
        }
    }

    private func getOrFetchVisitorData(videoId: String) async -> String {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        lock.lock()
        if !cachedVisitorData.isEmpty && (nowMs - cachedVisitorTimestampMs) < 25 * 60 * 1000 {
            let val = cachedVisitorData
            lock.unlock()
            return val
        }
        lock.unlock()

        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&hl=vi") else {
            return ""
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await session.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            if let groups = RegexUtils.firstMatch(in: html, pattern: #""VISITOR_DATA"\s*:\s*"([^"]+)""#),
               groups.count > 1, !groups[1].isEmpty {
                let found = groups[1]
                lock.lock()
                cachedVisitorData = found
                cachedVisitorTimestampMs = nowMs
                lock.unlock()
                return found
            }
        } catch {
            return ""
        }
        return ""
    }

    private func clearCachedVisitorData() {
        lock.lock()
        cachedVisitorData = ""
        lock.unlock()
    }

    private func queryInnertubePlayer(
        videoId: String,
        originalUrl: String,
        isShortsHint: Bool,
        profile: InnertubeClientProfile,
        visitorData: String
    ) async throws -> UnifiedMediaInfo {
        guard let endpointUrl = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw ExtractionError("Endpoint Innertube không hợp lệ")
        }

        var clientDict: [String: Any] = [
            "clientName": profile.clientName,
            "clientVersion": profile.clientVersion,
            "hl": "vi",
            "gl": "VN"
        ]
        for (k, v) in profile.extraFields {
            clientDict[k] = v
        }
        if !visitorData.isEmpty {
            clientDict["visitorData"] = visitorData
        }

        let payloadDict: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "context": [
                "client": clientDict
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: payloadDict)
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !visitorData.isEmpty {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        let (data, response) = try await session.data(for: request)
        if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            throw ExtractionError("HTTP \(httpResp.statusCode)")
        }
        guard !data.isEmpty, let rawJson = String(data: data, encoding: .utf8) else {
            throw ExtractionError("Phản hồi rỗng từ máy chủ YouTube")
        }

        return try parseInnertubePlayerResponse(
            rawJson: rawJson,
            videoId: videoId,
            originalUrl: originalUrl,
            isShortsHint: isShortsHint,
            clientUserAgent: profile.userAgent,
            providerName: profile.name,
            allowWebmFallback: false
        )
    }

    public func parseInnertubePlayerResponse(
        rawJson: String,
        videoId: String,
        originalUrl: String,
        isShortsHint: Bool,
        clientUserAgent: String,
        providerName: String,
        allowWebmFallback: Bool = false
    ) throws -> UnifiedMediaInfo {
        guard let rawData = rawJson.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any] else {
            throw ExtractionError("Dữ liệu JSON từ YouTube không hợp lệ")
        }

        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           !status.isEmpty && status != "OK" {
            let reason = (playability["reason"] as? String) ?? "Trạng thái phát: \(status)"
            throw ExtractionError(reason)
        }

        let videoDetails = root["videoDetails"] as? [String: Any]
        let parsedId = (videoDetails?["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? videoId
        let title = (videoDetails?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "YouTube Video \(parsedId)"
        let author = (videoDetails?["author"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "YouTube Creator"
        let durationSec = Self.jsonInt(videoDetails?["lengthSeconds"]) ?? 0
        let rawViews = Self.jsonString(videoDetails?["viewCount"]) ?? ""
        let viewCountText = MediaUrlDetector.formatCompactCountString(rawViews)

        var bestThumbFromJson = ""
        if let thumbContainer = videoDetails?["thumbnail"] as? [String: Any],
           let thumbs = thumbContainer["thumbnails"] as? [[String: Any]] {
            let best = thumbs.max { a, b in
                let areaA = (Self.jsonInt(a["width"]) ?? 0) * (Self.jsonInt(a["height"]) ?? 0)
                let areaB = (Self.jsonInt(b["width"]) ?? 0) * (Self.jsonInt(b["height"]) ?? 0)
                return areaA < areaB
            }
            bestThumbFromJson = (best?["url"] as? String) ?? ""
        }
        let coverUrl = bestThumbFromJson.isEmpty ? "https://i.ytimg.com/vi/\(parsedId)/hqdefault.jpg" : bestThumbFromJson

        guard let streamingData = root["streamingData"] as? [String: Any] else {
            throw ExtractionError("Video không chứa luồng tải công khai")
        }

        let progressiveFormats = ((streamingData["formats"] as? [[String: Any]]) ?? [])
            .compactMap { parseFormatNode($0, isProgressive: true) }
        let adaptiveFormats = ((streamingData["adaptiveFormats"] as? [[String: Any]]) ?? [])
            .compactMap { parseFormatNode($0, isProgressive: false) }

        if progressiveFormats.isEmpty && adaptiveFormats.isEmpty {
            throw ExtractionError("Không tìm thấy luồng tải trực tiếp cho video YouTube này")
        }

        let sampleVideo = adaptiveFormats.first { !$0.isAudioOnly && $0.width > 0 && $0.height > 0 }
            ?? progressiveFormats.first { $0.width > 0 && $0.height > 0 }
        let isVertical = sampleVideo != nil && sampleVideo!.height > sampleVideo!.width
        let isShorts = isShortsHint || (isVertical && (1...180).contains(durationSec))
        let mediaKindVi = isShorts ? "Shorts" : "Video"
        let mediaKindEn = isShorts ? "Short" : "Video"

        let mp4AudioCandidates = adaptiveFormats.filter { $0.isAudioOnly && $0.isMp4Container }
        let bestM4aAudio = mp4AudioCandidates.sorted { a, b in
            if (!a.isAutoDubbed) != (!b.isAutoDubbed) { return !a.isAutoDubbed && b.isAutoDubbed }
            if a.isDefaultAudio != b.isDefaultAudio { return a.isDefaultAudio && !b.isDefaultAudio }
            if (a.itag == 140) != (b.itag == 140) { return a.itag == 140 }
            return a.bitrate > b.bitrate
        }.first

        let bestProgressive = progressiveFormats
            .filter(\.isMp4Container)
            .max { a, b in
                (a.height * 10_000 + Int(a.bitrate / 1000)) < (b.height * 10_000 + Int(b.bitrate / 1000))
            } ?? progressiveFormats.first

        let progressive720 = progressiveFormats.first { $0.tier == .hd720p && $0.isMp4Container }
        let progressive360 = progressiveFormats.first { $0.tier == .sd && $0.isMp4Container } ?? bestProgressive

        let muxAudioUrl = bestM4aAudio?.url ?? ""
        let muxAudioSize = bestM4aAudio?.contentLength ?? 0
        let fallbackProgUrl = bestProgressive?.url ?? ""

        // On iOS, prioritize ISO-BMFF MP4 video tracks (H.264 / HEVC / AV1) for native AVFoundation muxing & Photos Library compatibility
        let adaptiveVideos = adaptiveFormats.filter { fmt in
            guard !fmt.isAudioOnly else { return false }
            if allowWebmFallback {
                return fmt.isMp4Container || fmt.isWebmContainer
            } else {
                return fmt.isMp4Container
            }
        }

        let groupedByTier = Dictionary(grouping: adaptiveVideos, by: \.tier)
        var bestAdaptiveByTier: [VideoResolutionTier: ParsedStreamFormat] = [:]
        for (tier, candidates) in groupedByTier {
            if let selected = selectBestVideoForTier(tier: tier, candidates: candidates) {
                bestAdaptiveByTier[tier] = selected
            }
        }

        var options: [DownloadQualityOption] = []
        let aboveHdTiers: [VideoResolutionTier] = [.uhd4k, .qhd2k, .fhd1080p]

        if !muxAudioUrl.isEmpty {
            for tier in aboveHdTiers {
                guard let rep = bestAdaptiveByTier[tier] else { continue }
                let fpsLabel = rep.fps >= 50 ? " \(rep.fps)FPS" : ""
                let hdrTag = rep.isHdr ? " HDR" : ""
                let dimText = (rep.width > 0 && rep.height > 0) ? "\(rep.width)×\(rep.height)" : ""

                let meta: QuadOptionMeta
                switch tier {
                case .uhd4k:
                    meta = QuadOptionMeta(
                        id: "ytb_video_4k",
                        vi: "Tải \(mediaKindVi) 4K Ultra HD (2160p\(fpsLabel)\(hdrTag))",
                        en: "Download \(mediaKindEn) 4K Ultra HD (2160p\(fpsLabel)\(hdrTag))",
                        badge: rep.fps >= 50 ? "4K 60FPS" : "4K UHD"
                    )
                case .qhd2k:
                    meta = QuadOptionMeta(
                        id: "ytb_video_2k",
                        vi: "Tải \(mediaKindVi) 2K Quad HD (1440p\(fpsLabel)\(hdrTag))",
                        en: "Download \(mediaKindEn) 2K Quad HD (1440p\(fpsLabel)\(hdrTag))",
                        badge: rep.fps >= 50 ? "2K 60FPS" : "2K QHD"
                    )
                default:
                    meta = QuadOptionMeta(
                        id: "ytb_video_1080p",
                        vi: "Tải \(mediaKindVi) Full HD (1080p\(fpsLabel))",
                        en: "Download \(mediaKindEn) Full HD (1080p\(fpsLabel))",
                        badge: rep.fps >= 50 ? "1080p 60FPS" : "1080p FHD"
                    )
                }

                let combinedSize = (rep.contentLength > 0 && muxAudioSize > 0)
                    ? (rep.contentLength + muxAudioSize)
                    : rep.contentLength

                var subViParts: [String] = []
                if !dimText.isEmpty { subViParts.append(dimText) }
                if rep.fps >= 50 { subViParts.append("\(rep.fps)fps mượt") }
                subViParts.append(rep.codecShortLabel)
                subViParts.append("Ghép âm thanh gốc AAC Lossless")

                var subEnParts: [String] = []
                if !dimText.isEmpty { subEnParts.append(dimText) }
                if rep.fps >= 50 { subEnParts.append("\(rep.fps)fps") }
                subEnParts.append(rep.codecShortLabel)
                subEnParts.append("Lossless AAC Mux")

                options.append(
                    DownloadQualityOption(
                        id: meta.id,
                        labelVi: meta.vi,
                        labelEn: meta.en,
                        subtitleVi: subViParts.joined(separator: " • "),
                        subtitleEn: subEnParts.joined(separator: " • "),
                        badge: meta.badge,
                        url: rep.url,
                        audioStreamUrl: muxAudioUrl,
                        fallbackUrl: fallbackProgUrl,
                        clientUserAgent: clientUserAgent,
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        sizeBytes: combinedSize,
                        width: rep.width,
                        height: rep.height,
                        fps: rep.fps,
                        codecLabel: rep.codecShortLabel,
                        isUltraHd: true,
                        isPrimary: options.isEmpty
                    )
                )
            }
        }

        let dash720 = bestAdaptiveByTier[.hd720p]
        if let progressive720 {
            options.append(
                DownloadQualityOption(
                    id: "ytb_video_720p",
                    labelVi: "Tải \(mediaKindVi) HD (720p Nguyên khối)",
                    labelEn: "Download \(mediaKindEn) HD (720p Progressive)",
                    subtitleVi: "\(progressive720.width)×\(progressive720.height) • H.264 • Có sẵn âm thanh",
                    subtitleEn: "\(progressive720.width)×\(progressive720.height) • H.264 • Built-in audio",
                    badge: "720p HD",
                    url: progressive720.url,
                    fallbackUrl: fallbackProgUrl,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    sizeBytes: progressive720.contentLength,
                    width: progressive720.width,
                    height: progressive720.height,
                    fps: progressive720.fps,
                    codecLabel: "H.264",
                    isPrimary: options.isEmpty
                )
            )
        } else if let dash720, !muxAudioUrl.isEmpty {
            let fps720 = dash720.fps >= 50 ? " \(dash720.fps)FPS" : ""
            let size720 = dash720.contentLength > 0 ? (dash720.contentLength + muxAudioSize) : 0
            options.append(
                DownloadQualityOption(
                    id: "ytb_video_720p",
                    labelVi: "Tải \(mediaKindVi) HD (720p\(fps720))",
                    labelEn: "Download \(mediaKindEn) HD (720p\(fps720))",
                    subtitleVi: "\(dash720.width)×\(dash720.height) • \(dash720.codecShortLabel) • Ghép âm thanh gốc AAC",
                    subtitleEn: "\(dash720.width)×\(dash720.height) • \(dash720.codecShortLabel) • Lossless AAC Mux",
                    badge: dash720.fps >= 50 ? "720p 60FPS" : "720p HD",
                    url: dash720.url,
                    audioStreamUrl: muxAudioUrl,
                    fallbackUrl: fallbackProgUrl,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    sizeBytes: size720,
                    width: dash720.width,
                    height: dash720.height,
                    fps: dash720.fps,
                    codecLabel: dash720.codecShortLabel,
                    isPrimary: options.isEmpty
                )
            )
        }

        if let dash480 = bestAdaptiveByTier[.sd480p], !muxAudioUrl.isEmpty {
            let size480 = dash480.contentLength > 0 ? (dash480.contentLength + muxAudioSize) : 0
            options.append(
                DownloadQualityOption(
                    id: "ytb_video_480p",
                    labelVi: "Tải \(mediaKindVi) Tiêu chuẩn+ (480p)",
                    labelEn: "Download \(mediaKindEn) Standard+ (480p)",
                    subtitleVi: "\(dash480.width)×\(dash480.height) • Dung lượng cân bằng & tiết kiệm",
                    subtitleEn: "\(dash480.width)×\(dash480.height) • Balanced file size",
                    badge: "480p",
                    url: dash480.url,
                    audioStreamUrl: muxAudioUrl,
                    fallbackUrl: fallbackProgUrl,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    sizeBytes: size480,
                    width: dash480.width,
                    height: dash480.height,
                    fps: dash480.fps,
                    codecLabel: dash480.codecShortLabel,
                    isPrimary: options.isEmpty
                )
            )
        }

        if let progressive360 {
            options.append(
                DownloadQualityOption(
                    id: "ytb_video_sd",
                    labelVi: "Tải \(mediaKindVi) Nhanh (360p Nguyên khối)",
                    labelEn: "Download \(mediaKindEn) Fast (360p Progressive)",
                    subtitleVi: "Luồng MP4 có sẵn âm thanh • Tải siêu tốc 1 chạm",
                    subtitleEn: "Single-stream MP4 with audio • Instant download",
                    badge: "360p SD",
                    url: progressive360.url,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    sizeBytes: progressive360.contentLength,
                    width: progressive360.width,
                    height: progressive360.height,
                    fps: progressive360.fps,
                    codecLabel: "H.264",
                    isPrimary: options.isEmpty
                )
            )
        }

        if let bestM4aAudio {
            let kbps = max(Int(bestM4aAudio.bitrate / 1000), 48)
            options.append(
                DownloadQualityOption(
                    id: "audio_m4a",
                    labelVi: "Tải Nhạc / Âm thanh gốc (M4A \(kbps)kbps)",
                    labelEn: "Download Original Audio (M4A \(kbps)kbps)",
                    subtitleVi: "Luồng âm thanh AAC nguyên bản trực tiếp từ YouTube",
                    subtitleEn: "Direct original YouTube AAC audio stream",
                    badge: "M4A AUDIO",
                    url: bestM4aAudio.url,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .audio,
                    extensionName: "m4a",
                    mimeType: "audio/mp4",
                    sizeBytes: bestM4aAudio.contentLength
                )
            )
        } else if let bestProgressive {
            options.append(
                DownloadQualityOption(
                    id: "audio_m4a",
                    labelVi: "Tách Nhạc / Âm thanh gốc (M4A)",
                    labelEn: "Extract Original Audio (M4A)",
                    subtitleVi: "Tách luồng AAC nguyên bản không giảm chất lượng",
                    subtitleEn: "Lossless hardware AAC track extraction",
                    badge: "M4A AUDIO",
                    url: bestProgressive.url,
                    clientUserAgent: clientUserAgent,
                    mediaCategory: .audio,
                    extensionName: "m4a",
                    mimeType: "audio/mp4",
                    demuxAudioFromVideo: true
                )
            )
        }

        if !coverUrl.isEmpty {
            options.append(
                DownloadQualityOption(
                    id: "cover_jpg",
                    labelVi: "Tải Ảnh bìa gốc (MaxRes Thumbnail)",
                    labelEn: "Download Original Thumbnail (MaxRes JPG)",
                    subtitleVi: "Ảnh thu nhỏ độ nét cao của video YouTube",
                    subtitleEn: "High-resolution YouTube video cover image",
                    badge: "THUMB HD",
                    url: coverUrl,
                    clientUserAgent: Self.desktopChromeUA,
                    mediaCategory: .image,
                    extensionName: "jpg",
                    mimeType: "image/jpeg"
                )
            )
        }

        let previewUrl = bestProgressive?.url
            ?? bestAdaptiveByTier[.hd720p]?.url
            ?? options.first(where: { $0.mediaCategory == .video })?.url
            ?? ""
        let topBadge = options.first(where: { $0.mediaCategory == .video })?.badge ?? ""

        return UnifiedMediaInfo(
            id: parsedId,
            platform: .youtube,
            originalUrl: YouTubeUrlParser.toCanonicalWatchUrl(videoId: parsedId, isShorts: isShorts),
            title: title,
            authorName: author,
            coverUrl: coverUrl,
            durationSeconds: durationSec,
            viewCountText: viewCountText,
            isVerticalShort: isShorts,
            previewStreamUrl: previewUrl,
            previewUserAgent: clientUserAgent,
            maxResolutionBadge: topBadge,
            downloadOptions: options,
            providerName: providerName
        )
    }

    private func selectBestVideoForTier(
        tier: VideoResolutionTier,
        candidates: [ParsedStreamFormat]
    ) -> ParsedStreamFormat? {
        candidates.sorted { a, b in
            if a.isMp4Container != b.isMp4Container {
                return a.isMp4Container && !b.isMp4Container
            }
            // Prefer Apple hardware native H.264/HEVC first when tied on container, then AV1
            let aApplePreferred = a.codecs.lowercased().contains("hvc1") ||
                a.codecs.lowercased().contains("hev1") ||
                a.codecs.lowercased().contains("avc1")
            let bApplePreferred = b.codecs.lowercased().contains("hvc1") ||
                b.codecs.lowercased().contains("hev1") ||
                b.codecs.lowercased().contains("avc1")
            if aApplePreferred != bApplePreferred {
                return aApplePreferred && !bApplePreferred
            }
            if tier == .uhd4k || tier == .qhd2k {
                if (!a.isHdr) != (!b.isHdr) {
                    return !a.isHdr && b.isHdr
                }
            }
            if a.fps != b.fps {
                return a.fps > b.fps
            }
            return a.bitrate > b.bitrate
        }.first
    }

    private func parseFormatNode(_ obj: [String: Any], isProgressive: Bool) -> ParsedStreamFormat? {
        guard let url = obj["url"] as? String, !url.isEmpty else { return nil }
        let itag = Self.jsonInt(obj["itag"]) ?? 0
        let rawMime = (obj["mimeType"] as? String) ?? ""
        let mimeBase = rawMime.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let codecs = RegexUtils.firstMatch(in: rawMime, pattern: #"codecs="([^"]+)""#)?
            .dropFirst().first ?? ""

        let qualityLabel = (obj["qualityLabel"] as? String) ?? ""
        let width = Self.jsonInt(obj["width"]) ?? 0
        let height = Self.jsonInt(obj["height"]) ?? 0
        let fps = Self.jsonInt(obj["fps"]) ?? 0
        let bitrate = Self.jsonInt64(obj["bitrate"]) ?? Self.jsonInt64(obj["averageBitrate"]) ?? 0
        let contentLength = Self.jsonInt64(obj["contentLength"]) ?? 0

        let isAudioOnly = mimeBase.lowercased().hasPrefix("audio/")
        let audioTrackObj = obj["audioTrack"] as? [String: Any]
        let audioDisplayName = (audioTrackObj?["displayName"] as? String) ?? ""
        let isAutoDubbed = ((audioTrackObj?["isAutoDubbed"] as? Bool) == true) ||
            audioDisplayName.localizedCaseInsensitiveContains("auto-dubbed")
        let isDefaultAudio = (audioTrackObj?["audioIsDefault"] as? Bool) ?? true

        return ParsedStreamFormat(
            itag: itag,
            url: url,
            mimeType: mimeBase,
            codecs: codecs,
            qualityLabel: qualityLabel,
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            contentLength: contentLength,
            isProgressive: isProgressive,
            isAudioOnly: isAudioOnly,
            isAutoDubbed: isAutoDubbed,
            isDefaultAudio: isDefaultAudio
        )
    }

    private func upgradeMaxResCoverIfAvailable(media: UnifiedMediaInfo, videoId: String) async -> UnifiedMediaInfo {
        if media.coverUrl.contains("maxresdefault") { return media }
        let maxResUrlStr = "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg"
        guard let maxResUrl = URL(string: maxResUrlStr) else { return media }

        var req = URLRequest(url: maxResUrl)
        req.httpMethod = "HEAD"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")

        let exists: Bool
        do {
            let (_, resp) = try await session.data(for: req)
            exists = (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            exists = false
        }

        guard exists else { return media }
        var copy = media
        copy.coverUrl = maxResUrlStr
        copy.downloadOptions = media.downloadOptions.map { opt in
            guard opt.id == "cover_jpg" else { return opt }
            var updated = opt
            updated.url = maxResUrlStr
            return updated
        }
        return copy
    }

    private func extractViaCustomEndpoint(
        endpoint: String,
        cleanUrl: String,
        videoId: String,
        isShortsHint: Bool
    ) async throws -> UnifiedMediaInfo {
        let encodedUrl = cleanUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanUrl
        let target: String
        if endpoint.contains("{url}") {
            target = endpoint.replacingOccurrences(of: "{url}", with: encodedUrl)
        } else {
            let sep = endpoint.contains("?") ? "&" : "?"
            target = "\(endpoint)\(sep)url=\(encodedUrl)"
        }
        guard let reqUrl = URL(string: target) else {
            throw ExtractionError("URL máy chủ tùy chỉnh không hợp lệ")
        }

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        if let httpResp = resp as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            throw ExtractionError("HTTP \(httpResp.statusCode)")
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        if bodyStr.contains("\"streamingData\"") {
            return try parseInnertubePlayerResponse(
                rawJson: bodyStr,
                videoId: videoId,
                originalUrl: cleanUrl,
                isShortsHint: isShortsHint,
                clientUserAgent: Self.iosYouTubeUA,
                providerName: "Custom Innertube Server"
            )
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let videoUrl = (obj["hd"] as? String) ?? (obj["url"] as? String),
              !videoUrl.isEmpty else {
            throw ExtractionError("JSON máy chủ tùy chỉnh thiếu trường url")
        }
        let title = (obj["title"] as? String) ?? "YouTube Video \(videoId)"
        let author = (obj["author"] as? String) ?? "YouTube Creator"
        let thumb = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"

        let options = [
            DownloadQualityOption(
                id: "ytb_custom_hd",
                labelVi: "Tải Video (Máy chủ tùy chỉnh)",
                labelEn: "Download Video (Custom Server)",
                subtitleVi: "Luồng trực tiếp từ máy chủ tùy chỉnh",
                subtitleEn: "Direct stream from custom endpoint",
                badge: "FULL HD",
                url: videoUrl,
                clientUserAgent: Self.desktopChromeUA,
                mediaCategory: .video,
                extensionName: "mp4",
                mimeType: "video/mp4",
                isPrimary: true
            )
        ]

        return UnifiedMediaInfo(
            id: videoId,
            platform: .youtube,
            originalUrl: cleanUrl,
            title: title,
            authorName: author,
            coverUrl: thumb,
            isVerticalShort: isShortsHint,
            previewStreamUrl: videoUrl,
            previewUserAgent: Self.desktopChromeUA,
            maxResolutionBadge: "FULL HD",
            downloadOptions: options,
            providerName: "Custom API"
        )
    }

    private static func jsonString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func jsonInt64(_ value: Any?) -> Int64? {
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }
}
