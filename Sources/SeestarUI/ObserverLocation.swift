import CoreLocation
import Observation
import SeestarKit

/// Position de l'observateur, juste assez précise pour dater le crépuscule.
///
/// Le télescope ne dit pas où il est, et le lever du soleil dépend du lieu :
/// on demande donc au système. Une seule mesure suffit — un télescope posé ne
/// se déplace pas de la soirée — et quelques kilomètres d'erreur ne changent
/// pas l'horaire d'une minute, d'où la précision volontairement grossière.
///
/// Si l'utilisateur refuse, ou si l'appareil ne sait pas se localiser, les
/// horaires disparaissent simplement de la barre : c'est un agrément, pas une
/// fonction dont dépend l'observation.
@MainActor
@Observable
final class ObserverLocation {
    private(set) var coordinate: CLLocationCoordinate2D?

    /// Attend la première position connue, puis rend la main : rien ne justifie
    /// de tenir le GPS éveillé toute la nuit sur un écran contemplatif.
    func start() async {
        guard coordinate == nil else { return }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.default) {
                if let location = update.location {
                    coordinate = location.coordinate
                    return
                }
            }
        } catch {
            // Localisation indisponible : la barre se passera des horaires.
        }
    }

    /// Horaires du jour pour la position connue, s'il y en a une.
    func sunTimes(on date: Date) -> SunTimes? {
        guard let coordinate else { return nil }
        return SunTimes(
            date: date,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}
