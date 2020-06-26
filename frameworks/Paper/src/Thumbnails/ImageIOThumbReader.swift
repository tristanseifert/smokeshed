//
//  ImageIOThumbReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import UniformTypeIdentifiers
import ImageIO

/**
 * Reads thumbnails from an image using the ImageIO framework.
 *
 * Most image types are supported by this, including many camera raw files, as well as standard types such
 * as JPEG.
 */
internal class ImageIOThumbReader: ThumbReaderImpl {
    /// Image source from which thumbnails should be read
    private var source: CGImageSource!
    
    /**
     * Creates an image source for the given file.
     */
    public required init(withFileAt url: URL) throws {
        // create source
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageIOThumbErrors.imageSourceCreateFailed
        }
        self.source = src
    }
    
    /**
     * Decode ImageIO thumbnails. This is a no-op.
     */
    public func decode() throws {
        // nothing :)
    }
    
    /**
     * Invoke ImageIO to generate a thumbnail with the given pixel dimension.
     */
    func getImage(_ size: CGFloat) -> CGImage? {
        // build options
        let opts: [CFString: Any] = [
            // do not cache images
            kCGImageSourceShouldCache: false,
            // maximum size
            kCGImageSourceThumbnailMaxPixelSize: size,
            // create thumbnail if required
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true
        ]
        
        // get the thumb
        return CGImageSourceCreateThumbnailAtIndex(self.source, 0,
                                                   opts as CFDictionary)
    }
    
    /**
     * Determine whether the provided type can be read by this implementation.
     */
    static func supportsType(_ type: UTType) -> Bool {
        return type.conforms(to: UTType.image)
    }
    
    // MARK: - Errors
    enum ImageIOThumbErrors: Error {
        /// Failed to create an image source
        case imageSourceCreateFailed
    }
}
