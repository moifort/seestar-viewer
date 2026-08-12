import Foundation

/// Événement diffusé spontanément par le télescope sur le port 4700.
///
/// Le flux est disponible sans authentification, contrairement aux commandes.
/// On ne modélise que les champs réellement exploités par l'affichage.
public struct SeestarEvent: Equatable {
    public let name: String
    public let timestamp: Double?
    /// Présent sur `View` : « star » en mode astro, « scenery » en paysage.
    /// C'est le signal qui indique si le canal d'imagerie va produire des trames.
    public let mode: String?
    public let state: String?
    public let tracking: Bool?
    public let batteryCapacity: Int?
    public let temperature: Double?
    /// Objet JSON complet, pour les champs non modélisés.
    public let raw: [String: Any]

    public static func == (lhs: SeestarEvent, rhs: SeestarEvent) -> Bool {
        lhs.name == rhs.name && lhs.timestamp == rhs.timestamp
            && lhs.mode == rhs.mode && lhs.state == rhs.state
    }

    init?(json: [String: Any]) {
        guard let name = json["Event"] as? String else { return nil }
        self.name = name
        // Le timestamp arrive en chaîne de caractères, pas en nombre.
        self.timestamp = (json["Timestamp"] as? String).flatMap(Double.init)
        self.mode = json["mode"] as? String
        self.state = json["state"] as? String
        self.tracking = json["tracking"] as? Bool
        self.batteryCapacity = json["battery_capacity"] as? Int
        self.temperature = json["temp"] as? Double
        self.raw = json
    }
}

extension SeestarEvent: @unchecked Sendable {}
