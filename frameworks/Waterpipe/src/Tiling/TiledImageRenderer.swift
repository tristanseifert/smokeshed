//
//  TiledImageRenderer.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200802.
//

import Foundation
import simd
import Metal

import CocoaLumberjackSwift

public class TiledImageRenderer {
    /// Device used for drawing the tiled image
    private(set) public var device: MTLDevice
    /// Pipeline state
    private var state: MTLRenderPipelineState! = nil
    
    /// Index buffer for drawing full screen quad
    private var quadIndexBuf: MTLBuffer! = nil
    
    // MARK: - Initialization
    /// Shader code library
    private var library: MTLLibrary!
    
    /**
     * Creates a new tiled image renderer bound to the specified Metal device.
     */
    public init(device: MTLDevice) throws {
        self.device = device
        
        let thisBundle = Bundle(for: type(of: self))
        
        // create shader library and quad buffers
        self.library = try device.makeDefaultLibrary(bundle: thisBundle)
        
        let indexData: [UInt32] = [0, 1, 2, 2, 1, 3]
        let indexBufSz = indexData.count * MemoryLayout<UInt32>.stride
        self.quadIndexBuf = self.device.makeBuffer(bytes: indexData, length: indexBufSz)!
        
        // set up the pipeline descriptor
        let desc = MTLRenderPipelineDescriptor()
        desc.sampleCount = 1
        desc.colorAttachments[0].pixelFormat = .rgba32Float
        desc.depthAttachmentPixelFormat = .invalid
    
        desc.vertexFunction = self.library.makeFunction(name: "tiledImageRenderVtx")!
        desc.fragmentFunction = self.library.makeFunction(name: "tiledImageRenderFrag")!
        
        desc.vertexDescriptor = Vertex.makeDescriptor()
        
        self.state = try self.device.makeRenderPipelineState(descriptor: desc)
    }
    
    // MARK: - Drawing
    /**
     * Draws the given view into the tiled image.
     *
     * - Parameter image: Tiled image to draw
     * - Parameter region: Region of the tiled image that is visible. It is drawn to fill the viewport.
     * - Parameter encoder: Render command encoder used for drawing
     */
    public func draw(image: TiledImage, region: MTLRegion, outputSize: CGSize, _ encoder: MTLRenderCommandEncoder) throws {
        // calculate the transform matrix
        var matrix = simd_float4x4(diagonal: SIMD4<Float>(repeating: 1))
        
        // origin X offset
        let xTranslate = CGFloat(region.origin.x) / outputSize.width
        matrix.columns.0[3] = Float(xTranslate)
        
        // origin Y offset
        let yTranslate = CGFloat(region.origin.y) / outputSize.height
        matrix.columns.1[3] = -Float(yTranslate)

        // scale pixel coords to output view
//        matrix.columns.0[0] = 1 / Float(outputSize.width / outputSize.height)
        
//        matrix.columns.0[0] = 1.0 / Float(outputSize.width) // x scale
//        matrix.columns.0[3] = -0.5 // x translate
//
//        matrix.columns.1[1] = 1.0 / Float(outputSize.height) // y scale
//        matrix.columns.1[3] = -0.5 // y translate
        
        // draw it
        let size = SIMD2<Float>(Float(outputSize.width), Float(outputSize.height))
        let uniform = Uniform(projection: matrix, viewport: size, tileSize: UInt32(image.tileSize))
        try self.draw(image: image, uniform: uniform, encoder)
    }
    
    /**
     * Draws the tiled image using the given transformation matrix.
     *
     * - Parameter image: Tiled image to draw
     * - Parameter uniform: Uniform information, including projection matrix
     * - Parameter encoder: Render command encoder used for drawing
     */
    private func draw(image: TiledImage, uniform: Uniform, _ encoder: MTLRenderCommandEncoder) throws {
        encoder.pushDebugGroup("TiledImageRenderer.draw")
        
        // make uniform buffer
        var uniform = uniform
        let uniformBuf = self.device.makeBuffer(bytes: &uniform,
                                                length: MemoryLayout<Uniform>.stride)!
        
        // build the per-vertex data and index buffers
        let indexBuf = try self.makeIndexBuf(image)
        let vertexBuf = try self.makeVertexBuf(image)
        
        // prepare pipeline state
        encoder.setRenderPipelineState(self.state!)
        encoder.setFragmentTexture(image.texture!, index: 0)
        
        encoder.setVertexBuffer(vertexBuf, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuf, offset: 0, index: 1)
        
        // draw
        let numTileIndices = image.numTiles * 6
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: numTileIndices,
                                      indexType: .uint32, indexBuffer: indexBuf,
                                      indexBufferOffset: 0)
        
        // clean up
        encoder.popDebugGroup()
    }
    
    /**
     * Creates a buffer of vertex data for the given tiled image.
     */
    private func makeVertexBuf(_ image: TiledImage) throws -> MTLBuffer {
        var data: [Vertex] = []
        
        // add entries for each tile
        for i in 0..<image.numTiles {
            let visibleRegion = image.visibleRegionForTile(i)!
            let visible = SIMD2<Float>(Float(visibleRegion.width), Float(visibleRegion.height))
            
            let origin = image.originForTile(i)!
            
            // these are screen space coords
            let positions = [
                (SIMD4<Float>(-1, 1, 0, 1), SIMD2<Float>(0, 0)),
                (SIMD4<Float>(-1, -1, 0, 1), SIMD2<Float>(0, 1)),
                (SIMD4<Float>(1, 1, 0, 1), SIMD2<Float>(1, 0)),
                (SIMD4<Float>(1, -1, 0, 1), SIMD2<Float>(1, 1))
            ]
            for pos in positions {
                // transform the coordinates into absolute pixel space
                var vertexPos = pos.0
                
                vertexPos.x *= (Float(image.tileSize) / 2.0)
                vertexPos.x += (Float(image.tileSize) / 2.0)
                vertexPos.y *= (Float(image.tileSize) / 2.0)
                vertexPos.y += (Float(image.tileSize) / 2.0)
                
                vertexPos.x += Float(origin.x)
                vertexPos.y += Float(origin.y)
                
                let vertex = Vertex(position: vertexPos, textureCoord: pos.1,
                                    visibleRegion: visible, slice: i)
                data.append(vertex)
            }
        }
        
        // create a buffer
        let vertexBufSz = data.count * MemoryLayout<Vertex>.stride
        return self.device.makeBuffer(bytes: data, length: vertexBufSz)!
    }
    
    /**
     * Creates the index buffer for rendering the tiled image.
     */
    private func makeIndexBuf(_ image: TiledImage) throws -> MTLBuffer {
        var indexData: [UInt32] = []
        
        // add six indices for each tile
        for i in 0..<image.numTiles {
            // vertex order for one quad
            let pattern: [UInt32] = [0, 1, 2, 2, 1, 3]
            pattern.forEach {
                indexData.append($0 + UInt32(i * 4))
            }
        }
        
        // create buffer
        let indexBufSz = indexData.count * MemoryLayout<UInt32>.stride
        return self.device.makeBuffer(bytes: indexData, length: indexBufSz)!
    }
    
    // MARK: - Types
    /// Vertex buffer entry
    private struct Vertex {
        public init(position: SIMD4<Float>, textureCoord: SIMD2<Float>, visibleRegion: SIMD2<Float>, slice: Int) {
            self.position = position
            self.textureInfo = SIMD4<Float>(textureCoord.x, textureCoord.y, visibleRegion.x,
                                            visibleRegion.y)
            self.slice = UInt32(slice)
        }
        
        /// Screen position (x, y, z, W) of the vertex
        var position = SIMD4<Float>()
        /// Texture coordinate (x,y) and visible texture region (z,w)
        var textureInfo = SIMD4<Float>()
        /// Texture slice to sample
        var slice: UInt32 = 0
        
        fileprivate static func makeDescriptor() -> MTLVertexDescriptor {
            let vertexDesc = MTLVertexDescriptor()
            
            vertexDesc.attributes[0].format = .float4
            vertexDesc.attributes[0].bufferIndex = 0
            vertexDesc.attributes[0].offset = 0
            
            vertexDesc.attributes[1].format = .float4
            vertexDesc.attributes[1].bufferIndex = 0
            vertexDesc.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
            
            vertexDesc.attributes[2].format = .uint
            vertexDesc.attributes[2].bufferIndex = 0
            vertexDesc.attributes[2].offset = MemoryLayout<SIMD4<Float>>.stride * 2
            
            vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
            
            return vertexDesc
        }
    }
    
    /// Uniform buffer entry
    private struct Uniform {
        /// Projection matrix (to convert from a pixel coordinate space to the screen coordinate space)
        var projection = simd_float4x4()
        /// Viewport size
        var viewport = SIMD2<Float>()
        /// Size of the square tiles making up the image (in pixels)
        var tileSize: UInt32 = 0
    }
}
