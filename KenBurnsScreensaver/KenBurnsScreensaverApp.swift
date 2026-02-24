import SwiftUI

@main
struct KenBurnsScreensaverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }  // optional: remove New/Open clutter
            CommandMenu("Slideshow") {
                Button("Choose Folder…") {
                    NotificationCenter.default.post(name: .choosePhotoFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
