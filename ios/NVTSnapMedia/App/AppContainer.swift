import Foundation
import UserNotifications

public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    public var onOpenDownloadsTab: (@MainActor () -> Void)?

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if (userInfo["open_tab"] as? String) == "downloads" {
            let callback = onOpenDownloadsTab
            Task { @MainActor in
                callback?()
            }
        }
        completionHandler()
    }
}

@MainActor
public final class AppContainer: ObservableObject {
    public let preferences: AppPreferences
    public let database: DownloadDatabase
    public let downloadManager: MediaDownloadManager
    public let mainViewModel: MainViewModel
    private let notificationRouter: NotificationRouter

    public init() {
        let prefs = AppPreferences()
        let db = DownloadDatabase()
        let dlManager = MediaDownloadManager(database: db, preferences: prefs)
        let vm = MainViewModel(
            preferences: prefs,
            database: db,
            downloadManager: dlManager,
            extractor: UnifiedMediaExtractor()
        )

        self.preferences = prefs
        self.database = db
        self.downloadManager = dlManager
        self.mainViewModel = vm

        let router = NotificationRouter()
        router.onOpenDownloadsTab = { [weak vm] in
            vm?.selectedTab = .downloads
        }
        self.notificationRouter = router
        UNUserNotificationCenter.current().delegate = router
    }
}
