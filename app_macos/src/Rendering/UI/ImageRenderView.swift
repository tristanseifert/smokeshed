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
                self.thumbSurface = nil
                self.thumbTexture = nil
            }

            // redraw UI, starting with the thumb image
            self.drawThumb = true
            self.needsDisplay = true
        }
    }
    
    /**
     * Thumbnail image to draw while waiting for the renderer to complete its first pass
     */
    internal var thumbSurface: IOSurface? = nil {
        didSet {
            // update the background texture
            self.updateThumbTexture()
            // do not force re-display; this happens once the new texture is computed
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
        
        // cached textures
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
    }
    
    /**
     * Updates the thumbnail texture
     */
    private func updateThumbTexture() {
        // release the old texture
        self.thumbTexture = nil
        
        guard let surface = self.thumbSurface else {
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
            return
        }
        
        // create a texture descriptor based on the surface
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: surface.width,
                                                            height: surface.height,
                                                            mipmapped: false)

        // create a metal texture from that surface
        guard let surfaceTex = self.device?.makeTexture(descriptor: desc, 
                                                        iosurface: surface.surfaceRef,
                                                        plane: 0) else {
            DDLogError("Failed to create thumb texture from surface \(surface) (desc \(desc))")
            return
        }

        // create a new output texture (that will contain the blurred version)
        guard let output = self.device?.makeTexture(descriptor: desc) else {
            DDLogError("Failed to create thumb output texture (desc \(desc))")
            return
        }

        // build the blur pass command buffer
        guard let buffer = self.queue.makeCommandBuffer() else {
            DDLogError("Failed to get command buffer from \(String(describing: self.queue))")
            return
        }
        buffer.pushDebugGroup("ThumbSurfaceBlur")
        
        let blur = MPSImageGaussianBlur(device: self.device!, sigma: 15)
        blur.encode(commandBuffer: buffer, sourceTexture: surfaceTex,
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
        self.updateThumbTexture()
        
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
    /// Should the thumbnail image be drawn? This is cleared once the renderer returns.
    private var drawThumb: Bool = true
    
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
        
        // set up render state
        self.setupBackgroundThumb(encoder)
        
        // draw
        if self.thumbTexture != nil, self.drawThumb {
            self.drawBackgroundThumb(encoder)
        }
        
        // finish encoding the pass and present it
        encoder.endEncoding()
        
        if let drawable = self.currentDrawable {
            buffer.present(drawable)
        }
        
        // commit the buffer to display
        buffer.commit()
    }
    
    // MARK: Thumbnail
    /**
     * Perform setup for drawing the background thumbnail
     */
    private func setupBackgroundThumb(_ encoder: MTLRenderCommandEncoder) {
        
    }
    
    /**
     * Draw the blurred background texture
     */
    private func drawBackgroundThumb(_ encoder: MTLRenderCommandEncoder) {
        // create pipeline descriptor
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm
        desc.depthAttachmentPixelFormat = .invalid
    
        desc.vertexFunction = self.library.makeFunction(name: "textureMapVtx")
        desc.fragmentFunction = self.library.makeFunction(name: "textureMapFrag")
    
        // create pipeline state and encode draw commands
        do {
            // create the pipeline state
            let state = try encoder.device.makeRenderPipelineState(descriptor: desc)
        
            // encode draw command
            encoder.pushDebugGroup("RenderThumb")
            
            encoder.setRenderPipelineState(state)
            encoder.setFragmentTexture(self.thumbTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, 
                                   vertexCount: 4, instanceCount: 1)
            
            encoder.popDebugGroup()
        } catch {
            DDLogError("Failed to draw thumb quad: \(error)")
        }
    }
}
