import MetalKit
import SwiftUI

/// One of the two pictures (the game's pane, the companion) as a Metal texture, drawn aspect-fit by every PixelView that
/// shows it. Uploads come from the main thread after a tick; the views redraw on the next run loop turn.
@MainActor
final class PixelRenderer {
    let width: Int
    let height: Int
    let device: MTLDevice?
    let texture: MTLTexture?
    fileprivate let pipeline: MTLRenderPipelineState?
    fileprivate let queue: MTLCommandQueue?
    private var views = NSHashTable<MTKView>.weakObjects()

    init(width: Int, height: Int, format: MTLPixelFormat) {
        self.width = width
        self.height = height
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        texture = device?.makeTexture(descriptor: desc)
        queue = device?.makeCommandQueue()
        pipeline = device.flatMap { PixelRenderer.makePipeline($0) }
    }

    var aspect: CGFloat { CGFloat(width) / CGFloat(height) }

    func upload(_ bytes: UnsafePointer<UInt8>?) {
        guard let bytes, let texture else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        for view in views.allObjects { view.setNeedsDisplay() }
    }

    fileprivate func attach(_ view: MTKView) {
        views.add(view)
    }

    private static func makePipeline(_ device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "pd_vertex"),
              let fragment = library.makeFunction(name: "pd_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// Where the picture goes in a [size] box: as big as fits, its shape kept, centred.
    static func fit(_ size: CGSize, aspect: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        var w = size.width, h = size.width / aspect
        if h > size.height {
            h = size.height
            w = h * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

struct PixelView: UIViewRepresentable {
    let renderer: PixelRenderer
    var background: UIColor = .black

    func makeCoordinator() -> Coordinator { Coordinator(renderer) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = false // touches go to the SwiftUI views around it
        renderer.attach(view)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        background.getRed(&r, green: &g, blue: &b, alpha: &a)
        view.clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: 1)
        view.setNeedsDisplay()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: PixelRenderer
        init(_ renderer: PixelRenderer) { self.renderer = renderer }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            MainActor.assumeIsolated { view.setNeedsDisplay() }
        }

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(view) }
        }

        private func render(_ view: MTKView) {
            guard let pipeline = renderer.pipeline, let queue = renderer.queue, let texture = renderer.texture,
                  let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            let size = view.drawableSize
            let rect = PixelRenderer.fit(size, aspect: renderer.aspect)
            if rect.width >= 1, rect.height >= 1 {
                encoder.setViewport(MTLViewport(originX: Double(rect.minX.rounded()), originY: Double(rect.minY.rounded()),
                                                width: Double(rect.width.rounded()), height: Double(rect.height.rounded()),
                                                znear: 0, zfar: 1))
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                // Screen pixels per texel, for the sharp-bilinear sampling (pixels stay square, edges a pixel soft).
                var scale = SIMD2<Float>(Float(rect.width) / Float(renderer.width), Float(rect.height) / Float(renderer.height))
                encoder.setFragmentBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}
