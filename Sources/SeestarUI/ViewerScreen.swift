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
    @State private var showsOverlay = true
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
                PortraitFitted {
                    Image(decorative: frame.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
                .antiBurnInDrift()
                .transition(.opacity)
            } else if let stream = session.rtspStreamURL {
                // Modes Paysage et Système solaire : l'image ne passe que par là.
                // Le flux est en portrait 1080x1920 comme le capteur, il suit
                // donc la même règle d'orientation que les trames décodées.
                switch PortraitFit.platformPolicy {
                case .fillWideScreen:
                    PortraitFitted { rtspPlayer(stream) }
                        .antiBurnInDrift()
                        .transition(.opacity)
                case .alwaysUpright:
                    // Le téléphone est plus élancé que le 9/16 du capteur :
                    // à hauteur égale il resterait deux bandes noires sur les
                    // côtés. On agrandit jusqu'aux bords, quitte à rogner un
                    // peu de champ — c'est le direct qu'on regarde, pas une
                    // pose qu'on cadre.
                    FullBleedStream { rtspPlayer(stream) }
                        .transition(.opacity)
                }
            } else {
                WaitingView(status: session.model.status)
            }

            TelemetryOverlay(
                status: displayedStatus,
                telemetry: session.model.telemetry,
                isVisible: showsOverlay
            )
        }
        // Sur la pile entière, et non sur l'image seule : sinon la zone de
        // sécurité tvOS rogne l'écran et l'image 16/9 ne remplit plus la dalle.
        .ignoresSafeArea()
        #if os(tvOS)
        // La flèche du haut de la télécommande montre et masque la barre.
        // Il faut que la vue puisse prendre le focus pour recevoir la commande.
        .focusable()
        .onMoveCommand { direction in
            guard direction == .up else { return }
            showsOverlay.toggle()
        }
        #endif
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

    /// L'état affiché doit décrire ce qui est à l'écran, pas ce que reçoit le
    /// canal binaire. En mode Solaire celui-ci reste muet, donc le modèle dit
    /// « en attente » alors que le flux vidéo, lui, s'affiche très bien.
    private var displayedStatus: ViewerStatus {
        if session.model.displayedFrame == nil, session.rtspStreamURL != nil {
            return .streaming
        }
        return session.model.status
    }


    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}


/// Écran d'attente. Le message `only available for continuous exposure` n'est
/// pas une erreur : le télescope est joignable, il n'expose simplement pas.
///
/// Les teintes sont écrites en blanc plutôt qu'en `.primary` et `.secondary` :
/// sur iOS, un téléphone réglé en thème clair rendait ces couleurs sémantiques
/// en noir, donc invisibles sur le fond noir de l'écran. Le fond ne dépend pas
/// du thème, le texte ne doit pas en dépendre non plus.
struct WaitingView: View {
    let status: ViewerStatus

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.title2)
                .foregroundStyle(.white)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
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
        case .live, .stacking, .streaming: return "photo"
        }
    }

    private var title: String {
        switch status {
        case .searching: return localized("Looking for your Seestar")
        case .waitingForExposure: return localized("Telescope connected")
        case .tooManyConnections: return localized("Telescope already busy")
        case .disconnected: return localized("Connection lost")
        case .live, .stacking, .streaming: return localized("Waiting for an image")
        }
    }

    /// Les phrases longues s'écrivent en littéral multiligne terminé par `\`,
    /// qui recolle les morceaux sans y glisser de retour à la ligne : la clé de
    /// traduction reste une phrase d'un seul tenant.
    private var detail: String {
        switch status {
        case .searching:
            return localized("""
                Make sure the Seestar is powered on and joined to the same \
                Wi-Fi network.
                """)
        case .waitingForExposure:
            return localized("Open the Seestar app.")
        case .tooManyConnections:
            return localized("""
                The Seestar allows only a handful of viewers on its image \
                channel, and the slot is taken. Close another device connected \
                to the telescope, then try again.
                """)
        case .disconnected:
            return localized("Reconnecting automatically.")
        case .live, .stacking, .streaming:
            return ""
        }
    }
}
