import SwiftUI

public struct HomeScreen: View {
    @ObservedObject public var viewModel: MainViewModel
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    @FocusState private var isUrlFieldFocused: Bool
    @State private var howToTab: Int = 0
    @State private var expandedFaqIndex: Int? = 0

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection

                if let candidate = viewModel.clipboardCandidate {
                    clipboardBanner(candidate)
                }

                heroInputCard

                if !viewModel.activeDownloads.isEmpty {
                    activeQueueStrip
                }

                if viewModel.isExtracting {
                    analyzingStateCard
                } else if let err = viewModel.extractionError {
                    extractionErrorCard(err)
                } else if let media = viewModel.extractedMedia {
                    extractedResultCard(media)
                }

                howToGuideCard
                featuresGridSection
                faqAccordionCard
                DisclaimerSummaryCard()
                DeveloperFooterPill()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background.ignoresSafeArea())
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandAppLogoIcon(size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(strings.appName)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.onBackground)

                        Text("iOS")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(BrandColors.horizontalPrimaryGradient)
                            )
                    }

                    Text(strings.appTagline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    featurePill(icon: "sparkles", text: strings.badgeAllInOne, accent: BrandColors.mediaIndigo)
                    featurePill(icon: "4k.tv.fill", text: strings.badgeUltraHd, accent: BrandColors.mediaViolet)
                    featurePill(icon: "checkmark.shield.fill", text: strings.badgeNoLogo, accent: BrandColors.mediaEmerald)
                    featurePill(icon: "waveform", text: strings.badgeAudioPhoto, accent: BrandColors.mediaCyan)
                }
            }
        }
    }

    private func featurePill(icon: String, text: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.onSurface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(palette.outline.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Smart Clipboard Banner

    private func clipboardBanner(_ candidate: DetectedMediaSource) -> some View {
        let accent = BrandColors.platformAccent(candidate.platform)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(strings.clipboardDetectedTitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                PlatformSourceBadge(platform: candidate.platform, compact: true)
            }

            Text(candidate.cleanUrl)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    isUrlFieldFocused = false
                    viewModel.useDetectedClipboardCandidate()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(strings.clipboardUseAction)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BrandColors.horizontalPrimaryGradient)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.dismissClipboardCandidate()
                } label: {
                    Text(strings.dismiss)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1.2)
        )
    }

    // MARK: - Hero Input Card

    private var heroInputCard: some View {
        let detected = viewModel.liveDetectedSource
        let borderAccent: Color = detected.map { BrandColors.platformAccent($0.platform) } ?? palette.outline

        return VStack(alignment: .leading, spacing: 14) {
            Text(strings.heroCardTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.onSurface)

            // Live Auto-Detect Indicator
            if let detected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BrandColors.platformAccent(detected.platform))
                    Text(strings.autoDetectedPrefix)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                    PlatformSourceBadge(platform: detected.platform, compact: true)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    Text(strings.autoDetectIdleHint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }

            // URL TextField
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(detected.map { BrandColors.platformAccent($0.platform) } ?? palette.primary)

                TextField(strings.inputPlaceholder, text: $viewModel.urlInput)
                    .font(.system(size: 14.5))
                    .foregroundStyle(palette.onSurface)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isUrlFieldFocused)
                    .onSubmit {
                        viewModel.analyzeCurrentInput()
                    }

                if !viewModel.urlInput.isEmpty {
                    Button {
                        viewModel.clearInputAndResult()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.onSurfaceVariant.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.clearInput)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.surfaceVariant)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderAccent.opacity(detected != nil ? 0.65 : 0.4), lineWidth: 1.2)
            )

            // Paste & Download CTA Row
            HStack(spacing: 10) {
                Button {
                    isUrlFieldFocused = false
                    viewModel.pasteFromClipboardAndAnalyze()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .bold))
                        Text(strings.pasteLink)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(palette.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(palette.surfaceVariant)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.outline.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isUrlFieldFocused = false
                    viewModel.analyzeCurrentInput()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isExtracting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(strings.downloadNow)
                            .font(.system(size: 14.5, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BrandColors.horizontalPrimaryGradient)
                    )
                    .shadow(color: BrandColors.mediaIndigo.opacity(0.32), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExtracting)
            }

            // Quick-open social platform shortcuts
            HStack(spacing: 8) {
                Text(strings.quickOpenLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                ForEach(MediaPlatform.allCases) { plat in
                    Button {
                        viewModel.openSocialPlatform(plat)
                    } label: {
                        PlatformSourceBadge(platform: plat, compact: true)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderAccent.opacity(detected != nil ? 0.5 : 0.4), lineWidth: 1)
        )
    }

    // MARK: - Active Queue Strip

    private var activeQueueStrip: some View {
        let active = viewModel.activeDownloads
        let lead = active.first
        let avgProgress: Double = {
            guard !active.isEmpty else { return 0 }
            let sum = active.reduce(0.0) { $0 + $1.progressFraction }
            return sum / Double(active.count)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(BrandColors.mediaCyan)
                Text("\(strings.activeQueueTitle) (\(active.count))")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button {
                    viewModel.selectedTab = .downloads
                } label: {
                    HStack(spacing: 4) {
                        Text(strings.viewQueue)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.primary)
                }
                .buttonStyle(.plain)
            }

            if let lead {
                HStack {
                    Text(lead.title)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                    Spacer()
                    let speedTxt = MediaUrlDetector.formatSpeed(lead.speedBytesPerSec)
                    if !speedTxt.isEmpty {
                        Text(speedTxt)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(BrandColors.mediaCyan)
                    }
                }
            }

            ProgressView(value: max(0.04, avgProgress), total: 1.0)
                .tint(BrandColors.mediaCyan)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BrandColors.mediaCyan.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Analyzing & Error Cards

    private var analyzingStateCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(palette.primary)
                .padding(.top, 4)

            Text(strings.analyzingLink)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .multilineTextAlignment(.center)

            Text(strings.analyzingSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.primary.opacity(0.35), lineWidth: 1)
        )
    }

    private func extractionErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.error)
                Text(message)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                viewModel.analyzeCurrentInput()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(strings.actionRetry)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.error)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.error.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Extracted Media Result Card

    private func extractedResultCard(_ media: UnifiedMediaInfo) -> some View {
        let isVi = viewModel.isVietnamese
        let durationText = MediaUrlDetector.formatDuration(media.durationSeconds)

        return VStack(alignment: .leading, spacing: 16) {
            // Cover Thumbnail Header
            ZStack(alignment: .bottomLeading) {
                RemoteMediaImage(
                    urlString: media.coverUrl,
                    contentMode: .fill,
                    placeholderSystemIcon: media.isImageGallery ? "photo.on.rectangle.angled" : "play.rectangle.fill"
                )
                .frame(height: media.isVerticalShort ? 250 : 196)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top-left & top-right badges
                VStack {
                    HStack {
                        PlatformSourceBadge(platform: media.platform)
                        Spacer()
                        if !media.maxResolutionBadge.isEmpty {
                            Text(media.maxResolutionBadge)
                                .font(.system(size: 11.5, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(BrandColors.ultraHdGradient)
                                )
                        }
                    }
                    Spacer()
                }
                .padding(12)

                // Bottom-left duration & bottom-right preview CTA
                HStack {
                    if !durationText.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text(durationText)
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.black.opacity(0.65))
                        )
                    }

                    Spacer()

                    Button {
                        viewModel.openExtractedPreview(media)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: media.isImageGallery ? "photo.stack.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(strings.previewMedia)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BrandColors.horizontalPrimaryGradient)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Metadata Block
            VStack(alignment: .leading, spacing: 8) {
                Text(media.title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Label(media.authorName, systemImage: "person.crop.circle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)

                    if !media.viewCountText.isEmpty {
                        Label(media.viewCountText, systemImage: "eye.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }

                    if !media.likeCountText.isEmpty {
                        Label(media.likeCountText, systemImage: "heart.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.copyCaptionToClipboard(media.title)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text(strings.copyCaption)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.primary)
                    }
                    .buttonStyle(.plain)
                }

                if !media.musicTitle.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BrandColors.mediaCyan)
                        Text(media.musicTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
            }

            // Photo Carousel Strip & 1-Tap Batch Download
            if media.isImageGallery && !media.galleryImages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(media.galleryImages.enumerated()), id: \.offset) { idx, imgUrl in
                                Button {
                                    viewModel.openExtractedPreview(media, initialGalleryIndex: idx)
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        RemoteMediaImage(
                                            urlString: imgUrl,
                                            contentMode: .fill,
                                            placeholderSystemIcon: "photo"
                                        )
                                        .frame(width: 96, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        Text("#\(idx + 1)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.black.opacity(0.65)))
                                            .padding(6)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        viewModel.downloadAllGalleryPhotos(media: media)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("\(strings.downloadAllPhotos) (\(media.galleryImages.count) \(strings.photosCountSuffix))")
                                .font(.system(size: 14, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(BrandColors.ultraHdGradient)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(palette.outline.opacity(0.35))

            // Quality Options List
            VStack(spacing: 10) {
                ForEach(media.downloadOptions) { opt in
                    qualityOptionButton(media: media, option: opt, isVi: isVi)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(BrandColors.platformAccent(media.platform).opacity(0.42), lineWidth: 1.1)
        )
    }

    private func qualityOptionButton(
        media: UnifiedMediaInfo,
        option: DownloadQualityOption,
        isVi: Bool
    ) -> some View {
        let mainLabel = isVi ? option.labelVi : option.labelEn
        let subLabel = isVi ? option.subtitleVi : option.subtitleEn
        let sizeLabel = MediaUrlDetector.formatFileSize(option.sizeBytes)

        let iconName: String = {
            switch option.mediaCategory {
            case .video: return option.isUltraHd ? "sparkles.tv.fill" : "video.fill"
            case .audio: return "waveform"
            case .image: return "photo.fill"
            }
        }()

        return Button {
            viewModel.startSingleDownload(media: media, option: option)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            option.isUltraHd
                                ? AnyShapeStyle(BrandColors.ultraHdGradient)
                                : AnyShapeStyle(option.mediaCategory == .audio ? BrandColors.mediaCyan.opacity(0.18) : palette.primaryContainer)
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            option.isUltraHd
                                ? .white
                                : (option.mediaCategory == .audio ? BrandColors.mediaCyan : palette.primary)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mainLabel)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)

                        Text(option.badge)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(option.isUltraHd ? .white : palette.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        option.isUltraHd
                                            ? AnyShapeStyle(BrandColors.ultraHdGradient)
                                            : AnyShapeStyle(palette.primaryContainer)
                                    )
                            )
                    }

                    HStack(spacing: 6) {
                        if !subLabel.isEmpty {
                            Text(subLabel)
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineLimit(1)
                        }
                        if !sizeLabel.isEmpty {
                            Text("• \(sizeLabel)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(option.isPrimary || option.isUltraHd ? palette.primary : palette.onSurfaceVariant)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(option.isPrimary ? palette.primaryContainer.opacity(0.35) : palette.surfaceVariant.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        option.isPrimary
                            ? palette.primary.opacity(0.65)
                            : palette.outline.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - How-To Guide Card

    private var howToGuideCard: some View {
        let steps: [(String, String)] = howToTab == 0
            ? [
                (strings.shareStep1Title, strings.shareStep1Desc),
                (strings.shareStep2Title, strings.shareStep2Desc),
                (strings.shareStep3Title, strings.shareStep3Desc)
            ]
            : [
                (strings.copyStep1Title, strings.copyStep1Desc),
                (strings.copyStep2Title, strings.copyStep2Desc),
                (strings.copyStep3Title, strings.copyStep3Desc)
            ]

        return VStack(alignment: .leading, spacing: 14) {
            Text(strings.howToTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.onSurface)

            SegmentedPillSelector(
                options: [
                    (0, strings.tabShareMethod),
                    (1, strings.tabCopyMethod)
                ],
                selected: howToTab,
                onSelect: { howToTab = $0 }
            )

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(BrandColors.primaryGradient)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.0)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(palette.onSurface)
                            Text(step.1)
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.outline.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - 2x2 Feature Grid

    private var featuresGridSection: some View {
        let items: [(icon: String, title: String, desc: String, color: Color)] = [
            ("wand.and.stars", strings.featAutoTitle, strings.featAutoDesc, BrandColors.mediaIndigo),
            ("4k.tv.fill", strings.featUltraTitle, strings.featUltraDesc, BrandColors.mediaViolet),
            ("bolt.horizontal.circle.fill", strings.featMuxTitle, strings.featMuxDesc, BrandColors.mediaCyan),
            ("photo.stack.fill", strings.featGalleryTitle, strings.featGalleryDesc, BrandColors.mediaEmerald)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text(strings.featuresTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.onBackground)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(item.color)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(item.color.opacity(0.15))
                            )

                        Text(item.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(palette.onSurface)

                        Text(item.desc)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(palette.outline.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - FAQ Accordion

    private var faqAccordionCard: some View {
        let faqs: [(q: String, a: String)] = [
            (strings.faq1Q, strings.faq1A),
            (strings.faq2Q, strings.faq2A),
            (strings.faq3Q, strings.faq3A),
            (strings.faq4Q, strings.faq4A)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text(strings.faqTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.onSurface)

            ForEach(Array(faqs.enumerated()), id: \.offset) { idx, faq in
                let isOpen = expandedFaqIndex == idx
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedFaqIndex = isOpen ? nil : idx
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(faq.q)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(palette.onSurface)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.primary)
                                .padding(.top, 3)
                        }
                    }
                    .buttonStyle(.plain)

                    if isOpen {
                        Text(faq.a)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.surfaceVariant.opacity(0.55))
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.outline.opacity(0.4), lineWidth: 1)
        )
    }
}
