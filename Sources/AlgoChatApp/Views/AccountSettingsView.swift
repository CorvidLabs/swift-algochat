import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// View for managing the current account settings
struct AccountSettingsView: View {
    @EnvironmentObject private var appState: ApplicationState
    @Environment(\.dismiss) private var dismiss

    @State private var accountName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var isSaving = false

    private var savedAccount: SavedAccount? {
        appState.currentSavedAccount
    }

    private var biometricName: String {
        AccountStorage.biometricType.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current Account Section
                Section("Current Account") {
                    if let address = appState.currentAddress {
                        LabeledContent("Address") {
                            Text(address.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .contextMenu {
                            Button {
                                copyToClipboard(address.description)
                            } label: {
                                Label("Copy Address", systemImage: "doc.on.doc")
                            }
                        }
                    }

                    LabeledContent("Network") {
                        Text(networkDisplayName)
                    }

                    if let balance = appState.accountBalance {
                        LabeledContent("Balance") {
                            Text("\(balance.algos, specifier: "%.6f") ALGO")
                        }
                    }
                }

                // Account Name Section
                if appState.isCurrentAccountSaved {
                    Section("Account Name") {
                        TextField("Account nickname", text: $accountName)
                            .textContentType(.name)
                            .autocorrectionDisabled()

                        if accountName != (savedAccount?.name ?? "") {
                            Button("Save Name") {
                                Task {
                                    await appState.renameSavedAccount(
                                        savedAccount!,
                                        to: accountName.isEmpty ? nil : accountName
                                    )
                                }
                            }
                        }
                    }
                }

                // Save Account Section
                if !appState.isCurrentAccountSaved {
                    Section {
                        TextField("Account nickname (optional)", text: $accountName)
                            .textContentType(.name)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                isSaving = true
                                do {
                                    try await appState.saveCurrentAccount(
                                        name: accountName.isEmpty ? nil : accountName
                                    )
                                } catch {
                                    appState.error = AppError(message: error.localizedDescription)
                                }
                                isSaving = false
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Save with \(biometricName)", systemImage: biometricIcon)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isSaving)
                    } header: {
                        Text("Save Account")
                    } footer: {
                        Text("Save this account to quickly unlock it with \(biometricName) next time.")
                    }
                }

                // Danger Zone
                Section {
                    if appState.isCurrentAccountSaved {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Remove Saved Account", systemImage: "trash")
                        }
                    }

                    Button(role: .destructive) {
                        appState.disconnect()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    if appState.isCurrentAccountSaved {
                        Text("Removing the saved account will require you to enter the mnemonic again.")
                    }
                }
            }
            .navigationTitle("Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                accountName = savedAccount?.name ?? ""
            }
            .confirmationDialog(
                "Remove Saved Account?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        if let account = savedAccount {
                            try? await appState.deleteSavedAccount(account)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to enter your mnemonic again to access this account.")
            }
        }
    }

    private var biometricIcon: String {
        switch AccountStorage.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "key"
        }
    }

    private var networkDisplayName: String {
        switch appState.currentNetwork {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .localnet:
            return "Localnet"
        case .custom:
            return "Custom"
        }
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
    AccountSettingsView()
        .environmentObject(ApplicationState())
}
