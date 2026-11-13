import SwiftUI
import UIKit

public struct RootTabView: View {
    @ObservedObject public var viewModel: MainViewModel
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    private var resolvedColorScheme: ColorScheme? {
        switch viewModel.preferences.settings.themeMode {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    private var effectiveIsDark: Bool {
        switch viewModel.preferences.settings.themeMode {
        case .dark: return true
        case .light: return false
        case .system: return systemColorScheme == .dark
        }
    }

    private var palette: AppPalette {
        effectiveIsDark ? .dark : .light
    }

    private var strings: AppStrings {
        viewModel.currentStrings
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $viewModel.selectedTab) {
                HomeScreen(viewModel: viewModel)
                    .tabItem {
                        Label(strings.navHome, systemImage: "arrow.down.circle.fill")
                    }
                    .tag(AppTab.home)

                DownloadsScreen(viewModel: viewModel)
                    .tabItem {
                        Label(strings.navDownloads, systemImage: "folder.fill.badge.person.crop")
                    }
                    .badge(viewModel.activeDownloadsCount)
                    .tag(AppTab.downloads)

                SettingsScreen(viewModel: viewModel)
                    .tabItem {
                        Label(strings.navSettings, systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }
            .tint(palette.primary)

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0x1E2246).opacity(0.96))
                            .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 4)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(BrandColors.mediaIndigo.opacity(0.55), lineWidth: 1)
                    )
                    .padding(.bottom, 64)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .environment(\.appPalette, palette)
        .environment(\.appStrings, strings)
        .preferredColorScheme(resolvedColorScheme)
        .onAppear {
            viewModel.checkClipboardOnForeground()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.checkClipboardOnForeground()
            }
        }
        .onOpenURL { incomingURL in
            viewModel.handleIncomingURL(incomingURL)
        }
        .fullScreenCover(item: $viewModel.viewerTarget) { target in
            MediaViewerView(
                target: target,
                onOpenAlbum: { rec in viewModel.openRecordInSystemAlbum(rec) },
                onShare: { rec in
                    viewModel.viewerTarget = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.shareDownloadedRecord(rec)
                    }
                }
            )
            .environment(\.appPalette, palette)
            .environment(\.appStrings, strings)
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            ActivityShareSheet(items: payload.items)
                .ignoresSafeArea()
        }
    }
}
