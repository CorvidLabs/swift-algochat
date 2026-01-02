import SwiftUI

@main
struct AlgoChatAppMain: App {
    @StateObject private var appState = ApplicationState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
        #endif
    }
}
