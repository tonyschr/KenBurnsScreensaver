import SwiftUI

@main
struct KenBurnsScreensaverApp: App {
    @State private var settings = AppSettings()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }  // Remove New/Open clutter
            CommandGroup(after: .appSettings) {
                Button("Choose Folder…") {
                    NotificationCenter.default.post(name: .choosePhotoFolder, object: nil)
                }
            }
//            CommandMenu("Tools") {
//                Button("Choose Folder…") {
//                    NotificationCenter.default.post(name: .choosePhotoFolder, object: nil)
//                }
//                .keyboardShortcut("o", modifiers: .command)
//            }
        }
        
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}

@Observable
final class AppSettings {
    var slideDuration: Double {
        didSet {
            UserDefaults.standard.set(slideDuration, forKey: "slideDuration")
        }
    }

    var fadeDuration: Double {
        didSet {
            UserDefaults.standard.set(fadeDuration, forKey: "fadeDuration")
        }
    }

    init() {
        slideDuration = UserDefaults.standard.double(forKey: "slideDuration")
        fadeDuration = UserDefaults.standard.double(forKey: "fadeDuration")
    }
}

// TONY: Move to its own file
struct SettingsView: View {
//    @AppStorage("enableFeature")
//    private var enableFeature = false
    
    @Environment(AppSettings.self)
    private var settings
    
    @State private var isEditing = false
    
    var body: some View {
        Form {
            VStack {
                HStack {
                    Slider(
                        value: Bindable(settings).slideDuration,
                        in: 0...20,
                        onEditingChanged: { editing in
                            isEditing = editing
                        }
                    ) {
                        Text("Slide Duration: ")
                    }
                    Text(String(format: "%.1f", settings.slideDuration))
                        .foregroundColor(isEditing ? .blue : .black)
                }
                HStack {
                    Slider(
                        value: Bindable(settings).fadeDuration,
                        in: 0...10,
                        onEditingChanged: { editing in
                            isEditing = editing
                        }
                    ) {
                        Text("Fade Duration: ")
                    }
                    Text(String(format: "%.1f", settings.fadeDuration))
                        .foregroundColor(isEditing ? .blue : .black)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}
