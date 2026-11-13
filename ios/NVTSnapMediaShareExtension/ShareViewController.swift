import SwiftUI
import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
public final class ShareViewController: UIViewController {

    private static let appGroupId = "group.com.nvtsnapmedia.app"
    private static let pendingSharedKey = "nvtsnapmedia_pending_shared_text"

    private let viewModel = ShareSheetViewModel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(
            rootView: ShareExtensionCardView(
                viewModel: viewModel,
                onOpenApp: { [weak self] in self?.launchHostAppAndComplete() },
                onCancel: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            )
        )
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        Task { @MainActor in
            let extracted = await self.extractSharedText()
            self.viewModel.sharedText = extracted
            self.viewModel.isLoading = false
            if !extracted.isEmpty {
                self.persistToAppGroup(extracted)
                // Auto-handoff into NVTSnapMedia main app
                try? await Task.sleep(nanoseconds: 180_000_000)
                self.launchHostAppAndComplete()
            }
        }
    }

    private func persistToAppGroup(_ text: String) {
        if let groupDefaults = UserDefaults(suiteName: Self.appGroupId) {
            groupDefaults.set(text, forKey: Self.pendingSharedKey)
            groupDefaults.synchronize()
        }
    }

    @MainActor
    private func launchHostAppAndComplete() {
        let raw = viewModel.sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        persistToAppGroup(raw)

        var comps = URLComponents()
        comps.scheme = "nvtsnapmedia"
        comps.host = "share"
        comps.queryItems = [URLQueryItem(name: "text", value: raw)]

        guard let deepLink = comps.url else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        let openedViaResponder = openURLViaResponderChain(deepLink)
        if openedViaResponder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        } else {
            extensionContext?.open(deepLink) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    /// Extension-safe responder chain launcher (`APPLICATION_EXTENSION_API_ONLY = YES` compliant).
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func extractSharedText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return ""
        }

        var collectedPieces: [String] = []
        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        for item in items {
            if let attrContent = item.attributedContentText?.string, !attrContent.isEmpty {
                collectedPieces.append(attrContent)
            }
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(urlType) {
                    if let urlStr = await loadProviderString(provider: provider, typeIdentifier: urlType) {
                        collectedPieces.append(urlStr)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(textType) {
                    if let txt = await loadProviderString(provider: provider, typeIdentifier: textType) {
                        collectedPieces.append(txt)
                    }
                }
            }
        }

        return collectedPieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func loadProviderString(provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let str = item as? String {
                    continuation.resume(returning: str)
                } else if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: str)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private final class ShareSheetViewModel: ObservableObject {
    @Published var sharedText: String = ""
    @Published var isLoading: Bool = true
}

private struct ShareExtensionCardView: View {
    @ObservedObject var viewModel: ShareSheetViewModel
    let onOpenApp: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.31, green: 0.27, blue: 0.90),
                                        Color(red: 0.49, green: 0.23, blue: 0.93),
                                        Color(red: 0.02, green: 0.71, blue: 0.83)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)

                        Image(systemName: "arrow.down.to.line.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NVTSnapMedia")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("YouTube • Facebook • TikTok 4K • Việt Thắng")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.72))
                    }

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(white: 0.6))
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Đang nhận liên kết chia sẻ...")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 8)
                } else if viewModel.sharedText.isEmpty {
                    Text("Không tìm thấy đường dẫn hợp lệ trong nội dung được chia sẻ.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(red: 0.96, green: 0.38, blue: 0.38))
                } else {
                    Text(viewModel.sharedText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.11, green: 0.13, blue: 0.21))
                        )

                    Button(action: onOpenApp) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Mở NVTSnapMedia & Tải 4K")
                                .font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.31, green: 0.27, blue: 0.90),
                                            Color(red: 0.49, green: 0.23, blue: 0.93),
                                            Color(red: 0.02, green: 0.71, blue: 0.83)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.09, blue: 0.15))
            )
            .padding(12)
        }
    }
}
