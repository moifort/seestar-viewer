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

    @State private var location = ObserverLocation()

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                // La minute est la plus petite unité qui compte ici : une
                // horloge à la seconde ferait clignoter la barre toute la nuit.
                TimelineView(.everyMinute) { context in
                    FlowLayout(spacing: 22, lineSpacing: 10) {
                        item(statusSymbol, statusText)
                        if let target = telemetry.target {
                            item("scope", target)
                        }
                        if let battery = telemetry.batteryCapacity {
                            // Le style `.percent` place le signe comme l'exige
                            // la langue : collé en anglais, précédé d'une
                            // espace en français.
                            item(batterySymbol(battery), battery.formatted(.percent))
                        }
                        if let temperature = telemetry.temperature {
                            item("thermometer.medium", String(format: "%.0f°C", temperature))
                        }
                        skyItems(now: context.date)
                        item("clock", time(context.date))
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                // Un coin arrondi plutôt qu'une gélule : sur deux lignes, la
                // gélule prendrait des flancs en demi-cercle démesurés.
                .background(.black.opacity(0.45), in: .rect(cornerRadius: 19, style: .continuous))
                // La barre ne dépasse jamais 90 % de la largeur : sur iPhone
                // elle touchait les bords, et il faut de la marge pour la
                // dérive anti-rémanence.
                .padding(.horizontal, geometry.size.width * 0.05)
                .padding(.bottom, 40)
                .antiBurnInDrift()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: isVisible)
        .task { await location.start() }
    }

    /// Ce que dit le ciel plutôt que le télescope : la lune qui va gêner, et
    /// les deux bornes de la nuit.
    @ViewBuilder
    private func skyItems(now: Date) -> some View {
        let moon = MoonPhase(date: now)
        item(moonSymbol(moon), moon.percentage.formatted(.percent))

        if let sun = location.sunTimes(on: now) {
            if let sunset = sun.sunset {
                item("sunset", time(sunset))
            }
            if let sunrise = sun.sunrise {
                item("sunrise", time(sunrise))
            }
        }
    }

    /// Heure seule, au format du pays : la date est celle du jour, l'écran est
    /// allumé devant l'observateur, il la connaît.
    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
        case .searching: return localized("Searching")
        case .waitingForExposure: return localized("Idle")
        case .live: return localized("Live")
        case .streaming: return localized("Live view")
        case .stacking: return localized("Stacking")
        case .tooManyConnections: return localized("Busy")
        case .disconnected: return localized("Disconnected")
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

    /// Le symbole dessine la phase, le pourcentage la quantifie : croissant ou
    /// gibbeuse se lit d'un coup d'œil, sans avoir à comparer deux nombres.
    ///
    /// Les variantes `inverse` sont celles qui conviennent sur fond noir : les
    /// symboles ordinaires remplissent la part *sombre* du disque, si bien
    /// qu'une nouvelle lune s'y afficherait en disque plein.
    private func moonSymbol(_ moon: MoonPhase) -> String {
        switch moon.illuminatedFraction {
        case ..<0.04: return "moonphase.new.moon.inverse"
        case ..<0.46: return moon.isWaxing
            ? "moonphase.waxing.crescent.inverse" : "moonphase.waning.crescent.inverse"
        case ..<0.54: return moon.isWaxing
            ? "moonphase.first.quarter.inverse" : "moonphase.last.quarter.inverse"
        case ..<0.96: return moon.isWaxing
            ? "moonphase.waxing.gibbous.inverse" : "moonphase.waning.gibbous.inverse"
        default: return "moonphase.full.moon.inverse"
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
