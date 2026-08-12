import SeestarUI
import SwiftUI

/// Application iPhone et iPad : le même écran, pour les autres spectateurs.
/// Appui long sur l'image pour saisir l'adresse du télescope.
@main
struct SeestarViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ViewerScreen { url in
                VLCStreamView(url: url)
            }
        }
    }
}
