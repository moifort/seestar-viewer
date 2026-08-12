import SwiftUI

/// Réglages minimaux : l'adresse du télescope, quand la découverte mDNS
/// n'aboutit pas. Accessible par appui long sur l'image.
struct SettingsView: View {
    @Bindable var session: SeestarSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.42", text: $session.manualHost)
                        #if !os(tvOS) && !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Seestar address")
                } footer: {
                    Text("Leave empty to discover the telescope automatically via "
                         + "seestar.local. Enter an IP address if it is not found.")
                }

                if let host = session.resolvedHost {
                    Section("Current connection") {
                        LabeledContent("Host", value: host)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        session.restart()
                        dismiss()
                    }
                }
            }
        }
    }
}
