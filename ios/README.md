# NVTSnapMedia for iOS — Native SwiftUI 4K Media Downloader

**Phát triển bởi:** Việt Thắng  
**Bundle Identifier:** `com.nvtsnapmedia.app`  
**Share Extension ID:** `com.nvtsnapmedia.app.ShareExtension`  
**Phiên bản:** `1.0.0` (Native iOS 16.0+ — Swift 5.10 + SwiftUI + `AVFoundation` + `AVKit` + `Photos` + `SQLite3`)

---

## 1. Kiến trúc & Tính năng Native iOS

Phiên bản iOS được thiết kế **100% Native** tương đương hoàn toàn với bản Android gốc, sử dụng các framework chuẩn của Apple (không phụ thuộc thư viện bên thứ ba):

- **Tự động nhận diện nguồn (`MediaUrlDetector`)**:
  - Phân biệt tức thì **YouTube** (`youtube.com`, `youtu.be`, `/shorts/`, `music.youtube.com`), **Facebook** (`facebook.com/reel`, `fb.watch`, `/share/v|r/`, `/videos/`, bài đăng nhiều ảnh) và **TikTok / Douyin** (`tiktok.com`, `vt.tiktok.com`, `vm.tiktok.com`, `v.douyin.com`).
  - Tự động gỡ lớp bọc chuyển tiếp của Messenger (`l.facebook.com/l.php?u=...`).
- **3 Engine Giải Mã Ultra-HD (4K / 2K / 1080p 60FPS)**:
  - `YouTubeExtractorService`: Đa cấu hình Innertube (`IOS` + `ANDROID`), tự động ưu tiên định dạng `MP4` (`AV1` / `HEVC` / `H.264`) tương thích phần cứng Apple và âm thanh gốc không bị lồng tiếng tự động (`!isAutoDubbed`).
  - `FacebookExtractorService`: Giải mã Relay HTML + `/watch/` Reel Ultra-HD upgrade + Video Embed Plugin + bảng kê MPEG-DASH `<MPD>` XML.
  - `TikTokExtractorService`: Kết hợp song song Direct Rehydration `bitrateInfo` + TikWM Master (`hd=1`) + bộ đọc header `tkhd` MP4 để tải video **Không Logo (No Watermark)** và **Ảnh cuộn (Photo Carousel)** 1 chạm.
- **Ghép Luồng Lossless trên Thiết Bị (`DashTrackMuxer` & `AudioTrackExtractor`)**:
  - Ghép luồng Video DASH `4K / 2K / 1080p60` với âm thanh `M4A (AAC)` bằng `AVMutableComposition` + `AVAssetExportSession(presetName: AVAssetExportPresetPassthrough)` không cần biên mã lại.
  - Tự động chuẩn hóa thẻ codec `hev1` → `hvc1` trong cấu trúc ISO-BMFF `stsd` để ứng dụng **Ảnh (Photos)** và trình phát iOS phát mượt mà mọi luồng HEVC.
- **Lưu trữ Kép Chuẩn iOS (Photos Album + Files App)**:
  - Tự động thêm Video & Ảnh vào Album riêng **`"NVTSnapMedia"`** trong ứng dụng **Ảnh (`Photos`)** của iOS.
  - Đồng thời lưu toàn bộ Video, Nhạc (`M4A`/`MP3`) và Ảnh tại **`Tệp (Files) → Trên iPhone của tôi → NVTSnapMedia/{Movies, Music, Pictures}`**.
- **iOS Share Extension (`NVTSnapMediaShareExtension`)**:
  - Cho phép bấm **Chia sẻ (Share) → NVTSnapMedia** trực tiếp từ ứng dụng YouTube, Facebook, TikTok hoặc Safari để chuyển thẳng liên kết sang ứng dụng chính và tự tải chất lượng ưu tiên.

---

## 2. Cấu trúc thư mục

```text
ios/
├── NVTSnapMedia.xcodeproj/           # Dự án Xcode hoàn chỉnh (mở trực tiếp trên macOS)
├── project.yml                       # Cấu hình XcodeGen (tùy chọn tái tạo project)
├── ExportOptions-Unsigned.plist      # Cấu hình xuất gói cài đặt iOS
├── NVTSnapMedia/
│   ├── App/                          # NVTSnapMediaApp, AppContainer, RootTabView
│   ├── Domain/
│   │   ├── Model/                    # UnifiedMedia, DownloadRecord
│   │   └── Util/                     # MediaUrlDetector, RegexUtils, 3 URL Parsers
│   ├── Data/
│   │   ├── Local/                    # AppPreferences (UserDefaults + App Group), DownloadDatabase (SQLite3)
│   │   ├── Remote/                   # UnifiedMediaExtractor + YouTube / Facebook / TikTok Services
│   │   └── Download/                 # MediaDownloadManager, DashTrackMuxer, AudioTrackExtractor
│   ├── UI/
│   │   ├── Theme/                    # Theme.swift (Dark / Light / System + Brand Gradients)
│   │   ├── I18n/                     # AppStrings.swift (Song ngữ Việt / Anh)
│   │   ├── Components/               # SnapMediaComponents, RemoteMediaImage
│   │   ├── Screens/                  # HomeScreen, DownloadsScreen, SettingsScreen, MediaViewerView
│   │   └── MainViewModel.swift
│   └── Resources/                    # Info.plist, NVTSnapMedia.entitlements, Assets.xcassets (AppIcon 1024x1024)
├── NVTSnapMediaShareExtension/       # iOS Share Sheet Extension (ShareViewController.swift)
└── NVTSnapMediaTests/                # Unit Tests (XCTest)
```

---

## 3. Hướng dẫn Biên dịch & Cài đặt lên iPhone / iPad

### Cách 1: Mở trực tiếp bằng Xcode trên macOS
1. Mở tệp `ios/NVTSnapMedia.xcodeproj` bằng **Xcode 15.4+ / Xcode 16+**.
2. Chọn target `NVTSnapMedia` → tab **Signing & Capabilities** → chọn **Team** (Apple ID cá nhân miễn phí hoặc tài khoản Apple Developer).
   - *Lưu ý với Apple ID miễn phí (Personal Team)*: Đổi `PRODUCT_BUNDLE_IDENTIFIER` thành chuỗi duy nhất (ví dụ `com.<tenban>.nvtsnapmedia`) cho cả `NVTSnapMedia` và `NVTSnapMediaShareExtension`. Nếu tài khoản miễn phí không cấp quyền App Groups, bạn có thể xóa mục **App Groups** trong Signing & Capabilities — tính năng Chia sẻ vẫn hoạt động mượt qua URL Scheme `nvtsnapmedia://share?text=...`.
3. Cắm iPhone/iPad (iOS 16.0 trở lên) hoặc chọn iOS Simulator và nhấn **Run (`⌘R`)** (hoặc **`⌘U`** để chạy bộ Unit Tests).

### Cách 2: Đóng gói `.ipa` tự động qua GitHub Actions (khi dùng Windows)
Nếu bạn đang làm việc trên Windows và chưa có máy Mac:
1. Đẩy mã nguồn lên GitHub — workflow `.github/workflows/ios-build.yml` sẽ tự động khởi chạy máy ảo `macos-15`, chạy toàn bộ Unit Tests và đóng gói tệp **`NVTSnapMedia-iOS.ipa`**.
2. Tải tệp `NVTSnapMedia-iOS.ipa` trong mục **Actions → Artifacts**.
3. Dùng **Sideloadly** hoặc **AltStore / SideStore** trên Windows để ký bằng Apple ID của bạn và cài đặt trực tiếp lên iPhone / iPad.
