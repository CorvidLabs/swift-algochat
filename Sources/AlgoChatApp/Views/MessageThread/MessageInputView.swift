import AlgoChat
import SwiftUI

struct MessageInputView: View {
    @EnvironmentObject private var appState: ApplicationState
    @State private var messageText = ""
    @State private var isSending = false
    @State private var replyingTo: Message?

    var body: some View {
        VStack(spacing: 0) {
            // Reply preview
            if let replyingTo {
                HStack {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(replyingTo.content)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        self.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.inputBackground)
            }

            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit {
                        Task { await sendMessage() }
                    }

                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? .blue : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        let success = await appState.sendMessage(text, replyTo: replyingTo)
        isSending = false

        if success {
            messageText = ""
            replyingTo = nil
        }
    }
}


#Preview {
    MessageInputView()
        .environmentObject(ApplicationState())
}
