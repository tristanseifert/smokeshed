//
//  TextureFiller.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200805.
//

import Foundation
import Metal
import simd

import CocoaLumberjackSwift

public class TextureFiller {
    /// Device on which the filler operates
    private(set) public var device: MTLDevice
    
    /// Shader code library
    private var library: MTLLibrary
    /// Compute pipeline state
    private var state: MTLComputePipelineState
    
    /**
     * Initializes a new texture filler using the specified device.
     */
    public init(device: MTLDevice) throws {
        self.device = device
        
        // create the shader library and compute pipeline state
        let bundle = Bundle(for: type(of: self))
        self.library = try device.makeDefaultLibrary(bundle: bundle)
        
        // set up compute pipeline state
        guard let function = self.library.makeFunction(name: "fillTexture") else {
            throw Errors.failedLoadingFunction
        }
        
        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = function
        desc.buffers[0].mutability = .immutable
        
        self.state = try device.makeComputePipelineState(descriptor: desc, options: [],
                                                         reflection: nil)
        
    }
    
    // MARK: - Encoding
    /**
     * Encodes into the specified command buffer a series of texture clear commands.
     *
     * This function will synchronously invoke the provided closure, with a helper struct that provides functions that allow encoding
     * individual clear operations. This allows batching multiple clears into one buffer.
     */
    public func encode(into buffer: MTLCommandBuffer, _ callback: (TextureFillerOperators) -> Void) throws {
        precondition(buffer.device.registryID == self.device.registryID)
        
        // create command encoder
        guard let encoder = buffer.makeComputeCommandEncoder() else {
            throw Errors.failedMakeCommandEncoder
        }
        encoder.label = "TextureFiller.encode(_:_:)"
        
        // invoke the callback
        let ops = TextureFillerOperators(self, encoder)
        callback(ops)
        
        // complete encoding
        encoder.endEncoding()
    }
    
    /**
     * Encodes into the buffer the commands to fill the texture with the specified value.
     */
    private func encodeClear(encoder: MTLComputeCommandEncoder, _ texture: MTLTexture, _ value: SIMD4<Float>) {
        precondition(encoder.device.registryID == self.device.registryID)
        
        // calculate the threadgroup sizes
        let w = self.state.threadExecutionWidth
        let h = self.state.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
        // create a buffer with the info required by the compute functions
        var uniforms = Uniforms(fillValue: value)
        let uniformBuf = self.device.makeBuffer(bytes: &uniforms,
                                                length: MemoryLayout<Uniforms>.stride)
        
        // invoke the function
        encoder.setComputePipelineState(self.state)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(uniformBuf, offset: 0, index: 0)
        
        // encode the compute command
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    // MARK: - Types
    /// Helper struct for encode methods
    public struct TextureFillerOperators {
        /// Texture filler that owns this
        private(set) public var filler: TextureFiller
        /// Compute command encoder created specifically for this pass
        private var encoder: MTLComputeCommandEncoder
        
        fileprivate init(_ filler: TextureFiller, _ encoder: MTLComputeCommandEncoder) {
            self.filler = filler
            self.encoder = encoder
        }
        
        /**
         * Fills the entire texture with the specified value.
         */
        public func clear(texture: MTLTexture, _ value: SIMD4<Float>) {
            self.filler.encodeClear(encoder: self.encoder, texture, value)
        }
    }
    
    /// Uniforms passed to compute kernel
    private struct Uniforms {
        /// Fill value for the texture
        var fillValue = SIMD4<Float>()
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to load the compute function
        case failedLoadingFunction
        /// Failed to create a command encoder
        case failedMakeCommandEncoder
    }
}
