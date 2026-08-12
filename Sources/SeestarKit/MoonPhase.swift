import Foundation

/// Phase de la Lune à un instant donné.
///
/// C'est la première chose que regarde un observateur avant de sortir : une
/// pleine lune noie le ciel et condamne la soirée aux cibles brillantes. Le
/// calcul est purement local, il ne demande ni réseau ni position.
///
/// Les termes viennent de Meeus, *Astronomical Algorithms*, chapitre 48,
/// tronqués aux premiers : l'écart sur la fraction éclairée reste bien
/// au-dessous du point de pourcentage, seule précision qu'on affiche.
public struct MoonPhase: Sendable, Equatable {
    /// Fraction du disque éclairée, de 0 (nouvelle lune) à 1 (pleine lune).
    public let illuminatedFraction: Double

    /// Vrai de la nouvelle à la pleine lune, quand le croissant grossit.
    /// Ne change pas la quantité de lumière, mais bien le dessin du disque.
    public let isWaxing: Bool

    public init(date: Date = .now) {
        // Siècles juliens depuis J2000.0, l'échelle de temps des séries.
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525

        // Élongation moyenne de la Lune, anomalie moyenne du Soleil, puis
        // celle de la Lune.
        let d = 297.850_192_1 + 445_267.111_403_4 * t - 0.001_881_9 * t * t
            + t * t * t / 545_868 - t * t * t * t / 113_065_000
        let sun = 357.529_109_2 + 35_999.050_290_9 * t - 0.000_153_6 * t * t
            + t * t * t / 24_490_000
        let moon = 134.963_396_4 + 477_198.867_505_5 * t + 0.008_741_4 * t * t
            + t * t * t / 69_699 - t * t * t * t / 14_712_000

        // Angle de phase Soleil-Lune-Terre, en degrés.
        let phaseAngle = 180
            - d
            - 6.289 * sin(radians(moon))
            + 2.100 * sin(radians(sun))
            - 1.274 * sin(radians(2 * d - moon))
            - 0.658 * sin(radians(2 * d))
            - 0.214 * sin(radians(2 * moon))
            - 0.110 * sin(radians(d))

        illuminatedFraction = (1 + cos(radians(phaseAngle))) / 2
        // L'élongation croît de 0° à la nouvelle lune jusqu'à 360° à la
        // suivante : la première moitié du cycle est celle qui grossit.
        isWaxing = normalized(d) < 180
    }

    /// Fraction éclairée en pourcentage entier, tel qu'on l'affiche.
    public var percentage: Int {
        Int((illuminatedFraction * 100).rounded())
    }
}

private func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

/// Ramène un angle dans [0, 360) : les séries ci-dessus le laissent filer sur
/// des milliers de tours.
private func normalized(_ degrees: Double) -> Double {
    let remainder = degrees.truncatingRemainder(dividingBy: 360)
    return remainder < 0 ? remainder + 360 : remainder
}
