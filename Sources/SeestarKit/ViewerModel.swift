import Foundation
import Observation

public enum ViewerStatus: Equatable, Sendable {
    case searching
    /// Le télescope répond mais n'expose pas : ce n'est pas une erreur.
    case waitingForExposure
    case live
    case stacking
    case disconnected
}

public struct Telemetry: Equatable, Sendable {
    public var target: String?
    public var mode: String?
    public var tracking: Bool?
    public var batteryCapacity: Int?
    public var temperature: Double?

    public init() {}
}

/// Arbitre l'image affichée et l'état visible.
///
/// L'arbitrage se fonde sur l'arrivée réelle des trames plutôt que sur les
/// événements, qui peuvent arriver en retard.
@MainActor
@Observable
public final class ViewerModel {
    /// Au-delà de ce délai sans nouvelle trame d'empilement, le live reprend
    /// la main. Deux fois l'intervalle typique entre deux subs.
    public static let stackExpiry: TimeInterval = 60

    public private(set) var displayedFrame: DecodedFrame?
    public private(set) var status: ViewerStatus = .searching
    public private(set) var telemetry = Telemetry()

    private var lastStackDate: Date?

    public init() {}

    public func consume(_ frame: RawFrame, at date: Date = Date()) {
        // Réponse en clair : un état, pas une image. Qu'il s'agisse de « done »
        // ou du refus « only available for continuous exposure », le scope nous
        // parle : on est connecté et en attente, plus en train de chercher.
        if frame.textMessage != nil {
            noteSignOfLife()
            return
        }

        guard let decoded = FrameDecoder.decode(frame) else { return }

        switch decoded.kind {
        case .stack:
            lastStackDate = date
            displayedFrame = decoded
            status = .stacking

        case .preview:
            // On ne remplace un empilement que s'il a cessé d'être alimenté.
            if let last = lastStackDate, date.timeIntervalSince(last) < Self.stackExpiry {
                return
            }
            lastStackDate = nil
            displayedFrame = decoded
            status = .live
        }
    }

    public func consume(_ event: SeestarEvent) {
        noteSignOfLife()
        if let mode = event.mode { telemetry.mode = mode }
        if let tracking = event.tracking { telemetry.tracking = tracking }
        if let battery = event.batteryCapacity { telemetry.batteryCapacity = battery }
        if let temperature = event.temperature { telemetry.temperature = temperature }
        if let target = event.raw["target_name"] as? String { telemetry.target = target }
    }

    /// Le télescope a donné signe de vie sans fournir d'image.
    ///
    /// Ne fait jamais reculer un affichage en cours : la télémétrie continue
    /// d'arriver pendant un empilement, elle ne doit pas le masquer.
    private func noteSignOfLife() {
        if status == .searching || status == .disconnected {
            status = .waitingForExposure
        }
    }

    /// La connexion est tombée : on garde la dernière image à l'écran.
    /// Jamais d'écran noir, c'est la règle d'or d'un affichage contemplatif.
    public func connectionLost() {
        status = .disconnected
    }

    /// Branche le modèle sur un transport et consomme ses deux flux.
    public func attach(to transport: any SeestarTransport) {
        Task {
            for await frame in transport.frames() { consume(frame) }
            connectionLost()
        }
        Task {
            for await event in transport.events() { consume(event) }
        }
        Task { await transport.start() }
    }
}
