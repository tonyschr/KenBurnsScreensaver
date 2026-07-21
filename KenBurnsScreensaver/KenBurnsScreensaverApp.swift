import SwiftUI

@main
struct KenBurnsScreensaverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

    var minRating: Int {
        didSet {
            UserDefaults.standard.set(minRating, forKey: "minRating")
        }
    }

    var maxRating: Int {
        didSet {
            UserDefaults.standard.set(maxRating, forKey: "maxRating")
        }
    }

    init() {
        slideDuration = UserDefaults.standard.double(forKey: "slideDuration")
        fadeDuration = UserDefaults.standard.double(forKey: "fadeDuration")
        minRating = UserDefaults.standard.integer(forKey: "minRating")
        maxRating = UserDefaults.standard.integer(forKey: "maxRating")
    }
}

// TONY: Move to its own file
struct SettingsView: View {
//    @AppStorage("enableFeature")
//    private var enableFeature = false
    
    @Environment(AppSettings.self)
    private var settings
    
    @State private var isEditing = false
    @State private var selectedValue: Int? = nil
    
    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Label("Filter by Rating", systemImage: "star.fill")
                VStack(alignment: .leading) {
                    HStack {
                        Picker("Minimum: ", selection: Bindable(settings).minRating) {
                            ForEach(0..<6) { num in
                                Text("\(num)")
                                    .tag(num)
                            }
                        }
                        .pickerStyle(.segmented)
                        .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Picker("Maximum: ", selection: Bindable(settings).maxRating) {
                            ForEach(0..<6) { num in
                                Text("\(num)")
                                    .tag(num)
                            }
                        }
                        .pickerStyle(.segmented)
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                
                Label("Playback", systemImage: "clock")
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
                .padding()
            }
        }
        .padding()
        .frame(width: 400)
    }
}
