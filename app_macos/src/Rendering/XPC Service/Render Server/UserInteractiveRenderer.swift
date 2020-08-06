//
//  UserInteractiveRenderer.swift
//  Renderer
//
//  Created by Tristan Seifert on 20200719.
//

import Foundation

import Metal
import MetalKit

import Waterpipe
import CocoaLumberjackSwift

/**
 * Implements a renderer optimized for user interactive display.
 */
internal class UserInteractiveRenderer: Renderer, RendererUserInteractiveXPCProtocol {
    /// Device used for rendering
    private(set) internal var device: MTLDevice
    
    /// Command queue for rendering
    private var queue: MTLCommandQueue!
    /// Pipeline state
    private var state: MTLRenderPipelineState!
    /// Output texture
    private var outTexture: MTLTexture? = nil
    /// Shader code library
    private var library: MTLLibrary! = nil
    
    /// Image rendering pipeline
    private var pipeline: RenderPipeline! = nil
    /// Current image
    private var renderImage: RenderPipelineImage? = nil
    /// Render pipeline state (for the current image)
    private var pipelineState: RenderPipelineState? = nil
    /// Tiled image for the renderer output
    private var renderOutput: TiledImage? = nil
    
    /// Current viewport
    private(set) internal var viewport: CGRect = .zero
    
    /// Drawing tiled images
    private var tiledImageDrawer: TiledImageRenderer!

    // MARK: - Initialization
    /**
     * Creates an user-interactive renderer that uses the given graphics device.
     */
    init(_ device: MTLDevice) throws {
        self.device = device
        super.init()
        
        DDLogVerbose("Created UI renderer for device \(device)")

        // create render pipeline
        self.pipeline = RenderPipeline(device: device)

        // create command queue
        self.queue = self.device.makeCommandQueue()!
        self.queue.label = String(format: "UserInteractiveRenderer-%@", self.identifier.uuidString)
        
        // tiled image drawer
        self.tiledImageDrawer = try TiledImageRenderer(device: device)
    }
    
    /**
     * Closes all graphics resources.
     */
    deinit {
        DDLogVerbose("Releasing UI renderer \(self)")
    }
    
    /**
     * Creates a new viewport texture of the given size.
     */
    private func makeViewportTexture(_ size: CGSize) throws -> MTLTexture {
        // set up texture descriptor
        let desc = MTLTextureDescriptor()
        
        desc.width = Int(size.width)
        desc.height = Int(size.height)
        
        desc.allowGPUOptimizedContents = true
        
        desc.pixelFormat = .bgr10a2Unorm
        desc.storageMode = .private
        desc.usage = [.renderTarget, .shaderRead]
        
        // create such a texture
        guard let texture = self.device.makeSharedTexture(descriptor: desc) else {
            throw Errors.outputTextureAllocFailed(desc)
        }
        
        return texture
    }
    
    // MARK: - XPC interface
    /**
     * Define the render descriptor for the image.
     */
    func setRenderDescriptor(_ descriptor: RenderDescriptor, withReply reply: @escaping (Error?) -> Void) {
        let progress = Progress(totalUnitCount: 2)
        
        do {
            // get new image
            progress.becomeCurrent(withPendingUnitCount: 1)
            if descriptor.discardCaches || self.renderImage == nil ||
                self.renderImage?.url != descriptor.url {
                let image = try RenderPipelineImage(url: descriptor.url)
                self.pipelineState = try self.pipeline.createState(image: image)
                
                self.renderImage = image
            }
            guard self.renderImage != nil, self.pipelineState != nil else {
                throw Errors.imageCreateFailed
            }
            progress.resignCurrent()

            // allocate new output texture if needed
            progress.becomeCurrent(withPendingUnitCount: 1)
            if self.renderOutput == nil ||
               self.renderOutput!.imageSize != self.renderImage!.size {
                self.renderOutput = nil
                guard let image = TiledImage(device: self.device, forImageSized: self.renderImage!.size, tileSize: 512) else {
                    throw Errors.renderOutputAllocFailed
                }
                self.renderOutput = image
            }
            progress.resignCurrent()
            
            reply(nil)
        } catch {
            DDLogError("Failed to set descriptor: \(error) (desc: \(descriptor), renderer \(self))")
            reply(error)
        }
    }
    
    /**
     * Sets the visible segment of the image.
     */
    func setViewport(_ visible: CGRect, withReply reply: @escaping (Error?) -> Void) {
        DDLogVerbose("Viewport: \(visible)")
        self.viewport = visible
        
        reply(nil)
    }
    
    /**
     * Resizes the output texture.
     */
    func resizeTexture(size newSize: CGSize, viewport: CGRect, withReply reply: @escaping (Error?, MTLSharedTextureHandle?) -> Void) {
        DDLogVerbose("New texture size: \(newSize), viewport is \(viewport)")
        
        // try to create texture
        do {
            // allocate new texture if needed
            if self.outTexture == nil ||
               self.outTexture?.width ?? 0 != Int(newSize.width) ||
               self.outTexture?.height ?? 0 != Int(newSize.height) {
                self.outTexture = try self.makeViewportTexture(newSize)
            }
            
            // get shared texture handle and render to it
            guard let handle = self.outTexture?.makeSharedTextureHandle() else {
                throw Errors.makeSharedTextureHandleFailed
            }
            
            return reply(nil, handle)
        } catch {
            DDLogError("Failed to resize texture to \(newSize): \(error)")
            return reply(error, nil)
        }
    }
    
    /**
     * Performs a render pass.
     */
    func redraw(withReply reply: @escaping (Error?) -> Void) {
        // any drawing commands that could fail
        do {
            try self.draw()
        } catch {
            DDLogError("Failed to redraw: \(error)")
            return reply(error)
        }

        // success rendering
        return reply(nil)
    }
    
    /**
     * Releases the renderer.
     */
    func destroy() {
        NotificationCenter.default.post(name: .rendererReleased, object: nil, userInfo: [
            "identifier": self.identifier
        ])
    }
    
    // MARK: - Drawing    
    /**
     * Drawing that shit, happens synchronously
     */
    private func draw() throws {
        // re-render the pipeline state
        guard let pipelineState = self.pipelineState else {
            return
        }

        try self.pipeline.render(pipelineState, self.renderOutput!)

        // draw the output image
        guard let buffer = self.queue.makeCommandBuffer() else {
            throw Errors.makeCommandBufferFailed
        }

        let descriptor = try self.renderPassDescriptor()
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw Errors.makeRenderCommandEncoderFailed(descriptor)
        }
        
        try self.drawRenderTexture(encoder)

        encoder.endEncoding()
        buffer.commit()

        // wait for render to texture to finish
        buffer.waitUntilCompleted()
    }

    /**
     * Creates a render pass descriptor.
     */
    private func renderPassDescriptor() throws -> MTLRenderPassDescriptor {
        guard self.outTexture != nil else {
            throw Errors.invalidOutputTexture
        }
        
        let pass = MTLRenderPassDescriptor()
        
        // size based on texture
        pass.renderTargetWidth = self.outTexture!.width
        pass.renderTargetHeight = self.outTexture!.height
        
        // clear on load and write to the texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].texture = self.outTexture!
        
        // clear to black with alpha 1
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0,
                                                            alpha: 0)
        
        return pass
    }
    
    /**
     * Draws the tiled image with the currently specified viewport.
     */
    private func drawRenderTexture(_ encoder: MTLRenderCommandEncoder) throws {
        var region = MTLRegion()
        region.origin = MTLOriginMake(Int(self.viewport.origin.x), Int(self.viewport.origin.y), 0)
        region.size = MTLSizeMake(Int(self.viewport.size.width), Int(self.viewport.size.height), 1)
        
        try self.tiledImageDrawer.draw(image: self.renderOutput!, region: region,
                                       outputSize: CGSize(width: self.outTexture!.width,
                                                          height: self.outTexture!.height),
                                       encoder)
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to allocate output tiled image
        case renderOutputAllocFailed
        /// Failed to allocate output texture with the given descriptor
        case outputTextureAllocFailed(_ desc: MTLTextureDescriptor)
        /// Failed to create a shared texture handle
        case makeSharedTextureHandleFailed
        /// Render pass descriptor is invalid
        case invalidRenderPassDescriptor
        /// The output texture is invalid.
        case invalidOutputTexture
        /// Failed to allocate a command buffer
        case makeCommandBufferFailed
        /// Failed to make a command encoder
        case makeRenderCommandEncoderFailed(_ descriptor: MTLRenderPassDescriptor)
        
        /// Couldn't create the image when setting render descriptor
        case imageCreateFailed
    }
}
