//
//  ImageReaderImpl.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation
import simd
import UniformTypeIdentifiers

/**
 * Protocol describing the interface of image reader implementations
 */
protocol ImageReaderImpl {
    /**
     * Determine whether the provided type can be read by this implementation.
     */
    static func supportsType(_ type: UTType) -> Bool
    
    /**
     * Initializes a pipeline image reader with the file at the given URL.
     *
     * This method should do no decoding of the file beyond verifying its type.
     *
     * - Throws: If the file could not be opened for reading.
     */
    init(withFileAt url: URL, _ type: UTType) throws
    
    /**
     * Decodes the image to a bitmap representation synchronously.
     *
     * This will decode the image to the format-native representation, and then converted to either 16-bit or 32-bit floating point,
     * 4 components per pixel data.
     */
    func decode(_ format: ImageReader.BitmapFormat) throws -> ImageReader.ImageBuffer
    
    /**
     * Allows the image reader to insert some format specific processing elements at the start of a pipeline state object.
     */
    func insertProcessingElements(_ pipeline: RenderPipelineState)
    
    /// If read from a file, URL to the file
    var url: URL? { get }
    /// Type of the original image
    var type: UTType { get }
    /// Dimensions of image
    var size: CGSize { get }
}
