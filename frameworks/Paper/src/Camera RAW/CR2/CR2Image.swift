//
//  CR2Image.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

/**
 * Decoded Canon RAW image
 */
public class CR2Image {
    // MARK: - Metadata
    /// Image metadata object
    internal(set) public var meta: ImageMeta! = nil

    /// Metadata IFD
    internal(set) public var metaIfd: TIFFReader.IFD! = nil

    // MARK: - Thumbnails
    /// An array of thumbnail images. The highest resolution is first.
    internal(set) public var thumbs: [CGImage] = []

    // MARK: - Raw image
    /// Size of the raw image, before trimming borders or any other processing to discard data
    internal(set) public var rawSize: CGSize = .zero
    /// Raw bitplanes
    internal(set) public var rawPlanes: [Data] = []

    /// Dimensions of visible image data
    internal(set) public var visibleImageSize: CGSize = .zero
    /// Sensor data; first row is RG pixels, second is GB pixels, with borders trimmed. (UInt16 per pixel)
    internal(set) public var rawValues: Data!
    /// Vertical shift of the Bayer matrix; the first actual line (after borders) may be GB pixels
    internal(set) public var rawValuesVshift: UInt = 0
    
    /// Black level factors, for each CFA index
    internal(set) public var rawBlackLevel: [UInt16] = []
    /// White balance compensation factors, in RG/GB order
    internal(set) public var rawWbMultiplier: [Double] = []

    // MARK: - Initialization
    internal init() {}
}
