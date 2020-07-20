//
//  ImageRenderView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200718.
//

import Cocoa
import Metal
import MetalKit
import MetalPerformanceShaders

import Waterpipe
import Smokeshop

import CocoaLumberjackSwift

class ImageRenderView: MTKView {
    // MARK: - Setup
    /// Notification observer on app quit
    private var quitObs: NSObjectProtocol? = nil
    
    /**
     * Decodes the view from an IB file.
     */
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }
    
    /**
     * Allocates a new view.
     */
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.commonInit()
    }
    
    /**
     * Common view initialization
     */
    private func commonInit() {
        // set default device if not already set
        if self.device == nil {
            self.updateDevice()
        } else {
            DDLogDebug("Using device \(String(describing: self.device)) from constructor")
            self.createMetalResources()
        }
        
        // pixel formats
        self.colorPixelFormat = .bgr10a2Unorm
        self.depthStencilPixelFormat = .invalid
        self.framebufferOnly = true
        
        self.colorspace = CGColorSpace(name: CGColorSpace.rommrgb)
        
        self.autoResizeDrawable = true
        
        // resizing
        self.setUpSizeChangeObserver()
        
        // install a quit observer to properly release renderer (XPC service handle)
        self.quitObs = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: nil) { [weak self] _ in
            self?.renderer = nil
        }
    }
    
    /**
     * Cleans up various observers and previously allocated resources on dealloc.
     */
    deinit {
        self.invalidateMetalResources()
        self.cleanUpSizeChangeObserver()
        
        if let obs = self.quitObs {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    // MARK: - Image display
    /// Currently showing image
    private var currentImage: Image? = nil
    
    /**
     * Sets the image to be displayed.
     */
    internal func setImage(_ image: Image, _ callback: @escaping (Result<Void, Error>) -> Void) {
        self.thumbTexture = nil
        
        // we must have a renderer
        guard self.renderer != nil else {
            return callback(.failure(Errors.noRenderer))
        }
        
        // try to get thumbnail texture
        ThumbHandler.shared.get(image) { imageId, res in
            do {
                let surface = try res.get()
                try self.updateThumb(surface)
            } catch {
                DDLogError("Failed to set thumb, ignoring error: \(error)")
            }
        }

        // update image and request redrawing
        self.renderer?.setImage(image) { res in
            do {
                let _ = try res.get()
                
                self.renderer?.redraw() { res in
                    return callback(res)
                }
            } catch {
                DDLogError("Failed to update image: \(error)")
                return callback(.failure(error))
            }
        }
        
        // redraw UI, starting with the thumb image
        self.shouldDrawViewport = false
        self.drawThumb = true
        self.needsDisplay = true
    }
    
    // MARK: - Metal resources
    /// Command queue used for display
    private var queue: MTLCommandQueue! = nil
    /// Shader library
    private var library: MTLLibrary! = nil
    
    /// Index buffer for triangle coordinates of the thumb
    private var quadIndexBuf: MTLBuffer? = nil
    /// Uniform buffer for thumb rendering
    private var quadUniformBuf: MTLBuffer? = nil
    
    /**
     * Invalidates all existing Metal resources.
     */
    private func invalidateMetalResources() {
        // release command queues and buffers
        self.queue = nil
        self.library = nil
        
        self.quadIndexBuf = nil
        self.quadUniformBuf = nil
        
        // thumbnail data
        self.thumbVertexBuf = nil
        self.thumbTexture = nil
        
        // viewport
        self.viewportUniformBuf = nil
        self.viewportVertexBuf = nil
        self.viewportTexture = nil
        
        // renderer
        self.renderer = nil
    }
    
    /**
     * Creates the Metal resources needed to display content on-screen.
     */
    private func createMetalResources() {
        precondition(self.device != nil, "Render device must be set")
        
        do {
            // create command queue
            self.queue = self.device!.makeCommandQueue()!
            self.queue.label = String(format: "ImageRenderView-%@", self)
            
            // create library for shader code
            self.library = self.device!.makeDefaultLibrary()!
            
            // index buffer for drawing full screen quad
            self.createQuadIndexBuf()
            self.createQuadUniforms()
            
            // thumbnail stuff
            try self.makeThumbPipelineState()
            
            // viewport
            self.createViewportBufs()
            try self.createViewportPipelineState()
            
            // renderer
            self.createRenderer()
        } catch {
            DDLogError("Failed to create metal resources: \(error)")
        }
    }
    
    /**
     * Creates an index buffer for drawing a full screen quad.
     */
    private func createQuadIndexBuf() {
        let indexData: [UInt32] = [
            // first triangle: top left, bottom left, top right (CCW)
            0, 1, 2,
            // second triangle: top right, bottom left, bottom right (CCW)
            2, 1, 3
        ]
        
        let indexBufSz = indexData.count * MemoryLayout<UInt32>.stride
        self.quadIndexBuf = self.device?.makeBuffer(bytes: indexData, length: indexBufSz)!
    }
    
    /**
     * Update thumbnail uniform buffer. Any time the view is resized, this is performed.
     */
    private func createQuadUniforms() {
        // ensure this is always run on main thread (due to reading bounds)
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                self.createQuadUniforms()
            }
        }
        
        // create an identity matrix
        var uniforms = Uniform()
        uniforms.projection = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        // correct for aspect ratio (x/y scale)
        uniforms.projection.columns.0[0] = 1 / Float(self.bounds.width / self.bounds.height)
        
        // compensate for the top inset from the title bar
        if let safeArea = self.window?.contentView?.safeAreaInsets {
            let screenSpaceOffset = Float(safeArea.top / self.bounds.height)
            uniforms.projection.columns.1[3] = -screenSpaceOffset // translate
            uniforms.projection.columns.1[1] = 1 - (screenSpaceOffset / 2) // y scale
        }
        
        DDLogVerbose("Projection matrix: \(uniforms.projection)")
        
        // create buffer
        let bufSize = MemoryLayout<Uniform>.stride
        self.quadUniformBuf = self.device?.makeBuffer(bytes: &uniforms,
                                                      length: bufSize)!
    }
    
    // MARK: - Size changes
    /// Size notification observer
    private var sizeObs: NSObjectProtocol? = nil
    
    /**
     * Sets up the size change notifications.
     */
    private func setUpSizeChangeObserver() {
        // remove old observer
        self.cleanUpSizeChangeObserver()
        
        // add observer and enable the notification
        self.sizeObs = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                              object: self, queue: nil) { note in
            // update uniforms (projection matrix) always
            self.createQuadUniforms()
            
            // resize viewport if not in live resize
            if !self.inLiveResize {
                self.updateViewportSize()
            }
        }
        self.postsFrameChangedNotifications = true
    }
    
    /**
     * Cleans up any old notifications.
     */
    private func cleanUpSizeChangeObserver() {
        // disable notifications
        self.postsFrameChangedNotifications = false
        
        // remove observer
        if let obs = self.sizeObs {
            NotificationCenter.default.removeObserver(obs)
            self.sizeObs = nil
        }
    }
    
    /**
     * When the view is added to a view hierarchy, ensure the viewport size is updated.
     */
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        
        if self.frame.size != .zero {
            self.updateViewportSize()
        }
    }

    /**
     * When the view has ended live resizing, ensure the viewport texture is sized properly.
     */
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        
        // update uniforms (projection matrix)
        self.createQuadUniforms()
        
        // resize the texture
        self.updateViewportSize()
        
        // redraw immediately
        self.needsDisplay = true
    }
    
    // MARK: - Device changes
    /**
     * Updates the display device used to draw the view.
     *
     * By default, we try to use the preferred device indicated by Metal; otherwise, we just go with the system default. All Metal resources
     * will automagically be re-created if the device changed.
     */
    private func updateDevice(_ inDevice: MTLDevice? = nil) {
        // what is the new device we should use?
        var newDevice: MTLDevice? = nil
        
        if let device = inDevice {
            // use the passed in device
            newDevice = device
        }
        else if let preferred = self.preferredDevice {
            // use preferred device if available
            newDevice = preferred
        }
        else {
            // otherwise, use the system default device
            newDevice = MTLCreateSystemDefaultDevice()
        }
        
        precondition(newDevice != nil, "Failed to get render device")
        
        // destruct old resources if the new preferred device is different
        guard self.device?.registryID != newDevice?.registryID else {
            return
        }
        self.invalidateMetalResources()
        
        // create resources on the new device
        self.device = newDevice
        self.createMetalResources()
        
        // we need to re-display the view
        self.needsDisplay = true
    }
    
    /**
     * When the view moves to a window, ensure that we use the preferred Metal device for that view to draw.
     */
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        guard let window = self.window, let preferred = self.preferredDevice else {
            return
        }
        
        DDLogVerbose("Preferred device ImageRenderView in \(window): \(preferred)")
        self.updateDevice()
    }

    // MARK: - Drawing
    /**
     * Requests that the view draws itself.
     */
    override func draw(_ dirtyRect: NSRect) {
        do {
            // set up for the render pass
            guard let descriptor = self.currentRenderPassDescriptor else {
                throw Errors.noRenderPassDescriptor
            }
            guard let buffer = self.queue.makeCommandBuffer() else {
                throw Errors.makeCommandBufferFailed
            }
            
            // draw thumbnail
            if self.thumbTexture != nil, self.drawThumb {
                guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                    throw Errors.makeRenderCommandEncoderFailed(descriptor)
                }
                
                try self.drawBackgroundThumb(encoder)
                
                encoder.endEncoding()
            }
            
            // render the viewport
            if self.shouldDrawViewport, self.viewportTexture != nil {
                guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                    throw Errors.makeRenderCommandEncoderFailed(descriptor)
                }
                
                // if in live resize, draw blurred viewport texture
                if self.inLiveResize {
                    
                }
                // otherwise, draw as-is
                else {
                    try self.drawViewport(encoder)
                }
                
                encoder.endEncoding()
            }
            
            // finish encoding the pass and present it
            if let drawable = self.currentDrawable {
                buffer.present(drawable)
            }
            
            buffer.commit()
        } catch {
            DDLogError("ImageRenderView draw(_:) failed: \(error)")
        }
    }
    
    // MARK: - Thumbnail
    /// Vertex coordinate buffer for thumbnail
    private var thumbVertexBuf: MTLBuffer? = nil
    /// Texture for the thumbnail image
    private var thumbTexture: MTLTexture? = nil
    
    /// Thumbnail render pipeline state
    private var thumbPipelineState: MTLRenderPipelineState? = nil
    
    /// Should the thumbnail image be drawn? This is cleared once the renderer returns.
    private var drawThumb: Bool = true
    
    /**
     * Updates the thumbnail to the given surface.
     */
    private func updateThumb(_ surface: IOSurface) throws {
        // create the input texture from the surface
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: surface.width,
                                                            height: surface.height,
                                                            mipmapped: false)
        guard let surfaceTex = self.device?.makeTexture(descriptor: desc,
                                                        iosurface: surface.surfaceRef,
                                                        plane: 0) else {
            throw Errors.makeTextureFailed
        }
        
        // defer to the texture based creation logic
        try self.updateThumb(surfaceTex)
    }
    
    /**
     * Updates the thumb given a generic texture as the input; an output texture is allocated.
     */
    private func updateThumb(_ texture: MTLTexture) throws {
        // create a new output texture (that will contain the blurred version)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: texture.width,
                                                            height: texture.height,
                                                            mipmapped: false)
        desc.usage.insert(.shaderWrite)
        desc.storageMode = .private
        
        guard let output = self.device?.makeTexture(descriptor: desc) else {
            throw Errors.makeTextureFailed
        }
        
        // update vertex buffer and render the texture
        self.updateThumbVertexBuf(input: texture)
        try self.updateThumbTexture(input: texture, output: output)
    }
    
    /**
     * Updates the thumbnail texture
     *
     * This blurs the provided input thumbnail into the output texture. Once the rendering completes, the output texture is stored as the
     * thumb texture and the view is displayed.
     */
    private func updateThumbTexture(input: MTLTexture, output: MTLTexture) throws {
        // release the old texture
        self.thumbTexture = nil

        // build the blur pass command buffer
        guard let buffer = self.queue.makeCommandBuffer() else {
            throw Errors.makeCommandBufferFailed
        }
        buffer.pushDebugGroup("ThumbSurfaceBlur")
        
        let blur = MPSImageGaussianBlur(device: self.device!, sigma: 5)
        blur.edgeMode = .clamp
        blur.encode(commandBuffer: buffer, sourceTexture: input,
                    destinationTexture: output)

        // add a completion handler
        buffer.addCompletedHandler() { _ in
            // set the thumb texture
            self.thumbTexture = output
            
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
        }
    
        // execute the buffer
        buffer.popDebugGroup()
        buffer.commit()
    }
    
    /**
     * Creates the thumbnail pipeline state
     */
    private func makeThumbPipelineState() throws {
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = .bgr10a2Unorm
        desc.depthAttachmentPixelFormat = .invalid
    
        desc.vertexFunction = self.library.makeFunction(name: "textureMapVtx")!
        desc.fragmentFunction = self.library.makeFunction(name: "textureMapFrag")!
        
        desc.vertexDescriptor = Vertex.makeDescriptor()
    
        // create the pipeline state
        self.thumbPipelineState = try self.device!.makeRenderPipelineState(descriptor: desc)
    }
    
    /**
     * Updates the vertex buffer for the image thumbnail quad.
     *
     * The coordinates are set such that the short edge of the image is 0.05 from the edge of the screen, and the long edge is
     * proportionally scaled. This preserves a semi-correct appearance when the actual rendered image comes in.
     */
    private func updateThumbVertexBuf(input: MTLTexture) {
        // deallocate previous buffer
        self.thumbVertexBuf = nil
        
        // vertex coords vary based on landscape/portrait layout
        var x: Float = 0
        var y: Float = 0
        
        if input.width >= input.height {
            x = Float(0.9)
            y = (Float(input.height) / Float(input.width)) * x
        } else {
            y = Float(0.9)
            x = (Float(input.width) / Float(input.height)) * y
        }
        
        let vertexData = [
            Vertex(position: SIMD4<Float>(-x, y, 0, 1), textureCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD4<Float>(-x, -y, 0, 1), textureCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD4<Float>(x, y, 0, 1), textureCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD4<Float>(x, -y, 0, 1), textureCoord: SIMD2<Float>(1, 1)),
        ]
        
        // create buffer
        let bufSize = vertexData.count * MemoryLayout<Vertex>.stride
        self.thumbVertexBuf = self.device?.makeBuffer(bytes: vertexData, length: bufSize)!
    }
    
    /**
     * Draw the blurred background texture
     */
    private func drawBackgroundThumb(_ encoder: MTLRenderCommandEncoder) throws {
        encoder.pushDebugGroup("RenderThumb")
        
        encoder.setRenderPipelineState(self.thumbPipelineState!)
        encoder.setFragmentTexture(self.thumbTexture!, index: 0)
        
        encoder.setVertexBuffer(self.thumbVertexBuf!, offset: 0, index: 0)
        encoder.setVertexBuffer(self.quadUniformBuf!, offset: 0, index: 1)
        
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32,
                                      indexBuffer: self.quadIndexBuf!, indexBufferOffset: 0)
        
        encoder.popDebugGroup()
    }
    
    // MARK: Viewport
    /// Uniform buffer for viewport drawing
    private var viewportUniformBuf: MTLBuffer? = nil
    /// Vertex coordinate buffer for viewport
    private var viewportVertexBuf: MTLBuffer? = nil
    /// Texture for the viewport image image
    private var viewportTexture: MTLTexture? = nil
    /// Render pipeline state used for displaying the viewport image
    private var viewportPipelineState: MTLRenderPipelineState? = nil
    
    /// Current viewport rect
    private var viewport: CGRect = .zero
    
    /// Should the viewport be drawn?
    private var shouldDrawViewport: Bool = false
    
    /**
     * Updates the vertex buffer used to draw the viewport texture.
     */
    private func createViewportBufs() {
        // create vertex buffer
        let vertices: [Vertex] = [
            Vertex(position: SIMD4<Float>(-1, 1, 0, 1), textureCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), textureCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD4<Float>(1, 1, 0, 1), textureCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD4<Float>(1, -1, 0, 1), textureCoord: SIMD2<Float>(1, 1)),
        ]
        
        let vertexBufSz = vertices.count * MemoryLayout<Vertex>.stride
        self.viewportVertexBuf = self.device?.makeBuffer(bytes: vertices, length: vertexBufSz)!
        
        // also, allocate the uniforms buffer
        var uniformViewport = Uniform()
        uniformViewport.projection = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        self.viewportUniformBuf = self.device?.makeBuffer(bytes: &uniformViewport,
                                                          length: MemoryLayout<Uniform>.stride)!
    }
    
    /**
     * Updates the viewport drawing pipeline state.
     */
    private func createViewportPipelineState() throws {
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = .bgr10a2Unorm
        desc.depthAttachmentPixelFormat = .invalid
    
        desc.vertexFunction = self.library.makeFunction(name: "textureMapVtx")!
        desc.fragmentFunction = self.library.makeFunction(name: "textureMapFrag")!
        
        desc.vertexDescriptor = Vertex.makeDescriptor()
    
        // create the pipeline state
        self.viewportPipelineState = try self.device!.makeRenderPipelineState(descriptor: desc)
    }
    
    /**
     * Draw the viewport texture
     */
    private func drawViewport(_ encoder: MTLRenderCommandEncoder) throws {
        guard self.viewportTexture != nil else {
            return
        }
        guard let state = self.viewportPipelineState else {
            throw Errors.noPipelineState
        }
        
        encoder.pushDebugGroup("RenderViewport")
        
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(self.viewportTexture!, index: 0)
        encoder.setVertexBuffer(self.viewportVertexBuf!, offset: 0, index: 0)
        encoder.setVertexBuffer(self.viewportUniformBuf!, offset: 0, index: 1)
        
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32,
                                      indexBuffer: self.quadIndexBuf!, indexBufferOffset: 0)
        
        encoder.popDebugGroup()
    }
    
    /**
     * Updates the current viewport rect.
     */
    func setViewport(_ viewport: CGRect, _ callback: @escaping (Result<Void, Error>) -> Void) {
        self.viewport = viewport
        
        // ensure there is a renderer
        guard self.renderer != nil else {
            return callback(.success(Void()))
        }
        
        // request resize from renderer
        self.renderer!.setViewport(self.viewport) {
            callback($0)
            
            // force re-display of view
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
        }
    }
    
    /**
     * Creates the viewport texture from a shared texture handle.
     */
    private func makeViewportTex(_ handle: MTLSharedTextureHandle) throws {
        // create the texture
        guard let texture = self.device?.makeSharedTexture(handle: handle) else {
            throw Errors.makeSharedTextureFailed
        }
        
        self.requestXpcRedraw() { res in
            switch res {
            case .success():
                self.viewportTexture = texture
            case .failure(let error):
                DDLogError("Failed to draw: \(error)")
            }
        }
    }
    
    // MARK: - Renderer
    /// Renderer instance currently being used
    private var renderer: DisplayImageRenderer? = nil
    
    /**
     * Instantiates a new renderer for the current Metal device.
     */
    private func createRenderer() {
        self.renderer = nil
        
        RenderManager.shared.getDisplayRenderer(self.device) { [weak self] res in
            do {
                // get the renderer
                let renderer = try res.get()
                self?.renderer = renderer
                
                // prepare it for display
                DispatchQueue.main.async {
                    self?.updateViewportSize()
                }
            } catch {
                DDLogError("Failed to get renderer: \(error)")
            }
        }
    }
    
    /**
     * Resize the viewport texture to fill the view.
     */
    private func updateViewportSize() {
        // calculate new size (including title bar insets, at backing store pixel scale)
        let newSize = self.frame.size
        let scaledSize = self.convertToBacking(newSize)
        
        DDLogDebug("Resizing viewport to: \(newSize) (scaled \(scaledSize))")
        
        // ensure the viewport actually changed
        if scaledSize.width == CGFloat(self.viewportTexture?.width ?? 0),
           scaledSize.height == CGFloat(self.viewportTexture?.height ?? 0) {
            return
        }
        
        // request renrerer resizes viewport (if different than current viewport texture size)
        self.renderer?.getOutputTexture(scaledSize, viewport: self.viewport) {
            do {
                let handle = try $0.get()
                try self.makeViewportTex(handle)
            } catch {
                DDLogError("Failed to update viewport size: \(error)")
            }
        }
    }
    
    /**
     * Request that the render service redraws.
     *
     * This runs asynchronously; the view will however be redisplayed once the draw completes. The callback is executed before the
     * view is displayed.
     */
    private func requestXpcRedraw(_ callback: @escaping (Result<Void, Error>) -> Void) {
        self.renderer?.redraw() { res in
            callback(res)
            
            do {
                let _ = try res.get()
                
                DispatchQueue.main.async {
                    self.shouldDrawViewport = true
                    self.needsDisplay = true
                }
                
                NotificationCenter.default.post(name: .renderViewUpdatedImage, object: self)
            } catch {
                DDLogError("Redraw failed: \(error)")
            }
        }
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// No current render descriptor
        case noRenderPassDescriptor
        /// Failled to create a texture
        case makeTextureFailed
        /// Could not create a local texture handle from an existing shared texture
        case makeSharedTextureFailed
        /// Failed to create a command buffer
        case makeCommandBufferFailed
        /// Failed to create a command encoder with the given descriptor
        case makeRenderCommandEncoderFailed(_ desc: MTLRenderPassDescriptor)
        /// There isn't a renderer instance available
        case noRenderer
        /// There isn't an allocated pipeline state
        case noPipelineState
    }

    // MARK: - Types
    /**
     * Texture map vertex buffer type
     */
    private struct Vertex {
        /// Screen position (x, y, z, W) of the vertex
        var position = SIMD4<Float>()
        /// Texture coordinate (x, y)
        var textureCoord = SIMD2<Float>()
        
        static func makeDescriptor() -> MTLVertexDescriptor {
            let vertexDesc = MTLVertexDescriptor()
            
            vertexDesc.attributes[0].format = .float4
            vertexDesc.attributes[0].bufferIndex = 0
            vertexDesc.attributes[0].offset = 0
            
            vertexDesc.attributes[1].format = .float2
            vertexDesc.attributes[1].bufferIndex = 0
            vertexDesc.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
            
            vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
            
            return vertexDesc
        }
    }
    
    /**
     * Texture map vertex uniforms
     */
    private struct Uniform {
        /// Projection matrix
        var projection = simd_float4x4()
    }
}

internal extension Notification.Name {
    /// Image render view has rendered full image data via the viewport.
    static let renderViewUpdatedImage = Notification.Name("me.tseifert.smokeshed.renderview.updated")
}
