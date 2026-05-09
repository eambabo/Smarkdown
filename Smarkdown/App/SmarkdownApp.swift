import SwiftUI

@main
struct SmarkdownApp: App {
    var body: some Scene {
        WindowGroup("Editor", id: "editor") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)

        WindowGroup("Documents", id: "documents") {
            FileListView()
        }
        .defaultSize(width: 380, height: 640)
    }
}
