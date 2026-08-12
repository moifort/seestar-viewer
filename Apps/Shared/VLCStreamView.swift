import SwiftUI
import UIKit
import VLCKitSPM

/// Lit le flux RTSP du télescope, seul chemin d'image en modes Paysage et
/// Système solaire.
///
/// `AVPlayer` ne connaît pas le RTSP : VLCKit fait le travail. Le tampon
/// réseau est réduit au minimum utilisable, la latence important plus que la
/// fluidité absolue quand on regarde le Soleil bouger dans le champ.
struct VLCStreamView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.start(streaming: url, into: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.start(streaming: url, into: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Point de sortie de SwiftUI : c'est ici qu'on relâche le lecteur.
    /// Un `deinit` ne peut pas le faire, Swift 6 interdisant d'y toucher à un
    /// type non-Sendable depuis un contexte non isolé.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var player: VLCMediaPlayer?
        private weak var drawable: UIView?
        private var currentURL: URL?
        private var watchdog: Task<Void, Never>?

        func start(streaming url: URL, into view: UIView) {
            drawable = view
            guard currentURL != url || player == nil else { return }
            currentURL = url
            play(url, into: view)
            startWatchdog()
        }

        private func play(_ url: URL, into view: UIView) {
            player?.stop()
            // 300 ms de tampon : au-delà, l'image traîne derrière le télescope.
            let player = VLCMediaPlayer(options: ["--network-caching=300"])
            player.media = VLCMedia(url: url)
            player.drawable = view
            player.play()
            self.player = player
        }

        /// Relance la lecture quand le flux s'interrompt.
        ///
        /// Le télescope redémarre son flux RTSP dès qu'on change ses réglages :
        /// mesuré sur le zoom x2, qui fait passer la résolution de 1080x1920 à
        /// 536x960. L'URL reste la même, donc rien ne nous prévient — sans ce
        /// garde-fou, la session meurt et l'écran reste noir jusqu'au
        /// redémarrage de l'application.
        ///
        /// On surveille l'état de lecture plutôt que les notifications de
        /// VLCKit : l'énumération des états varie d'une version à l'autre,
        /// alors que « ça ne joue plus » reste vrai partout.
        private func startWatchdog() {
            watchdog?.cancel()
            watchdog = Task { [weak self] in
                var idleChecks = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, let player = self.player else { return }

                    if player.isPlaying {
                        idleChecks = 0
                        continue
                    }
                    // Deux relevés consécutifs : on laisse au flux le temps de
                    // s'ouvrir avant de conclure qu'il est mort.
                    idleChecks += 1
                    guard idleChecks >= 2,
                          let url = self.currentURL,
                          let view = self.drawable
                    else { continue }

                    idleChecks = 0
                    self.play(url, into: view)
                }
            }
        }

        func stop() {
            watchdog?.cancel()
            watchdog = nil
            player?.stop()
            player = nil
            currentURL = nil
        }
    }
}
