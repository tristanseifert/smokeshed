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
    
    /// Vertex buffers (contains screen space coords and texture coords)
    private var quadVertexBuf: MTLBuffer! = nil
    /// Uniform buffer (contains identity projection matrix)
    private var quadUniformBuf: MTLBuffer! = nil
    /// Index buffer for drawing full screen quad
    private var quadIndexBuf: MTLBuffer! = nil
    
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
        
        // create library for shader code
        self.library = self.device!.makeDefaultLibrary()!
        
        // create index buffer for a full screen quad
        let indexData: [UInt32] = [0, 1, 2, 2, 1, 3]
        
        let indexBufSz = indexData.count * MemoryLayout<UInt32>.stride
        self.quadIndexBuf = self.device.makeBuffer(bytes: indexData, length: indexBufSz)!
        
        // create uniform buffer (projection matrix is diagonal identity matrix)
        var uniform = Uniform()
        uniform.projection = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        self.quadUniformBuf = self.device.makeBuffer(bytes: &uniform,
                                                     length: MemoryLayout<Uniform>.stride)!
        
        // create vertex buffer
        let vertices: [Vertex] = [
            Vertex(position: SIMD4<Float>(-1, 1, 0, 1), textureCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), textureCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD4<Float>(1, 1, 0, 1), textureCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD4<Float>(1, -1, 0, 1), textureCoord: SIMD2<Float>(1, 1)),
        ]
        
        let vertexBufSz = vertices.count * MemoryLayout<Vertex>.stride
        self.quadVertexBuf = self.device.makeBuffer(bytes: vertices, length: vertexBufSz)!
        
        // set up the pipeline descriptor
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = .bgr10a2Unorm
        desc.depthAttachmentPixelFormat = .invalid
    
        desc.vertexFunction = self.library.makeFunction(name: "textureMapVtx")!
        desc.fragmentFunction = self.library.makeFunction(name: "textureMapFrag")!
        
        desc.vertexDescriptor = Vertex.makeDescriptor()
        
        self.state = try self.device.makeRenderPipelineState(descriptor: desc)
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
