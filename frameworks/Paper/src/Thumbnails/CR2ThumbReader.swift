//
//  CR2ThumbReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import UniformTypeIdentifiers

import CocoaLumberjackSwift

/**
 * Extracts existing JPEG (and RGB interleaved bitmap) thumbnails from a CR2 file.
 */
internal class CR2ThumbReader: ThumbReaderImpl {
    /// CR2 reader instance
    private var reader: CR2Reader!
    /// Decoded raw image
    private var image: CR2Image!
    
    /**
     * Creates a new reader.
     */
    required init(withFileAt url: URL) throws {
        self.reader = try CR2Reader(fromUrl: url, decodeRawData: false,
                                    decodeThumbs: true)
    }
    
    /**
     * Decodes the CR2 file.
     */
    func decode() throws {
        self.image = try self.reader.decode()
    }
    
    /**
     * Extracts a suitable thumbnail from the image.
     *
     * This will try to find the best thumbnail image closest to the provided dimension. We will always prefer
     * larger images over smaller ones, but always want the image with the smallest absolute size difference
     * to the input size.
     */
    func getImage(_ requestedSize: CGFloat) -> CGImage? {
        precondition(self.image != nil, "Invalid CR2 image; did you forget to call decode()?")
        
        guard !self.image.thumbs.isEmpty else {
            DDLogWarn("Failed to decode thumbs: \(String(describing: self.reader)): \(String(describing: self.image))")
            return nil
        }
        
        // determine which side of the image is larger
        var widthIsLarger = true
        
        if self.image.rawSize.width < self.image.rawSize.height {
            widthIsLarger = false
        }
        
        // get images and their sizes
        var sizes: [CGFloat: CGImage] = [:]
        
        for thumb in self.image.thumbs {
            var size: CGFloat = 0
            
            if widthIsLarger {
                size = CGFloat(thumb.width)
            } else {
                size = CGFloat(thumb.height)
            }
            
            sizes[size - requestedSize] = thumb
        }
        
        // if there are positive values, remove all negative values
        if sizes.contains(where: { $0.key >= 0 }) {
            let keysToRemove = sizes.keys.filter({ $0 < 0 })
            for key in keysToRemove {
                sizes.removeValue(forKey: key)
            }
        }
        
        // find image with smallest difference from desired size
        if let bestKey = sizes.keys.min(by: { ($0) < ($1) }) {
            return sizes[bestKey]
        }
        
        // failed to find a suitable size
        return nil
    }
    
    /// Type identifier of CR2 files
    static let uti = UTType("com.canon.cr2-raw-image")!
    
    /**
     * Determines whether the provided image type is supported by the CR2 reader.
     */
    static func supportsType(_ type: UTType) -> Bool {
        return type.conforms(to: Self.uti)
    }
    
    /**
     * Return the decoded image size
     */
    var originalImageSize: CGSize {
        return self.image.rawSize
    }
}
