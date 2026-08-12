import SeestarUI
import SwiftUI

/// Application Apple TV : un seul écran, contemplatif, sans navigation.
@main
struct SeestarTVApp: App {
    var body: some Scene {
        WindowGroup {
            ViewerScreen { url in
                VLCStreamView(url: url)
            }
        }
    }
}
