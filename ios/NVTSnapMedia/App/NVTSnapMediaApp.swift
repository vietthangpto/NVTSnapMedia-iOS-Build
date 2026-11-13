import SwiftUI

@main
struct NVTSnapMediaApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: container.mainViewModel)
        }
    }
}
