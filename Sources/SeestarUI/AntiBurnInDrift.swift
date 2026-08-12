import SwiftUI

/// Fait dériver très lentement le contenu de quelques pixels.
///
/// Une image astro reste identique pendant des heures : sur une dalle OLED,
/// c'est le scénario type de la rémanence. Le cycle est assez lent pour être
/// imperceptible à l'œil, et assez ample pour répartir la charge des pixels.
struct AntiBurnInDrift: ViewModifier {
    /// Amplitude en points, de part et d'autre de la position centrale.
    var amplitude: CGFloat = 8
    /// Durée d'un aller-retour complet.
    var period: TimeInterval = 240

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / period
            content.offset(
                x: amplitude * CGFloat(cos(2 * .pi * phase)),
                y: amplitude * CGFloat(sin(2 * .pi * phase))
            )
        }
    }
}

extension View {
    func antiBurnInDrift() -> some View {
        modifier(AntiBurnInDrift())
    }
}
