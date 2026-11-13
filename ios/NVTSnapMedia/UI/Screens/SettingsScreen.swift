import SwiftUI

public struct SettingsScreen: View {
    @ObservedObject public var viewModel: MainViewModel
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    @State private var endpointDraft: String = ""
    @FocusState private var isEndpointFocused: Bool

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let settings = viewModel.preferences.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(strings.settingsTitle)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.onBackground)

                DeveloperShowcaseCard()

                appearanceSection(settings: settings)
                automationSection(settings: settings)
                storageAndApiSection(settings: settings)
                aboutSection
                disclaimerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background.ignoresSafeArea())
        .onAppear {
            endpointDraft = settings.customEndpoint
        }
    }

    // MARK: - Appearance & Language

    private func appearanceSection(settings: UserSettings) -> some View {
        settingsCard(title: strings.sectionAppearance, icon: "paintbrush.pointed.fill", accent: BrandColors.mediaViolet) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.prefThemeTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.onSurface)

                    SegmentedPillSelector(
                        options: [
                            (ThemeMode.dark, strings.themeDarkShort),
                            (ThemeMode.light, strings.themeLightShort),
                            (ThemeMode.system, strings.themeSystemShort)
                        ],
                        selected: settings.themeMode,
                        onSelect: { viewModel.preferences.setThemeMode($0) }
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.prefLanguageTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.onSurface)

                    SegmentedPillSelector(
                        options: [
                            (AppLanguage.vi, "Tiếng Việt"),
                            (AppLanguage.en, "English")
                        ],
                        selected: settings.language,
                        onSelect: { viewModel.preferences.setLanguage($0) }
                    )
                }
            }
        }
    }

    // MARK: - Smart Automation & Preferred Quality

    private func automationSection(settings: UserSettings) -> some View {
        let qualityChoices: [(PreferredQuality, String, String)] = [
            (.ultraHdMax, strings.qualityUltraHdVideo, strings.qualityUltraHdVideoSub),
            (.fhd1080p, strings.qualityFhd1080Video, strings.qualityFhd1080VideoSub),
            (.hdVideo, strings.qualityHdVideo, strings.qualityHdVideoSub),
            (.sdVideo, strings.qualitySdVideo, strings.qualitySdVideoSub),
            (.audioOnly, strings.qualityAudioOnly, strings.qualityAudioOnlySub)
        ]

        return settingsCard(title: strings.sectionAutomation, icon: "bolt.badge.automatic.fill", accent: BrandColors.mediaCyan) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    isOn: Binding(
                        get: { settings.autoCheckClipboard },
                        set: { viewModel.preferences.setAutoCheckClipboard($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strings.prefAutoClipboardTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                        Text(strings.prefAutoClipboardDesc)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                .tint(palette.primary)

                Divider()
                    .overlay(palette.outline.opacity(0.35))

                Toggle(
                    isOn: Binding(
                        get: { settings.autoDownloadOnShare },
                        set: { viewModel.preferences.setAutoDownloadOnShare($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strings.prefAutoShareDownloadTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                        Text(strings.prefAutoShareDownloadDesc)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                .tint(palette.primary)

                Divider()
                    .overlay(palette.outline.opacity(0.35))

                Text(strings.prefDefaultQualityTitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(palette.onSurface)

                VStack(spacing: 8) {
                    ForEach(qualityChoices, id: \.0) { choice in
                        SelectableOptionRow(
                            title: choice.1,
                            subtitle: choice.2,
                            selected: settings.preferredQuality == choice.0
                        ) {
                            viewModel.preferences.setPreferredQuality(choice.0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Storage, Custom Endpoint & Clear History

    private func storageAndApiSection(settings: UserSettings) -> some View {
        settingsCard(title: strings.sectionStorage, icon: "externaldrive.fill.badge.checkmark", accent: BrandColors.mediaEmerald) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(strings.storagePathTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.onSurface)

                    Text(strings.storagePathValue)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(palette.surfaceVariant.opacity(0.6))
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.customApiTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.onSurface)

                    TextField(strings.customApiHint, text: $endpointDraft)
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(palette.onSurface)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .focused($isEndpointFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(palette.surfaceVariant)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.outline.opacity(0.45), lineWidth: 1)
                        )

                    Button {
                        isEndpointFocused = false
                        viewModel.preferences.setCustomEndpoint(endpointDraft)
                        viewModel.showToast("✓ \(strings.save)")
                    } label: {
                        Text(strings.save)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(BrandColors.horizontalPrimaryGradient)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .overlay(palette.outline.opacity(0.35))

                Button {
                    Task {
                        await viewModel.downloadManager.clearFinishedHistoryKeepFiles()
                        viewModel.showToast(strings.historyClearedMsg)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.slash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BrandColors.mediaAmber)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(strings.clearHistoryTitle)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(palette.onSurface)
                            Text(strings.clearHistoryDesc)
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(palette.surfaceVariant.opacity(0.55))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - About & Legal Disclaimer

    private var aboutSection: some View {
        settingsCard(title: strings.sectionAbout, icon: "info.circle.fill", accent: BrandColors.mediaIndigo) {
            Text(strings.aboutDisclaimer)
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclaimerSection: some View {
        settingsCard(title: strings.sectionDisclaimer, icon: "exclamationmark.shield.fill", accent: BrandColors.mediaAmber) {
            DisclaimerClauseList()
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(palette.onSurface)
            }

            content()
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
