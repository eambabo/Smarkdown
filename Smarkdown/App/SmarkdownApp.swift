import SwiftUI

@main
struct SmarkdownApp: App {
    var body: some Scene {
        WindowGroup("Editor", id: "editor") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            PreferencesView()
        }
    }
}
