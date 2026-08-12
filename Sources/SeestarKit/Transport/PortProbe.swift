import Foundation
import Network
import os

/// Teste l'ouverture d'un port TCP, sans y écrire le moindre octet.
///
/// Sert à détecter le mode de fonctionnement du télescope : le port RTSP 4554
/// n'est ouvert qu'en modes Paysage et Système solaire, où le canal d'imagerie
/// binaire reste muet. C'est le signal le plus fiable dont on dispose, et il
/// ne consomme pas de connexion sur le canal d'images, dont le nombre de
/// clients simultanés est très limité.
public enum PortProbe {
    public static func isOpen(host: String, port: UInt16, timeout: TimeInterval = 3) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
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
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
