import CoreGraphics
import SwiftUI

/// Décide si l'image du télescope doit pivoter pour épouser l'écran.
///
/// Le capteur du Seestar produit toujours du portrait, et dans le ciel il n'y
/// a pas de haut : on pourrait donc tourner librement. Mais ce n'est
/// souhaitable que là où l'utilisateur ne peut pas tourner l'écran lui-même.
public enum PortraitFit {
    /// Ce qu'on attend de l'appareil qui affiche.
    public enum Policy: Sendable {
        /// Écran figé en paysage : l'image doit pivoter, sans quoi elle
        /// n'occuperait qu'une bande centrale entre deux larges marges noires.
        /// C'est le cas du téléviseur.
        case fillWideScreen
        /// L'utilisateur oriente l'appareil à la main : on respecte son geste
        /// et on laisse l'image dans son sens naturel, quitte à la voir
        /// encadrée de noir en paysage. C'est le cas de l'iPhone et de l'iPad.
        case alwaysUpright
    }

    /// La politique de la plateforme courante.
    public static var platformPolicy: Policy {
        #if os(tvOS)
        .fillWideScreen
        #else
        .alwaysUpright
        #endif
    }

    public static func shouldRotate(policy: Policy, container: CGSize) -> Bool {
        switch policy {
        case .alwaysUpright:
            return false
        case .fillWideScreen:
            guard container.width > 0, container.height > 0 else { return false }
            return container.width > container.height
        }
    }
}

/// Étire le flux vidéo jusqu'aux bords de l'écran, quitte à en rogner les
/// côtés.
///
/// Le téléphone est plus élancé que le capteur : à hauteur égale, le flux
/// laisserait deux bandes noires. Sur un écran entièrement noir, l'image
/// paraît alors flotter en timbre-poste.
struct FullBleedStream<Content: View>: View {
    @ViewBuilder var content: Content

    /// Le capteur filme en 1080x1920, et le zoom x2 en 536x960 : toujours du
    /// 9/16. VLCKit inscrit l'image dans sa vue en respectant les proportions
    /// du flux, donner ces proportions à la vue suffit donc à la remplir.
    private static var aspectRatio: CGFloat { 9.0 / 16.0 }

    var body: some View {
        GeometryReader { geometry in
            content
                .aspectRatio(Self.aspectRatio, contentMode: .fill)
                // Le débord couvre la dérive anti-rémanence : sans lui, elle
                // découvrirait une bande noire au bord à chaque oscillation.
                .frame(
                    width: geometry.size.width + 2 * AntiBurnInDrift.defaultAmplitude,
                    height: geometry.size.height + 2 * AntiBurnInDrift.defaultAmplitude
                )
                .clipped()
                .antiBurnInDrift()
                // Le cadre déborde de l'écran : sans recentrage, la vue
                // resterait accrochée en haut à gauche et ne rognerait qu'en
                // bas et à droite.
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

/// Pose l'image du télescope selon la politique de la plateforme.
///
/// La permutation largeur/hauteur avant rotation est indispensable : sans
/// elle, le contenu tourne mais garde son cadre d'origine et se retrouve
/// rogné dans les angles.
struct PortraitFitted<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            if PortraitFit.shouldRotate(policy: PortraitFit.platformPolicy,
                                        container: geometry.size) {
                content
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}
