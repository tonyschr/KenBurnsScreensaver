import SwiftUI
import MetalKit
import UniformTypeIdentifiers

// MARK: – NSViewRepresentable bridge
struct MetalKenBurnsView: NSViewRepresentable {
    @Binding var settings: AppSettings
    @Binding var photoFolderURL: URL?

    func makeCoordinator() -> KenBurnsRenderer? {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        return KenBurnsRenderer(settings: settings, mtkView: mtkView)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false

        if let renderer = KenBurnsRenderer(settings: settings, mtkView: mtkView) {
            mtkView.delegate = renderer
            objc_setAssociatedObject(mtkView, &AssociatedKeys.renderer, renderer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            if let url = photoFolderURL {
                renderer.loadPhotos(from: url)
            } else {
                renderer.loadPhotos(from: defaultPhotoFolder())
            }
        }
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = objc_getAssociatedObject(nsView, &AssociatedKeys.renderer) as? KenBurnsRenderer,
              let url = photoFolderURL else { return }
        renderer.loadPhotos(from: url)
    }

    private func defaultPhotoFolder() -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
    }
}

private enum AssociatedKeys {
    static var renderer = "KenBurnsRendererKey"
}

// MARK: – Notification used to trigger the folder picker from the menu
extension Notification.Name {
    static let choosePhotoFolder = Notification.Name("choosePhotoFolder")
}

// MARK: – Main Content View
struct ContentView: View {
    @State private var photoFolderURL: URL? = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
    @State private var isPickerPresented = false

    @Environment(AppSettings.self)
    private var settings
    
    var body: some View {
        MetalKenBurnsView(settings: Binding.constant(settings), photoFolderURL: $photoFolderURL)
            .ignoresSafeArea()
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    _ = url.startAccessingSecurityScopedResource()
                    photoFolderURL = url
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .choosePhotoFolder)) { _ in
                isPickerPresented = true
            }
    }
}
