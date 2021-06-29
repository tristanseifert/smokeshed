//
//  ThumbReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import OSLog

/**
 * Provides an interface to extract thumbnails of a given size from a variety of image formats.
 */
public class ThumbReader {
    fileprivate static var logger = Logger(subsystem: Bundle(for: ThumbReader.self).bundleIdentifier!,
                                         category: "ThumbReader")
    
    /// Actual reader implementation for the file
    private var reader: ThumbReaderImpl!
    
    // MARK: - Initialization
    /**
     * Creates a thumb reader for the given file if supported.
     */
    public init?(_ url: URL) {
        // get the UTI of the input type
        guard let resVals = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
              let typeString = resVals.typeIdentifier,
              let type = UTType(typeString) else {
            return nil
        }
        
        // query each reader implementation
        for reader in Self.readers {
            if reader.supportsType(type) {
                do {
                    self.reader = try reader.init(withFileAt: url)
                    break
                } catch {
                    Self.logger.error("Failed to create reader for type \(type) (at \(url)): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }
        
        // ensure we created a reader
        guard self.reader != nil else {
            return nil
        }
        
        // attempt to decode
        do {
            try self.reader.decode()
        } catch {
            Self.logger.error("Failed to decode \(type) (at \(url)): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - Generation
    /**
     * Get a thumbnail image whose small edge has approximately the given length.
     */
    public func getThumb(_ size: CGFloat) -> CGImage? {
        return self.reader.getImage(size)
    }
    
    // MARK: - Helpers
    /// Size of the original image
    public var originalSize: CGSize {
        return self.reader.originalImageSize
    }
    
    // MARK: - Configuration
    /**
     * Types of image readers, in descending priority order.
     *
     * Each reader in this list, from first to last, is queried to determine whether it can read thumbnails from
     * an image of the provided type. Therefore, the most specific (e.g. camera specific) formats should be
     * listed first.
     */
    private static let readers: [ThumbReaderImpl.Type] = [
        // camera raw formats
        CR2ThumbReader.self,
        // last resort: ImageIO
        ImageIOThumbReader.self
    ]
}
