import Foundation

/// Lever et coucher du soleil pour un lieu et un jour donnés.
///
/// Sur un écran d'astronomie ce sont les deux bornes de la soirée : l'heure à
/// partir de laquelle le ciel devient exploitable, et celle où il faut ranger.
///
/// L'algorithme est celui du NOAA (« sunrise equation »), au demi-degré près
/// sur la position du Soleil : l'écart sur les horaires reste de l'ordre de la
/// minute, sous la résolution de ce qu'on affiche. Le disque est considéré levé
/// quand son bord haut touche l'horizon, réfraction comprise, comme partout
/// ailleurs (−0,833°).
public struct SunTimes: Sendable, Equatable {
    /// Nil aux latitudes polaires, quand le soleil ne franchit pas l'horizon
    /// de la journée : il n'y a alors ni lever ni coucher à annoncer.
    public let sunrise: Date?
    public let sunset: Date?

    public init(date: Date = .now, latitude: Double, longitude: Double) {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5

        // Jour solaire local, compté depuis le 1ᵉʳ janvier 2000 : le décalage
        // par la longitude fait tomber le repère sur le midi du lieu, et non
        // sur celui de Greenwich.
        let cycle = (julianDay - 2_451_545.0 + 0.000_8).rounded()
        let meanSolarDay = cycle - longitude / 360

        // Anomalie moyenne, équation du centre, puis longitude écliptique.
        let anomaly = normalized(357.529_1 + 0.985_600_28 * meanSolarDay)
        let center = 1.914_8 * sin(radians(anomaly))
            + 0.020_0 * sin(radians(2 * anomaly))
            + 0.000_3 * sin(radians(3 * anomaly))
        let eclipticLongitude = normalized(anomaly + center + 180 + 102.937_2)

        // Passage au méridien : le midi solaire vrai du lieu.
        let transit = 2_451_545.0 + meanSolarDay
            + 0.005_3 * sin(radians(anomaly))
            - 0.006_9 * sin(radians(2 * eclipticLongitude))

        let declination = asin(sin(radians(eclipticLongitude)) * sin(radians(23.44)))
        let cosHourAngle = (sin(radians(-0.833)) - sin(radians(latitude)) * sin(declination))
            / (cos(radians(latitude)) * cos(declination))

        guard abs(cosHourAngle) <= 1 else {
            // Soleil de minuit ou nuit polaire : rien à afficher plutôt qu'une
            // heure inventée.
            sunrise = nil
            sunset = nil
            return
        }

        let hourAngle = degrees(acos(cosHourAngle))
        sunrise = Self.date(julianDay: transit - hourAngle / 360)
        sunset = Self.date(julianDay: transit + hourAngle / 360)
    }

    private static func date(julianDay: Double) -> Date {
        Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86_400)
    }
}

private func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

private func degrees(_ radians: Double) -> Double {
    radians * 180 / .pi
}

/// Ramène un angle dans [0, 360) : les séries ci-dessus le laissent filer sur
/// des milliers de tours.
private func normalized(_ degrees: Double) -> Double {
    let remainder = degrees.truncatingRemainder(dividingBy: 360)
    return remainder < 0 ? remainder + 360 : remainder
}
