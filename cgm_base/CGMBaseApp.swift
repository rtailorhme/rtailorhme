import SwiftUI

@main
struct CGMBaseApp: App {
    var main: CGMManager = CGMManager.shared

    @SceneBuilder var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(main.app)
        }
    }
}
