import SeestarKit
import SwiftUI

/// Incrustation discrète : ce qu'il faut savoir sans quitter la contemplation.
///
/// Elle s'efface quand une image est à l'écran, pour ne pas encombrer, et
/// reste visible tant qu'il n'y a rien à regarder.
struct TelemetryOverlay: View {
    let status: ViewerStatus
    let telemetry: Telemetry
    let hasImage: Bool

    @State private var visible = true

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 20) {
                Label(statusText, systemImage: statusSymbol)
                if let target = telemetry.target {
                    Label(target, systemImage: "scope")
                }
                if let battery = telemetry.batteryCapacity {
                    Label("\(battery) %", systemImage: batterySymbol(battery))
                }
                if let temperature = telemetry.temperature {
                    Label(String(format: "%.0f °C", temperature), systemImage: "thermometer.medium")
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
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 1.2), value: visible)
        .onChange(of: hasImage) { _, nowHasImage in
            guard nowHasImage else { visible = true; return }
            // Une image vient d'arriver : on montre l'incrustation quelques
            // secondes, puis on laisse la place à l'image.
            visible = true
            Task {
                try? await Task.sleep(for: .seconds(6))
                visible = false
            }
        }
    }

    private var statusText: String {
        switch status {
        case .searching: return "Recherche"
        case .waitingForExposure: return "En attente"
        case .live: return "Live"
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
