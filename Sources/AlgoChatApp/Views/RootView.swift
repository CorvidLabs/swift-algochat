import AlgoChat
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: ApplicationState

    var body: some View {
        Group {
            if appState.isConnected {
                MainView()
            } else if !appState.savedAccounts.isEmpty {
                AccountPickerView()
            } else {
                LoginView()
            }
        }
        .alert(item: $appState.error) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.message),
                dismissButton: .default(Text("OK")) {
                    appState.clearError()
                }
            )
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: ApplicationState

    var body: some View {
        #if os(iOS)
        NavigationStack {
            ConversationListView()
                .navigationDestination(item: $appState.selectedConversation) { _ in
                    MessageThreadView()
                }
        }
        #else
        NavigationSplitView {
            ConversationListView()
                .frame(minWidth: 250)
        } detail: {
            if appState.selectedConversation != nil {
                MessageThreadView()
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation or start a new one")
                )
            }
        }
        #endif
    }
}

extension Conversation: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}
