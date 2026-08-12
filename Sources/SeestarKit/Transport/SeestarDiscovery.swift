import Foundation
import Network
import os

/// Trouve l'adresse du télescope sur le réseau local.
///
/// Mesuré le 2026-08-12 : le Seestar publie bien `seestar.local` en mDNS
/// lorsqu'il est rattaché au réseau domestique (mode station).
public enum SeestarDiscovery {
    public static let bonjourHost = "seestar.local"

    /// Rend l'hôte à utiliser : l'adresse saisie si elle existe, sinon le nom
    /// mDNS s'il se résout, sinon `nil`.
    public static func resolve(manualHost: String? = nil) async -> String? {
        if let manual = manualHost?.trimmingCharacters(in: .whitespaces), !manual.isEmpty {
            return manual
        }
        return await resolvesOnNetwork(bonjourHost) ? bonjourHost : nil
    }

    /// Vérifie qu'un nom se résout, en ouvrant brièvement une connexion vers
    /// le port de contrôle. Aucun octet n'est envoyé.
    private static func resolvesOnNetwork(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: .init(rawValue: DirectTransport.controlPort)!,
                using: .tcp
            )
            let settled = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ value: Bool) {
                let alreadyDone = settled.withLock { done -> Bool in
                    defer { done = true }
                    return done
                }
                guard !alreadyDone else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}
