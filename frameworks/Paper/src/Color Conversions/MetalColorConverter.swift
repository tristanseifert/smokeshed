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
        desc.buffers[0].mutability = .immutable
        
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
    
    /**
     * Given a matrix to convert from sensor color space to X*Y*Z, produce a final conversion matrix that converts the pixel data
     * to the ProPhoto RGB (RIMM) color space, used as the working space for the render pipeline.
     */
    private func conversionMatrixFrom(xyz matrix: simd_float3x3) -> simd_float3x3 {
        // multiply by the xyz -> proPhoto matrix
        var temp = matrix * Self.proPhotoMatrix
        
        // normalization step
        for i in 0..<3 {
            // sum up the entire row (arithmetic sum)
            let sum = temp[0][i] + temp[1][i] + temp[2][i]
            
            // divide each element in the column by this
            for j in 0..<3 {
                temp[j][i] /= sum
            }
        }
        
        // pseudoinverse
        let inverse = temp.pseudoinverse
        
        // done!
        return inverse
    }
    
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
        guard let matrix = try self.xyzMatrixForModel(modelName) else {
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
        let conversionMatrix = self.conversionMatrixFrom(xyz: xyzMatrix)
        
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

extension simd_float3x3 {
    /**
     * Returns the pseudoinverse of the matrix.
     */
    fileprivate var pseudoinverse: simd_float3x3 {
        var out = simd_float3x3()
        var work: [[Float]] = [[0, 0, 0, 0, 0, 0],
                               [0, 0, 0, 0, 0, 0],
                               [0, 0, 0, 0, 0, 0]]
        
        // step 1 of this horribly fucked function
        for i in 0..<3 {
            for j in 0..<6 {
                work[i][j] = (j == (i + 3)) ? 1 : 0
            }
            
            for j in 0..<3 {
                for k in 0..<3 {
                    work[i][j] += self[i][k] * self[j][k]
                }
            }
        }
        
        // stage 2 of this fuckshow
        for i in 0..<3 {
            // normalize some shit
            let num = work[i][i]
            for j in 0..<6 {
                work[i][j] /= num
            }
            
            // yeah idk anymore
            for k in 0..<3 {
                if k == i {
                    continue
                }
                
                let num2 = work[k][i]
                for j in 0..<6 {
                    work[k][j] -= work[i][j] * num2
                }
            }
        }
        
        // stage 3 fuckery
        for i in 0..<3 {
            for j in 0..<3 {
                out[j][i] = 0
                
                for k in 0..<3 {
                    out[j][i] += work[j][k+3] * self[k][i]
                }
            }
        }
        
        return out
    }
}
