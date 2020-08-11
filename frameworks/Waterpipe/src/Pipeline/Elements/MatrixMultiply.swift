//
//  MatrixMultiply.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200810.
//

import Foundation
import Metal
import simd
import CocoaLumberjackSwift

import Paper

/**
 * Multiplies each pixel of the input image by a given conversion matrix, and writes the result to the output image.
 */
internal class MatrixMultiply: RenderPipelineElement {
    /// Tag value
    private(set) internal var tag: Tag?
    /// Metal device
    private(set) internal var device: MTLDevice!
    
    /// Shader code library
    private var library: MTLLibrary! = nil
    /// Compute pipeline state
    private var state: MTLComputePipelineState! = nil
    
    /// Conversion matrix
    private(set) internal var matrix = simd_float3x3(1)
    
    // MARK: - Initialization
    /**
     * Creates a new matrix multiply pipeline element.
     */
    required init(_ device: MTLDevice, tag: Tag? = nil) throws {
        self.device = device
        self.tag = tag
        
        try self.initMetalResources(device)
    }
    
    /**
     * Creates a new matrix multiply pipeline element, with the given matrix.
     */
    required init(_ device: MTLDevice, tag: Tag? = nil, matrix: simd_float3x3) throws {
        self.device = device
        self.tag = tag
        self.matrix = matrix
    
        try self.initMetalResources(device)
    }
    
    /**
     * Initializes Metal resources for the given device.
     */
    private func initMetalResources(_ device: MTLDevice) throws {
        // get the shader library
        let bundle = Bundle(for: type(of: self))
        self.library = try device.makeDefaultLibrary(bundle: bundle)
        
        // set up compute pipeline state
        guard let function = self.library.makeFunction(name: "RPE_MatrixMultiply") else {
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
     * Encodes the matrix multiplying into the given buffer.
     */
    func encode(_ buffer: MTLCommandBuffer, in inImage: TiledImage, out: TiledImage) throws {
        // create command encoder
        guard let encoder = buffer.makeComputeCommandEncoder() else {
            throw Errors.failedMakeCommandEncoder
        }
        encoder.label = "MatrixMultiply.encode(_:_:_:)"
        
        // grab textures
        guard let inTexture = inImage.texture, let outTexture = out.texture else {
            throw Errors.invalidImage
        }
        
        // calculate the threadgroup sizes
        let w = self.state.threadExecutionWidth
        let h = self.state.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: inTexture.width, height: inTexture.height,
                                     depth: inTexture.arrayLength)
        
        // create a buffer with the info required by the compute functions
        let conversionMatrix = CameraColorInfo.conversionMatrixFrom(xyz: self.matrix)
        
        var uniforms = Uniforms(conversionMatrix: conversionMatrix)
        let uniformBuf = self.device.makeBuffer(bytes: &uniforms,
                                                length: MemoryLayout<Uniforms>.stride)
        
        // invoke the function
        encoder.setComputePipelineState(self.state)
        
        encoder.setTexture(inTexture, index: 0)
        encoder.setTexture(outTexture, index: 1)
        
        encoder.setBuffer(uniformBuf, offset: 0, index: 0)
        
        // encode the compute command
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to load the compute function
        case failedLoadingFunction
        /// Failed to create a command encoder
        case failedMakeCommandEncoder
        /// Invalid images were passed in (no texture)
        case invalidImage
    }
    
    // MARK: - Types
    /**
     * Uniform buffer passed to the compute shader: this contains the conversion matrix
     */
    private struct Uniforms {
        /// Color space conversion matrix
        var conversionMatrix = simd_float3x3()
    }
}
