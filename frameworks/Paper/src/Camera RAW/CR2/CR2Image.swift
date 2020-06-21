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
    /// Size of the raw image
    internal(set) public var rawSize: CGSize = .zero
    /// Raw bitplanes
    internal(set) public var rawPlanes: [Data] = []

    /// Dimensions of sensor data
    internal(set) public var rawValuesSize: CGSize = .zero
    /// Sensor data; first row is RG pixels, second is GB pixels, with borders trimmed.
    internal(set) public var rawValues: Data!
    /// Vertical shift of the Bayer matrix; the first actual line (after borders) may be GB pixels
    internal(set) public var rawValuesVshift: UInt = 0

    // MARK: - Initialization
    internal init() {}
}
