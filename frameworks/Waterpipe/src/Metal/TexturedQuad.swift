//
//  TexturedQuad.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200721.
//

import Foundation

import Metal
import MetalKit
import simd

/**
 * Handles drawing a single texture into a quad.
 */
public class TexturedQuad {
    /// Current device
    private var device: MTLDevice! = nil
    /// Shader code library
    private var library: MTLLibrary! = nil
    
    /// Pipeline state
    private var state: MTLRenderPipelineState! = nil
    
    /// Vertices used for drawing the quad
    private var vertexData: [Vertex] = []
    /// Vertex buffers (contains screen space coords and texture coords)
    private var quadVertexBuf: MTLBuffer! = nil
    
    /// Shader uniforms
    private var uniforms: Uniform = Uniform()
    /// Uniform buffer (contains identity projection matrix)
    private var quadUniformBuf: MTLBuffer! = nil
    /// Index buffer for drawing full screen quad
    private var quadIndexBuf: MTLBuffer! = nil
    
    // MARK: - Initialization
    /**
     * Sets up a new textured quad drawing helper on the given device.
     */
    public init(_ device: MTLDevice) throws {
        self.device = device
        
        // load shaders
        self.library = try device.makeDefaultLibrary(bundle: Bundle(for: type(of: self)))
        
        // create index buffer (for one quad)
        let indexData: [UInt32] = [0, 1, 2, 2, 1, 3]
        
        let indexBufSz = indexData.count * MemoryLayout<UInt32>.stride
        self.quadIndexBuf = self.device.makeBuffer(bytes: indexData, length: indexBufSz)!
        
        // create uniform buffer (projection matrix is diagonal identity matrix)
        self.projection = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        // create vertex buffer (full screen quad)
        self.vertices = [
            Vertex(position: SIMD4<Float>(-1, 1, 0, 1), textureCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), textureCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD4<Float>(1, 1, 0, 1), textureCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD4<Float>(1, -1, 0, 1), textureCoord: SIMD2<Float>(1, 1)),
        ]
        
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
    
    // MARK: - Properties
    /**
     * Projection matrix used to transform vertex coordinates into screen space coordinates
     */
    public var projection: simd_float4x4 {
        get {
            return self.uniforms.projection
        }
        set {
            self.uniforms.projection = newValue
            self.quadUniformBuf = self.device.makeBuffer(bytes: &self.uniforms,
                                                         length: MemoryLayout<Uniform>.stride)!
        }
    }
    
    /**
     * Array of vertices to use in drawing the quad. This must contain four vertices exactly.
     */
    public var vertices: [Vertex] {
        get {
            return self.vertexData
        }
        set {
            precondition(newValue.count == 4, "Invalid vertex count: \(newValue.count)")
            self.vertexData = newValue
            
            let vertexBufSz = self.vertexData.count * MemoryLayout<Vertex>.stride
            self.quadVertexBuf = self.device.makeBuffer(bytes: self.vertexData, length: vertexBufSz)!
        }
    }
    
    // MARK: - Drawing
    /**
     * Encodes display of the given texture into the command encoder.
     */
    public func encode(_ encoder: MTLRenderCommandEncoder, texture: MTLTexture) throws {
        encoder.pushDebugGroup("TexturedQuad.encode(_:, texture:)")
        
        encoder.setRenderPipelineState(self.state!)
        encoder.setFragmentTexture(texture, index: 0)
        
        encoder.setVertexBuffer(self.quadVertexBuf!, offset: 0, index: 0)
        encoder.setVertexBuffer(self.quadUniformBuf!, offset: 0, index: 1)
        
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32,
                                      indexBuffer: self.quadIndexBuf!, indexBufferOffset: 0)
        
        encoder.popDebugGroup()
    }
    
    // MARK: - Types
    /// Vertex buffer entry
    public struct Vertex {
        public init(position: SIMD4<Float>, textureCoord: SIMD2<Float>) {
            self.position = position
            self.textureCoord = textureCoord
        }
        
        /// Screen position (x, y, z, W) of the vertex
        var position = SIMD4<Float>()
        /// Texture coordinate (x, y)
        var textureCoord = SIMD2<Float>()
        
        fileprivate static func makeDescriptor() -> MTLVertexDescriptor {
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
    
    /// Uniform buffer entry
    private struct Uniform {
        /// Projection matrix
        var projection = simd_float4x4()
    }
}
