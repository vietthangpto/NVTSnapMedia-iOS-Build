import Foundation

public struct DashVideoRepresentation: Equatable, Sendable {
    public let id: String
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bandwidth: Int64
    public let codecs: String
    public let qualityLabel: String
    public let baseUrl: String

    public var tier: VideoResolutionTier {
        VideoResolutionTier.classify(width: width, height: height, qualityHint: qualityLabel)
    }

    public var codecShortLabel: String {
        let c = codecs.lowercased()
        if c.hasPrefix("av01") || c.contains("av1") { return "AV1" }
        if c.hasPrefix("vp09") || c.contains("vp9") { return "VP9" }
        if c.hasPrefix("hvc1") || c.hasPrefix("hev1") || c.contains("265") { return "HEVC" }
        if c.hasPrefix("avc1") || c.contains("264") { return "H.264" }
        return "MP4"
    }

    public var isAppleNativePreferred: Bool {
        let c = codecs.lowercased()
        if c.isEmpty { return true }
        return c.hasPrefix("avc1") || c.contains("264") ||
            c.hasPrefix("hvc1") || c.hasPrefix("hev1") || c.contains("265") ||
            c.hasPrefix("av01")
    }
}

public struct DashAudioRepresentation: Equatable, Sendable {
    public let bandwidth: Int64
    public let codecs: String
    public let baseUrl: String
}

public struct ParsedDashManifest: Equatable, Sendable {
    public let videoTracks: [DashVideoRepresentation]
    public let bestAudioTrack: DashAudioRepresentation?
}

public final class FacebookExtractorService: Sendable {

    public static let desktopChromeUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    public static let fbCdnDownloadUA = "facebookexternalhit/1.1"

    private let session: URLSession
    private let probeSession: URLSession

    private struct QuadOptionMeta {
        let id: String
        let vi: String
        let en: String
        let badge: String
    }

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.probeSession = session
        } else {
            let mainCfg = URLSessionConfiguration.ephemeral
            mainCfg.timeoutIntervalForRequest = 20
            mainCfg.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: mainCfg)

            let probeCfg = URLSessionConfiguration.ephemeral
            probeCfg.timeoutIntervalForRequest = 4
            probeCfg.timeoutIntervalForResource = 5
            self.probeSession = URLSession(configuration: probeCfg)
        }
    }

    public static func parseFrameRateAttribute(_ raw: String?) -> Int {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return 0
        }
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let num = Double(parts[0]),
                  let den = Double(parts[1]),
                  den > 0.0 else {
                return 0
            }
            return Int((num / den).rounded())
        }
        return Double(trimmed).map { Int($0.rounded()) } ?? 0
    }

    public func extractMedia(
        rawInput: String,
        customEndpoint: String = ""
    ) async -> Result<UnifiedMediaInfo, Error> {
        guard let cleanUrl = FacebookUrlParser.extractUrl(rawInput) else {
            return .failure(
                ExtractionError("Liên kết Facebook không hợp lệ. Vui lòng dán link Video, Reels hoặc Watch hợp lệ.")
            )
        }

        let trimmedEndpoint = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEndpoint.isEmpty {
            if let custom = try? await extractViaCustomApi(fbUrl: cleanUrl, endpoint: trimmedEndpoint) {
                return .success(custom)
            }
        }

        let expandedUrl = (try? await resolveRedirects(url: cleanUrl)) ?? cleanUrl
        let desktopUrl = FacebookUrlParser.toDesktopFacebookUrl(expandedUrl)
        let videoId = FacebookUrlParser.extractVideoId(desktopUrl)

        if var info = try? await extractViaDirectRelayHtml(originalUrl: cleanUrl, desktopUrl: desktopUrl) {
            let hasAboveHd = info.downloadOptions.contains(where: \.isUltraHd)
            if !hasAboveHd,
               !info.isImageGallery,
               let videoId, !videoId.isEmpty,
               desktopUrl.localizedCaseInsensitiveContains("/reel/") {
                let watchRdr = "https://www.facebook.com/watch/?v=\(videoId)&_rdr"
                if let watchAttempt = try? await extractViaDirectRelayHtml(originalUrl: cleanUrl, desktopUrl: watchRdr),
                   watchAttempt.downloadOptions.contains(where: \.isUltraHd) {
                    var upgraded = watchAttempt
                    upgraded.isVerticalShort = true
                    info = upgraded
                }
            }
            let enriched = await enrichSizes(info)
            return .success(enriched)
        }

        if let videoId, !videoId.isEmpty {
            let canonicalWatch = "https://www.facebook.com/watch/?v=\(videoId)&_rdr"
            if let watchRelay = try? await extractViaDirectRelayHtml(originalUrl: cleanUrl, desktopUrl: canonicalWatch) {
                return .success(await enrichSizes(watchRelay))
            }
        }

        if let embedInfo = try? await extractViaVideoEmbedPlugin(originalUrl: cleanUrl, targetVideoUrl: desktopUrl) {
            return .success(await enrichSizes(embedInfo))
        }

        if let videoId, !videoId.isEmpty {
            let canonicalWatch = "https://www.facebook.com/watch/?v=\(videoId)"
            if let embedWatch = try? await extractViaVideoEmbedPlugin(originalUrl: cleanUrl, targetVideoUrl: canonicalWatch) {
                return .success(await enrichSizes(embedWatch))
            }
        }

        return .failure(
            ExtractionError(
                "Không tìm thấy luồng tải công khai trên Facebook. Hãy đảm bảo Video/Reels ở chế độ Công khai (Public)."
            )
        )
    }

    private func resolveRedirects(url: String) async throws -> String {
        guard let reqUrl = URL(string: url) else { return url }
        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")

        let (_, resp) = try await session.data(for: req)
        return resp.url?.absoluteString ?? url
    }

    private func extractViaDirectRelayHtml(
        originalUrl: String,
        desktopUrl: String
    ) async throws -> UnifiedMediaInfo {
        guard let reqUrl = URL(string: desktopUrl) else {
            throw ExtractionError("URL Facebook không hợp lệ")
        }
        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("HTTP \(http.statusCode)")
        }
        let finalUrl = resp.url?.absoluteString ?? desktopUrl
        let html = String(data: data, encoding: .utf8) ?? ""
        guard !html.isEmpty else {
            throw ExtractionError("Phản hồi rỗng từ Facebook")
        }
        return try parseFacebookHtml(
            html: html,
            originalUrl: originalUrl,
            resolvedUrl: finalUrl,
            providerName: "NVTSnapMedia Facebook Ultra-HD"
        )
    }

    private func extractViaVideoEmbedPlugin(
        originalUrl: String,
        targetVideoUrl: String
    ) async throws -> UnifiedMediaInfo {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encodedHref = targetVideoUrl.addingPercentEncoding(withAllowedCharacters: allowed) ?? targetVideoUrl
        let pluginUrlStr = "https://www.facebook.com/plugins/video.php?href=\(encodedHref)&show_text=1"
        guard let pluginUrl = URL(string: pluginUrlStr) else {
            throw ExtractionError("Plugin URL không hợp lệ")
        }

        var req = URLRequest(url: pluginUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://www.facebook.com/", forHTTPHeaderField: "Referer")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("Plugin HTTP \(http.statusCode)")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        guard !html.isEmpty else {
            throw ExtractionError("Plugin phản hồi rỗng")
        }
        return try parseFacebookHtml(
            html: html,
            originalUrl: originalUrl,
            resolvedUrl: targetVideoUrl,
            providerName: "NVTSnapMedia Facebook Embed"
        )
    }

    public func parseFacebookHtml(
        html: String,
        originalUrl: String,
        resolvedUrl: String,
        providerName: String
    ) throws -> UnifiedMediaInfo {
        let hdUrl = firstDecodedJsonUrl(
            in: html,
            keys: [
                "browser_native_hd_url",
                "playable_url_quality_hd",
                "hd_src_no_ratelimit",
                "hd_src"
            ]
        )

        let sdUrl = firstDecodedJsonUrl(
            in: html,
            keys: [
                "browser_native_sd_url",
                "playable_url",
                "sd_src_no_ratelimit",
                "sd_src"
            ]
        )

        let dashParsed = extractDashStreamsFromHtml(html)
        let dashAudioUrl = (dashParsed.bestAudioTrack?.baseUrl).flatMap { $0.isEmpty ? nil : $0 }
            ?? extractDashAudioUrl(html)

        let mediaId = FacebookUrlParser.extractVideoId(resolvedUrl)
            ?? RegexUtils.firstMatch(in: html, pattern: #""video_id"\s*:\s*"(\d+)""#)?.dropFirst().first
            ?? RegexUtils.firstMatch(in: html, pattern: #""id"\s*:\s*"(\d{8,})""#)?.dropFirst().first
            ?? "\(Int64(Date().timeIntervalSince1970 * 1000))"

        let durationMs = RegexUtils.firstMatch(in: html, pattern: #""playable_duration_in_ms"\s*:\s*(\d+)"#)?
            .dropFirst().first.flatMap(Int64.init) ?? 0
        let durationSec = Int(durationMs / 1000)

        let rawOgTitle = extractMetaContent(html: html, property: "og:title")
        let ogDesc = extractMetaContent(html: html, property: "og:description")
        let rawOgDesc = ogDesc.isEmpty ? extractMetaNameContent(html: html, name: "description") : ogDesc

        let ownerPrimary = extractJsonStringField(
            html: html,
            pattern: #""owner"\s*:\s*\{[^{}]*"name"\s*:\s*"((?:\\.|[^"\\])+)""#
        )
        let ownerFallback = extractJsonStringField(
            html: html,
            pattern: #""actors"\s*:\s*\[\s*\{[^{}]*"name"\s*:\s*"((?:\\.|[^"\\])+)""#
        )
        let ownerName = !ownerPrimary.isEmpty ? ownerPrimary : (!ownerFallback.isEmpty ? ownerFallback : "Facebook Creator")

        let viewCountText = RegexUtils.firstMatch(
            in: rawOgTitle,
            pattern: #"([\d.,]+[KMBkmb]?)\s*(?:views|lượt xem)"#,
            options: [.caseInsensitive]
        )?.dropFirst().first ?? ""

        let reactionCountText = RegexUtils.firstMatch(
            in: rawOgTitle,
            pattern: #"([\d.,]+[KMBkmb]?)\s*(?:reactions|cảm xúc)"#,
            options: [.caseInsensitive]
        )?.dropFirst().first ?? ""

        let cleanedTitle = buildCleanTitle(ogDesc: rawOgDesc, ogTitle: rawOgTitle, fallbackId: mediaId)
        let coverUrl = extractPosterThumbnail(html)
        let isReel = resolvedUrl.localizedCaseInsensitiveContains("/reel/") ||
            originalUrl.localizedCaseInsensitiveContains("/share/r/") ||
            originalUrl.localizedCaseInsensitiveContains("/reel/")

        var options: [DownloadQualityOption] = []
        let hasAnyVideo = !hdUrl.isEmpty || !sdUrl.isEmpty || !dashParsed.videoTracks.isEmpty

        if hasAnyVideo {
            let muxAudioSource = !dashAudioUrl.isEmpty ? dashAudioUrl : (!sdUrl.isEmpty ? sdUrl : hdUrl)
            let progressiveFallback = !hdUrl.isEmpty ? hdUrl : sdUrl

            let validAboveHd = dashParsed.videoTracks.filter { $0.tier.isAboveHd && !$0.baseUrl.isEmpty }
            let groupedAboveHd = Dictionary(grouping: validAboveHd, by: \.tier)
            let sortedAboveHdTiers = groupedAboveHd.keys.sorted(by: >)

            for (idx, tier) in sortedAboveHdTiers.enumerated() {
                guard let list = groupedAboveHd[tier],
                      let rep = list.sorted(by: { a, b in
                          if a.isAppleNativePreferred != b.isAppleNativePreferred {
                              return a.isAppleNativePreferred && !b.isAppleNativePreferred
                          }
                          if a.fps != b.fps { return a.fps > b.fps }
                          return a.bandwidth > b.bandwidth
                      }).first else {
                    continue
                }

                let dimText = (rep.width > 0 && rep.height > 0) ? "\(rep.width)×\(rep.height)" : ""
                let fpsLabel = rep.fps >= 50 ? " \(rep.fps)FPS" : ""
                let mediaKindVi = isReel ? "Reels" : "Video"
                let mediaKindEn = isReel ? "Reel" : "Video"

                let meta: QuadOptionMeta
                switch tier {
                case .uhd4k:
                    meta = QuadOptionMeta(
                        id: "fb_video_4k",
                        vi: "Tải \(mediaKindVi) 4K Ultra HD (2160p\(fpsLabel))",
                        en: "Download \(mediaKindEn) 4K Ultra HD (2160p\(fpsLabel))",
                        badge: rep.fps >= 50 ? "4K 60FPS" : "4K UHD"
                    )
                case .qhd2k:
                    meta = QuadOptionMeta(
                        id: "fb_video_2k",
                        vi: "Tải \(mediaKindVi) 2K Quad HD (1440p\(fpsLabel))",
                        en: "Download \(mediaKindEn) 2K Quad HD (1440p\(fpsLabel))",
                        badge: rep.fps >= 50 ? "2K 60FPS" : "2K QHD"
                    )
                default:
                    meta = QuadOptionMeta(
                        id: "fb_video_1080p",
                        vi: "Tải \(mediaKindVi) Full HD (1080p\(fpsLabel))",
                        en: "Download \(mediaKindEn) Full HD (1080p\(fpsLabel))",
                        badge: rep.fps >= 50 ? "1080p 60FPS" : "1080p FHD"
                    )
                }

                var subViParts: [String] = []
                if !dimText.isEmpty { subViParts.append(dimText) }
                if rep.fps >= 50 { subViParts.append("\(rep.fps)fps mượt") }
                subViParts.append(rep.codecShortLabel)
                subViParts.append("Ghép âm thanh gốc Lossless")

                var subEnParts: [String] = []
                if !dimText.isEmpty { subEnParts.append(dimText) }
                if rep.fps >= 50 { subEnParts.append("\(rep.fps)fps") }
                subEnParts.append(rep.codecShortLabel)
                subEnParts.append("Lossless Audio Mux")

                options.append(
                    DownloadQualityOption(
                        id: meta.id,
                        labelVi: meta.vi,
                        labelEn: meta.en,
                        subtitleVi: subViParts.joined(separator: " • "),
                        subtitleEn: subEnParts.joined(separator: " • "),
                        badge: meta.badge,
                        url: rep.baseUrl,
                        audioStreamUrl: muxAudioSource,
                        fallbackUrl: progressiveFallback,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        width: rep.width,
                        height: rep.height,
                        fps: rep.fps,
                        codecLabel: rep.codecShortLabel,
                        isUltraHd: true,
                        isPrimary: idx == 0
                    )
                )
            }

            let hasAboveHdOptions = !options.isEmpty
            let dash720 = dashParsed.videoTracks
                .filter { $0.tier == .hd720p && !$0.baseUrl.isEmpty }
                .max(by: { $0.bandwidth < $1.bandwidth })

            if !hdUrl.isEmpty {
                let dim720 = (dash720 != nil && dash720!.width > 0 && dash720!.height > 0)
                    ? "\(dash720!.width)×\(dash720!.height) • "
                    : ""
                let labelVi: String
                let labelEn: String
                if hasAboveHdOptions {
                    labelVi = isReel ? "Tải Reels HD (720p Nhanh)" : "Tải Video HD (720p Nhanh)"
                    labelEn = isReel ? "Download Reel HD (720p Fast)" : "Download Video HD (720p Fast)"
                } else {
                    labelVi = isReel ? "Tải Reels HD (Sắc nét)" : "Tải Video HD (720p)"
                    labelEn = isReel ? "Download Reel HD" : "Download Video HD (720p)"
                }
                options.append(
                    DownloadQualityOption(
                        id: "fb_video_hd",
                        labelVi: labelVi,
                        labelEn: labelEn,
                        subtitleVi: "\(dim720)Luồng MP4 nguyên khối • Có sẵn âm thanh",
                        subtitleEn: "\(dim720)Progressive MP4 • Full audio included",
                        badge: hasAboveHdOptions ? "720p HD" : "FULL HD",
                        url: hdUrl,
                        fallbackUrl: sdUrl,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        width: dash720?.width ?? 0,
                        height: dash720?.height ?? 0,
                        isPrimary: !hasAboveHdOptions
                    )
                )
            } else if let dash720, !muxAudioSource.isEmpty {
                let dim720 = (dash720.width > 0 && dash720.height > 0) ? "\(dash720.width)×\(dash720.height) • " : ""
                options.append(
                    DownloadQualityOption(
                        id: "fb_video_hd",
                        labelVi: isReel ? "Tải Reels HD (720p)" : "Tải Video HD (720p)",
                        labelEn: isReel ? "Download Reel HD (720p)" : "Download Video HD (720p)",
                        subtitleVi: "\(dim720)Chuẩn HD 720p • Đầy đủ âm thanh",
                        subtitleEn: "\(dim720)720p HD • Full audio muxed",
                        badge: "720p HD",
                        url: dash720.baseUrl,
                        audioStreamUrl: muxAudioSource,
                        fallbackUrl: sdUrl,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        width: dash720.width,
                        height: dash720.height,
                        isPrimary: !hasAboveHdOptions
                    )
                )
            }

            if !sdUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "fb_video_sd",
                        labelVi: "Tải Video Tiêu chuẩn (SD Nhanh)",
                        labelEn: "Download Standard Video (Fast SD)",
                        subtitleVi: "Dung lượng nhẹ • Tải siêu tốc tiết kiệm 4G/5G",
                        subtitleEn: "Compact size • Ultra-fast download",
                        badge: "SD MP4",
                        url: sdUrl,
                        fallbackUrl: hdUrl,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .video,
                        extensionName: "mp4",
                        mimeType: "video/mp4",
                        isPrimary: options.isEmpty
                    )
                )
            }

            let audioSourceUrl = !dashAudioUrl.isEmpty ? dashAudioUrl : (!sdUrl.isEmpty ? sdUrl : hdUrl)
            if !audioSourceUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "audio_m4a",
                        labelVi: "Tải Âm Thanh Gốc (M4A / Audio)",
                        labelEn: "Download Original Audio (M4A)",
                        subtitleVi: "Tách luồng âm thanh AAC gốc không giảm chất lượng",
                        subtitleEn: "Lossless original AAC audio track",
                        badge: "AUDIO",
                        url: audioSourceUrl,
                        fallbackUrl: !hdUrl.isEmpty ? hdUrl : sdUrl,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .audio,
                        extensionName: "m4a",
                        mimeType: "audio/mp4",
                        demuxAudioFromVideo: dashAudioUrl.isEmpty
                    )
                )
            }

            if !coverUrl.isEmpty {
                options.append(
                    DownloadQualityOption(
                        id: "cover_jpg",
                        labelVi: "Tải Ảnh Thu Nhỏ (Thumbnail HD)",
                        labelEn: "Download Video Thumbnail (HD JPG)",
                        subtitleVi: "Ảnh bìa gốc của Video / Reels",
                        subtitleEn: "Original video cover image",
                        badge: "JPG",
                        url: coverUrl,
                        clientUserAgent: Self.fbCdnDownloadUA,
                        mediaCategory: .image,
                        extensionName: "jpg",
                        mimeType: "image/jpeg"
                    )
                )
            }
        } else {
            let postImages = extractPostImages(html)
            if !postImages.isEmpty {
                for (index, imgUrl) in postImages.enumerated() {
                    let num = index + 1
                    options.append(
                        DownloadQualityOption(
                            id: "fb_photo_\(num)",
                            labelVi: "Tải Ảnh #\(num) (Độ nét cao)",
                            labelEn: "Download Photo #\(num) (High Res)",
                            subtitleVi: "Ảnh gốc từ bài viết Facebook",
                            subtitleEn: "Original photo from Facebook post",
                            badge: "ẢNH \(num)/\(postImages.count)",
                            url: imgUrl,
                            clientUserAgent: Self.fbCdnDownloadUA,
                            mediaCategory: .image,
                            extensionName: "jpg",
                            mimeType: "image/jpeg",
                            isPrimary: index == 0,
                            imageIndex: num
                        )
                    )
                }
                return UnifiedMediaInfo(
                    id: mediaId,
                    platform: .facebook,
                    originalUrl: originalUrl,
                    title: cleanedTitle,
                    authorName: ownerName,
                    coverUrl: postImages[0],
                    viewCountText: viewCountText,
                    likeCountText: reactionCountText,
                    isVerticalShort: false,
                    isImageGallery: true,
                    galleryImages: postImages,
                    maxResolutionBadge: "HD PHOTO",
                    downloadOptions: options,
                    providerName: providerName
                )
            }
        }

        guard !options.isEmpty else {
            throw ExtractionError("Không tìm thấy luồng video công khai trong trang Facebook này")
        }

        let sampleTrack = dashParsed.videoTracks.first { $0.width > 0 && $0.height > 0 }
        let isVertical = isReel || (sampleTrack != nil && sampleTrack!.height > sampleTrack!.width)
        let topVideoBadge = options.first(where: { $0.mediaCategory == .video })?.badge ?? ""
        let previewUrl = !hdUrl.isEmpty ? hdUrl : (!sdUrl.isEmpty ? sdUrl : options[0].url)

        return UnifiedMediaInfo(
            id: mediaId,
            platform: .facebook,
            originalUrl: originalUrl,
            title: cleanedTitle,
            authorName: ownerName,
            coverUrl: coverUrl,
            durationSeconds: durationSec,
            viewCountText: viewCountText,
            likeCountText: reactionCountText,
            isVerticalShort: isVertical,
            previewStreamUrl: previewUrl,
            previewUserAgent: Self.fbCdnDownloadUA,
            maxResolutionBadge: topVideoBadge,
            downloadOptions: options,
            providerName: providerName
        )
    }

    public func extractDashStreamsFromHtml(_ html: String) -> ParsedDashManifest {
        var videoList: [DashVideoRepresentation] = []
        var audioList: [DashAudioRepresentation] = []

        let manifestPattern = #""(?:dash_manifest_xml_string|manifest_xml|dash_manifest|playlist)"\s*:\s*"((?:\\.|[^"\\])+)""#
        var xmlManifests: [String] = []

        for groups in RegexUtils.allMatches(in: html, pattern: manifestPattern) {
            guard groups.count > 1 else { continue }
            let rawVal = groups[1]
            guard rawVal != "null" else { continue }
            let decoded = Self.decodeJsonEscapedString(rawVal)
            let maybeUnquoted: String
            if decoded.lowercased().hasPrefix("%3c") {
                maybeUnquoted = decoded.removingPercentEncoding ?? decoded
            } else {
                maybeUnquoted = decoded
            }
            if maybeUnquoted.localizedCaseInsensitiveContains("<MPD") ||
                maybeUnquoted.localizedCaseInsensitiveContains("<Representation") {
                xmlManifests.append(maybeUnquoted)
            }
        }

        for xml in xmlManifests {
            parseMpdXml(xml, videoOut: &videoList, audioOut: &audioList)
        }

        let jsonRepPattern = #"\{[^{}]*"base_url"\s*:\s*"(https?:(?:\\.|[^"\\])+)"[^{}]*\}"#
        for groups in RegexUtils.allMatches(in: html, pattern: jsonRepPattern) {
            guard let block = groups.first else { continue }
            let rawBase = RegexUtils.firstMatch(in: block, pattern: #""base_url"\s*:\s*"((?:\\.|[^"\\])+)""#)?
                .dropFirst().first ?? ""
            let baseUrl = Self.decodeJsonEscapedString(rawBase)
            guard baseUrl.hasPrefix("http") else { continue }

            let mime = RegexUtils.firstMatch(in: block, pattern: #""mime_type"\s*:\s*"((?:\\.|[^"\\])+)""#)?
                .dropFirst().first.map(Self.decodeJsonEscapedString) ?? ""
            let codecs = RegexUtils.firstMatch(in: block, pattern: #""codecs"\s*:\s*"([^"]+)""#)?
                .dropFirst().first ?? ""
            let bw = RegexUtils.firstMatch(in: block, pattern: #""bandwidth"\s*:\s*(\d+)"#)?
                .dropFirst().first.flatMap(Int64.init) ?? 0
            let w = RegexUtils.firstMatch(in: block, pattern: #""width"\s*:\s*(\d+)"#)?
                .dropFirst().first.flatMap(Int.init) ?? 0
            let h = RegexUtils.firstMatch(in: block, pattern: #""height"\s*:\s*(\d+)"#)?
                .dropFirst().first.flatMap(Int.init) ?? 0
            let qLabel = RegexUtils.firstMatch(in: block, pattern: #""(?:quality_label|FBQualityLabel)"\s*:\s*"([^"]+)""#)?
                .dropFirst().first ?? ""

            if mime.hasPrefix("audio") || codecs.hasPrefix("mp4a") || codecs.hasPrefix("opus") {
                audioList.append(DashAudioRepresentation(bandwidth: bw, codecs: codecs, baseUrl: baseUrl))
            } else if mime.hasPrefix("video") || w > 0 || h > 0 || !qLabel.isEmpty {
                videoList.append(
                    DashVideoRepresentation(
                        id: qLabel.isEmpty ? "\(w)x\(h)" : qLabel,
                        width: w,
                        height: h,
                        fps: 0,
                        bandwidth: bw,
                        codecs: codecs,
                        qualityLabel: qLabel,
                        baseUrl: baseUrl
                    )
                )
            }
        }

        let bestAudio = audioList.sorted { a, b in
            let aMp4 = a.codecs.lowercased().hasPrefix("mp4a")
            let bMp4 = b.codecs.lowercased().hasPrefix("mp4a")
            if aMp4 != bMp4 { return aMp4 && !bMp4 }
            return a.bandwidth > b.bandwidth
        }.first

        var seenUrls = Set<String>()
        let uniqueVideos = videoList.filter { seenUrls.insert($0.baseUrl).inserted }

        return ParsedDashManifest(videoTracks: uniqueVideos, bestAudioTrack: bestAudio)
    }

    private func parseMpdXml(
        _ xml: String,
        videoOut: inout [DashVideoRepresentation],
        audioOut: inout [DashAudioRepresentation]
    ) {
        let adaptPattern = #"<AdaptationSet\b([^>]*)>(.*?)</AdaptationSet>"#
        let repPattern = #"<Representation\b([^>]*)>(.*?)</Representation>"#
        let baseUrlPattern = #"<BaseURL>\s*([^<]+?)\s*</BaseURL>"#

        let adaptMatches = RegexUtils.allMatches(
            in: xml,
            pattern: adaptPattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        let blocks: [(String, String)] = adaptMatches.isEmpty
            ? [("", xml)]
            : adaptMatches.compactMap { $0.count >= 3 ? ($0[1], $0[2]) : nil }

        for (adaptAttrs, innerXml) in blocks {
            let adaptContentType = extractXmlAttr(adaptAttrs, name: "contentType")
            let adaptMimeType = extractXmlAttr(adaptAttrs, name: "mimeType")
            let adaptFrameRate = Self.parseFrameRateAttribute(extractXmlAttr(adaptAttrs, name: "frameRate"))

            let repMatches = RegexUtils.allMatches(
                in: innerXml,
                pattern: repPattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            )

            for repGroups in repMatches {
                guard repGroups.count >= 3 else { continue }
                let repAttrs = repGroups[1]
                let repBody = repGroups[2]

                let rawBaseUrl = RegexUtils.firstMatch(
                    in: repBody,
                    pattern: baseUrlPattern,
                    options: [.dotMatchesLineSeparators, .caseInsensitive]
                )?.dropFirst().first ?? ""

                let baseUrl = Self.decodeHtmlEntities(rawBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines))
                guard baseUrl.hasPrefix("http") else { continue }

                let repId = extractXmlAttr(repAttrs, name: "id")
                let repMime = extractXmlAttr(repAttrs, name: "mimeType")
                let mime = repMime.isEmpty ? adaptMimeType : repMime
                let codecs = extractXmlAttr(repAttrs, name: "codecs")
                let bw = Int64(extractXmlAttr(repAttrs, name: "bandwidth")) ?? 0
                let w = Int(extractXmlAttr(repAttrs, name: "width")) ?? 0
                let h = Int(extractXmlAttr(repAttrs, name: "height")) ?? 0
                let repFps = Self.parseFrameRateAttribute(extractXmlAttr(repAttrs, name: "frameRate"))
                let fps = repFps > 0 ? repFps : adaptFrameRate
                let fbQLabel = extractXmlAttr(repAttrs, name: "FBQualityLabel")
                let qualityLabel = fbQLabel.isEmpty ? extractXmlAttr(repAttrs, name: "qualityLabel") : fbQLabel

                let isAudio = adaptContentType.caseInsensitiveCompare("audio") == .orderedSame ||
                    mime.lowercased().hasPrefix("audio/") ||
                    codecs.lowercased().hasPrefix("mp4a") ||
                    codecs.lowercased().hasPrefix("opus")

                let isVideo = adaptContentType.caseInsensitiveCompare("video") == .orderedSame ||
                    mime.lowercased().hasPrefix("video/") ||
                    w > 0 || h > 0 || !qualityLabel.isEmpty

                if isAudio && !isVideo {
                    audioOut.append(DashAudioRepresentation(bandwidth: bw, codecs: codecs, baseUrl: baseUrl))
                } else if isVideo {
                    videoOut.append(
                        DashVideoRepresentation(
                            id: repId,
                            width: w,
                            height: h,
                            fps: fps,
                            bandwidth: bw,
                            codecs: codecs,
                            qualityLabel: qualityLabel,
                            baseUrl: baseUrl
                        )
                    )
                }
            }
        }
    }

    private func extractXmlAttr(_ attrs: String, name: String) -> String {
        guard !attrs.isEmpty else { return "" }
        return RegexUtils.firstMatch(
            in: attrs,
            pattern: "\\b\(name)\\s*=\\s*\"([^\"]*)\"",
            options: [.caseInsensitive]
        )?.dropFirst().first ?? ""
    }

    private func enrichSizes(_ info: UnifiedMediaInfo) async -> UnifiedMediaInfo {
        guard !info.isImageGallery else { return info }
        let uniqueUrls = Array(
            Set(
                info.downloadOptions
                    .filter { $0.mediaCategory == .video || $0.mediaCategory == .audio }
                    .flatMap { [$0.url, $0.audioStreamUrl].filter { !$0.isEmpty } }
            )
        )

        let sizeMap: [String: Int64] = await withTaskGroup(of: (String, Int64).self) { group in
            for u in uniqueUrls {
                group.addTask { [probeSession] in
                    let sz = await Self.probeContentSize(url: u, session: probeSession)
                    return (u, sz)
                }
            }
            var collected: [String: Int64] = [:]
            for await (u, sz) in group where sz > 0 {
                collected[u] = sz
            }
            return collected
        }

        var updated = info
        updated.downloadOptions = info.downloadOptions.map { opt in
            if opt.sizeBytes > 0 { return opt }
            var copy = opt
            if opt.mediaCategory == .video {
                let vSize = sizeMap[opt.url] ?? 0
                let aSize = !opt.audioStreamUrl.isEmpty ? (sizeMap[opt.audioStreamUrl] ?? 0) : 0
                let total = vSize > 0 ? (vSize + aSize) : 0
                if total > 0 { copy.sizeBytes = total }
            } else if opt.mediaCategory == .audio && !opt.demuxAudioFromVideo {
                if let aSize = sizeMap[opt.url], aSize > 0 {
                    copy.sizeBytes = aSize
                }
            }
            return copy
        }
        return updated
    }

    private static func probeContentSize(url: String, session: URLSession) async -> Int64 {
        guard let reqUrl = URL(string: url) else { return 0 }
        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(fbCdnDownloadUA, forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse,
               let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
               let slashIdx = contentRange.lastIndex(of: "/") {
                let totalStr = contentRange[contentRange.index(after: slashIdx)...]
                return Int64(totalStr.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        } catch {
            return 0
        }
        return 0
    }

    private func extractViaCustomApi(fbUrl: String, endpoint: String) async throws -> UnifiedMediaInfo {
        guard var comps = URLComponents(string: endpoint) else {
            throw ExtractionError("URL máy chủ tùy chỉnh không hợp lệ")
        }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "url", value: fbUrl))
        comps.queryItems = items
        guard let reqUrl = comps.url else {
            throw ExtractionError("URL máy chủ tùy chỉnh không hợp lệ")
        }

        var req = URLRequest(url: reqUrl)
        req.httpMethod = "GET"
        req.setValue(Self.desktopChromeUA, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExtractionError("HTTP \(http.statusCode)")
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ExtractionError("JSON máy chủ tùy chỉnh không hợp lệ")
        }
        let uhd = (root["uhd"] as? String) ?? (root["fhd"] as? String) ?? ""
        let hd = (root["hd"] as? String) ?? ""
        let sd = (root["sd"] as? String) ?? ""
        if uhd.isEmpty && hd.isEmpty && sd.isEmpty {
            throw ExtractionError("Không có link tải")
        }
        let title = ((root["title"] as? String) ?? "").isEmpty ? "Facebook Video" : (root["title"] as! String)
        let thumb = (root["thumbnail"] as? String) ?? ""
        let id = FacebookUrlParser.extractVideoId(fbUrl) ?? "\(Int64(Date().timeIntervalSince1970 * 1000))"

        var options: [DownloadQualityOption] = []
        if !uhd.isEmpty {
            options.append(
                DownloadQualityOption(
                    id: "fb_video_1080p",
                    labelVi: "Tải Video Ultra HD (1080p / 4K)",
                    labelEn: "Download Video Ultra HD (1080p / 4K)",
                    badge: "ULTRA HD",
                    url: uhd,
                    fallbackUrl: !hd.isEmpty ? hd : sd,
                    clientUserAgent: Self.fbCdnDownloadUA,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    isUltraHd: true,
                    isPrimary: true
                )
            )
        }
        if !hd.isEmpty {
            options.append(
                DownloadQualityOption(
                    id: "fb_video_hd",
                    labelVi: "Tải Video HD",
                    labelEn: "Download Video HD",
                    badge: "720p HD",
                    url: hd,
                    fallbackUrl: sd,
                    clientUserAgent: Self.fbCdnDownloadUA,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    isPrimary: uhd.isEmpty
                )
            )
        }
        if !sd.isEmpty {
            options.append(
                DownloadQualityOption(
                    id: "fb_video_sd",
                    labelVi: "Tải Video SD",
                    labelEn: "Download Video SD",
                    badge: "SD MP4",
                    url: sd,
                    fallbackUrl: hd,
                    clientUserAgent: Self.fbCdnDownloadUA,
                    mediaCategory: .video,
                    extensionName: "mp4",
                    mimeType: "video/mp4",
                    isPrimary: uhd.isEmpty && hd.isEmpty
                )
            )
        }

        return UnifiedMediaInfo(
            id: id,
            platform: .facebook,
            originalUrl: fbUrl,
            title: title,
            authorName: "Facebook",
            coverUrl: thumb,
            isVerticalShort: fbUrl.contains("/reel/"),
            previewStreamUrl: !sd.isEmpty ? sd : (!hd.isEmpty ? hd : uhd),
            previewUserAgent: Self.fbCdnDownloadUA,
            maxResolutionBadge: options[0].badge,
            downloadOptions: options,
            providerName: "Custom Server"
        )
    }

    private func firstDecodedJsonUrl(in html: String, keys: [String]) -> String {
        for key in keys {
            let pattern = "\"\(key)\"\\s*:\\s*\"(https?:(?:\\\\.|[^\"\\\\])+)\""
            if let raw = RegexUtils.firstMatch(in: html, pattern: pattern)?.dropFirst().first,
               !raw.isEmpty {
                let decoded = Self.decodeJsonEscapedString(raw)
                if decoded.hasPrefix("http") { return decoded }
            }
        }
        return ""
    }

    private func extractDashAudioUrl(_ html: String) -> String {
        let patterns = [
            #""mime_type"\s*:\s*"audio\\/mp4"[^{}]*?"base_url"\s*:\s*"(https?:(?:\\.|[^"\\])+)""#,
            #""base_url"\s*:\s*"(https?:(?:\\.|[^"\\])+)"[^{}]*?"mime_type"\s*:\s*"audio\\/mp4""#
        ]
        for p in patterns {
            if let raw = RegexUtils.firstMatch(in: html, pattern: p)?.dropFirst().first,
               !raw.isEmpty {
                let decoded = Self.decodeJsonEscapedString(raw)
                if decoded.hasPrefix("http") { return decoded }
            }
        }
        return ""
    }

    private func extractPosterThumbnail(_ html: String) -> String {
        let patterns = [
            #""preferred_thumbnail"\s*:\s*\{\s*"image"\s*:\s*\{\s*"uri"\s*:\s*"(https?:(?:\\.|[^"\\])+)""#,
            #""thumbnailImage"\s*:\s*\{[^{}]*"uri"\s*:\s*"(https?:(?:\\.|[^"\\])+)""#,
            #""image"\s*:\s*\{\s*"uri"\s*:\s*"(https?:\\?/\\?/scontent[^"]+t15\.[^"]+)""#,
            #""image"\s*:\s*\{\s*"uri"\s*:\s*"(https?:\\?/\\?/scontent[^"]+)""#
        ]
        for p in patterns {
            if let raw = RegexUtils.firstMatch(in: html, pattern: p)?.dropFirst().first,
               !raw.isEmpty {
                let decoded = Self.decodeJsonEscapedString(raw)
                if decoded.hasPrefix("http") && !decoded.hasSuffix(".kf") {
                    return decoded
                }
            }
        }
        return extractMetaContent(html: html, property: "og:image")
    }

    private func extractPostImages(_ html: String) -> [String] {
        let pattern = #""image"\s*:\s*\{\s*"uri"\s*:\s*"(https?:\\?/\\?/scontent[^"]+)""#
        var seen = Set<String>()
        var result: [String] = []
        for groups in RegexUtils.allMatches(in: html, pattern: pattern) {
            guard groups.count > 1 else { continue }
            let url = Self.decodeJsonEscapedString(groups[1])
            guard url.hasPrefix("http"),
                  !url.contains("/m1/v/t6/"),
                  !url.hasSuffix(".kf"),
                  !url.contains("p50x50"),
                  !url.contains("s40x40"),
                  seen.insert(url).inserted else {
                continue
            }
            result.append(url)
            if result.count >= 12 { break }
        }
        return result
    }

    private func extractJsonStringField(html: String, pattern: String) -> String {
        guard let raw = RegexUtils.firstMatch(in: html, pattern: pattern)?.dropFirst().first else {
            return ""
        }
        return Self.decodeJsonEscapedString(raw)
    }

    private func extractMetaContent(html: String, property: String) -> String {
        let p1 = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\""
        let p2 = "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"\(property)\""
        let raw = RegexUtils.firstMatch(in: html, pattern: p1, options: [.caseInsensitive])?.dropFirst().first
            ?? RegexUtils.firstMatch(in: html, pattern: p2, options: [.caseInsensitive])?.dropFirst().first
        guard let raw else { return "" }
        return Self.decodeHtmlEntities(raw)
    }

    private func extractMetaNameContent(html: String, name: String) -> String {
        let p1 = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]+)\""
        let p2 = "<meta[^>]+content=\"([^\"]+)\"[^>]+name=\"\(name)\""
        let raw = RegexUtils.firstMatch(in: html, pattern: p1, options: [.caseInsensitive])?.dropFirst().first
            ?? RegexUtils.firstMatch(in: html, pattern: p2, options: [.caseInsensitive])?.dropFirst().first
        guard let raw else { return "" }
        return Self.decodeHtmlEntities(raw)
    }

    private func buildCleanTitle(ogDesc: String, ogTitle: String, fallbackId: String) -> String {
        let trimmedDesc = ogDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDesc.isEmpty { return trimmedDesc }

        let trimmedTitle = ogTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            var cleaned = trimmedTitle
            if cleaned.hasSuffix("| Facebook") {
                cleaned = String(cleaned.dropLast("| Facebook".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleaned.contains("|") {
                let parts = cleaned
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.count >= 2 &&
                    (parts[0].localizedCaseInsensitiveContains("views") ||
                     parts[0].localizedCaseInsensitiveContains("lượt xem")) {
                    cleaned = parts.dropFirst().joined(separator: " • ")
                }
            }
            if !cleaned.isEmpty && cleaned.caseInsensitiveCompare("Facebook") != .orderedSame {
                return cleaned
            }
        }
        return "Facebook Video #\(fallbackId)"
    }

    public static func decodeJsonEscapedString(_ raw: String) -> String {
        if let jsonData = "\"\(raw)\"".data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: jsonData) {
            return decodeHtmlEntities(decoded)
        }
        let manual = raw
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\u0025", with: "%")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003C", with: "<")
            .replacingOccurrences(of: "\\u003c", with: "<")
            .replacingOccurrences(of: "\\u003E", with: ">")
            .replacingOccurrences(of: "\\u003e", with: ">")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u003d", with: "=")
        return decodeHtmlEntities(manual)
    }

    public static func decodeHtmlEntities(_ input: String) -> String {
        var result = input
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        result = RegexUtils.replacingMatches(in: result, pattern: #"&#x([0-9a-fA-F]+);"#) { groups in
            guard groups.count > 1,
                  let scalarVal = UInt32(groups[1], radix: 16),
                  let scalar = UnicodeScalar(scalarVal) else {
                return groups.first ?? ""
            }
            return String(scalar)
        }

        result = RegexUtils.replacingMatches(in: result, pattern: #"&#(\d+);"#) { groups in
            guard groups.count > 1,
                  let scalarVal = UInt32(groups[1], radix: 10),
                  let scalar = UnicodeScalar(scalarVal) else {
                return groups.first ?? ""
            }
            return String(scalar)
        }

        return result
    }
}
