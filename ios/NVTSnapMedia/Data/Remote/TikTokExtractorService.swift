import Foundation

public struct DirectVideoGear: Equatable, Sendable {
    public let gearName: String
    public let qualityType: Int
    public let codecLabel: String
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrate: Int64
    public let sizeBytes: Int64
    public let url: String
    public let cookieHeader: String

    public init(
        gearName: String,
        qualityType: Int,
        codecLabel: String,
        width: Int,
        height: Int,
        fps: Int,
        bitrate: Int64,
        sizeBytes: Int64,
        url: String,
        cookieHeader: String
    ) {
        self.gearName = gearName
        self.qualityType = qualityType
        self.codecLabel = codecLabel
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        self.sizeBytes = sizeBytes
        self.url = url
        self.cookieHeader = cookieHeader
    }

    public var tier: VideoResolutionTier {
        VideoResolutionTier.classify(width: width, height: height, qualityHint: gearName)
    }
}

public struct Mp4ProbeResult: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let totalBytes: Int64

    public init(width: Int = 0, height: Int = 0, totalBytes: Int64 = 0) {
        self.width = width
        self.height = height
        self.totalBytes = totalBytes
    }
}

public final class TikTokExtractorService: Sendable {

    private static let tikWmBase = "https://www.tikwm.com"
    private static let tikWmApiPrimary = "https://www.tikwm.com/api/"
    private static let tikWmApiMirror = "https://tikwm.com/api/"
    private static let workerFallbackApi = "https://tdownv4.sl-bjs.workers.dev/"

    public static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
    public static let desktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"

    private let session: URLSession
    private let probeSession: URLSession

    private struct QuadStrings {
        let id: String
        let vi: String
        let en: String
        let badge: String
    }

    public struct DirectRehydrationResult: Sendable {
        public let gears: [DirectVideoGear]
        public let mediaInfo: UnifiedMediaInfo?
    }

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.probeSession = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 20
            cfg.timeoutIntervalForResource = 35
            self.session = URLSession(configuration: cfg)

            let probeCfg = URLSessionConfiguration.ephemeral
            probeCfg.timeoutIntervalForRequest = 5
            probeCfg.timeoutIntervalForResource = 7
            self.probeSession = URLSession(configuration: probeCfg)
        }
    }

    /// Parses MP4 ISO-BMFF `tkhd` (Track Header) atom to extract true pixel width & height.
    public static func parseMp4TkhdDimensions(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 88 else { return nil }
        let limit = bytes.count - 88
        var idx = 0
        var bestPixels: Int64 = 0
        var bestPair: (Int, Int)?

        let tByte = UInt8(ascii: "t")
        let kByte = UInt8(ascii: "k")
        let hByte = UInt8(ascii: "h")
        let dByte = UInt8(ascii: "d")

        while idx <= limit {
            if bytes[idx] == tByte &&
                bytes[idx + 1] == kByte &&
                bytes[idx + 2] == hByte &&
                bytes[idx + 3] == dByte {
                let version = Int(bytes[idx + 4])
                let widthOffset = (version == 1) ? (idx + 92) : (idx + 80)
                let heightOffset = (version == 1) ? (idx + 96) : (idx + 84)
                if heightOffset + 4 <= bytes.count {
                    let wFixed = readBigEndianUInt32(bytes, offset: widthOffset)
                    let hFixed = readBigEndianUInt32(bytes, offset: heightOffset)
                    let w = Int((wFixed >> 16) & 0xFFFF)
                    let h = Int((hFixed >> 16) & 0xFFFF)
                    if (120...8192).contains(w) && (120...8192).contains(h) {
                        let area = Int64(w) * Int64(h)
                        if area > bestPixels {
                            bestPixels = area
                            bestPair = (w, h)
                        }
                    }
                }
                idx += 4
            } else {
                idx += 1
            }
        }
        return bestPair
    }

    private static func readBigEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) |
        (UInt32(bytes[offset + 1]) << 16) |
        (UInt32(bytes[offset + 2]) << 8) |
        UInt32(bytes[offset + 3])
    }

    public func extractMedia(
        rawInput: String,
        customEndpoint: String = ""
    ) async -> Result<UnifiedMediaInfo, Error> {
        guard let cleanUrl = TikTokUrlParser.extractUrl(rawInput) else {
            return .failure(
                ExtractionError("Liên kết TikTok không hợp lệ. Vui lòng dán liên kết TikTok hợp lệ.")
            )
        }

        var errors: [String] = []
        let trimmedEndpoint = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedEndpoint.isEmpty {
            do {
                let base = try await extractViaTikWmCompatible(
                    tiktokUrl: cleanUrl,
                    endpoint: trimmedEndpoint,
                    providerName: "Custom Server"
                )
                let enriched = await enrichWithUltraHdStreams(baseMedia: base, cleanUrl: cleanUrl)
                return .success(enriched)
            } catch {
                errors.append("Custom: \(error.localizedDescription)")
            }
        }

        let expandedUrl = (try? await expandShortUrl(cleanUrl)) ?? cleanUrl

        async let directTask: DirectRehydrationResult? = fetchDirectRehydrationPage(
            expandedUrl: expandedUrl,
            originalUrl: cleanUrl
        )

        do {
            let baseMedia = try await extractViaTikWmPostWithRetry(
                tiktokUrl: cleanUrl,
                endpoint: Self.tikWmApiPrimary,
                providerName: "NVTSnapMedia TikTok Ultra-HD"
            )
            let directPage = await directTask
            let merged = await enrichBaseMediaWithUltraHd(
                baseMedia: baseMedia,
                directGears: directPage?.gears ?? []
            )
            return .success(merged)
        } catch {
            errors.append("Server 1: \(error.localizedDescription)")
        }

        do {
            let baseMedia = try await extractViaTikWmCompatible(
                tiktokUrl: expandedUrl,
                endpoint: Self.tikWmApiMirror,
                providerName: "NVTSnapMedia TikTok Server 2"
            )
            let directPage = await directTask
            let merged = await enrichBaseMediaWithUltraHd(
                baseMedia: baseMedia,
                directGears: directPage?.gears ?? []
            )
            return .success(merged)
        } catch {
            errors.append("Server 2: \(error.localizedDescription)")
        }

        let finalDirectPage = await directTask
        if let standalone = finalDirectPage?.mediaInfo {
            return .success(standalone)
        }

        do {
            let fallbackMedia = try await extractViaWorkerFallback(tiktokUrl: expandedUrl)
            return .success(fallbackMedia)
        } catch {
            errors.append("Server 3: \(error.localizedDescription)")
        }

        let detail = errors.first?.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            ?? "Không thể kết nối máy chủ phân tích TikTok."
        return .failure(
            ExtractionError("Không thể lấy dữ liệu TikTok (\(detail)). Vui lòng kiểm tra video ở chế độ Công khai.")
        )
    }

    private func enrichWithUltraHdStreams(
        baseMedia: UnifiedMediaInfo,
        cleanUrl: String
    ) async -> UnifiedMediaInfo {
        let expanded = (try? await expandShortUrl(cleanUrl)) ?? cleanUrl
        let direct = await fetchDirectRehydrationPage(expandedUrl: expanded, originalUrl: cleanUrl)
        return await enrichBaseMediaWithUltraHd(baseMedia: baseMedia, directGears: direct?.gears ?? [])
    }

    private func enrichBaseMediaWithUltraHd(
        baseMedia: UnifiedMediaInfo,
        directGears: [DirectVideoGear]
    ) async -> UnifiedMediaInfo {
        guard !baseMedia.isImageGallery else { return baseMedia }
        let hdOpt = baseMedia.downloadOptions.first { $0.id == "video_hd_nologo" }
        let sdOpt = baseMedia.downloadOptions.first { $0.id == "video_sd_nologo" }

        async let hdProbeTask: Mp4ProbeResult = probeOptionalMp4(url: hdOpt?.url)
        async let sdProbeTask: Mp4ProbeResult = probeOptionalMp4(
            url: (sdOpt?.url != hdOpt?.url) ? sdOpt?.url : nil
        )

        let hdProbe = await hdProbeTask
        let sdProbe = await sdProbeTask

        return mergeUltraHdOptions(
            baseMedia: baseMedia,
            directGears: directGears,
            hdProbe: hdProbe,
            sdProbe: sdProbe
        )
    }

    private func probeOptionalMp4(url: String?) async -> Mp4ProbeResult {
        guard let url, !url.isEmpty else { return Mp4ProbeResult() }
        return await probeMp4DimensionsAndSize(url: url)
    }

    public func mergeUltraHdOptions(
        baseMedia: UnifiedMediaInfo,
        directGears: [DirectVideoGear],
        hdProbe: Mp4ProbeResult = Mp4ProbeResult(),
        sdProbe: Mp4ProbeResult = Mp4ProbeResult()
    ) -> UnifiedMediaInfo {
        guard !baseMedia.isImageGallery else { return baseMedia }
        if directGears.isEmpty && hdProbe.width <= 0 && sdProbe.width <= 0 {
            return baseMedia
        }

        let existingHd = baseMedia.downloadOptions.first { $0.id == "video_hd_nologo" }
        let existingSd = baseMedia.downloadOptions.first { $0.id == "video_sd_nologo" }
        let server2Opt = baseMedia.downloadOptions.first { $0.id == "video_server2_nologo" }
        let nonVideoAndAux = baseMedia.downloadOptions.filter {
            $0.id != "video_hd_nologo" && $0.id != "video_sd_nologo" && $0.id != "video_server2_nologo"
        }

        struct CandidateStream {
            let tier: VideoResolutionTier
            let width: Int
            let height: Int
            let fps: Int
            let codecLabel: String
            let sizeBytes: Int64
            let bitrate: Int64
            let url: String
            let fallbackUrl: String
            let cookieHeader: String
            let isOriginalMaster: Bool
        }

        var candidates: [CandidateStream] = []

        if let existingHd {
            let w = hdProbe.width
            let h = hdProbe.height
            let sz = existingHd.sizeBytes > 0 ? existingHd.sizeBytes : hdProbe.totalBytes
            let matchedGear = directGears.first { sz > 0 && $0.sizeBytes == sz }
            let tier: VideoResolutionTier
            if w > 0 && h > 0 {
                tier = VideoResolutionTier.classify(width: w, height: h, qualityHint: "hd")
            } else {
                tier = matchedGear?.tier ?? .fhd1080p
            }
            let resolvedW = w > 0 ? w : (matchedGear?.width ?? 0)
            let resolvedH = h > 0 ? h : (matchedGear?.height ?? 0)
            let estBitrate = matchedGear?.bitrate ?? (sz * 8 / Int64(max(baseMedia.durationSeconds, 1)))

            candidates.append(
                CandidateStream(
                    tier: tier,
                    width: resolvedW,
                    height: resolvedH,
                    fps: matchedGear?.fps ?? 0,
                    codecLabel: matchedGear?.codecLabel ?? "",
                    sizeBytes: sz,
                    bitrate: estBitrate,
                    url: existingHd.url,
                    fallbackUrl: existingHd.fallbackUrl,
                    cookieHeader: "",
                    isOriginalMaster: true
                )
            )
        }

        for gear in directGears where !gear.url.isEmpty {
            let fallback: String
            if gear.tier.isAboveHd, let existingHd {
                fallback = existingHd.url
            } else if let existingSd {
                fallback = existingSd.url
            } else {
                fallback = existingHd?.url ?? ""
            }
            candidates.append(
                CandidateStream(
                    tier: gear.tier,
                    width: gear.width,
                    height: gear.height,
                    fps: gear.fps,
                    codecLabel: gear.codecLabel,
                    sizeBytes: gear.sizeBytes,
                    bitrate: gear.bitrate,
                    url: gear.url,
                    fallbackUrl: fallback,
                    cookieHeader: gear.cookieHeader,
                    isOriginalMaster: false
                )
            )
        }

        if let existingSd {
            let w = sdProbe.width
            let h = sdProbe.height
            let sz = existingSd.sizeBytes > 0 ? existingSd.sizeBytes : sdProbe.totalBytes
            let matchedGear = directGears.first { sz > 0 && $0.sizeBytes == sz }
            let resolvedW = w > 0 ? w : (matchedGear?.width ?? 0)
            let resolvedH = h > 0 ? h : (matchedGear?.height ?? 0)
            let tier: VideoResolutionTier = (resolvedW > 0 && resolvedH > 0)
                ? VideoResolutionTier.classify(width: resolvedW, height: resolvedH)
                : .sd

            candidates.append(
                CandidateStream(
                    tier: tier,
                    width: resolvedW,
                    height: resolvedH,
                    fps: matchedGear?.fps ?? 0,
                    codecLabel: matchedGear?.codecLabel ?? "",
                    sizeBytes: sz,
                    bitrate: matchedGear?.bitrate ?? 0,
                    url: existingSd.url,
                    fallbackUrl: existingSd.fallbackUrl,
                    cookieHeader: "",
                    isOriginalMaster: false
                )
            )
        }

        let grouped = Dictionary(grouping: candidates, by: \.tier)
        let sortedTiers = grouped.keys.sorted(by: >)

        var videoOptions: [DownloadQualityOption] = []
        for (idx, tier) in sortedTiers.enumerated() {
            guard let list = grouped[tier],
                  let stream = list.sorted(by: { a, b in
                      let scoreA = a.isOriginalMaster ? (a.sizeBytes * 105 / 100) : a.sizeBytes
                      let scoreB = b.isOriginalMaster ? (b.sizeBytes * 105 / 100) : b.sizeBytes
                      if scoreA != scoreB { return scoreA > scoreB }
                      if a.fps != b.fps { return a.fps > b.fps }
                      return a.bitrate > b.bitrate
                  }).first else {
                continue
            }

            let dimLabel = (stream.width > 0 && stream.height > 0) ? "\(stream.width)×\(stream.height)" : ""
            let fpsTag = stream.fps >= 50 ? " \(stream.fps)FPS" : ""
            let codecTag = stream.codecLabel.isEmpty ? "MP4" : stream.codecLabel

            let meta: QuadStrings
            switch tier {
            case .uhd4k:
                meta = QuadStrings(
                    id: "tik_video_4k",
                    vi: "Tải Video 4K Ultra HD (2160p • Không Logo)",
                    en: "Download 4K Ultra HD (2160p • No Watermark)",
                    badge: stream.fps >= 50 ? "4K 60FPS" : "4K UHD"
                )
            case .qhd2k:
                meta = QuadStrings(
                    id: "tik_video_2k",
                    vi: "Tải Video 2K Quad HD (1440p • Không Logo)",
                    en: "Download 2K Quad HD (1440p • No Watermark)",
                    badge: stream.fps >= 50 ? "2K 60FPS" : "2K QHD"
                )
            case .fhd1080p:
                meta = QuadStrings(
                    id: "tik_video_1080p",
                    vi: "Tải Video Full HD 1080p\(fpsTag) (Không Logo)",
                    en: "Download Full HD 1080p\(fpsTag) (No Watermark)",
                    badge: stream.fps >= 50 ? "1080p 60FPS" : "1080p FHD"
                )
            case .hd720p:
                meta = QuadStrings(
                    id: "video_hd_nologo",
                    vi: "Tải Video HD 720p (Không Logo)",
                    en: "Download HD 720p Video (No Watermark)",
                    badge: "720p HD"
                )
            default:
                meta = QuadStrings(
                    id: "video_sd_nologo",
                    vi: "Tải Video Tiêu chuẩn (SD • Không Logo)",
                    en: "Download Standard Video (SD • No Watermark)",
                    badge: "SD MP4"
                )
            }

            var detailPartsVi: [String] = []
            if !dimLabel.isEmpty { detailPartsVi.append(dimLabel) }
            if stream.fps >= 50 { detailPartsVi.append("\(stream.fps)fps mượt") }
            detailPartsVi.append(codecTag)
            detailPartsVi.append(tier.isAboveHd ? "Siêu nét gốc • Không logo" : "Không dính ID")

            var detailPartsEn: [String] = []
            if !dimLabel.isEmpty { detailPartsEn.append(dimLabel) }
            if stream.fps >= 50 { detailPartsEn.append("\(stream.fps)fps") }
            detailPartsEn.append(codecTag)
            detailPartsEn.append(tier.isAboveHd ? "Ultra-sharp Master • No Logo" : "Clean No Watermark")

            let isTikWmHost = stream.url.localizedCaseInsensitiveContains("tikwm.com")
            let referer = isTikWmHost ? "https://www.tikwm.com/" : "https://www.tiktok.com/"
            let ua = (!isTikWmHost && !stream.cookieHeader.isEmpty) ? Self.desktopUserAgent : Self.browserUserAgent

            videoOptions.append(
                DownloadQualityOption(
                    id: meta.id,
                    labelVi: meta.vi,
                    labelEn: meta.en,
                    subtitleVi: detailPartsVi.joined(separator: " • "),
                    subtitleEn: detailPartsEn.joined(separator: " • "),
                    badge: meta.badge,
                    url: stream.url,
                    fallbackUrl: stream.fallbackUrl,
                    clientUserAgent: ua,
                    cookieHeader: stream.cookieHeader,
                    refererHeader: referer,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    sizeBytes: stream.sizeBytes,
                    width: stream.width,
                    height: stream.height,
                    fps: stream.fps,
                    codecLabel: stream.codecLabel,
                    isUltraHd: tier.isAboveHd,
                    isPrimary: idx == 0
                )
            )
        }

        if var server2Opt {
            server2Opt.isPrimary = false
            videoOptions.append(server2Opt)
        }

        let auxNormalized = nonVideoAndAux.map { opt -> DownloadQualityOption in
            var copy = opt
            copy.isPrimary = false
            return copy
        }

        var updated = baseMedia
        updated.maxResolutionBadge = videoOptions.first?.badge ?? ""
        updated.downloadOptions = videoOptions + auxNormalized
        return updated
    }

    private func fetchDirectRehydrationPage(
        expandedUrl: String,
        originalUrl: String
    ) async -> DirectRehydrationResult? {
        guard let reqUrl = URL(string: expandedUrl) else { return nil }
        let cookieCfg = URLSessionConfiguration.ephemeral
        cookieCfg.timeoutIntervalForRequest = 18
        cookieCfg.httpCookieAcceptPolicy = .always
        cookieCfg.httpShouldSetCookies = true
        let isolatedSession = URLSession(configuration: cookieCfg)
        defer { isolatedSession.finishTasksAndInvalidate() }

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, resp) = try await isolatedSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let storedCookies = cookieCfg.httpCookieStorage?.cookies ?? []
            let cookieHeader = storedCookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            let html = String(data: data, encoding: .utf8) ?? ""
            guard !html.isEmpty else { return nil }
            return parseDirectRehydrationHtml(html: html, originalUrl: originalUrl, cookieHeader: cookieHeader)
        } catch {
            return nil
        }
    }

    public func parseDirectRehydrationHtml(
        html: String,
        originalUrl: String,
        cookieHeader: String = ""
    ) -> DirectRehydrationResult {
        guard let groups = RegexUtils.firstMatch(
            in: html,
            pattern: #"<script[^>]*id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>"#,
            options: [.dotMatchesLineSeparators]
        ), groups.count > 1 else {
            return DirectRehydrationResult(gears: [], mediaInfo: nil)
        }

        guard let jsonData = groups[1].data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let defaultScope = root["__DEFAULT_SCOPE__"] as? [String: Any],
              let videoDetail = defaultScope["webapp.video-detail"] as? [String: Any],
              let itemInfo = videoDetail["itemInfo"] as? [String: Any],
              let itemStruct = itemInfo["itemStruct"] as? [String: Any] else {
            return DirectRehydrationResult(gears: [], mediaInfo: nil)
        }

        let videoObj = itemStruct["video"] as? [String: Any]
        var gears: [DirectVideoGear] = []

        if let videoObj {
            if let bitrateArray = videoObj["bitrateInfo"] as? [[String: Any]] {
                for brObj in bitrateArray {
                    let gearName = Self.optString(brObj, "GearName")
                    let qualityType = Self.optInt(brObj, "QualityType", default: 99)
                    let rawCodec = Self.optString(brObj, "CodecType").lowercased()
                    let codecLabel: String
                    if rawCodec.contains("265") || rawCodec.contains("hvc") || rawCodec.contains("bytevc1") {
                        codecLabel = "HEVC"
                    } else if rawCodec.contains("bytevc2") || rawCodec.contains("266") {
                        codecLabel = "VVC"
                    } else if rawCodec.contains("av1") || rawCodec.contains("av01") {
                        codecLabel = "AV1"
                    } else {
                        codecLabel = "H.264"
                    }
                    let fps = Self.optInt(brObj, "FPS", default: 0)
                    let bitrate = Self.optInt64(brObj, "Bitrate", default: 0)
                    guard let playAddr = brObj["PlayAddr"] as? [String: Any] else { continue }
                    let w = Self.optInt(playAddr, "Width", default: 0)
                    let h = Self.optInt(playAddr, "Height", default: 0)
                    let dataSize = Self.optInt64(playAddr, "DataSize", default: 0)
                    let urlList = ((playAddr["UrlList"] as? [Any]) ?? [])
                        .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let chosenUrl = urlList.first { !$0.contains("tiktok.com/aweme/") }
                        ?? urlList.first ?? ""

                    if chosenUrl.hasPrefix("http") {
                        gears.append(
                            DirectVideoGear(
                                gearName: gearName,
                                qualityType: qualityType,
                                codecLabel: codecLabel,
                                width: w,
                                height: h,
                                fps: fps,
                                bitrate: bitrate,
                                sizeBytes: dataSize,
                                url: chosenUrl,
                                cookieHeader: cookieHeader
                            )
                        )
                    }
                }
            }

            if gears.isEmpty {
                let mainPlay = Self.optString(videoObj, "playAddr")
                if mainPlay.hasPrefix("http") {
                    gears.append(
                        DirectVideoGear(
                            gearName: Self.optString(videoObj, "ratio", default: "hd"),
                            qualityType: 10,
                            codecLabel: "H.264",
                            width: Self.optInt(videoObj, "width", default: 0),
                            height: Self.optInt(videoObj, "height", default: 0),
                            fps: 0,
                            bitrate: Self.optInt64(videoObj, "bitrate", default: 0),
                            sizeBytes: Self.optInt64(videoObj, "size", default: 0),
                            url: mainPlay,
                            cookieHeader: cookieHeader
                        )
                    )
                }
            }
        }

        guard !gears.isEmpty else {
            return DirectRehydrationResult(gears: [], mediaInfo: nil)
        }

        let rawId = Self.optString(itemStruct, "id")
        let id = rawId.isEmpty ? "\(Int64(Date().timeIntervalSince1970 * 1000))" : rawId
        let rawDesc = Self.optString(itemStruct, "desc")
        let desc = rawDesc.isEmpty ? "TikTok Video #\(id)" : rawDesc
        let authorObj = itemStruct["author"] as? [String: Any]
        let rawAuthorId = Self.optString(authorObj, "uniqueId")
        let authorId = rawAuthorId.isEmpty ? "tiktok_user" : rawAuthorId
        let rawNick = Self.optString(authorObj, "nickname")
        let authorNick = rawNick.isEmpty ? authorId : rawNick
        let avatar = Self.optString(authorObj, "avatarLarger")
        let originCover = Self.optString(videoObj, "originCover")
        let cover = originCover.isEmpty ? Self.optString(videoObj, "cover") : originCover
        let duration = Self.optInt(videoObj, "duration", default: 0)
        let stats = itemStruct["stats"] as? [String: Any]
        let playCount = Self.optInt64(stats, "playCount", default: 0)
        let diggCount = Self.optInt64(stats, "diggCount", default: 0)
        let musicObj = itemStruct["music"] as? [String: Any]
        let musicUrl = Self.optString(musicObj, "playUrl")
        let rawMusicTitle = Self.optString(musicObj, "title")
        let musicTitle = rawMusicTitle.isEmpty ? "Original Sound" : rawMusicTitle

        var auxOptions: [DownloadQualityOption] = []
        if !musicUrl.isEmpty {
            auxOptions.append(
                DownloadQualityOption(
                    id: "audio_mp3",
                    labelVi: "Tải Nhạc Nền (MP3)",
                    labelEn: "Download Original Audio (MP3)",
                    subtitleVi: musicTitle,
                    subtitleEn: musicTitle,
                    badge: "MP3",
                    url: musicUrl,
                    clientUserAgent: Self.desktopUserAgent,
                    cookieHeader: cookieHeader,
                    refererHeader: "https://www.tiktok.com/",
                    mediaCategory: .audio,
                    extensionName: "mp3",
                    mimeType: "audio/mpeg"
                )
            )
        }
        if !cover.isEmpty {
            auxOptions.append(
                DownloadQualityOption(
                    id: "cover_jpg",
                    labelVi: "Tải Ảnh Bìa (Thumbnail HD)",
                    labelEn: "Download Cover Image (HD)",
                    subtitleVi: "Ảnh bìa gốc của video TikTok",
                    subtitleEn: "Original TikTok cover thumbnail",
                    badge: "JPG",
                    url: cover,
                    clientUserAgent: Self.browserUserAgent,
                    refererHeader: "https://www.tiktok.com/",
                    mediaCategory: .image,
                    extensionName: "jpg",
                    mimeType: "image/jpeg"
                )
            )
        }

        let cleanHandle = authorId.hasPrefix("@") ? String(authorId.dropFirst()) : authorId
        let skeleton = UnifiedMediaInfo(
            id: id,
            platform: .tiktok,
            originalUrl: originalUrl,
            title: desc,
            authorName: authorNick,
            authorHandle: "@\(cleanHandle)",
            authorAvatarUrl: avatar,
            coverUrl: cover,
            durationSeconds: duration,
            viewCountText: MediaUrlDetector.formatCompactCount(playCount),
            likeCountText: MediaUrlDetector.formatCompactCount(diggCount),
            musicTitle: musicTitle,
            isVerticalShort: true,
            previewStreamUrl: gears.last?.url ?? "",
            previewUserAgent: Self.desktopUserAgent,
            downloadOptions: auxOptions,
            providerName: "NVTSnapMedia TikTok Direct Ultra-HD"
        )

        let fullStandalone = mergeUltraHdOptions(baseMedia: skeleton, directGears: gears)
        return DirectRehydrationResult(gears: gears, mediaInfo: fullStandalone)
    }

    private func probeMp4DimensionsAndSize(url: String) async -> Mp4ProbeResult {
        guard !url.isEmpty, let reqUrl = URL(string: url) else { return Mp4ProbeResult() }
        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-131071", forHTTPHeaderField: "Range")

        do {
            let (data, resp) = try await probeSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return Mp4ProbeResult()
            }
            var totalBytes: Int64 = 0
            if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
               let slashIdx = contentRange.lastIndex(of: "/") {
                let totalStr = contentRange[contentRange.index(after: slashIdx)...]
                totalBytes = Int64(totalStr.trimmingCharacters(in: .whitespaces)) ?? 0
            }
            if totalBytes <= 0, http.expectedContentLength > 0 {
                totalBytes = http.expectedContentLength
            }
            let headerSlice = data.prefix(131_072)
            let dims = Self.parseMp4TkhdDimensions(headerSlice)
            return Mp4ProbeResult(
                width: dims?.width ?? 0,
                height: dims?.height ?? 0,
                totalBytes: totalBytes
            )
        } catch {
            return Mp4ProbeResult()
        }
    }

    private func extractViaTikWmPostWithRetry(
        tiktokUrl: String,
        endpoint: String,
        providerName: String
    ) async throws -> UnifiedMediaInfo {
        do {
            return try await extractViaTikWmPost(tiktokUrl: tiktokUrl, endpoint: endpoint, providerName: providerName)
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("1 request") ||
                msg.localizedCaseInsensitiveContains("limit") ||
                msg.localizedCaseInsensitiveContains("busy") {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                return try await extractViaTikWmPost(tiktokUrl: tiktokUrl, endpoint: endpoint, providerName: providerName)
            }
            throw error
        }
    }

    private func extractViaTikWmPost(
        tiktokUrl: String,
        endpoint: String,
        providerName: String
    ) async throws -> UnifiedMediaInfo {
        guard let reqUrl = URL(string: endpoint) else {
            throw ExtractionError("URL máy chủ không hợp lệ")
        }
        var formAllowed = CharacterSet.urlQueryAllowed
        formAllowed.remove(charactersIn: "&+=?")
        let encodedUrl = tiktokUrl.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? tiktokUrl
        let formString = "url=\(encodedUrl)&count=12&cursor=0&web=0&hd=1"

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "POST"
        req.httpBody = formString.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue(Self.tikWmBase, forHTTPHeaderField: "Origin")
        req.setValue("\(Self.tikWmBase)/", forHTTPHeaderField: "Referer")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("HTTP \(http.statusCode)")
        }
        guard !data.isEmpty, let bodyStr = String(data: data, encoding: .utf8) else {
            throw ExtractionError("Phản hồi rỗng từ máy chủ")
        }
        return try parseTikWmJson(rawJson: bodyStr, originalUrl: tiktokUrl, providerName: providerName)
    }

    private func extractViaTikWmCompatible(
        tiktokUrl: String,
        endpoint: String,
        providerName: String
    ) async throws -> UnifiedMediaInfo {
        guard var comps = URLComponents(string: endpoint) else {
            throw ExtractionError("URL máy chủ không hợp lệ")
        }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "url", value: tiktokUrl))
        items.append(URLQueryItem(name: "hd", value: "1"))
        comps.queryItems = items
        guard let reqUrl = comps.url else {
            throw ExtractionError("URL máy chủ không hợp lệ")
        }

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("HTTP \(http.statusCode)")
        }
        guard !data.isEmpty, let bodyStr = String(data: data, encoding: .utf8) else {
            throw ExtractionError("Phản hồi rỗng từ máy chủ")
        }
        return try parseTikWmJson(rawJson: bodyStr, originalUrl: tiktokUrl, providerName: providerName)
    }

    public func parseTikWmJson(
        rawJson: String,
        originalUrl: String,
        providerName: String
    ) throws -> UnifiedMediaInfo {
        guard let jsonData = rawJson.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            throw ExtractionError("JSON phản hồi TikTok không hợp lệ")
        }

        let code = Self.optInt(root, "code", default: -1)
        let msg = Self.optString(root, "msg", default: "Unknown error")
        if code != 0 {
            throw ExtractionError(msg)
        }

        guard let data = root["data"] as? [String: Any] else {
            throw ExtractionError("Không tìm thấy dữ liệu media cho liên kết TikTok này")
        }

        let rawId = Self.optString(data, "id")
        let id = rawId.isEmpty ? "\(Int64(Date().timeIntervalSince1970 * 1000))" : rawId
        let rawTitle = Self.optString(data, "title")
        let contentDesc = Self.optString(data, "content_desc")
        let title = !rawTitle.isEmpty ? rawTitle : (!contentDesc.isEmpty ? contentDesc : "TikTok Video #\(id)")

        let authorObj = data["author"] as? [String: Any]
        let rawUniqueId = Self.optString(authorObj, "unique_id")
        let authorUniqueId = rawUniqueId.isEmpty ? "tiktok_user" : rawUniqueId
        let rawNickname = Self.optString(authorObj, "nickname")
        let authorNickname = rawNickname.isEmpty ? authorUniqueId : rawNickname
        let authorAvatar = normalizeTikWmUrl(Self.optString(authorObj, "avatar"))

        let coverUrl = normalizeTikWmUrl(Self.optString(data, "cover"))
        let rawOriginCover = normalizeTikWmUrl(Self.optString(data, "origin_cover"))
        let originCoverUrl = rawOriginCover.isEmpty ? coverUrl : rawOriginCover

        let duration = Self.optInt(data, "duration", default: 0)
        let playCount = Self.optInt64(data, "play_count", default: 0)
        let diggCount = Self.optInt64(data, "digg_count", default: 0)

        let playUrl = normalizeTikWmUrl(Self.optString(data, "play"))
        let hdPlayUrl = normalizeTikWmUrl(Self.optString(data, "hdplay"))
        let wmPlayUrl = normalizeTikWmUrl(Self.optString(data, "wmplay"))

        let sizeBytes = Self.optInt64(data, "size", default: 0)
        let hdSizeBytes = Self.optInt64(data, "hd_size", default: 0)
        let wmSizeBytes = Self.optInt64(data, "wm_size", default: 0)

        let musicInfo = data["music_info"] as? [String: Any]
        let rawMusicField = Self.optString(data, "music")
        let musicUrl = normalizeTikWmUrl(
            rawMusicField.isEmpty ? Self.optString(musicInfo, "play") : rawMusicField
        )
        let rawMusicTitle = Self.optString(musicInfo, "title")
        let musicTitle = rawMusicTitle.isEmpty ? "Original Sound - \(authorNickname)" : rawMusicTitle

        let slideImages = ((data["images"] as? [Any]) ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(normalizeTikWmUrl)

        let isSlideshow = !slideImages.isEmpty

        let proxyPlayUrl = "\(Self.tikWmBase)/video/media/play/\(id).mp4"
        let proxyHdPlayUrl = "\(Self.tikWmBase)/video/media/hdplay/\(id).mp4"
        let proxyWmPlayUrl = "\(Self.tikWmBase)/video/media/wmplay/\(id).mp4"
        let proxyMusicUrl = "\(Self.tikWmBase)/video/music/\(id).mp3"

        var options: [DownloadQualityOption] = []

        if isSlideshow {
            for (index, imgUrl) in slideImages.enumerated() {
                let num = index + 1
                options.append(
                    DownloadQualityOption(
                        id: "slide_\(num)",
                        labelVi: "Tải ảnh #\(num) (Không logo)",
                        labelEn: "Download Photo #\(num) (No Watermark)",
                        subtitleVi: "Ảnh gốc chất lượng cao",
                        subtitleEn: "Original high-res photo",
                        badge: "ẢNH \(num)/\(slideImages.count)",
                        url: imgUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .image,
                        extensionName: "jpg",
                        mimeType: "image/jpeg",
                        isPrimary: index == 0,
                        imageIndex: num
                    )
                )
            }
            if !musicUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "audio_mp3",
                        labelVi: "Tải Nhạc Nền (MP3)",
                        labelEn: "Download Background Audio (MP3)",
                        subtitleVi: musicTitle,
                        subtitleEn: musicTitle,
                        badge: "MP3",
                        url: musicUrl,
                        fallbackUrl: proxyMusicUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .audio,
                        extensionName: "mp3",
                        mimeType: "audio/mpeg"
                    )
                )
            }
        } else {
            let hasDistinctHd = !hdPlayUrl.isEmpty && hdPlayUrl != playUrl
            if !hdPlayUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "video_hd_nologo",
                        labelVi: "Tải Video Full HD / Gốc (Không Logo)",
                        labelEn: "Download Master Full HD (No Watermark)",
                        subtitleVi: "Bản gốc chất lượng cao nhất • Không dính ID TikTok",
                        subtitleEn: "Original Master Bitrate • Clean No Watermark",
                        badge: "FULL HD",
                        url: hdPlayUrl,
                        fallbackUrl: proxyHdPlayUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        sizeBytes: hdSizeBytes > 0 ? hdSizeBytes : sizeBytes,
                        isUltraHd: true,
                        isPrimary: true
                    )
                )
            }

            if !playUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "video_sd_nologo",
                        labelVi: "Tải Video (Không Logo)",
                        labelEn: "Download Video (No Watermark)",
                        subtitleVi: "Tốc độ tải nhanh • Chuẩn MP4",
                        subtitleEn: "Fast CDN • Standard MP4",
                        badge: "NO LOGO",
                        url: playUrl,
                        fallbackUrl: proxyPlayUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        sizeBytes: sizeBytes,
                        isPrimary: !hasDistinctHd && hdPlayUrl.isEmpty
                    )
                )

                options.append(
                    DownloadQualityOption(
                        id: "video_server2_nologo",
                        labelVi: "Tải Video Không Logo (Server 2)",
                        labelEn: "Download Video No Logo (Server 2)",
                        subtitleVi: "Máy chủ dự phòng nếu mạng chậm",
                        subtitleEn: "Mirror proxy server",
                        badge: "SERVER 2",
                        url: proxyPlayUrl,
                        fallbackUrl: playUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        sizeBytes: sizeBytes
                    )
                )
            }

            if !musicUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "audio_mp3",
                        labelVi: "Tải Nhạc Nền (MP3)",
                        labelEn: "Download Original Audio (MP3)",
                        subtitleVi: musicTitle,
                        subtitleEn: musicTitle,
                        badge: "MP3",
                        url: musicUrl,
                        fallbackUrl: proxyMusicUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .audio,
                        extensionName: "mp3",
                        mimeType: "audio/mpeg"
                    )
                )
            }

            if !wmPlayUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "video_watermark",
                        labelVi: "Tải Video (Có Logo TikTok)",
                        labelEn: "Download Video (With Watermark)",
                        subtitleVi: "Giữ nguyên watermark của tác giả",
                        subtitleEn: "Keeps creator TikTok watermark",
                        badge: "LOGO",
                        url: wmPlayUrl,
                        fallbackUrl: proxyWmPlayUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        sizeBytes: wmSizeBytes,
                        isWatermark: true
                    )
                )
            }

            if !originCoverUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "cover_jpg",
                        labelVi: "Tải Ảnh Bìa (Thumbnail HD)",
                        labelEn: "Download Cover Image (HD)",
                        subtitleVi: "Ảnh bìa gốc của video",
                        subtitleEn: "Original video cover thumbnail",
                        badge: "JPG",
                        url: originCoverUrl,
                        fallbackUrl: coverUrl,
                        clientUserAgent: Self.browserUserAgent,
                        refererHeader: "\(Self.tikWmBase)/",
                        mediaCategory: .image,
                        extensionName: "jpg",
                        mimeType: "image/jpeg"
                    )
                )
            }
        }

        guard !options.isEmpty else {
            throw ExtractionError("Không tìm thấy luồng tải khả dụng cho liên kết TikTok này")
        }

        let previewStream = !playUrl.isEmpty ? playUrl : (!hdPlayUrl.isEmpty ? hdPlayUrl : musicUrl)
        let cleanHandle = authorUniqueId.hasPrefix("@") ? String(authorUniqueId.dropFirst()) : authorUniqueId
        let resolvedCover = !coverUrl.isEmpty ? coverUrl : (slideImages.first ?? "")
        let maxBadge: String
        if !isSlideshow && !hdPlayUrl.isEmpty {
            maxBadge = "FULL HD"
        } else if isSlideshow {
            maxBadge = "\(slideImages.count) ẢNH"
        } else {
            maxBadge = ""
        }

        return UnifiedMediaInfo(
            id: id,
            platform: .tiktok,
            originalUrl: originalUrl,
            title: title,
            authorName: authorNickname,
            authorHandle: "@\(cleanHandle)",
            authorAvatarUrl: authorAvatar,
            coverUrl: resolvedCover,
            durationSeconds: duration,
            viewCountText: MediaUrlDetector.formatCompactCount(playCount),
            likeCountText: MediaUrlDetector.formatCompactCount(diggCount),
            musicTitle: musicTitle,
            isVerticalShort: !isSlideshow,
            isImageGallery: isSlideshow,
            galleryImages: slideImages,
            previewStreamUrl: isSlideshow ? "" : previewStream,
            previewUserAgent: Self.browserUserAgent,
            maxResolutionBadge: maxBadge,
            downloadOptions: options,
            providerName: providerName
        )
    }

    private func extractViaWorkerFallback(tiktokUrl: String) async throws -> UnifiedMediaInfo {
        guard var comps = URLComponents(string: Self.workerFallbackApi) else {
            throw ExtractionError("Fallback URL invalid")
        }
        comps.queryItems = [URLQueryItem(name: "down", value: tiktokUrl)]
        guard let reqUrl = comps.url else {
            throw ExtractionError("Fallback URL invalid")
        }

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("HTTP \(http.statusCode)")
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ExtractionError("Fallback JSON invalid")
        }
        let vPrimary = Self.optString(root, "video")
        let videoUrl = vPrimary.isEmpty ? Self.optString(root, "play") : vPrimary
        guard !videoUrl.isEmpty else {
            throw ExtractionError("Fallback không có link video")
        }

        let aPrimary = Self.optString(root, "music")
        let audioUrl = aPrimary.isEmpty ? Self.optString(root, "audio") : aPrimary
        let rawTitle = Self.optString(root, "title")
        let title = rawTitle.isEmpty ? "TikTok Video" : rawTitle
        let authorObj = root["author"] as? [String: Any]
        let uId = Self.optString(authorObj, "unique_id")
        let rawHandle = uId.isEmpty ? Self.optString(authorObj, "id") : uId
        let authorHandle = rawHandle.isEmpty ? "tiktok" : rawHandle
        let rawNick = Self.optString(authorObj, "nickname")
        let authorName = rawNick.isEmpty ? authorHandle : rawNick
        let cover = Self.optString(root, "cover")
        let id = RegexUtils.firstMatch(in: tiktokUrl, pattern: #"/(?:video|photo)/(\d+)"#)?
            .dropFirst().first ?? "\(Int64(Date().timeIntervalSince1970 * 1000))"

        var options: [DownloadQualityOption] = [
            DownloadQualityOption(
                id: "video_sd_nologo",
                labelVi: "Tải Video (Không Logo)",
                labelEn: "Download Video (No Watermark)",
                subtitleVi: "Máy chủ dự phòng 3",
                subtitleEn: "Fallback Server 3",
                badge: "NO LOGO",
                url: videoUrl,
                clientUserAgent: Self.browserUserAgent,
                mediaCategory: .video,
                extensionName: "mp4",
                mimeType: "video/mp4",
                isPrimary: true
            )
        ]
        if !audioUrl.isEmpty {
            options.append(
                DownloadQualityOption(
                    id: "audio_mp3",
                    labelVi: "Tải Nhạc Nền (MP3)",
                    labelEn: "Download Audio (MP3)",
                    badge: "MP3",
                    url: audioUrl,
                    clientUserAgent: Self.browserUserAgent,
                    mediaCategory: .audio,
                    extensionName: "mp3",
                    mimeType: "audio/mpeg"
                )
            )
        }

        let cleanHandle = authorHandle.hasPrefix("@") ? String(authorHandle.dropFirst()) : authorHandle
        return UnifiedMediaInfo(
            id: id,
            platform: .tiktok,
            originalUrl: tiktokUrl,
            title: title,
            authorName: authorName,
            authorHandle: "@\(cleanHandle)",
            coverUrl: cover,
            isVerticalShort: true,
            previewStreamUrl: videoUrl,
            previewUserAgent: Self.browserUserAgent,
            downloadOptions: options,
            providerName: "NVTSnapMedia TikTok Server 3"
        )
    }

    private func expandShortUrl(_ url: String) async throws -> String {
        guard let comps = RegexUtils.safeURLComponents(url),
              let host = comps.host?.lowercased() else {
            return url
        }
        if !host.hasPrefix("vt.") && !host.hasPrefix("vm.") && !url.contains("/t/") {
            return url
        }
        guard let reqUrl = URL(string: url) else { return url }
        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")

        let (_, resp) = try await session.data(for: req)
        return resp.url?.absoluteString ?? url
    }

    private func normalizeTikWmUrl(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        } else if trimmed.hasPrefix("//") {
            return "https:\(trimmed)"
        } else if trimmed.hasPrefix("/") {
            return "\(Self.tikWmBase)\(trimmed)"
        } else {
            return "\(Self.tikWmBase)/\(trimmed)"
        }
    }

    private static func optString(_ dict: [String: Any]?, _ key: String, default fallback: String = "") -> String {
        guard let dict, let val = dict[key] else { return fallback }
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        return fallback
    }

    private static func optInt(_ dict: [String: Any]?, _ key: String, default fallback: Int = 0) -> Int {
        guard let dict, let val = dict[key] else { return fallback }
        if let i = val as? Int { return i }
        if let n = val as? NSNumber { return n.intValue }
        if let s = val as? String, let parsed = Int(s) { return parsed }
        return fallback
    }

    private static func optInt64(_ dict: [String: Any]?, _ key: String, default fallback: Int64 = 0) -> Int64 {
        guard let dict, let val = dict[key] else { return fallback }
        if let i = val as? Int64 { return i }
        if let i = val as? Int { return Int64(i) }
        if let n = val as? NSNumber { return n.int64Value }
        if let s = val as? String, let parsed = Int64(s) { return parsed }
        return fallback
    }
}
