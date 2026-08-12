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
                    Text("Adresse du Seestar")
                } footer: {
                    Text("Laisse vide pour la découverte automatique via "
                         + "seestar.local. Renseigne une adresse IP si le "
                         + "télescope n'est pas trouvé.")
                }

                if let host = session.resolvedHost {
                    Section("Connexion en cours") {
                        LabeledContent("Hôte", value: host)
                    }
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        session.restart()
                        dismiss()
                    }
                }
            }
        }
    }
}
