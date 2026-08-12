import Foundation

/// Source de données du télescope, indépendante du moyen d'y accéder.
///
/// La connexion directe n'en est qu'une implémentation. Si la mesure montre
/// que le télescope ne sert qu'un seul client à la fois (hypothèse 3 de la
/// spec), un relais viendra s'y substituer sans que le reste du code change.
public protocol SeestarTransport: Sendable {
    /// Le flux de trames doit être borné par `bufferingNewest(1)` : à 4 Mo par
    /// trame et une trame par seconde, toute mise en file finit en saturation.
    func frames() -> AsyncStream<RawFrame>
    func events() -> AsyncStream<SeestarEvent>
    func start() async
    func stop() async
}
