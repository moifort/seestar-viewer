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

    /// Flux vidéo du télescope, disponible uniquement en modes Paysage et
    /// Système solaire. Dans ces modes le canal d'imagerie binaire reste muet :
    /// c'est ce flux, et lui seul, qui porte l'image.
    public private(set) var rtspStreamURL: URL?

    private static let hostKey = "seestar.manualHost"
    private static let rtspPort: UInt16 = 4554
    private var transport: DirectTransport?
    private var frameTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var rtspTask: Task<Void, Never>?

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
        rtspTask?.cancel()
        frameTask = nil
        eventTask = nil
        rtspTask = nil
        rtspStreamURL = nil
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
        startRTSPProbe(host: host)
        await transport.start()
    }

    /// Surveille l'ouverture du port RTSP pour détecter les modes Paysage et
    /// Système solaire. On sonde plutôt que d'écouter les événements : le
    /// champ `mode` peut arriver en retard, alors que le port ouvert est un
    /// fait immédiat. La sonde n'écrit rien et ne consomme aucune place sur le
    /// canal d'imagerie.
    private func startRTSPProbe(host: String) {
        rtspTask = Task { [weak self] in
            while !Task.isCancelled {
                let open = await PortProbe.isOpen(host: host, port: Self.rtspPort)
                guard let self, !Task.isCancelled else { return }
                let url = open ? URL(string: "rtsp://\(host):\(Self.rtspPort)/stream") : nil
                if url != self.rtspStreamURL {
                    self.rtspStreamURL = url
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
