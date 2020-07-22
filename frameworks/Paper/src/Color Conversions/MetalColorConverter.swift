//
//  MetalColorConverter.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200722.
//

import Foundation

import Metal
import simd

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
        
        // load some information
        let bundle = Bundle(for: type(of: self))
        try self.loadInfo()
        
        // get the library
        self.library = try device.makeDefaultLibrary(bundle: bundle)
        
        // set up compute pipeline state
        guard let function = self.library.makeFunction(name: "convertToWorking") else {
            throw Errors.failedLoadingFunction
        }
        
        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = function
        
        desc.buffers[0].mutability = .mutable
        desc.buffers[1].mutability = .immutable
        
        self.state = try device.makeComputePipelineState(descriptor: desc, options: [],
                                                         reflection: nil)
    }
    
    // MARK: - Matrix handling
    /**
     * Map of camera model -> XYZ matrices. Each matrix is stored with each component multiplied by 10000.
     */
    private var camToXyz: [String: Any] = [:]
    
    /**
     * Mapping of camera model aliases. Marketing names of cameras may vary for the same hardware, so this compensates
     * for such situations.
     */
    private var modelNameAliases: [String: String] = [:]
    
    /**
     * Loads the camera to XYZ matrices, as well as the marketing name alias list.
     */
    private func loadInfo() throws {
        let bundle = Bundle(for: type(of: self))
        
        // load the cam xyz matrix
        let xyzUrl = bundle.url(forResource: "CamToXYZInfo", withExtension: "plist")!
        let xyzData = try Data(contentsOf: xyzUrl)
        
        let xyzPlist = try PropertyListSerialization.propertyList(from: xyzData,
                                                                  options: [], format: nil)
        guard let camToXyz = xyzPlist as? [String: Any] else {
            throw Errors.invalidXyzMap
        }
        self.camToXyz = camToXyz
        
        // load the model name aliases
        let aliasesUrl = bundle.url(forResource: "CamToXYZAliases", withExtension: "plist")!
        let aliasesData = try Data(contentsOf: aliasesUrl)
        
        let aliasesPlist = try PropertyListSerialization.propertyList(from: aliasesData,
                                                                      options: [],
                                                                      format: nil)
        guard let aliases = aliasesPlist as? [String: String] else {
            throw Errors.invalidModelAliasMap
        }
        self.modelNameAliases = aliases
    }
    
    /**
     * Gets information for a particular camera by model name.
     *
     * - Parameter inModelName: Camera model name, as taken from metadata.
     * - Returns: Dictionary of information as read from the `CamToXYZ` plist
     * - Throws: If an error decoding the information took place.
     */
    internal func infoForModel(_ inModelName: String) throws -> [String: Any]? {
        // check if there's a model name alias
        var modelName = inModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let alias = self.modelNameAliases[inModelName] {
            modelName = alias
        }
        
        // read the conversion info
        guard let rawInfo = self.camToXyz[modelName] else {
            return nil
        }
        guard let info = rawInfo as? [String: Any] else {
            throw Errors.invalidXyzData(modelName)
        }
        
        return info
    }
    
    /**
     * Looks up a matrix for the given model name.
     *
     * - Parameter inModelName: Camera model name, as taken from metadata. Used to fetch the appropriate color
     * space conversion matrix.
     * - Returns: A 3x3 matrix for converting from the sensor color space to XYZ working space, if found.
     * - Throws: If an error decoding the matrix or other information took place.
     */
    internal func xyzMatrixForModel(_ inModelName: String) throws -> simd_float3x3? {
        guard let info = try self.infoForModel(inModelName) else {
            return nil
        }
        guard let matrixValues = info["matrix"] as? [Double] else {
            throw Errors.invalidXyzData(inModelName)
        }
        
        // create matrix
        var rows: [SIMD3<Float>] = []
        
        for row in 0..<3 {
            let values = matrixValues[(row * 3)..<((row * 3) + 3)].map {
                return Float($0 / 10000)
            }
            
            rows.append(SIMD3<Float>(values))
        }
        
        return simd_float3x3(rows: rows)
    }
    
    // MARK: - Compute pass encoding
    /**
     * Encodes a conversion operation into the provided compute encoder. The transform executes in place.
     *
     * - Parameter encoder: Command encoder on which the operation is encoded
     * - Parameter imageDataBuffer: A buffer object containing pixel data, in RGBA format.
     * - Parameter imageSize: Total size of the image, in pixels.
     * - Parameter modelName: Camera model name, used to look up the conversion matrix
     */
    public func encode(_ encoder: MTLComputeCommandEncoder, _ imageDataBuffer: MTLBuffer, imageSize: CGSize, modelName: String) throws {
        guard let matrix = try self.xyzMatrixForModel(modelName) else {
            throw Errors.unknownModel(modelName)
        }
        
        try self.encode(encoder, imageDataBuffer, imageSize: imageSize, matrix: matrix)
    }
    /**
     * Encodes a conversion operation into the provided compute encoder. The transform executes in place.
     *
     * - Parameter encoder: Command encoder on which the operation is encoded
     * - Parameter imageDataBuffer: A buffer object containing pixel data, in RGBA format.
     * - Parameter imageSize: Total size of the image, in pixels.
     * - Parameter matrix: Camera model name, used to look up the conversion matrix
     */
    public func encode(_ encoder: MTLComputeCommandEncoder, _ imageDataBuffer: MTLBuffer, imageSize: CGSize, matrix: simd_float3x3) throws {
        // calculate the threadgroup sizes
        let w = self.state.threadExecutionWidth
        let h = self.state.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        
        let threadsPerGrid = MTLSize(width: Int(imageSize.width),
                                     height: Int(imageSize.height),
                                     depth: 1)
        
        // create a buffer with the info required by the compute functions
        var uniforms = Uniforms(conversionMatrix: matrix)
        let uniformBuf = self.device.makeBuffer(bytes: &uniforms,
                                                length: MemoryLayout<Uniforms>.stride)
        
        // invoke the function
        encoder.setComputePipelineState(self.state)
        encoder.setBuffer(imageDataBuffer, offset: 0, index: 0)
        encoder.setBuffer(uniformBuf, offset: 0, index: 1)
        
        // encode the compute command
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
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
        /// Failed to load the compute function
        case failedLoadingFunction
        /// Camera to XYZ map is corrupt
        case invalidXyzMap
        /// An entry in the XYZ map is corrupt
        case invalidXyzData(_ model: String)
        /// Camera model name alias map is corrupt
        case invalidModelAliasMap
        /// No conversion data is available for the given model.
        case unknownModel(_ model: String)
    }
}
