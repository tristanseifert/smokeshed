//
//  MetalColorConverter.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200722.
//

import Foundation

import Metal
import simd

import CocoaLumberjackSwift

/**
 * Converts pixel data from a camera specific color space to the working color space.
 */
public class MetalColorConverter {
    /// Compute device
    private var device: MTLDevice! = nil
    
    /// Shader code library
    private var library: MTLLibrary! = nil
    /// Compute pipeline state
    private var state: MTLComputePipelineState! = nil
    
    // MARK: - Initialization
    /**
     * Creates a new color converter that will run on the specified device.
     */
    public init(_ device: MTLDevice) throws {
        self.device = device
        
        // device color conversions
        guard let colorInfo = CameraColorInfo() else {
            throw Errors.failedCameraColorInfo
        }
        self.colorInfo = colorInfo
        
        // get the library
        let bundle = Bundle(for: type(of: self))
        self.library = try device.makeDefaultLibrary(bundle: bundle)
        
        // set up compute pipeline state
        guard let function = self.library.makeFunction(name: "convertToWorking") else {
            throw Errors.failedLoadingFunction
        }
        
        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = function
        desc.buffers[0].mutability = .immutable
        
        self.state = try device.makeComputePipelineState(descriptor: desc, options: [],
                                                         reflection: nil)
    }
    
    // MARK: - Matrix handling
    /// Gets info on color matrices
    private var colorInfo: CameraColorInfo!
    
    // MARK: - Compute pass encoding
    /**
     * Encodes a conversion operation into the provided compute encoder. The transform executes in place.
     *
     * - Parameter buffer: Command buffer on which the operation is encoded
     * - Parameter image: Image texture in RGBA format
     * - Parameter imageSize: Total size of the image, in pixels.
     * - Parameter modelName: Camera model name, used to look up the conversion matrix
     */
    public func encode(_ buffer: MTLCommandBuffer, input: MTLTexture, output: MTLTexture?, modelName: String) throws {
        guard let matrix = try self.colorInfo.xyzMatrixForModel(modelName) else {
            throw Errors.unknownModel(modelName)
        }
        
        try self.encode(buffer, input: input, matrix: matrix)
    }
    /**
     * Encodes a conversion operation into the provided compute encoder. The transform executes in place.
     *
     * - Parameter buffer: Command buffer on which the operation is encoded
     * - Parameter image: Image texture in RGBA format
     * - Parameter imageSize: Total size of the image, in pixels.
     * - Parameter matrix: Conversion matrix from sensor color space to XYZ color space
     */
    public func encode(_ buffer: MTLCommandBuffer, input inImage: MTLTexture, matrix xyzMatrix: simd_float3x3) throws {
        // create command encoder
        guard let encoder = buffer.makeComputeCommandEncoder() else {
            throw Errors.failedMakeCommandEncoder
        }
        encoder.label = "MetalColorConverter.encode(_:_:_:)"
        
        // calculate the threadgroup sizes
        let w = self.state.threadExecutionWidth
        let h = self.state.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: inImage.width, height: inImage.height, depth: 1)
        
        // create a buffer with the info required by the compute functions
        let conversionMatrix = CameraColorInfo.conversionMatrixFrom(xyz: xyzMatrix)
        
        var uniforms = Uniforms(conversionMatrix: conversionMatrix)
        let uniformBuf = self.device.makeBuffer(bytes: &uniforms,
                                                length: MemoryLayout<Uniforms>.stride)
        
        // invoke the function
        encoder.setComputePipelineState(self.state)
        encoder.setTexture(inImage, index: 0)
        encoder.setBuffer(uniformBuf, offset: 0, index: 0)
        
        // encode the compute command
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
    
    // MARK: - Types
    /**
     * Uniform (constant) data shared by all invocations of the compute function
     */
    private struct Uniforms {
        /// Camera RGB color space conversion matrix
        var conversionMatrix = simd_float3x3()
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to initialize the color conversion database
        case failedCameraColorInfo
        /// No conversion data is available for the given model.
        case unknownModel(_ model: String)
        /// Failed to load the required functions from the shader
        case failedLoadingFunction
        /// Failed to create a command encoder
        case failedMakeCommandEncoder
    }
    
    // MARK: - Constants
    /**
     * Conversion matrix to go from X*Y*Z color space to ProPhoto RGB (RIMM) color space, which is used as the working
     * space by the render pipeline.
     */
    private static let proPhotoMatrix = {
        return simd_float3x3(SIMD3<Float>(0.529317, 0.098368, 0.016879),
                             SIMD3<Float>(0.330092, 0.873465, 0.117663),
                             SIMD3<Float>(0.140588, 0.028169, 0.865457))
    }()
}
