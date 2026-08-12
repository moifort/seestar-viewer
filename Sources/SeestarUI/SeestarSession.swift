import Foundation
import Observation
import SeestarKit

/// Orchestre la découverte, le transport et le modèle d'affichage.
///
/// C'est le seul objet que les applications manipulent : elles lui demandent
/// de démarrer, il se débrouille pour trouver le télescope et alimenter la vue.
@MainActor
@Observable
public final class SeestarSession {
    public let model = ViewerModel()

    /// Adresse saisie à la main, prioritaire sur la découverte mDNS.
    public var manualHost: String {
        didSet { UserDefaults.standard.set(manualHost, forKey: Self.hostKey) }
    }

    /// Hôte réellement utilisé, une fois la découverte faite.
    public private(set) var resolvedHost: String?

    private static let hostKey = "seestar.manualHost"
    private var transport: DirectTransport?
    private var frameTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    public init() {
        manualHost = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
    }

    public func start() {
        guard transport == nil else { return }
        Task { await connect() }
    }

    /// Ferme proprement les deux canaux.
    ///
    /// Indispensable sur iOS : le système suspend les sockets en arrière-plan,
    /// mieux vaut couper nous-mêmes que laisser des connexions à moitié mortes.
    public func stop() async {
        frameTask?.cancel()
        eventTask?.cancel()
        frameTask = nil
        eventTask = nil
        await transport?.stop()
        transport = nil
    }

    /// Reprend la connexion après un changement d'adresse ou un retour au
    /// premier plan.
    public func restart() {
        Task {
            await stop()
            await connect()
        }
    }

    private func connect() async {
        let manual = manualHost.trimmingCharacters(in: .whitespaces)
        guard let host = await SeestarDiscovery.resolve(manualHost: manual.isEmpty ? nil : manual)
        else {
            resolvedHost = nil
            // Rien trouvé : on retentera au prochain démarrage ou après saisie
            // d'une adresse. Inutile de marteler le réseau.
            return
        }

        resolvedHost = host
        let transport = DirectTransport(host: host)
        self.transport = transport

        frameTask = Task { [model] in
            for await frame in transport.frames() {
                model.consume(frame)
            }
            model.connectionLost()
        }
        eventTask = Task { [model] in
            for await event in transport.events() {
                model.consume(event)
            }
        }
        await transport.start()
    }
}
