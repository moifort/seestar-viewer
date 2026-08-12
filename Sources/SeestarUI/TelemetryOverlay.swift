import SeestarKit
import SwiftUI

/// Incrustation discrète : ce qu'il faut savoir sans quitter la contemplation.
///
/// Sa visibilité est pilotée par l'écran parent, au doigt de l'utilisateur,
/// plutôt que par une minuterie : sur un écran contemplatif, une information
/// qui disparaît toute seule oblige à faire un geste pour la retrouver.
struct TelemetryOverlay: View {
    let status: ViewerStatus
    let telemetry: Telemetry
    let isVisible: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 22) {
                item(statusSymbol, statusText)
                if let target = telemetry.target {
                    item("scope", target)
                }
                if let battery = telemetry.batteryCapacity {
                    // Unité collée au nombre : c'est une seule valeur, pas deux mots.
                    item(batterySymbol(battery), "\(battery)%")
                }
                if let temperature = telemetry.temperature {
                    item("thermometer.medium", String(format: "%.0f°C", temperature))
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 40)
            .antiBurnInDrift()
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: isVisible)
    }

    /// Icône et texte serrés l'un contre l'autre : ils forment une seule
    /// information, l'espacement par défaut de `Label` les dissocie trop.
    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
    }

    private var statusText: String {
        switch status {
        case .searching: return "Recherche"
        case .waitingForExposure: return "En attente"
        case .live: return "Live"
        case .streaming: return "Direct"
        case .stacking: return "Empilement"
        case .tooManyConnections: return "Occupé"
        case .disconnected: return "Déconnecté"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .searching: return "antenna.radiowaves.left.and.right"
        case .waitingForExposure: return "hourglass"
        case .live: return "dot.radiowaves.left.and.right"
        case .streaming: return "play.tv"
        case .stacking: return "square.stack.3d.up"
        case .tooManyConnections: return "person.2.slash"
        case .disconnected: return "exclamationmark.triangle"
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<15: return "battery.25"
        case ..<60: return "battery.50"
        default: return "battery.100"
        }
    }
}
