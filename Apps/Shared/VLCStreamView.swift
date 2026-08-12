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

    final class Coordinator {
        private var player: VLCMediaPlayer?
        private var currentURL: URL?

        func start(streaming url: URL, into view: UIView) {
            guard currentURL != url else { return }
            currentURL = url

            player?.stop()
            // 300 ms de tampon : au-delà, l'image traîne derrière le télescope.
            let player = VLCMediaPlayer(options: ["--network-caching=300"])
            player.media = VLCMedia(url: url)
            player.drawable = view
            player.play()
            self.player = player
        }

        deinit {
            player?.stop()
        }
    }
}
