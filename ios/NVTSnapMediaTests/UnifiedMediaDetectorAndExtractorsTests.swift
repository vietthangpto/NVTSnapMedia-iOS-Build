import Foundation
import XCTest
@testable import NVTSnapMedia

final class UnifiedMediaDetectorAndExtractorsTests: XCTestCase {

    func testAutoDetectorIdentifiesYouTubeFacebookAndTikTokLinks() {
        // YouTube variants
        let ytWatch = MediaUrlDetector.detect("Xem thử video 4K này: https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=12s hay cực!")
        XCTAssertNotNil(ytWatch)
        XCTAssertEqual(ytWatch?.platform, .youtube)
        XCTAssertTrue(ytWatch?.cleanUrl.contains("dQw4w9WgXcQ") == true)

        let ytShort = MediaUrlDetector.detect("https://youtube.com/shorts/9bZkp7q19f0?si=xyz")
        XCTAssertNotNil(ytShort)
        XCTAssertEqual(ytShort?.platform, .youtube)

        let ytBare = MediaUrlDetector.detect("youtu.be/dQw4w9WgXcQ")
        XCTAssertNotNil(ytBare)
        XCTAssertEqual(ytBare?.platform, .youtube)

        // Facebook variants
        let fbReel = MediaUrlDetector.detect("Check reel: https://www.facebook.com/reel/1122334455667788/?s=single_unit")
        XCTAssertNotNil(fbReel)
        XCTAssertEqual(fbReel?.platform, .facebook)

        let fbWatch = MediaUrlDetector.detect("fb.watch/xYzAbCdEfG/")
        XCTAssertNotNil(fbWatch)
        XCTAssertEqual(fbWatch?.platform, .facebook)

        let fbShare = MediaUrlDetector.detect("https://www.facebook.com/share/v/1AbCdEfGhI/")
        XCTAssertNotNil(fbShare)
        XCTAssertEqual(fbShare?.platform, .facebook)

        // TikTok & Douyin variants
        let tikVideo = MediaUrlDetector.detect("Video hot https://www.tiktok.com/@vietthang/video/7355667788990011223?_t=8m")
        XCTAssertNotNil(tikVideo)
        XCTAssertEqual(tikVideo?.platform, .tiktok)

        let tikShort = MediaUrlDetector.detect("vt.tiktok.com/ZSF987654/")
        XCTAssertNotNil(tikShort)
        XCTAssertEqual(tikShort?.platform, .tiktok)

        let douyinShort = MediaUrlDetector.detect("7.43 复制打开抖音 https://v.douyin.com/iY89abc/ 看看作品")
        XCTAssertNotNil(douyinShort)
        XCTAssertEqual(douyinShort?.platform, .tiktok)
    }

    func testAutoDetectorUnwrapsFacebookMessengerLinkShims() {
        let wrappedYouTube =
            "https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&h=AT0xyz"
        let detectedYt = MediaUrlDetector.detect(wrappedYouTube)
        XCTAssertNotNil(detectedYt)
        XCTAssertEqual(detectedYt?.platform, .youtube)
        XCTAssertTrue(detectedYt?.cleanUrl.contains("youtube.com") == true)

        let wrappedTikTok =
            "https://lm.facebook.com/l.php?u=https%3A%2F%2Fvt.tiktok.com%2FZSF123456%2F&h=AT1abc"
        let detectedTik = MediaUrlDetector.detect(wrappedTikTok)
        XCTAssertNotNil(detectedTik)
        XCTAssertEqual(detectedTik?.platform, .tiktok)
    }

    func testAutoDetectorRejectsSpoofedAndUnsupportedDomains() {
        XCTAssertNil(MediaUrlDetector.detect("https://fakeyoutube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(MediaUrlDetector.detect("https://fakefacebook.com/reel/123456789"))
        XCTAssertNil(MediaUrlDetector.detect("https://faketiktok.com/@user/video/123456"))
        XCTAssertNil(MediaUrlDetector.detect("https://evil.example.com/youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(MediaUrlDetector.detect("https://evil.example.com/tiktok.com/@a/video/123"))
        XCTAssertNil(MediaUrlDetector.detect("Xin chào Việt Thắng, đây chỉ là văn bản bình thường"))
    }

    func testYouTubeEngineParses4K60FpsMp4AndPrefersOriginalNonDubbedAudio() throws {
        let service = YouTubeExtractorService()
        let mockJson = """
        {
          "playabilityStatus": { "status": "OK" },
          "videoDetails": {
            "videoId": "dQw4w9WgXcQ",
            "title": "Vietnam 4K HDR Nature Film",
            "author": "VietThang Studio",
            "lengthSeconds": "180",
            "viewCount": "2500000"
          },
          "streamingData": {
            "formats": [
              {
                "itag": 18,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=18",
                "mimeType": "video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"",
                "width": 640,
                "height": 360,
                "fps": 30,
                "bitrate": 550000,
                "contentLength": "12000000"
              }
            ],
            "adaptiveFormats": [
              {
                "itag": 315,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=315",
                "mimeType": "video/webm; codecs=\\"vp9\\"",
                "width": 3840,
                "height": 2160,
                "fps": 60,
                "bitrate": 28000000,
                "contentLength": "580000000"
              },
              {
                "itag": 701,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=701",
                "mimeType": "video/mp4; codecs=\\"av01.0.12M.08\\"",
                "width": 3840,
                "height": 2160,
                "fps": 60,
                "bitrate": 24000000,
                "contentLength": "510000000"
              },
              {
                "itag": 299,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=299",
                "mimeType": "video/mp4; codecs=\\"avc1.64002a\\"",
                "width": 1920,
                "height": 1080,
                "fps": 60,
                "bitrate": 5800000,
                "contentLength": "120000000"
              },
              {
                "itag": 140,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=140&lang=dub",
                "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"",
                "bitrate": 132000,
                "contentLength": "2900000",
                "audioTrack": { "displayName": "English (auto-dubbed)", "audioIsDefault": false, "isAutoDubbed": true }
              },
              {
                "itag": 140,
                "url": "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=140&lang=vi",
                "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"",
                "bitrate": 129000,
                "contentLength": "2850000",
                "audioTrack": { "displayName": "Vietnamese original", "audioIsDefault": true, "isAutoDubbed": false }
              }
            ]
          }
        }
        """

        let info = try service.parseInnertubePlayerResponse(
            rawJson: mockJson,
            videoId: "dQw4w9WgXcQ",
            originalUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            isShortsHint: false,
            clientUserAgent: YouTubeExtractorService.iosYouTubeUA,
            providerName: "YouTube iOS Engine"
        )

        XCTAssertEqual(info.platform, .youtube)
        XCTAssertEqual(info.maxResolutionBadge, "4K 60FPS")
        let top4k = try XCTUnwrap(info.downloadOptions.first)
        XCTAssertTrue(top4k.isUltraHd)
        XCTAssertEqual(top4k.width, 3840)
        XCTAssertEqual(top4k.height, 2160)
        XCTAssertTrue(top4k.url.contains("itag=701"), "Should prefer AVFoundation-compatible MP4 over WebM")
        XCTAssertTrue(top4k.audioStreamUrl.contains("lang=vi"), "Should select original non-dubbed audio")
    }

    func testFacebookEngineParsesMpegDash4KAnd1080p60StreamsFromRelayHtml() throws {
        let service = FacebookExtractorService()
        let rawMpd = """
        <MPD>
          <Period>
            <AdaptationSet mimeType="video/mp4">
              <Representation id="v4k" width="2160" height="3840" frameRate="60" bandwidth="18500000" codecs="hvc1.1.6.L150">
                <BaseURL>https://video.fhan2-1.fna.fbcdn.net/v/4k_stream.mp4</BaseURL>
              </Representation>
              <Representation id="v1080" width="1080" height="1920" frameRate="60" bandwidth="6200000" codecs="avc1.64002a">
                <BaseURL>https://video.fhan2-1.fna.fbcdn.net/v/1080p_stream.mp4</BaseURL>
              </Representation>
            </AdaptationSet>
            <AdaptationSet mimeType="audio/mp4">
              <Representation id="a1" bandwidth="128000" codecs="mp4a.40.5">
                <BaseURL>https://video.fhan2-1.fna.fbcdn.net/v/audio_aac.m4a</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """
        let escapedMpd = rawMpd
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let mockHtml = """
        <html>
          <head>
            <meta property="og:title" content="Facebook Reel 4K Test - Viet Thang" />
            <meta property="og:image" content="https://scontent.fhan2-1.fna.fbcdn.net/cover.jpg" />
          </head>
          <body>
            <script>
              {"video_id":"9988776655","browser_native_hd_url":"https:\\/\\/video.fhan2-1.fna.fbcdn.net\\/v\\/720p_prog.mp4","browser_native_sd_url":"https:\\/\\/video.fhan2-1.fna.fbcdn.net\\/v\\/sd_prog.mp4","dash_manifest":"\(escapedMpd)"}
            </script>
          </body>
        </html>
        """

        let info = try service.parseFacebookHtml(
            html: mockHtml,
            originalUrl: "https://www.facebook.com/reel/9988776655",
            resolvedUrl: "https://www.facebook.com/reel/9988776655",
            providerName: "Facebook Relay Engine"
        )

        XCTAssertEqual(info.platform, .facebook)
        XCTAssertTrue(info.maxResolutionBadge.contains("4K"))
        let top = try XCTUnwrap(info.downloadOptions.first)
        XCTAssertTrue(top.isUltraHd)
        XCTAssertEqual(top.audioStreamUrl, "https://video.fhan2-1.fna.fbcdn.net/v/audio_aac.m4a")
    }

    func testTikTokEngineParsesVideoUltraHdUpgradeAndPhotoCarouselSlideshows() throws {
        let service = TikTokExtractorService()
        let videoJson = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "id": "7399887766554433221",
            "title": "TikTok 4K Showcase #vietthang",
            "duration": 24,
            "play": "https://cdn.tikwm.com/play_sd.mp4",
            "hdplay": "https://cdn.tikwm.com/play_master.mp4",
            "wmplay": "https://cdn.tikwm.com/play_wm.mp4",
            "music": "https://cdn.tikwm.com/music.mp3",
            "cover": "https://cdn.tikwm.com/cover.jpg",
            "size": 4200000,
            "hd_size": 18500000,
            "author": { "unique_id": "vietthang.dev", "nickname": "Việt Thắng" }
          }
        }
        """

        let baseVideo = try service.parseTikWmJson(
            rawJson: videoJson,
            originalUrl: "https://www.tiktok.com/@vietthang.dev/video/7399887766554433221",
            providerName: "TikTok Engine"
        )
        let upgraded = service.mergeUltraHdOptions(
            baseMedia: baseVideo,
            directGears: [
                DirectVideoGear(
                    gearName: "adapt_2160_1",
                    qualityType: 2,
                    codecLabel: "HEVC",
                    width: 2160,
                    height: 3840,
                    fps: 60,
                    bitrate: 16_000_000,
                    sizeBytes: 48_000_000,
                    url: "https://v16-webapp-prime.tiktok.com/video/4k60.mp4",
                    cookieHeader: "ttwid=abc123"
                )
            ]
        )

        XCTAssertEqual(upgraded.platform, .tiktok)
        XCTAssertTrue(upgraded.isVerticalShort)
        XCTAssertEqual(upgraded.maxResolutionBadge, "4K 60FPS")
        XCTAssertTrue(upgraded.downloadOptions.first?.isUltraHd == true)

        // Photo slideshow JSON
        let galleryJson = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "id": "7311223344556677889",
            "title": "Bộ ảnh cuộn TikTok",
            "images": [
              "https://p16-sign.tiktokcdn.com/img1.jpeg",
              "https://p16-sign.tiktokcdn.com/img2.jpeg",
              "https://p16-sign.tiktokcdn.com/img3.jpeg"
            ],
            "music": "https://cdn.tikwm.com/slide_music.mp3",
            "author": { "unique_id": "vietthang", "nickname": "Việt Thắng" }
          }
        }
        """

        let galleryInfo = try service.parseTikWmJson(
            rawJson: galleryJson,
            originalUrl: "https://www.tiktok.com/@vietthang/photo/7311223344556677889",
            providerName: "TikTok Engine"
        )
        XCTAssertTrue(galleryInfo.isImageGallery)
        XCTAssertEqual(galleryInfo.galleryImages.count, 3)
        XCTAssertEqual(galleryInfo.downloadOptions.filter { $0.imageIndex != nil }.count, 3)
        XCTAssertTrue(galleryInfo.downloadOptions.contains { $0.mediaCategory == .audio })
    }

    func testDashMuxerExtractsIsoBoxAndNormalizesHev1ToHvc1() throws {
        let payload = Data([0x81, 0x08, 0x0C, 0x00])
        var box = Data()
        var bigLen = UInt32(8 + payload.count).bigEndian
        withUnsafeBytes(of: &bigLen) { box.append(contentsOf: $0) }
        box.append(contentsOf: "av1C".utf8)
        box.append(payload)

        var stream = Data(repeating: 0, count: 0)
        // Prepend a dummy 16-byte `ftyp` box
        var ftypLen = UInt32(16).bigEndian
        withUnsafeBytes(of: &ftypLen) { stream.append(contentsOf: $0) }
        stream.append(contentsOf: "ftyp".utf8)
        stream.append(Data(repeating: 0, count: 8))
        stream.append(box)

        let extracted = DashTrackMuxer.extractIsoBoxPayload(data: stream, boxType: "av1C")
        XCTAssertEqual(extracted, payload)

        // Build synthetic `moov -> trak -> stsd` containing a `hev1` sample entry and verify normalization to `hvc1`
        func makeAtom(_ fourCC: String, body: Data) -> Data {
            var d = Data()
            var sz = UInt32(8 + body.count).bigEndian
            withUnsafeBytes(of: &sz) { d.append(contentsOf: $0) }
            d.append(contentsOf: fourCC.utf8)
            d.append(body)
            return d
        }

        let hev1Entry = makeAtom("hev1", body: Data(repeating: 0xAA, count: 16))
        var stsdBody = Data([0, 0, 0, 0, 0, 0, 0, 1]) // version/flags + entry_count=1
        stsdBody.append(hev1Entry)
        let stsd = makeAtom("stsd", body: stsdBody)
        let stbl = makeAtom("stbl", body: stsd)
        let minf = makeAtom("minf", body: stbl)
        let mdia = makeAtom("mdia", body: minf)
        let trak = makeAtom("trak", body: mdia)
        let moov = makeAtom("moov", body: trak)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_hevc_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try moov.write(to: tempURL)

        DashTrackMuxer.normalizeHevcSampleEntryIfNeeded(at: tempURL)
        let patched = try Data(contentsOf: tempURL)
        let patchedAscii = String(data: patched, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(patchedAscii.contains("hvc1"))
        XCTAssertFalse(patchedAscii.contains("hev1"))
    }

    func testStringsIncludeAlbumActionAndCompleteLegalDisclaimerInBothLanguages() {
        for s in [VietnameseStrings, EnglishStrings] {
            XCTAssertFalse(s.developerName.isEmpty)
            XCTAssertEqual(s.developerName, "Việt Thắng")
            XCTAssertFalse(s.actionOpenAlbum.isEmpty)
            XCTAssertFalse(s.actionOpenAlbumDesc.isEmpty)
            XCTAssertFalse(s.sectionDisclaimer.isEmpty)
            XCTAssertFalse(s.disclaimerShortNotice.isEmpty)
            XCTAssertFalse(s.disclaimerItem1Title.isEmpty)
            XCTAssertFalse(s.disclaimerItem1Body.isEmpty)
            XCTAssertFalse(s.disclaimerItem2Title.isEmpty)
            XCTAssertFalse(s.disclaimerItem2Body.isEmpty)
            XCTAssertFalse(s.disclaimerItem3Title.isEmpty)
            XCTAssertFalse(s.disclaimerItem3Body.isEmpty)
            XCTAssertFalse(s.disclaimerItem4Title.isEmpty)
            XCTAssertFalse(s.disclaimerItem4Body.isEmpty)
            XCTAssertFalse(s.albumFileNotFoundMsg.isEmpty)
            XCTAssertFalse(s.albumNoAppFoundMsg.isEmpty)
        }
    }
}
