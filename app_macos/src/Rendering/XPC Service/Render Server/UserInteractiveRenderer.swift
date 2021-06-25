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
    
    /// Pipeline state
    private var state: MTLRenderPipelineState!
    
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
    
    /// Texture clearer
    private var textureClearer: TextureFiller!

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
        
        // tiled image drawer and texture filler
        self.textureClearer = try TextureFiller(device: device)
    }
    
    /**
     * Closes all graphics resources.
     */
    deinit {
        DDLogVerbose("Releasing UI renderer \(self)")
    }
    
    // MARK: - XPC interface
    /**
     * Define the render descriptor for the image.
     */
    func setRenderDescriptor(_ descriptor: RenderDescriptor, withReply reply: @escaping (Error?, TiledImage.TiledImageArchive?) -> Void) {
        let progress = Progress(totalUnitCount: 2)
        
        // start security-scoped access to image
        let relinquish = descriptor.url.startAccessingSecurityScopedResource()
        
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
                guard let image = TiledImage(device: self.device, forImageSized: self.renderImage!.size, tileSize: 512, .rgba32Float, true) else {
                    throw Errors.renderOutputAllocFailed
                }
                self.renderOutput = image
            }
            progress.resignCurrent()
            
            reply(nil, self.renderOutput!.toArchive())
        } catch {
            DDLogError("Failed to set descriptor: \(error) (desc: \(descriptor), renderer \(self))")
            reply(error, nil)
        }
        
        // release security-scoped access if it was required earlier
        if relinquish {
            descriptor.url.stopAccessingSecurityScopedResource()
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
