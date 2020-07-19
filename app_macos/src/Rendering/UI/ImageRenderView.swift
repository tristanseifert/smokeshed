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
    /**
     * Image to render in this view
     *
     * When set, a render job is kicked off automatically, if the image changed. If `nil` is set as the new image, all UI resources (and
     * the render job, if any) is deallocated.
     */
    internal var image: Image? = nil {
        didSet {
            // clear state if image was reset
            if self.image == nil {
                self.thumbTexture = nil
            }

            // redraw UI, starting with the thumb image
            self.drawThumb = true
            self.needsDisplay = true
        }
    }
    
    // MARK: - Setup
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
    }
    
    // MARK: - Metal resources
    /// Command queue used for display
    private var queue: MTLCommandQueue! = nil
    /// Shader library
    private var library: MTLLibrary! = nil

    /// Texture for the thumbnail image
    private var thumbTexture: MTLTexture? = nil
    
    /**
     * Invalidates all existing Metal resources.
     */
    private func invalidateMetalResources() {
        DDLogVerbose("Invalidating Metal state")
        
        // release command queues and buffers
        self.queue = nil
        
        // thumbnail data
        self.thumbIndexBuf = nil
        self.thumbVertexBuf = nil
        self.thumbUniformBuf = nil
        self.thumbTexture = nil
    }
    
    /**
     * Creates the Metal resources needed to display content on-screen.
     */
    private func createMetalResources() {
        precondition(self.device != nil, "Render device must be set")
        
        DDLogVerbose("Creating Metal state")
        
        // create command queue
        self.queue = self.device!.makeCommandQueue()!
        self.queue.label = String(format: "ImageRenderView-%@", self)
        
        // create library for shader code
        self.library = self.device!.makeDefaultLibrary()!
        
        // thumbnail stuff
        self.createThumbIndexBuf()
        self.updateThumbUniforms()
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
        // set up the render descriptor, command buffer and encoder
        guard let descriptor = self.currentRenderPassDescriptor else {
            DDLogError("Failed to get render pass descriptor for \(self)")
            return
        }
        guard let buffer = self.queue.makeCommandBuffer() else {
            DDLogError("Failed to get command buffer from \(String(describing: self.queue))")
            return
        }
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            DDLogError("Failed to get command encoder from \(String(describing: buffer))")
            return
        }
        
        // draw thumbnail
        if self.thumbTexture != nil, self.drawThumb {
            self.drawBackgroundThumb(encoder)
        }
        
        // if in live resize, draw blurred viewport texture
        if self.inLiveResize {
            
        }
        // otherwise, draw as-is
        else {
            
        }
        
        // finish encoding the pass and present it
        encoder.endEncoding()
        
        if let drawable = self.currentDrawable {
            buffer.present(drawable)
        }
        
        // commit the buffer to display
        buffer.commit()
    }
    
    // MARK: - Thumbnail
    /// Index buffer for triangle coordinates of the thumb
    private var thumbIndexBuf: MTLBuffer? = nil
    /// Vertex coordinate buffer for thumbnail
    private var thumbVertexBuf: MTLBuffer? = nil
    /// Uniform buffer for thumb rendering
    private var thumbUniformBuf: MTLBuffer? = nil
    
    /// Should the thumbnail image be drawn? This is cleared once the renderer returns.
    private var drawThumb: Bool = true
    
    /**
     * Updates the thumbnail to the given surface.
     */
    internal func updateThumb(_ surface: IOSurface) {
        // create the input texture from the surface
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: surface.width,
                                                            height: surface.height,
                                                            mipmapped: false)
        guard let surfaceTex = self.device?.makeTexture(descriptor: desc,
                                                        iosurface: surface.surfaceRef,
                                                        plane: 0) else {
            DDLogError("Failed to create thumb texture from surface \(surface) (desc \(desc))")
            return
        }
        
        // defer to the texture based creation logic
        self.updateThumb(surfaceTex)
    }
    
    /**
     * Updates the thumb given a generic texture as the input; an output texture is allocated.
     */
    internal func updateThumb(_ texture: MTLTexture) {
        DispatchQueue.global(qos: .userInitiated).async {
            // create a new output texture (that will contain the blurred version)
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                width: texture.width,
                                                                height: texture.height,
                                                                mipmapped: false)
            desc.usage.insert(.shaderWrite)
            desc.storageMode = .private
            
            guard let output = self.device?.makeTexture(descriptor: desc) else {
                DDLogError("Failed to create thumb output texture (desc \(desc))")
                return
            }
            
            // update vertex buffer and render the texture
            self.updateThumbUniforms()
            self.updateThumbVertexBuf(input: texture)
            self.updateThumbTexture(input: texture, output: output)
        }
    }
    
    /**
     * Updates the thumbnail texture
     */
    private func updateThumbTexture(input: MTLTexture, output: MTLTexture) {
        // release the old texture
        self.thumbTexture = nil

        // build the blur pass command buffer
        guard let buffer = self.queue.makeCommandBuffer() else {
            DDLogError("Failed to get command buffer from \(String(describing: self.queue))")
            return
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
     * Creates the thumbnail index buffer.
     */
    private func createThumbIndexBuf() {
        self.thumbIndexBuf = nil
        
        var indexData = [UInt32]()
        
        // first triangle: top left, bottom left, top right (CCW)
        indexData.append(0)
        indexData.append(1)
        indexData.append(2)
        
        // second triangle: top right, bottom left, bottom right (CCW)
        indexData.append(2)
        indexData.append(1)
        indexData.append(3)
        
        // create buffer
        let bufSize = indexData.count * MemoryLayout<UInt32>.stride
        self.thumbIndexBuf = self.device?.makeBuffer(bytes: indexData, length: bufSize)!
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
        
        var vertexData = [Vertex]()
        
        // texture coordinates are always constant
        let textureCoords = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1),
        ]
        
        var vertexCoords = [SIMD4<Float>]()
        
        // landscape images (width >= height)
        if input.width >= input.height {
            let edge = Float(0.9)
            let ratio = (Float(input.height) / Float(input.width)) * edge
            
            vertexCoords.append(SIMD4<Float>(-edge, ratio, 0, 1))
            vertexCoords.append(SIMD4<Float>(-edge, -ratio, 0, 1))
            vertexCoords.append(SIMD4<Float>(edge, ratio, 0, 1))
            vertexCoords.append(SIMD4<Float>(edge, -ratio, 0, 1))
        }
        // portrait images (height > width)
        else {
            let edge = Float(0.9)
            let ratio = (Float(input.width) / Float(input.height)) * edge
            
            vertexCoords.append(SIMD4<Float>(-ratio, edge, 0, 1))
            vertexCoords.append(SIMD4<Float>(-ratio, -edge, 0, 1))
            vertexCoords.append(SIMD4<Float>(ratio, edge, 0, 1))
            vertexCoords.append(SIMD4<Float>(ratio, -edge, 0, 1))
        }
        
        // fill vertex data
        for i in 0..<4 {
            vertexData.append(Vertex(position: vertexCoords[i],
                                          textureCoord: textureCoords[i]))
        }
        
        // create buffer
        let bufSize = vertexData.count * MemoryLayout<Vertex>.stride
        self.thumbVertexBuf = self.device?.makeBuffer(bytes: vertexData, length: bufSize)!
    }
    
    /**
     * Update thumbnail uniform buffer. Any time the view is resized, this is performed.
     */
    private func updateThumbUniforms() {
        // ensure this is always run on main thread (due to reading bounds)
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                self.updateThumbUniforms()
            }
        }
        
        // create an identity matrix
        var uniforms = Uniform()
        uniforms.projection = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        // correct for aspect ratio (x/y scale)
        uniforms.projection.columns.0[0] = 1 / Float(self.bounds.width / self.bounds.height)
        
        // compensate for the top inset from the titel bar
        if let safeArea = self.window?.contentView?.safeAreaInsets {
            let screenSpaceOffset = Float(safeArea.top / self.bounds.height)
            uniforms.projection.columns.1[3] = -screenSpaceOffset // translate
            uniforms.projection.columns.1[1] = 1 - (screenSpaceOffset / 2) // y scale
        }
        
        DDLogVerbose("Projection matrix: \(uniforms.projection)")
        
        // create buffer
        let bufSize = MemoryLayout<Uniform>.stride
        self.thumbUniformBuf = self.device?.makeBuffer(bytes: &uniforms,
                                                      length: bufSize)!
    }
    
    /**
     * Draw the blurred background texture
     */
    private func drawBackgroundThumb(_ encoder: MTLRenderCommandEncoder) {
        // create pipeline descriptor
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = self.colorPixelFormat
        desc.depthAttachmentPixelFormat = self.depthStencilPixelFormat
    
        desc.vertexFunction = self.library.makeFunction(name: "textureMapVtx")!
        desc.fragmentFunction = self.library.makeFunction(name: "textureMapFrag")!
        
        let vertexDesc = MTLVertexDescriptor()
        
        vertexDesc.attributes[0].format = .float4
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[0].offset = 0
        
        vertexDesc.attributes[1].format = .float2
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        
        vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
        
        desc.vertexDescriptor = vertexDesc
    
        // create pipeline state and encode draw commands
        do {
            // create the pipeline state
            let state = try encoder.device.makeRenderPipelineState(descriptor: desc)
        
            // encode draw command
            encoder.pushDebugGroup("RenderThumb")
            
            encoder.setRenderPipelineState(state)
            encoder.setFragmentTexture(self.thumbTexture!, index: 0)
            
            encoder.setVertexBuffer(self.thumbVertexBuf!, offset: 0, index: 0)
            encoder.setVertexBuffer(self.thumbUniformBuf!, offset: 0, index: 1)
            
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32,
                                          indexBuffer: self.thumbIndexBuf!, indexBufferOffset: 0)
            
            encoder.popDebugGroup()
        } catch {
            DDLogError("Failed to draw thumb quad: \(error)")
        }
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
    }
    
    /**
     * Texture map vertex uniforms
     */
    private struct Uniform {
        /// Projection matrix
        var projection = simd_float4x4()
    }
}
