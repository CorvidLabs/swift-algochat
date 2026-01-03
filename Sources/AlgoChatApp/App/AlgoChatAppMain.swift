import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct AlgoChatAppMain: App {
    @StateObject private var appState = ApplicationState()
    @StateObject private var contactsStore = ContactsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(contactsStore)
                .task {
                    await appState.loadSavedAccounts()
                }
                .onAppear {
                    activateWindow()
                }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }

    private func activateWindow() {
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        #endif
    }
}
