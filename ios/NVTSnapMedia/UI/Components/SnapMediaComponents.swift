import SwiftUI
import UIKit

/// Crisp vector brand icon matching the NVTSnapMedia launcher emblem.
public struct BrandAppLogoIcon: View {
    public var size: CGFloat = 44

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(BrandColors.primaryGradient)
                .shadow(color: BrandColors.mediaIndigo.opacity(0.35), radius: 8, x: 0, y: 4)

            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

            ZStack {
                Image(systemName: "arrow.down.to.line.circle.fill")
                    .font(.system(size: size * 0.54, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Platform badge pill (`YouTube` / `Facebook` / `TikTok`) with signature brand accent colors.
public struct PlatformSourceBadge: View {
    public let platform: MediaPlatform
    public var compact: Bool = false

    public init(platform: MediaPlatform, compact: Bool = false) {
        self.platform = platform
        self.compact = compact
    }

    private var iconName: String {
        switch platform {
        case .youtube: return "play.rectangle.fill"
        case .facebook: return "f.cursive.circle.fill"
        case .tiktok: return "music.note"
        }
    }

    public var body: some View {
        let accent = BrandColors.platformAccent(platform)
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 10 : 11, weight: .bold))
            Text(platform.displayName)
                .font(.system(size: compact ? 11 : 12, weight: .bold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule(style: .continuous)
                .fill(accent.opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(accent.opacity(0.38), lineWidth: 1)
        )
    }
}

/// Reusable animated segmented pill selector (used for How-To methods, Theme Mode, Language).
public struct SegmentedPillSelector<T: Hashable>: View {
    public let options: [(value: T, label: String)]
    public let selected: T
    public let onSelect: (T) -> Void

    @Environment(\.appPalette) private var palette

    public init(
        options: [(value: T, label: String)],
        selected: T,
        onSelect: @escaping (T) -> Void
    ) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                let isSelected = item.value == selected
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        onSelect(item.value)
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? .white : palette.onSurfaceVariant)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 8)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(BrandColors.horizontalPrimaryGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(palette.surfaceVariant)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(palette.outline.opacity(0.45), lineWidth: 1)
        )
    }
}

/// Radio-style selectable option row for Preferred Auto-Download Quality.
public struct SelectableOptionRow: View {
    public let title: String
    public let subtitle: String
    public let selected: Bool
    public let action: () -> Void

    @Environment(\.appPalette) private var palette

    public init(
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? palette.primary : palette.onSurfaceVariant.opacity(0.6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? palette.primaryContainer.opacity(0.65) : palette.surfaceVariant.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? palette.primary.opacity(0.75) : palette.outline.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Featured Developer Attribution Showcase Card (`Việt Thắng`).
public struct DeveloperShowcaseCard: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 54, height: 54)
                    Text("VT")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.developerRoleLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 6) {
                        Text(strings.developerName)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: 0x38BDF8))
                    }

                    Text(strings.appVersionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(["YouTube 4K", "Facebook Reels", "TikTok No-Logo"], id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.16))
                        )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandColors.primaryGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: BrandColors.mediaIndigo.opacity(0.28), radius: 12, x: 0, y: 6)
    }
}

/// Compact Developer Credit Footer Pill on HomeScreen.
public struct DeveloperFooterPill: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.primary)
            Text("\(strings.appName) • \(strings.developerCreditShort)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.onSurfaceVariant)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(BrandColors.mediaCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(palette.outline.opacity(0.45), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

/// Full 4-clause Legal Disclaimer list.
public struct DisclaimerClauseList: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    public init() {}

    private var clauses: [(title: String, body: String, icon: String)] {
        [
            (strings.disclaimerItem1Title, strings.disclaimerItem1Body, "shield.lefthalf.filled"),
            (strings.disclaimerItem2Title, strings.disclaimerItem2Body, "c.circle.fill"),
            (strings.disclaimerItem3Title, strings.disclaimerItem3Body, "person.badge.shield.checkmark.fill"),
            (strings.disclaimerItem4Title, strings.disclaimerItem4Body, "lock.iphone")
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(clauses.enumerated()), id: \.offset) { _, clause in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: clause.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandColors.mediaAmber)
                        Text(clause.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(palette.onSurface)
                    }
                    Text(clause.body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.surfaceVariant.opacity(0.6))
                )
            }
        }
    }
}

/// Summary Legal Disclaimer Card with modal detail sheet trigger.
public struct DisclaimerSummaryCard: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings
    @State private var showFullSheet = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrandColors.mediaAmber)
                Text(strings.sectionDisclaimer)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button {
                    showFullSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(strings.disclaimerViewDetails)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.primary)
                }
                .buttonStyle(.plain)
            }

            Text(strings.disclaimerShortNotice)
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BrandColors.mediaAmber.opacity(0.32), lineWidth: 1)
        )
        .sheet(isPresented: $showFullSheet) {
            DisclaimerDetailSheet()
                .environment(\.appPalette, palette)
                .environment(\.appStrings, strings)
        }
    }
}

public struct DisclaimerDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette
    @Environment(\.appStrings) private var strings

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(strings.disclaimerShortNotice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)

                    DisclaimerClauseList()
                }
                .padding(18)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(strings.sectionDisclaimer)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.disclaimerUnderstood) {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }
}

/// Identifiable payload for presenting iOS native `UIActivityViewController`.
public struct ShareSheetPayload: Identifiable {
    public let id = UUID()
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }
}

public struct ActivityShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
