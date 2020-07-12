//
//  ThumbReaderImpl.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import UniformTypeIdentifiers

/**
 * Interface for a thumbnail reader, which allows extracting thumbnails from an image.
 */
internal protocol ThumbReaderImpl {
    /**
     * Determine whether the provided type can be read by this implementation.
     */
    static func supportsType(_ type: UTType) -> Bool
    
    /**
     * Initializes a thumbnail reader with the file at the given URL.
     *
     * This method should do no decoding of the file beyond verifying its type.
     *
     * - Throws: If the file could not be opened for reading.
     */
    init(withFileAt url: URL) throws
    
    /**
     * Decodes the file and extracts information about thumbnails.
     *
     * It is implementation defined whether any embedded images are decoded at this stage, or if they are
     * decoded when the first thumbnail request is made.
     *
     * - Throws: File decoding errors, or if no thumbnails could be read.
     */
    func decode() throws
    
    /**
     * Get a thumbnail image whose small edge has approximately the given length.
     *
     * This method makes no guarantee about the returned image; it may be the exact size requested,
     * larger, or smaller, depending on what was decoded from the file.
     */
    func getImage(_ size: CGFloat) -> CGImage?
    
    /**
     * Size of the original image
     */
    var originalImageSize: CGSize { get }
}
