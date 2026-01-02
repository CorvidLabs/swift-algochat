import AlgoChat
import SwiftUI

struct MessageThreadView: View {
    @EnvironmentObject private var appState: ApplicationState
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let conversation = appState.selectedConversation {
                            ForEach(conversation.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.selectedConversation?.messages.count) { _, _ in
                    if let lastId = appState.selectedConversation?.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            MessageInputView()
        }
        .navigationTitle(conversationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        isRefreshing = true
                        await appState.refreshSelectedConversation()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var conversationTitle: String {
        guard let conversation = appState.selectedConversation else { return "Messages" }
        let addr = conversation.participant.description
        if addr.count > 12 {
            return "\(addr.prefix(6))...\(addr.suffix(4))"
        }
        return addr
    }
}

struct MessageBubble: View {
    let message: Message
    @EnvironmentObject private var appState: ApplicationState
    @State private var showReplyOption = false

    private var isSent: Bool {
        message.direction == .sent
    }

    var body: some View {
        HStack {
            if isSent { Spacer(minLength: 60) }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 4) {
                // Reply preview if this is a reply
                if let replyContext = message.replyContext {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 2)

                        Text(replyContext.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 2)
                }

                // Message content
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSent ? Color.blue : Color.chatBubbleBackground)
                    .foregroundStyle(isSent ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                Button {
                    copyToClipboard(message.content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if !isSent {
                    Button {
                        showReplyOption = true
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                }
            }

            if !isSent { Spacer(minLength: 60) }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}


#Preview {
    NavigationStack {
        MessageThreadView()
            .environmentObject(ApplicationState())
    }
}
