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
        // get type of the file and provide an identifier hint
        let resVals = try url.resourceValues(forKeys: [.typeIdentifierKey])

        guard let uti = resVals.typeIdentifier else {
            throw ImageIOThumbErrors.failedToGetType
        }
        
        // create source
        let opts: [CFString: Any] = [
            // provide the UTI of the file
            kCGImageSourceTypeIdentifierHint: uti,
            // cache decoded image
            kCGImageSourceShouldCache: true
        ]
        
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else {
            throw ImageIOThumbErrors.imageSourceCreateFailed
        }
        self.source = src
        
        guard CGImageSourceGetStatus(src) == .statusComplete else {
            throw ImageIOThumbErrors.invalidStatus(CGImageSourceGetStatus(src).rawValue)
        }
        
        // get the index of the main image
        self.primaryIndex = CGImageSourceGetPrimaryImageIndex(self.source)
    }
    
    /**
     * Decode ImageIO thumbnails. This is a no-op.
     */
    public func decode() throws {
        // get the image size
        guard let props = CGImageSourceCopyPropertiesAtIndex(self.source, self.primaryIndex, nil)
                as? [CFString: Any] else {
            throw ImageIOThumbErrors.imagePropertiesFailed
        }
        
        let width = (props[kCGImagePropertyPixelWidth] as! NSNumber).intValue
        let height = (props[kCGImagePropertyPixelHeight] as! NSNumber).intValue
        
        self.originalImageSize = CGSize(width: width, height: height)
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
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            // scale it proportionally and remember orientation
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        // get the thumb
        return CGImageSourceCreateThumbnailAtIndex(self.source, self.primaryIndex,
                                                   opts as CFDictionary)
    }
    
    /**
     * Determine whether the provided type can be read by this implementation.
     */
    static func supportsType(_ type: UTType) -> Bool {
        return type.conforms(to: UTType.image)
    }
    
    /**
     * Return the decoded image size
     */
    private(set) var originalImageSize: CGSize = .zero
    
    /// Primary image index
    private var primaryIndex: Int
    
    // MARK: - Errors
    enum ImageIOThumbErrors: Error {
        /// Couldn't determine the type of the input image
        case failedToGetType
        /// Failed to create an image source
        case imageSourceCreateFailed
        /// Failed to get properties for the image source
        case imagePropertiesFailed
        /// Invalid image source status
        case invalidStatus(_ status: Int32)
    }
}
