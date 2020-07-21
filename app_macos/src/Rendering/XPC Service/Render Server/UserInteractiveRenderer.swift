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
    private var device: MTLDevice! = nil
    
    /// Command queue for rendering
    private var queue: MTLCommandQueue! = nil
    
    /// Pipeline state
    private var state: MTLRenderPipelineState! = nil
    
    /// Output texture
    private var outTexture: MTLTexture? = nil
    
    /// Shader code library
    private var library: MTLLibrary! = nil
    
    // MARK: - Initialization
    /**
     * Creates an user-interactive renderer that uses the given graphics device.
     */
    init(_ device: MTLDevice) throws {
        super.init()
        self.device = device
        
        DDLogVerbose("Created UI renderer for device \(device)")
        
        // create command queue
        self.queue = self.device.makeCommandQueue()!
        self.queue.label = String(format: "UserInteractiveRenderer-%@", self.identifier.uuidString)
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
    func setRenderDescriptor(_ descriptor: [AnyHashable : Any], withReply reply: @escaping (Error?) -> Void) {
        DDLogVerbose("Render descriptor: \(descriptor)")
    }
    
    /**
     * Sets the visible segment of the image.
     */
    func setViewport(_ visible: CGRect, withReply reply: @escaping (Error?) -> Void) {
        DDLogVerbose("Viewport: \(visible)")
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
            try self.draw() {
                return reply(nil)
            }
        } catch {
            DDLogError("Failed to redraw: \(error)")
            return reply(error)
        }
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
     * Drawing that shit
     */
    private func draw(_ completion: @escaping () -> Void) throws {
        guard let buffer = self.queue.makeCommandBuffer() else {
            throw Errors.makeCommandBufferFailed
        }
        
        // render the final pass to the output texture
        let descriptor = try self.renderPassDescriptor()
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw Errors.makeRenderCommandEncoderFailed(descriptor)
        }
        
        buffer.addCompletedHandler() { _ in
            completion()
        }
        
        // TODO: drawing
        
        encoder.endEncoding()
        buffer.commit()
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
    
    // MARK: - Errors
    enum Errors: Error {
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
    }
}
