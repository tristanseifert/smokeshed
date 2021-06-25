//
//  CameraColorInfo.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200808.
//

import Foundation
import simd

import CocoaLumberjackSwift

/**
 * Allows queries against the database of camera models to conversion matrices.
 *
 * These conversion matricies are used to convert from the camera sensors' native color space to the XYZ working space.
 */
public class CameraColorInfo {
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
     * Initializes a new camera color info object. This will load the color info from disk.
     */
    public init?() {
        do {
            let bundle = Bundle(for: type(of: self))
            
            // load the cam xyz matrix
            let xyzUrl = bundle.url(forResource: "CamToXYZInfo", withExtension: "plist")!
            let xyzData = try Data(contentsOf: xyzUrl)
            
            let xyzPlist = try PropertyListSerialization.propertyList(from: xyzData,
                                                                      options: [], format: nil)
            guard let camToXyz = xyzPlist as? [String: Any] else {
                DDLogError("Invalid xyz plist: \(xyzPlist)")
                return nil
            }
            self.camToXyz = camToXyz
            
            // load the model name aliases
            let aliasesUrl = bundle.url(forResource: "CamToXYZAliases", withExtension: "plist")!
            let aliasesData = try Data(contentsOf: aliasesUrl)
            
            let aliasesPlist = try PropertyListSerialization.propertyList(from: aliasesData,
                                                                          options: [],
                                                                          format: nil)
            guard let aliases = aliasesPlist as? [String: String] else {
                DDLogError("Invalid alias plist: \(aliasesPlist)")
                return nil
            }
            self.modelNameAliases = aliases
        } catch {
            DDLogError("Failed to load color info: \(error)")
            return nil
        }
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
    public func xyzMatrixForModel(_ inModelName: String) throws -> simd_float3x3? {
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
    public class func conversionMatrixFrom(xyz matrix: simd_float3x3) -> simd_float3x3 {
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
    
    // MARK: - Errors
    enum Errors: Error {
        /// An entry in the XYZ map is corrupt
        case invalidXyzData(_ model: String)
        /// No conversion data is available for the given model.
        case unknownModel(_ model: String)
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
