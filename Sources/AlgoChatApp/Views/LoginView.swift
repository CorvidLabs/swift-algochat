import Algorand
import AlgoKit
import SwiftUI

enum NetworkSelection: String, CaseIterable, Hashable {
    case testnet
    case mainnet

    var network: AlgorandConfiguration.Network {
        switch self {
        case .testnet: .testnet
        case .mainnet: .mainnet
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: ApplicationState
    @State private var mnemonic = ""
    @State private var selectedNetwork: NetworkSelection = .testnet
    @State private var generatedAddress: String?
    @State private var showCopiedAlert = false

    var body: some View {
        VStack(spacing: 24) {
            // Logo
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("AlgoChat")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Encrypted messaging on Algorand")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            Spacer()

            // Login form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("25-word mnemonic")
                            .font(.headline)

                        Spacer()

                        Button("Generate New") {
                            generateNewAccount()
                        }
                        .font(.subheadline)
                    }

                    TextEditor(text: $mnemonic)
                        .frame(height: 100)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()

                    // Show address if mnemonic is valid
                    if let address = generatedAddress {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Address:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text(address)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Button {
                                    copyToClipboard(address)
                                    showCopiedAlert = true
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Picker("Network", selection: $selectedNetwork) {
                    Text("Testnet").tag(NetworkSelection.testnet)
                    Text("Mainnet").tag(NetworkSelection.mainnet)
                }
                .pickerStyle(.segmented)

                // Fund on testnet button
                if selectedNetwork == .testnet, generatedAddress != nil {
                    Button {
                        openTestnetFaucet()
                    } label: {
                        Label("Fund on Testnet Faucet", systemImage: "dollarsign.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    Task {
                        await appState.connect(mnemonic: mnemonic.trimmingCharacters(in: .whitespacesAndNewlines), network: selectedNetwork.network)
                    }
                } label: {
                    if appState.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(mnemonic.split(separator: " ").count < 25 || appState.isLoading)
            }
            .padding()
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()

            VStack(spacing: 4) {
                Text("Your mnemonic is processed locally and never transmitted.")
                if generatedAddress != nil {
                    Text("Save your mnemonic securely - it cannot be recovered!")
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: 500)
        #if os(macOS)
        .frame(minHeight: 600)
        #endif
        .onChange(of: mnemonic) { _, newValue in
            updateAddressFromMnemonic(newValue)
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Address copied to clipboard")
        }
    }

    private func generateNewAccount() {
        do {
            let account = try Account()
            mnemonic = try account.mnemonic()
            generatedAddress = account.address.description
        } catch {
            // Should never fail for new account generation
        }
    }

    private func updateAddressFromMnemonic(_ mnemonicText: String) {
        let words = mnemonicText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.split(separator: " ").count == 25 else {
            generatedAddress = nil
            return
        }

        do {
            let account = try Account(mnemonic: words)
            generatedAddress = account.address.description
        } catch {
            generatedAddress = nil
        }
    }

    private func openTestnetFaucet() {
        guard let address = generatedAddress,
              let url = URL(string: "https://bank.testnet.algorand.network/?account=\(address)") else {
            return
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
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
    LoginView()
        .environmentObject(ApplicationState())
}
