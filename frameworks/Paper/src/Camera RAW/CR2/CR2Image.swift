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
    /// Metadata IFD
    internal(set) public var metaIfd: TIFFReader.IFD! = nil

    // MARK: - Thumbnails
    /// An array of thumbnail images. The highest resolution is first.
    internal(set) public var thumbs: [CGImage] = []

    // MARK: - Raw image
    /// Size of the raw image
    internal(set) public var rawSize: CGSize = .zero

    // MARK: - Initialization
    internal init() {}
}
