import SwiftUI

public struct AppStrings: Equatable, Sendable {
    public let appName: String
    public let appTagline: String
    public let developerName: String
    public let developerRoleLabel: String
    public let developerCreditShort: String
    public let appVersionLabel: String
    public let navHome: String
    public let navDownloads: String
    public let navSettings: String
    public let heroCardTitle: String
    public let autoDetectIdleHint: String
    public let autoDetectedPrefix: String
    public let quickOpenLabel: String
    public let inputPlaceholder: String
    public let pasteLink: String
    public let clearInput: String
    public let downloadNow: String
    public let analyzingLink: String
    public let analyzingSubtitle: String
    public let clipboardDetectedTitle: String
    public let clipboardUseAction: String
    public let dismiss: String
    public let badgeAllInOne: String
    public let badgeUltraHd: String
    public let badgeNoLogo: String
    public let badgeAudioPhoto: String
    public let copyCaption: String
    public let captionCopied: String
    public let previewMedia: String
    public let downloadAllPhotos: String
    public let photosCountSuffix: String
    public let activeQueueTitle: String
    public let viewQueue: String
    public let howToTitle: String
    public let tabShareMethod: String
    public let tabCopyMethod: String
    public let shareStep1Title: String
    public let shareStep1Desc: String
    public let shareStep2Title: String
    public let shareStep2Desc: String
    public let shareStep3Title: String
    public let shareStep3Desc: String
    public let copyStep1Title: String
    public let copyStep1Desc: String
    public let copyStep2Title: String
    public let copyStep2Desc: String
    public let copyStep3Title: String
    public let copyStep3Desc: String
    public let featuresTitle: String
    public let featAutoTitle: String
    public let featAutoDesc: String
    public let featUltraTitle: String
    public let featUltraDesc: String
    public let featMuxTitle: String
    public let featMuxDesc: String
    public let featGalleryTitle: String
    public let featGalleryDesc: String
    public let faqTitle: String
    public let faq1Q: String
    public let faq1A: String
    public let faq2Q: String
    public let faq2A: String
    public let faq3Q: String
    public let faq3A: String
    public let faq4Q: String
    public let faq4A: String
    public let downloadsTitle: String
    public let searchDownloadsHint: String
    public let filterAll: String
    public let filterVideo: String
    public let filterAudio: String
    public let filterImage: String
    public let emptyDownloadsTitle: String
    public let emptyDownloadsDesc: String
    public let statusCompleted: String
    public let statusDownloading: String
    public let statusQueued: String
    public let statusFailed: String
    public let statusCanceled: String
    public let actionPlay: String
    public let actionOpenAlbum: String
    public let actionOpenAlbumDesc: String
    public let actionShare: String
    public let actionRetry: String
    public let actionCancel: String
    public let actionDelete: String
    public let actionOpenSource: String
    public let deleteConfirmTitle: String
    public let deleteConfirmBody: String
    public let confirm: String
    public let settingsTitle: String
    public let sectionAutomation: String
    public let prefAutoClipboardTitle: String
    public let prefAutoClipboardDesc: String
    public let prefAutoShareDownloadTitle: String
    public let prefAutoShareDownloadDesc: String
    public let prefDefaultQualityTitle: String
    public let qualityUltraHdVideo: String
    public let qualityUltraHdVideoSub: String
    public let qualityFhd1080Video: String
    public let qualityFhd1080VideoSub: String
    public let qualityHdVideo: String
    public let qualityHdVideoSub: String
    public let qualitySdVideo: String
    public let qualitySdVideoSub: String
    public let qualityAudioOnly: String
    public let qualityAudioOnlySub: String
    public let sectionAppearance: String
    public let prefThemeTitle: String
    public let themeDarkShort: String
    public let themeLightShort: String
    public let themeSystemShort: String
    public let prefLanguageTitle: String
    public let sectionStorage: String
    public let storagePathTitle: String
    public let storagePathValue: String
    public let customApiTitle: String
    public let customApiHint: String
    public let save: String
    public let clearHistoryTitle: String
    public let clearHistoryDesc: String
    public let historyClearedMsg: String
    public let sectionAbout: String
    public let aboutDisclaimer: String
    public let sectionDisclaimer: String
    public let disclaimerShortNotice: String
    public let disclaimerViewDetails: String
    public let disclaimerUnderstood: String
    public let disclaimerItem1Title: String
    public let disclaimerItem1Body: String
    public let disclaimerItem2Title: String
    public let disclaimerItem2Body: String
    public let disclaimerItem3Title: String
    public let disclaimerItem3Body: String
    public let disclaimerItem4Title: String
    public let disclaimerItem4Body: String
    public let albumFileNotFoundMsg: String
    public let albumNoAppFoundMsg: String
    public let emptyClipboardMsg: String
    public let invalidUrlMsg: String
    public let startedDownloadMsg: String
}

public let VietnameseStrings = AppStrings(
    appName: "NVTSnapMedia",
    appTagline: "YouTube • Facebook • TikTok 4K • Việt Thắng",
    developerName: "Việt Thắng",
    developerRoleLabel: "NHÀ PHÁT TRIỂN ỨNG DỤNG",
    developerCreditShort: "Phát triển bởi Việt Thắng",
    appVersionLabel: "Phiên bản 1.0.0 • All-in-One 4K Native iOS",
    navHome: "Tải xuống",
    navDownloads: "Kho lưu trữ",
    navSettings: "Cài đặt",
    heroCardTitle: "Dán link bất kỳ — Tự nhận diện nguồn 4K",
    autoDetectIdleHint: "Tự động nhận diện: YouTube • Facebook • TikTok",
    autoDetectedPrefix: "Đã nhận diện tự động:",
    quickOpenLabel: "Mở nhanh:",
    inputPlaceholder: "Dán link YouTube, Facebook hoặc TikTok...",
    pasteLink: "Dán Link",
    clearInput: "Xóa",
    downloadNow: "Tải Ngay",
    analyzingLink: "Đang nhận diện & bóc tách luồng 4K...",
    analyzingSubtitle: "Tự động kết nối engine YouTube / Facebook / TikTok tương ứng",
    clipboardDetectedTitle: "Phát hiện liên kết trong bộ nhớ tạm",
    clipboardUseAction: "Dán & Phân tích",
    dismiss: "Bỏ qua",
    badgeAllInOne: "3 Trong 1",
    badgeUltraHd: "4K • 2K • 1080p",
    badgeNoLogo: "Không Logo",
    badgeAudioPhoto: "MP3/M4A & Ảnh",
    copyCaption: "Chép tiêu đề",
    captionCopied: "Đã sao chép tiêu đề vào bộ nhớ tạm",
    previewMedia: "Xem thử",
    downloadAllPhotos: "Tải tất cả ảnh",
    photosCountSuffix: "ảnh",
    activeQueueTitle: "Đang tải xuống",
    viewQueue: "Xem tiến trình",
    howToTitle: "Hướng dẫn tải đa nền tảng trên iOS",
    tabShareMethod: "Chia sẻ 1 chạm",
    tabCopyMethod: "Sao chép liên kết",
    shareStep1Title: "Mở YouTube, Facebook hoặc TikTok",
    shareStep1Desc: "Xem bất kỳ Video, Shorts, Reels hoặc bài đăng Ảnh cuộn công khai nào.",
    shareStep2Title: "Nhấn Chia sẻ → Chọn NVTSnapMedia",
    shareStep2Desc: "Share Extension trên iOS tự động chuyển tiếp và nhận diện đúng nền tảng gốc.",
    shareStep3Title: "Chọn 4K / 2K / 1080p, Không Logo hoặc Nhạc",
    shareStep3Desc: "Tải siêu tốc và ghép âm thanh gốc Lossless trực tiếp vào Album Ảnh & Tệp.",
    copyStep1Title: "Sao chép liên kết từ bất kỳ ứng dụng nào",
    copyStep1Desc: "Hỗ trợ link YouTube, Shorts, Facebook Watch/Reels, TikTok & Douyin.",
    copyStep2Title: "Mở ứng dụng NVTSnapMedia",
    copyStep2Desc: "Bộ nhận diện thông minh tự phát hiện nền tảng ngay khi bạn dán link.",
    copyStep3Title: "Bấm Tải Ngay để lưu chất lượng cao nhất",
    copyStep3Desc: "Lưu tự động vào Album \"NVTSnapMedia\" trong ứng dụng Ảnh (Photos) và ứng dụng Tệp (Files).",
    featuresTitle: "Sức mạnh hợp nhất 3 trong 1",
    featAutoTitle: "Tự nhận diện nguồn",
    featAutoDesc: "Tự phân biệt chính xác link YouTube, Facebook và TikTok chỉ từ một ô nhập duy nhất.",
    featUltraTitle: "Siêu nét 4K • 2K • 60FPS",
    featUltraDesc: "Mở khóa trọn bộ 2160p 4K, 1440p 2K, 1080p 60fps và TikTok gốc không dính logo.",
    featMuxTitle: "Ghép Lossless & Tốc độ cao",
    featMuxDesc: "Tải phân mảnh chống bóp băng thông CDN và ghép hình + tiếng AAC nguyên bản bằng AVFoundation.",
    featGalleryTitle: "Ảnh cuộn & Nhạc MP3/M4A",
    featGalleryDesc: "Tải trọn bộ ảnh cuộn TikTok/Facebook 1 chạm cùng âm thanh gốc MP3 & M4A 128kbps.",
    faqTitle: "Câu hỏi thường gặp",
    faq1Q: "Ứng dụng tự nhận diện YouTube, Facebook và TikTok như thế nào?",
    faq1A: "Bạn chỉ cần dán hoặc chia sẻ bất kỳ đường dẫn nào vào ô nhập — NVTSnapMedia sẽ tự động phân tích tên miền (kể cả link rút gọn youtu.be, fb.watch, vt.tiktok.com hay link qua Messenger) để kích hoạt đúng bộ giải mã gốc.",
    faq2Q: "Video 4K / 2K / 1080p tải về có đầy đủ âm thanh và không dính logo chứ?",
    faq2A: "Hoàn toàn đầy đủ! Với YouTube & Facebook, ứng dụng tự ghép luồng hình Ultra-HD với âm thanh AAC gốc bằng AVFoundation Passthrough. Với TikTok, ứng dụng tải trực tiếp bản Master không dính watermark.",
    faq3Q: "Các tệp tải xong nằm ở đâu trên iPhone / iPad?",
    faq3A: "Video và Ảnh được thêm tự động vào Album \"NVTSnapMedia\" trong ứng dụng Ảnh (Photos) của iOS, đồng thời toàn bộ Video, Nhạc M4A/MP3 và Ảnh đều được lưu trong ứng dụng Tệp (Files → Trên iPhone của tôi → NVTSnapMedia). Bạn cũng có thể bấm \"Mở Album\" để chuyển nhanh tới ứng dụng Ảnh hoặc Tệp.",
    faq4Q: "Có cần đăng nhập tài khoản mạng xã hội không?",
    faq4A: "Không cần đăng nhập! NVTSnapMedia hoạt động độc lập trên iOS, an toàn tuyệt đối và không thu thập bất kỳ dữ liệu tài khoản nào.",
    downloadsTitle: "Kho lưu trữ đa nền tảng",
    searchDownloadsHint: "Tìm theo tiêu đề, kênh hoặc tác giả...",
    filterAll: "Tất cả",
    filterVideo: "Video",
    filterAudio: "Nhạc",
    filterImage: "Ảnh",
    emptyDownloadsTitle: "Chưa có tệp nào được tải",
    emptyDownloadsDesc: "Dán link YouTube, Facebook hoặc TikTok ở tab Tải xuống để lưu media 4K về máy.",
    statusCompleted: "Hoàn tất",
    statusDownloading: "Đang tải",
    statusQueued: "Đang chờ",
    statusFailed: "Lỗi tải",
    statusCanceled: "Đã hủy",
    actionPlay: "Mở xem",
    actionOpenAlbum: "Mở Album",
    actionOpenAlbumDesc: "Mở trong ứng dụng Ảnh (Photos) hoặc Tệp (Files) của iOS",
    actionShare: "Chia sẻ",
    actionRetry: "Thử lại",
    actionCancel: "Hủy",
    actionDelete: "Xóa tệp",
    actionOpenSource: "Mở bài gốc",
    deleteConfirmTitle: "Xóa tệp đã tải?",
    deleteConfirmBody: "Tệp này sẽ bị xóa khỏi danh sách ứng dụng và thư mục lưu trữ nội bộ.",
    confirm: "Xóa",
    settingsTitle: "Cài đặt",
    sectionAutomation: "Tự động hóa thông minh",
    prefAutoClipboardTitle: "Tự động quét Clipboard",
    prefAutoClipboardDesc: "Tự phát hiện link YouTube, Facebook hoặc TikTok vừa sao chép khi mở app",
    prefAutoShareDownloadTitle: "Tải ngay khi Chia sẻ sang app",
    prefAutoShareDownloadDesc: "Tự động tải chất lượng ưu tiên khi bấm Share từ YouTube / Facebook / TikTok",
    prefDefaultQualityTitle: "Chất lượng tự động ưu tiên",
    qualityUltraHdVideo: "Siêu nét tối đa (4K / 2K / 1080p 60FPS)",
    qualityUltraHdVideoSub: "Tự chọn bản nét nhất không logo có sẵn của nguồn",
    qualityFhd1080Video: "Full HD 1080p",
    qualityFhd1080VideoSub: "Sắc nét cao, tương thích mọi thiết bị Apple",
    qualityHdVideo: "Video HD (720p)",
    qualityHdVideoSub: "Cân bằng độ nét và dung lượng tệp",
    qualitySdVideo: "Video Tiêu chuẩn (SD Nhanh)",
    qualitySdVideoSub: "Tải siêu nhanh, tiết kiệm dữ liệu di động",
    qualityAudioOnly: "Chỉ tải Nhạc / Âm thanh (M4A / MP3)",
    qualityAudioOnlySub: "Tự động lưu bản nhạc gốc từ video",
    sectionAppearance: "Giao diện & Ngôn ngữ",
    prefThemeTitle: "Chế độ giao diện",
    themeDarkShort: "Tối",
    themeLightShort: "Sáng",
    themeSystemShort: "Hệ thống",
    prefLanguageTitle: "Ngôn ngữ hiển thị",
    sectionStorage: "Lưu trữ & Máy chủ",
    storagePathTitle: "Vị trí lưu trữ trên iOS",
    storagePathValue: "• Ảnh (Photos) → Album \"NVTSnapMedia\" (Video & Ảnh)\n• Tệp (Files) → Trên iPhone của tôi → NVTSnapMedia/{Movies, Music, Pictures}",
    customApiTitle: "Máy chủ API tùy chỉnh (Không bắt buộc)",
    customApiHint: "Để trống để dùng 3 Engine gốc tích hợp sẵn",
    save: "Lưu cấu hình",
    clearHistoryTitle: "Dọn lịch sử danh sách tải",
    clearHistoryDesc: "Xóa danh sách lịch sử trong ứng dụng nhưng giữ nguyên các file trong Ảnh & Tệp",
    historyClearedMsg: "Đã dọn sạch danh sách lịch sử",
    sectionAbout: "Thông tin ứng dụng",
    aboutDisclaimer: "NVTSnapMedia v1.0.0 (Native iOS) — Phát triển bởi Việt Thắng.\nỨng dụng hợp nhất 3 bộ giải mã gốc (YouTube, Facebook & TikTok) với khả năng tự động nhận diện nguồn thông minh và tải Ultra-HD 4K.",
    sectionDisclaimer: "Miễn trừ trách nhiệm",
    disclaimerShortNotice: "NVTSnapMedia là công cụ kỹ thuật độc lập phục vụ nhu cầu lưu trữ cá nhân hợp pháp, không liên kết với YouTube, Facebook hay TikTok. Mọi bản quyền nội dung thuộc về tác giả gốc — người dùng tự chịu trách nhiệm tuân thủ pháp luật và Điều khoản dịch vụ.",
    disclaimerViewDetails: "Xem chi tiết",
    disclaimerUnderstood: "Đã hiểu",
    disclaimerItem1Title: "1. Độc lập & Không liên kết thương hiệu",
    disclaimerItem1Body: "NVTSnapMedia là ứng dụng tiện ích độc lập, không liên kết, hợp tác, được tài trợ hay ủy quyền bởi YouTube (Google LLC), Facebook (Meta Platforms, Inc.), TikTok / Douyin (ByteDance Ltd.) hoặc bất kỳ bên thứ ba nào. Mọi nhãn hiệu, tên gọi và biểu trưng đều thuộc quyền sở hữu của chủ sở hữu tương ứng.",
    disclaimerItem2Title: "2. Bản quyền & Quyền sở hữu trí tuệ",
    disclaimerItem2Body: "Toàn bộ quyền sở hữu trí tuệ đối với video, âm thanh, hình ảnh và bài đăng thuộc về nhà sáng tạo nội dung (tác giả) và nền tảng gốc. Vui lòng tôn trọng bản quyền và xin phép chủ sở hữu trước khi sao chép, chỉnh sửa, đăng tải lại hoặc sử dụng vào mục đích thương mại.",
    disclaimerItem3Title: "3. Mục đích sử dụng & Trách nhiệm người dùng",
    disclaimerItem3Body: "Ứng dụng chỉ phục vụ mục đích lưu trữ cá nhân, học tập và xem ngoại tuyến hợp pháp đối với nội dung công khai. Người dùng hoàn toàn tự chịu trách nhiệm pháp lý đối với hành vi tải xuống và sử dụng dữ liệu. Nhà phát triển miễn trừ mọi trách nhiệm đối với các hành vi xâm phạm bản quyền, vi phạm Điều khoản dịch vụ (ToS) hoặc thiệt hại phát sinh từ việc sử dụng sai mục đích.",
    disclaimerItem4Title: "4. Quyền riêng tư & Xử lý trên thiết bị",
    disclaimerItem4Body: "NVTSnapMedia không lưu trữ, sao lưu hay phân phối bất kỳ tệp đa phương tiện nào trên máy chủ riêng, không yêu cầu đăng nhập tài khoản mạng xã hội và không thu thập thông tin cá nhân. Mọi quá trình xử lý đều diễn ra trực tiếp trên thiết bị iOS của người dùng.",
    albumFileNotFoundMsg: "Không tìm thấy tệp trên thiết bị (có thể đã bị di chuyển hoặc xóa)",
    albumNoAppFoundMsg: "Không thể mở ứng dụng Ảnh / Tệp trên thiết bị này",
    emptyClipboardMsg: "Bộ nhớ tạm hiện đang trống",
    invalidUrlMsg: "Vui lòng nhập liên kết hợp lệ từ YouTube, Facebook hoặc TikTok",
    startedDownloadMsg: "Đã thêm vào tiến trình tải xuống!"
)

public let EnglishStrings = AppStrings(
    appName: "NVTSnapMedia",
    appTagline: "YouTube • Facebook • TikTok 4K • by Việt Thắng",
    developerName: "Việt Thắng",
    developerRoleLabel: "LEAD APPLICATION DEVELOPER",
    developerCreditShort: "Developed by Việt Thắng",
    appVersionLabel: "Version 1.0.0 • All-in-One 4K Native iOS",
    navHome: "Download",
    navDownloads: "Library",
    navSettings: "Settings",
    heroCardTitle: "Paste any link — Auto-detect 4K source",
    autoDetectIdleHint: "Auto-detects: YouTube • Facebook • TikTok",
    autoDetectedPrefix: "Auto-detected source:",
    quickOpenLabel: "Quick open:",
    inputPlaceholder: "Paste YouTube, Facebook, or TikTok link...",
    pasteLink: "Paste",
    clearInput: "Clear",
    downloadNow: "Download",
    analyzingLink: "Auto-detecting & extracting 4K streams...",
    analyzingSubtitle: "Routing to native YouTube / Facebook / TikTok Ultra-HD engine",
    clipboardDetectedTitle: "Media link found in clipboard",
    clipboardUseAction: "Paste & Analyze",
    dismiss: "Dismiss",
    badgeAllInOne: "3-in-1",
    badgeUltraHd: "4K • 2K • 1080p",
    badgeNoLogo: "No Watermark",
    badgeAudioPhoto: "MP3/M4A & Photos",
    copyCaption: "Copy title",
    captionCopied: "Title copied to clipboard",
    previewMedia: "Preview",
    downloadAllPhotos: "Download All Photos",
    photosCountSuffix: "photos",
    activeQueueTitle: "Downloading",
    viewQueue: "View queue",
    howToTitle: "How to download on iOS",
    tabShareMethod: "1-Tap Share",
    tabCopyMethod: "Copy Link",
    shareStep1Title: "Open YouTube, Facebook, or TikTok",
    shareStep1Desc: "Find any public Video, Short, Reel, or Photo Carousel post.",
    shareStep2Title: "Tap Share → Select NVTSnapMedia",
    shareStep2Desc: "The iOS Share Extension automatically hands off and detects the platform.",
    shareStep3Title: "Pick 4K / 2K / 1080p, No-Logo, or Audio",
    shareStep3Desc: "Streams at full speed and muxes lossless audio directly to Photos & Files.",
    copyStep1Title: "Copy link from any supported app",
    copyStep1Desc: "Supports YouTube, Shorts, Facebook Watch/Reels, TikTok & Douyin.",
    copyStep2Title: "Open NVTSnapMedia",
    copyStep2Desc: "Smart auto-detection recognizes the platform immediately.",
    copyStep3Title: "Tap Download to save in highest quality",
    copyStep3Desc: "Saved automatically to the \"NVTSnapMedia\" album in Photos and to the iOS Files app.",
    featuresTitle: "All-in-One Powerhouse",
    featAutoTitle: "Smart Source Detection",
    featAutoDesc: "Automatically distinguishes YouTube, Facebook, and TikTok links from a single input box.",
    featUltraTitle: "True 4K • 2K • 60FPS",
    featUltraDesc: "Unlocks 2160p 4K, 1440p 2K, 1080p 60fps, and clean unwatermarked TikTok masters.",
    featMuxTitle: "Lossless Mux & Full Speed",
    featMuxDesc: "Unthrottled chunked CDN streaming + on-device AVFoundation lossless video/audio muxing.",
    featGalleryTitle: "Photo Slides & MP3/M4A",
    featGalleryDesc: "1-tap batch photo slideshow downloads plus original MP3 & 128kbps M4A audio.",
    faqTitle: "Frequently Asked Questions",
    faq1Q: "How does auto-detection work across YouTube, Facebook, and TikTok?",
    faq1A: "Simply paste or share any link — NVTSnapMedia inspects the URL (including shortlinks like youtu.be, fb.watch, vt.tiktok.com, and Messenger link shims) and routes it to the right native engine.",
    faq2Q: "Do 4K / 2K / 1080p downloads include full audio and no watermark?",
    faq2A: "Yes! YouTube & Facebook Ultra-HD streams are losslessly muxed with original AAC audio via AVFoundation, and TikTok videos use clean unwatermarked master streams.",
    faq3Q: "Where are downloaded files saved on iPhone / iPad?",
    faq3A: "Videos and photos are saved directly to the \"NVTSnapMedia\" album in the iOS Photos app, and all Videos, Audio (M4A/MP3), and Photos are accessible in the iOS Files app under On My iPhone → NVTSnapMedia. Tap \"Album\" on any item to jump straight there.",
    faq4Q: "Do I need to sign in to any social account?",
    faq4A: "No login required! Everything runs safely and privately on your iOS device.",
    downloadsTitle: "Unified Media Library",
    searchDownloadsHint: "Search by title, channel, or creator...",
    filterAll: "All",
    filterVideo: "Videos",
    filterAudio: "Audio",
    filterImage: "Photos",
    emptyDownloadsTitle: "No downloads yet",
    emptyDownloadsDesc: "Paste a YouTube, Facebook, or TikTok link on the Download tab to save 4K media.",
    statusCompleted: "Completed",
    statusDownloading: "Downloading",
    statusQueued: "Queued",
    statusFailed: "Failed",
    statusCanceled: "Canceled",
    actionPlay: "Open",
    actionOpenAlbum: "Album",
    actionOpenAlbumDesc: "Open in iOS Photos or Files app",
    actionShare: "Share",
    actionRetry: "Retry",
    actionCancel: "Cancel",
    actionDelete: "Delete",
    actionOpenSource: "Open Original",
    deleteConfirmTitle: "Delete downloaded file?",
    deleteConfirmBody: "This removes the item from the app list and deletes its file from the app folder.",
    confirm: "Delete",
    settingsTitle: "Settings",
    sectionAutomation: "Smart Automation",
    prefAutoClipboardTitle: "Auto-detect clipboard links",
    prefAutoClipboardDesc: "Detect copied YouTube, Facebook, or TikTok links when opening the app",
    prefAutoShareDownloadTitle: "Instant download on Share",
    prefAutoShareDownloadDesc: "Automatically download preferred quality when shared from another app",
    prefDefaultQualityTitle: "Preferred auto-download quality",
    qualityUltraHdVideo: "Max Ultra-HD (4K / 2K / 1080p 60FPS)",
    qualityUltraHdVideoSub: "Automatically picks the highest clean resolution available",
    qualityFhd1080Video: "Full HD 1080p",
    qualityFhd1080VideoSub: "Sharp Full HD compatible with all Apple devices",
    qualityHdVideo: "HD Video (720p)",
    qualityHdVideoSub: "Balanced sharpness and file size",
    qualitySdVideo: "Fast Standard Video (SD)",
    qualitySdVideoSub: "Smallest size, saves mobile data",
    qualityAudioOnly: "Original Audio Only (M4A / MP3)",
    qualityAudioOnlySub: "Save clean audio track only",
    sectionAppearance: "Appearance & Language",
    prefThemeTitle: "Theme mode",
    themeDarkShort: "Dark",
    themeLightShort: "Light",
    themeSystemShort: "System",
    prefLanguageTitle: "App language",
    sectionStorage: "Storage & Extraction Engine",
    storagePathTitle: "Default iOS media locations",
    storagePathValue: "• Photos app → \"NVTSnapMedia\" Album (Videos & Photos)\n• Files app → On My iPhone → NVTSnapMedia/{Movies, Music, Pictures}",
    customApiTitle: "Custom API Endpoint (Optional)",
    customApiHint: "Leave blank to use built-in 3-platform engines",
    save: "Save Endpoint",
    clearHistoryTitle: "Clear download history list",
    clearHistoryDesc: "Removes entries from app list while keeping saved media files in Photos & Files",
    historyClearedMsg: "Download history cleared",
    sectionAbout: "About",
    aboutDisclaimer: "NVTSnapMedia v1.0.0 (Native iOS) — Developed by Việt Thắng.\nAll-in-one native downloader uniting YouTube, Facebook & TikTok engines with automatic source detection and 4K Ultra-HD support.",
    sectionDisclaimer: "Legal Disclaimer",
    disclaimerShortNotice: "NVTSnapMedia is an independent utility for lawful personal offline archiving and is not affiliated with YouTube, Facebook, or TikTok. All copyrights belong to the original creators — users are solely responsible for complying with laws and platform Terms of Service.",
    disclaimerViewDetails: "Full Disclaimer",
    disclaimerUnderstood: "Got it",
    disclaimerItem1Title: "1. Non-Affiliation & Trademarks",
    disclaimerItem1Body: "NVTSnapMedia is an independent utility app and is not affiliated with, endorsed, sponsored, or authorized by YouTube (Google LLC), Facebook (Meta Platforms, Inc.), TikTok / Douyin (ByteDance Ltd.), or any third party. All trademarks, names, and logos belong to their respective owners.",
    disclaimerItem2Title: "2. Copyright & Intellectual Property",
    disclaimerItem2Body: "All intellectual property rights for downloaded videos, audio tracks, photos, and posts remain with the original content creators and publishing platforms. Please respect copyright and obtain permission from the rights holder before copying, modifying, reposting, or using content commercially.",
    disclaimerItem3Title: "3. Personal Use & User Responsibility",
    disclaimerItem3Body: "This app is provided strictly for lawful personal archiving, educational reference, and offline viewing of public content. Users assume full legal responsibility for their downloads and usage. The developer disclaims all liability for copyright infringement, platform Terms of Service (ToS) violations, or any damages arising from misuse.",
    disclaimerItem4Title: "4. Privacy & On-Device Processing",
    disclaimerItem4Body: "NVTSnapMedia does not host, store, or redistribute any media files on external servers, requires no social account login, and collects no personal data. All stream extraction and file saving take place directly on your iOS device.",
    albumFileNotFoundMsg: "File not found on device (it may have been moved or deleted)",
    albumNoAppFoundMsg: "Unable to open Photos or Files app on this device",
    emptyClipboardMsg: "Clipboard is empty",
    invalidUrlMsg: "Please enter a valid YouTube, Facebook, or TikTok link",
    startedDownloadMsg: "Added to download queue!"
)

public func stringsForLanguage(_ language: AppLanguage) -> AppStrings {
    switch language {
    case .vi: return VietnameseStrings
    case .en: return EnglishStrings
    }
}

private struct AppStringsKey: EnvironmentKey {
    static let defaultValue: AppStrings = VietnameseStrings
}

public extension EnvironmentValues {
    var appStrings: AppStrings {
        get { self[AppStringsKey.self] }
        set { self[AppStringsKey.self] = newValue }
    }
}
