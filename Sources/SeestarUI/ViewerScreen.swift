import SeestarKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Écran principal : l'image du télescope en plein écran, et rien d'autre.
///
/// Trois règles héritées de la spec, qui expliquent la plupart des choix ici :
/// jamais d'écran noir, jamais de mise en veille, jamais d'image parfaitement
/// immobile (rémanence des dalles OLED).
public struct ViewerScreen<RTSPPlayer: View>: View {
    @State private var session = SeestarSession()
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private let rtspPlayer: (URL) -> RTSPPlayer

    /// Le lecteur du flux vidéo est injecté par l'application : il repose sur
    /// VLCKit, que ce module ne veut pas connaître pour rester testable sans
    /// dépendance ni matériel.
    public init(@ViewBuilder rtspPlayer: @escaping (URL) -> RTSPPlayer) {
        self.rtspPlayer = rtspPlayer
    }

    public var body: some View {
        ZStack {
            Color.black

            if let frame = session.model.displayedFrame {
                Image(decorative: frame.image, scale: 1, orientation: Self.orientation)
                    .resizable()
                    .scaledToFit()
                    .antiBurnInDrift()
                    .transition(.opacity)
            } else if let stream = session.rtspStreamURL {
                // Modes Paysage et Système solaire : l'image ne passe que par là.
                rtspPlayer(stream)
                    .antiBurnInDrift()
                    .transition(.opacity)
            } else {
                WaitingView(status: session.model.status, host: session.resolvedHost)
            }

            TelemetryOverlay(
                status: session.model.status,
                telemetry: session.model.telemetry,
                hasImage: session.model.displayedFrame != nil || session.rtspStreamURL != nil
            )
        }
        // Sur la pile entière, et non sur l'image seule : sinon la zone de
        // sécurité tvOS rogne l'écran et l'image 16/9 ne remplit plus la dalle.
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: session.model.displayedFrame?.width)
        .onAppear {
            setIdleTimerDisabled(true)
            session.start()
        }
        .onDisappear { setIdleTimerDisabled(false) }
        .onChange(of: scenePhase) { _, phase in
            // Sur iOS le système suspend les sockets en arrière-plan : on coupe
            // et on rouvre nous-mêmes. Sur tvOS ce cas ne se présente pas.
            switch phase {
            case .active: session.start()
            case .background: Task { await session.stop() }
            default: break
            }
        }
        #if !os(tvOS)
        .onLongPressGesture { showsSettings = true }
        .sheet(isPresented: $showsSettings) {
            SettingsView(session: session)
        }
        #endif
    }

    /// Dans le ciel il n'y a pas de haut : on tourne librement l'image portrait
    /// du capteur pour épouser l'écran.
    private static var orientation: Image.Orientation {
        #if os(tvOS)
        // 1080x1920 devient 1920x1080, soit exactement du 16/9.
        return .right
        #else
        // Sur iPhone et iPad, le portrait natif tombe déjà dans le bon sens.
        return .up
        #endif
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// Écran d'attente. Le message `only available for continuous exposure` n'est
/// pas une erreur : le télescope est joignable, il n'expose simplement pas.
struct WaitingView: View {
    let status: ViewerStatus
    let host: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding()
    }

    private var symbol: String {
        switch status {
        case .searching: return "antenna.radiowaves.left.and.right"
        case .waitingForExposure: return "moon.stars"
        case .tooManyConnections: return "person.2.slash"
        case .disconnected: return "wifi.exclamationmark"
        case .live, .stacking: return "photo"
        }
    }

    private var title: String {
        switch status {
        case .searching: return "Recherche du Seestar"
        case .waitingForExposure: return "Télescope connecté"
        case .tooManyConnections: return "Télescope déjà occupé"
        case .disconnected: return "Connexion perdue"
        case .live, .stacking: return "En attente d'image"
        }
    }

    private var detail: String {
        switch status {
        case .searching:
            return "Vérifie que le Seestar est allumé et rattaché au même réseau Wi-Fi."
        case .waitingForExposure:
            let where_ = host.map { " sur \($0)" } ?? ""
            return "Connecté\(where_). Lance une vue en mode Stargazing "
                + "depuis l'application officielle pour recevoir les images."
        case .tooManyConnections:
            return "Le Seestar n'accepte qu'un nombre très limité de spectateurs "
                + "sur son canal d'images, et la place est prise. Ferme un autre "
                + "appareil connecté au télescope, puis réessaie."
        case .disconnected:
            return "Reconnexion automatique en cours."
        case .live, .stacking:
            return ""
        }
    }
}
