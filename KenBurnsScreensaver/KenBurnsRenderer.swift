import Metal
import MetalKit
import AppKit

// MARK: – Uniform layout must match the shader
struct KenBurnsUniforms {
    var srcOrigin: SIMD2<Float>
    var srcSize:   SIMD2<Float>
    var alpha:     Float
    var _pad:      SIMD3<Float> = .zero   // keep 16-byte alignment
}

// MARK: – One slide of animation
struct Slide {
    let texture: MTLTexture
    // Ken Burns start/end crop rects in normalised [0,1] texture space,
    // expressed as fractions of the aspect-ratio-corrected base rect.
    // Values are in [0,1] where 1.0 means "fill the letterboxed area".
    let startZoom: Float   // 1.0 = no zoom into the base rect, <1.0 = zoomed in
    let startPan:  SIMD2<Float>   // normalised offset within the zoom budget
    let endZoom:   Float
    let endPan:    SIMD2<Float>
}

// MARK: – Main renderer
final class KenBurnsRenderer: NSObject, MTKViewDelegate {

    // Tunables
    var slideDuration:     Double = 6.0   // seconds each photo stays
    var crossfadeDuration: Double = 1.5   // seconds of overlap

    // Metal objects
    private let device:        MTLDevice
    private let commandQueue:  MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer:  MTLBuffer!

    // Slides
    private var slides:       [Slide] = []
    private var currentIndex = 0

    // Timing
    private var slideStartTime: Double = 0
    private var totalTime:      Double = 0   // driven by draw()

    init?(mtkView: MTKView) {
        guard let dev   = MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = dev.makeCommandQueue()         else { return nil }
        device       = dev
        commandQueue = queue
        mtkView.device           = dev
        mtkView.clearColor       = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly  = false
        super.init()
        buildPipeline(mtkView: mtkView)
        buildFullscreenQuad()
        mtkView.delegate = self
    }

    // MARK: – Build pipeline from the compiled .metal shader
    private func buildPipeline(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal default library. Make sure KenBurns.metal is in the target.")
        }
        let vf = library.makeFunction(name: "kenBurnsVertex")!
        let ff = library.makeFunction(name: "kenBurnsFragment")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vf
        desc.fragmentFunction = ff
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        // Alpha blending for the cross-dissolve
        desc.colorAttachments[0].isBlendingEnabled           = true
        desc.colorAttachments[0].sourceRGBBlendFactor        = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor   = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor      = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: – Full-screen quad: (x, y, u, v) × 4 vertices
    private func buildFullscreenQuad() {
        let verts: [Float] = [
            -1,  1,   0, 0,   // top-left
            -1, -1,   0, 1,   // bottom-left
             1,  1,   1, 0,   // top-right
             1, -1,   1, 1,   // bottom-right
        ]
        vertexBuffer = device.makeBuffer(bytes: verts,
                                         length: verts.count * MemoryLayout<Float>.size,
                                         options: .storageModeShared)
    }

    // MARK: – Load photos from a folder
    func loadPhotos(from folderURL: URL) {
        let fm   = FileManager.default
        let exts = Set(["jpg","jpeg","png","heic","tiff","tif","gif","bmp"])
        guard let enumerator = fm.enumerator(at: folderURL,
              includingPropertiesForKeys: [.isRegularFileKey],
              options: [.skipsHiddenFiles]) else { return }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if exts.contains(url.pathExtension.lowercased()) { urls.append(url) }
        }
        urls.shuffle()

        let loader = MTKTextureLoader(device: device)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let loaded: [Slide] = urls.compactMap { url -> Slide? in
                guard let tex = try? loader.newTexture(URL: url, options: [
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue as NSObject,
                    .generateMipmaps: true as NSObject,
                    .SRGB: false as NSObject
                ]) else { return nil }
                return self.makeSlide(texture: tex)
            }

            DispatchQueue.main.async {
                guard !loaded.isEmpty else {
                    print("No photos found in \(folderURL.path)")
                    return
                }
                self.slides         = loaded
                self.currentIndex   = 0
                self.slideStartTime = self.totalTime
                print("Loaded \(loaded.count) photos.")
            }
        }
    }

    // MARK: – Randomise Ken Burns parameters for one slide
    //
    // We store zoom and pan as view-independent values [0,1].
    // The conversion to actual UV rects happens in computeUVRect(for:zoom:pan:viewSize:),
    // which accounts for the image aspect ratio vs. the current view aspect ratio.
    private func makeSlide(texture: MTLTexture) -> Slide {
        // zoom: 1.0 = show the whole letterboxed image, 0.77 ≈ 30 % zoom-in
        func randomZoom() -> Float { Float.random(in: 0.77...1.0) }
        // pan: random position within the "slack" allowed by the zoom level
        func randomPan() -> SIMD2<Float> { SIMD2(Float.random(in: 0...1), Float.random(in: 0...1)) }

        return Slide(
            texture:   texture,
            startZoom: randomZoom(),
            startPan:  randomPan(),
            endZoom:   randomZoom(),
            endPan:    randomPan()
        )
    }

    // MARK: – Compute UV rect preserving aspect ratio
    //
    // Strategy: "aspect-fill" the view with the image (like CSS cover), then
    // apply Ken Burns zoom/pan within that fitted rect — entirely in UV space.
    //
    // Returns (origin, size) in normalised [0,1] texture coordinates.
    private func computeUVRect(for texture: MTLTexture,
                               zoom: Float,
                               pan: SIMD2<Float>,
                               viewSize: CGSize) -> (origin: SIMD2<Float>, size: SIMD2<Float>) {

        let imgW  = Float(texture.width)
        let imgH  = Float(texture.height)
        let viewW = Float(viewSize.width)
        let viewH = Float(viewSize.height)

        guard imgW > 0, imgH > 0, viewW > 0, viewH > 0 else {
            return (origin: .zero, size: SIMD2(1, 1))
        }

        let imgAspect  = imgW / imgH
        let viewAspect = viewW / viewH

        // Base rect: the largest centered crop of the image that matches the view's aspect ratio.
        // In UV space this is a sub-rect of [0,1]×[0,1].
        let baseW: Float
        let baseH: Float

        if imgAspect > viewAspect {
            // Image is wider than the view → crop sides (pillarbox in reverse: we crop the image)
            baseH = 1.0
            baseW = viewAspect / imgAspect
        } else {
            // Image is taller than the view → crop top/bottom
            baseW = 1.0
            baseH = imgAspect / viewAspect
        }

        // Centre the base rect in the texture
        let baseOriginX = (1.0 - baseW) * 0.5
        let baseOriginY = (1.0 - baseH) * 0.5

        // Apply Ken Burns zoom: shrink the sample region by `zoom`
        let sampleW = baseW * zoom
        let sampleH = baseH * zoom

        // Pan: distribute the slack proportionally via pan [0,1]
        let slackX = baseW - sampleW   // room to move horizontally
        let slackY = baseH - sampleH

        let originX = baseOriginX + pan.x * slackX
        let originY = baseOriginY + pan.y * slackY

        return (origin: SIMD2(originX, originY), size: SIMD2(sampleW, sampleH))
    }

    // MARK: – MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard !slides.isEmpty else { return }
        guard let drawable       = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let cmdBuf         = commandQueue.makeCommandBuffer()
        else { return }

        let fps = Double(view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60)
        totalTime += 1.0 / fps

        let elapsed = totalTime - slideStartTime

        // Advance slide index when the full duration (including crossfade) is done
        if elapsed >= slideDuration {
            currentIndex    = (currentIndex + 1) % slides.count
            slideStartTime  = totalTime
            return
        }

        let t              = Float(min(elapsed / slideDuration, 1.0))
        let crossfadeStart = slideDuration - crossfadeDuration
        let fadeProgress   = Float(min(max((elapsed - crossfadeStart) / crossfadeDuration, 0.0), 1.0))
        let nextIndex      = (currentIndex + 1) % slides.count

        // Snapshot the drawable size once per frame so both slides use the same value
        let drawableSize = view.drawableSize

        renderPassDesc.colorAttachments[0].loadAction = .clear

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        func drawSlide(_ slide: Slide, alpha: Float, t: Float) {
            let zoom   = slide.startZoom + (slide.endZoom - slide.startZoom) * t
            let pan    = slide.startPan  + (slide.endPan  - slide.startPan)  * t
            let (origin, size) = computeUVRect(for: slide.texture,
                                               zoom: zoom,
                                               pan: pan,
                                               viewSize: drawableSize)
            var uniforms = KenBurnsUniforms(srcOrigin: origin, srcSize: size, alpha: alpha)
            encoder.setFragmentTexture(slide.texture, index: 0)
            encoder.setFragmentBytes(&uniforms,
                                     length: MemoryLayout<KenBurnsUniforms>.size,
                                     index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if fadeProgress > 0 && nextIndex != currentIndex {
            // Drive the incoming slide's Ken Burns from 0→(crossfadeDuration/slideDuration)
            // over the crossfade window, so its t=0 matches what it will be at the moment
            // it becomes currentIndex — no jump on transition.
            let nextT = Float((elapsed - crossfadeStart) / slideDuration)
            // TONYSCHR: debug the cross-fade glitch.
            // print("CrossFade: t: \(t), nextT: \(nextT), elapsed: \(elapsed), start: \(crossfadeStart), duration: \(slideDuration)")
            drawSlide(slides[nextIndex], alpha: fadeProgress, t: nextT)
        }
        
        drawSlide(slides[currentIndex], alpha: 1.0 - fadeProgress, t: t)

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
