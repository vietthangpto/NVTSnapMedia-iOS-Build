import AVFoundation
import AVKit
import SwiftUI
import UIKit

public struct MediaViewerView: View {
    public let target: MediaViewerTarget
    public let onOpenAlbum: (DownloadRecord) -> Void
    public let onShare: (DownloadRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appStrings) private var strings

    @State private var player: AVPlayer?
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastImageOffset: CGSize = .zero

    public init(
        target: MediaViewerTarget,
        onOpenAlbum: @escaping (DownloadRecord) -> Void,
        onShare: @escaping (DownloadRecord) -> Void
    ) {
        self.target = target
        self.onOpenAlbum = onOpenAlbum
        self.onShare = onShare
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if target.category == .image {
                zoomableImageBody
            } else {
                videoOrAudioPlayerBody
            }

            VStack {
                topOverlayBar
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupPlayerIfNeeded()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Top Bar

    private var topOverlayBar: some View {
        HStack(spacing: 12) {
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.16)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    PlatformSourceBadge(platform: target.platform, compact: true)
                    if !target.subtitle.isEmpty {
                        Text(target.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if let rec = target.associatedRecord {
                Button {
                    onOpenAlbum(rec)
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.actionOpenAlbum)

                Button {
                    onShare(rec)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.actionShare)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.82), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Video & Audio Playback

    private var videoOrAudioPlayerBody: some View {
        ZStack {
            if let player {
                NativeAVPlayerControllerView(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
            }

            if target.category == .audio {
                VStack(spacing: 16) {
                    RemoteMediaImage(
                        urlString: target.coverUrl,
                        contentMode: .fill,
                        placeholderSystemIcon: "music.note"
                    )
                    .frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: BrandColors.mediaCyan.opacity(0.35), radius: 18, x: 0, y: 8)

                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(BrandColors.mediaCyan)
                        Text(target.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func setupPlayerIfNeeded() {
        guard target.category != .image, player == nil else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        let asset: AVURLAsset
        if target.isLocalFile {
            asset = AVURLAsset(url: target.streamOrFileURL)
        } else {
            var headers: [String: String] = [:]
            if !target.userAgent.isEmpty {
                headers["User-Agent"] = target.userAgent
            }
            if !target.referer.isEmpty {
                headers["Referer"] = target.referer
            }
            if !target.cookie.isEmpty {
                headers["Cookie"] = target.cookie
            }
            if headers.isEmpty {
                asset = AVURLAsset(url: target.streamOrFileURL)
            } else {
                asset = AVURLAsset(
                    url: target.streamOrFileURL,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                )
            }
        }

        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        avPlayer.play()
    }

    // MARK: - Pinch-to-Zoom Image Viewer

    private var zoomableImageBody: some View {
        RemoteMediaImage(
            urlString: target.isLocalFile ? "" : target.streamOrFileURL.absoluteString,
            localFileURL: target.isLocalFile ? target.streamOrFileURL : nil,
            contentMode: .fit,
            placeholderSystemIcon: "photo"
        )
        .scaleEffect(imageScale)
        .offset(imageOffset)
        .gesture(
            MagnificationGesture()
                .onChanged { val in
                    let next = lastImageScale * val
                    imageScale = min(max(next, 1.0), 4.5)
                }
                .onEnded { _ in
                    lastImageScale = imageScale
                    if imageScale <= 1.02 {
                        withAnimation(.spring()) {
                            imageScale = 1.0
                            lastImageScale = 1.0
                            imageOffset = .zero
                            lastImageOffset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard imageScale > 1.02 else { return }
                    imageOffset = CGSize(
                        width: lastImageOffset.width + value.translation.width,
                        height: lastImageOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    lastImageOffset = imageOffset
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                if imageScale > 1.1 {
                    imageScale = 1.0
                    lastImageScale = 1.0
                    imageOffset = .zero
                    lastImageOffset = .zero
                } else {
                    imageScale = 2.5
                    lastImageScale = 2.5
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NativeAVPlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
