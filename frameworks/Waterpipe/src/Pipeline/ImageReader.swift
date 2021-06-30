//
//  ImageReader.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation
import UniformTypeIdentifiers

import Paper

/**
 * Picks the most optimal image reader for the input file and uses it to read the file.
 */
internal class ImageReader {
    /// Shared image reader instance
    private(set) internal static var shared = ImageReader()
    
    // MARK: - Initialization
    /**
     * Initializes a new image reader.
     */
    private init() {
        
    }
    
    // MARK: - Reading
    /**
     * Returns an image object for the image at the given url, if a reader exists to handle it.
     *
     * - Parameter url: Location of the image to read
     * - Returns Read image, or nil if the format isn't supported.
     * - Throws If the file type can't be determined, or something goes wrong while reading the image.
     */
    internal func read(url: URL) throws -> ImageReaderImpl? {
        // get the type
        guard let resVals = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
              let typeString = resVals.typeIdentifier,
              let type = UTType(typeString) else {
            throw Errors.failedToGetType(url: url)
        }
        
        // query each reader implementation
        for reader in Self.readers {
            if reader.supportsType(type) {
                return try reader.init(withFileAt: url, type)
            }
        }
        
        // the file isn't supported
        return nil
    }
    
    // MARK: - Configuration
    /**
     * Types of image readers, in descending priority order.
     *
     * Each reader in this list, from first to last, is queried to determine whether it can read of the provided type. Therefore, the
     * most specific (e.g. camera specific) formats should be listed first.
     */
    private static let readers: [ImageReaderImpl.Type] = [
        // camera raw formats
        LibRawImageReaderImpl.self,
//        CR2ImageReaderImpl.self
    ]
    
    // MARK: - Types
    /// Formats for image decode outputs; all are floating point, with a normal range of [0, 1].
    enum BitmapFormat {
        /// 16-bit (half precision) floating point components
        case float16
        /// 32-bit (single precision) floating point components
        case float32
    }
    
    /// Describes an image buffer returned from a decode command.
    public struct ImageBuffer {
        /// Data buffer containing image data. Must be at least `bytesPerRow` * `rows` bytes.
        var data: Data
        /// Bytes per row of image data
        var bytesPerRow: Int
        /// Number of rows in the image
        var rows: UInt
        /// Number of columns in the image
        var cols: UInt
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to get the UTI for the input file
        case failedToGetType(url: URL)
    }
}
