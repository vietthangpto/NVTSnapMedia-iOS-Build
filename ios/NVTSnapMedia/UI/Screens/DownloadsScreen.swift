import SwiftUI

public struct DownloadsScreen: View {
    @ObservedObject public var viewModel: MainViewModel
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    @State private var recordPendingDelete: DownloadRecord?

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let items = viewModel.filteredDownloads

        VStack(spacing: 0) {
            headerAndFilters
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if items.isEmpty {
                emptyLibraryState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { record in
                            DownloadRecordCard(
                                record: record,
                                onPlay: { viewModel.openDownloadedRecordViewer(record) },
                                onOpenAlbum: { viewModel.openRecordInSystemAlbum(record) },
                                onShare: { viewModel.shareDownloadedRecord(record) },
                                onRetry: { viewModel.downloadManager.retryDownload(record.id) },
                                onCancel: { viewModel.downloadManager.cancelDownload(record.id) },
                                onOpenSource: { viewModel.openOriginalSourceURL(record.sourceUrl) },
                                onDelete: { recordPendingDelete = record }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .alert(
            strings.deleteConfirmTitle,
            isPresented: Binding(
                get: { recordPendingDelete != nil },
                set: { if !$0 { recordPendingDelete = nil } }
            ),
            presenting: recordPendingDelete
        ) { target in
            Button(strings.confirm, role: .destructive) {
                Task {
                    await viewModel.downloadManager.deleteDownload(target, deleteLocalFile: true)
                }
                recordPendingDelete = nil
            }
            Button(strings.actionCancel, role: .cancel) {
                recordPendingDelete = nil
            }
        } message: { _ in
            Text(strings.deleteConfirmBody)
        }
    }

    // MARK: - Search & Filter Chips

    private var headerAndFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.downloadsTitle)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.onBackground)
                Spacer()
                Text("\(viewModel.database.downloads.count)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.primaryContainer)
                    )
            }

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                TextField(strings.searchDownloadsHint, text: $viewModel.searchQuery)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.onSurface)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(palette.outline.opacity(0.45), lineWidth: 1)
            )

            // Platform filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        label: strings.filterAll,
                        selected: viewModel.platformFilter == nil,
                        accent: palette.primary
                    ) {
                        viewModel.platformFilter = nil
                    }

                    ForEach(MediaPlatform.allCases) { plat in
                        filterChip(
                            label: plat.displayName,
                            selected: viewModel.platformFilter == plat,
                            accent: BrandColors.platformAccent(plat)
                        ) {
                            viewModel.platformFilter = (viewModel.platformFilter == plat) ? nil : plat
                        }
                    }
                }
            }

            // Media Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        label: strings.filterAll,
                        selected: viewModel.categoryFilter == nil,
                        accent: BrandColors.mediaCyan
                    ) {
                        viewModel.categoryFilter = nil
                    }

                    filterChip(
                        label: strings.filterVideo,
                        selected: viewModel.categoryFilter == .video,
                        accent: BrandColors.mediaIndigo
                    ) {
                        viewModel.categoryFilter = (viewModel.categoryFilter == .video) ? nil : .video
                    }

                    filterChip(
                        label: strings.filterAudio,
                        selected: viewModel.categoryFilter == .audio,
                        accent: BrandColors.mediaCyan
                    ) {
                        viewModel.categoryFilter = (viewModel.categoryFilter == .audio) ? nil : .audio
                    }

                    filterChip(
                        label: strings.filterImage,
                        selected: viewModel.categoryFilter == .image,
                        accent: BrandColors.mediaEmerald
                    ) {
                        viewModel.categoryFilter = (viewModel.categoryFilter == .image) ? nil : .image
                    }
                }
            }
        }
    }

    private func filterChip(
        label: String,
        selected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? .white : palette.onSurfaceVariant)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? accent : palette.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? accent : palette.outline.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(palette.primary.opacity(0.75))

            Text(strings.emptyDownloadsTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.onBackground)

            Text(strings.emptyDownloadsDesc)
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DownloadRecordCard: View {
    let record: DownloadRecord
    let onPlay: () -> Void
    let onOpenAlbum: () -> Void
    let onShare: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onOpenSource: () -> Void
    let onDelete: () -> Void

    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    private var statusBadgeInfo: (text: String, color: Color) {
        switch record.status {
        case .completed: return (strings.statusCompleted, BrandColors.mediaEmerald)
        case .downloading: return (strings.statusDownloading, BrandColors.mediaCyan)
        case .queued: return (strings.statusQueued, BrandColors.mediaAmber)
        case .failed: return (strings.statusFailed, palette.error)
        case .cancelled: return (strings.statusCanceled, palette.onSurfaceVariant)
        }
    }

    private var placeholderIcon: String {
        switch record.mediaCategory {
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .image: return "photo.fill"
        }
    }

    var body: some View {
        let statusInfo = statusBadgeInfo
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if record.status == .completed {
                        onPlay()
                    }
                } label: {
                    ZStack {
                        RemoteMediaImage(
                            urlString: record.thumbnailUrl,
                            localFileURL: record.resolvedFileURL,
                            contentMode: .fill,
                            placeholderSystemIcon: placeholderIcon,
                            referer: record.refererHeader,
                            cookie: record.cookieHeader
                        )
                        .frame(width: 88, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if record.status == .completed {
                            Circle()
                                .fill(.black.opacity(0.55))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: record.mediaCategory == .image ? "magnifyingglass" : "play.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        PlatformSourceBadge(platform: record.platform, compact: true)

                        Text(record.qualityTag)
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(palette.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(palette.primaryContainer)
                            )

                        Spacer(minLength: 0)

                        Text(statusInfo.text)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusInfo.color)
                    }

                    Text(record.title)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(record.authorName)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)

                        let sizeStr = MediaUrlDetector.formatFileSize(
                            record.totalBytes > 0 ? record.totalBytes : record.downloadedBytes
                        )
                        if !sizeStr.isEmpty {
                            Text("• \(sizeStr)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                }
            }

            // Live Progress Bar for Downloading / Queued items
            if record.status == .downloading || record.status == .queued {
                VStack(alignment: .leading, spacing: 5) {
                    if record.totalBytes > 0 {
                        ProgressView(value: record.progressFraction, total: 1.0)
                            .tint(BrandColors.mediaCyan)
                    } else {
                        ProgressView()
                            .tint(BrandColors.mediaCyan)
                    }

                    HStack {
                        let downTxt = MediaUrlDetector.formatFileSize(record.downloadedBytes)
                        let totTxt = MediaUrlDetector.formatFileSize(record.totalBytes)
                        Text(totTxt.isEmpty ? downTxt : "\(downTxt) / \(totTxt)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.onSurfaceVariant)

                        Spacer()

                        let speedTxt = MediaUrlDetector.formatSpeed(record.speedBytesPerSec)
                        if !speedTxt.isEmpty {
                            Text(speedTxt)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(BrandColors.mediaCyan)
                        }
                    }
                }
            }

            if record.status == .failed && !record.errorMessage.isEmpty {
                Text(record.errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.error)
                    .lineLimit(2)
            }

            Divider()
                .overlay(palette.outline.opacity(0.35))

            // Action Buttons Row
            HStack(spacing: 8) {
                if record.status == .completed {
                    cardActionPill(icon: "play.fill", label: strings.actionPlay, primary: true, action: onPlay)
                    cardActionPill(icon: "photo.on.rectangle", label: strings.actionOpenAlbum, primary: false, action: onOpenAlbum)
                        .accessibilityLabel(strings.actionOpenAlbumDesc)
                    cardActionPill(icon: "square.and.arrow.up", label: strings.actionShare, primary: false, action: onShare)
                } else if record.status == .downloading || record.status == .queued {
                    cardActionPill(icon: "xmark.circle.fill", label: strings.actionCancel, primary: false, action: onCancel)
                } else {
                    cardActionPill(icon: "arrow.clockwise", label: strings.actionRetry, primary: true, action: onRetry)
                }

                Spacer(minLength: 0)

                Menu {
                    Button {
                        onOpenSource()
                    } label: {
                        Label(strings.actionOpenSource, systemImage: "safari")
                    }

                    if record.status == .completed {
                        Button {
                            onOpenAlbum()
                        } label: {
                            Label(strings.actionOpenAlbum, systemImage: "folder")
                        }
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(strings.actionDelete, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(4)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.outline.opacity(0.42), lineWidth: 1)
        )
    }

    private func cardActionPill(
        icon: String,
        label: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(primary ? .white : palette.onSurface)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(primary ? AnyShapeStyle(BrandColors.horizontalPrimaryGradient) : AnyShapeStyle(palette.surfaceVariant))
            )
        }
        .buttonStyle(.plain)
    }
}
