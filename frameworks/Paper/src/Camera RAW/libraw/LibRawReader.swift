//
//  LibRawReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200815.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Generic reader for camera raw formats, using the LibRaw library.
 */
public class LibRawReader {
    /// URL the file was read from
    private var url: URL
    
    /// Image reader
    private var reader: PAPLibRawReader!
    
    /// Debayered image data
    private var debayered: Data? = nil
    
    // MARK: - Initialization
    /// Whether the thumb data should be decoded
    private var decodeThumbs = false
    /// Whether raw image data should be decoded
    private var decodeRaw = false
    
    /**
     * Creates a raw file reader by reading from the given URL.
     */
    public init(fromUrl url: URL, decodeRawData: Bool, decodeThumbs: Bool) throws {
        self.url = url
        
        // try to create reader
        self.reader = try PAPLibRawReader(from: url)
        
        // store decoding state
        self.decodeRaw = decodeRawData
        self.decodeThumbs = decodeThumbs
    }
    
    /**
     * Decodes the image.
     */
    public func decode() throws {
        if self.decodeRaw {
            try self.reader.unpackRawData()
            self.debayered = try self.reader.debayerRawData()
        }
        
        if self.decodeThumbs {
            try self.reader.unpackThumbs()
        }
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to create a libraw based reader
    }
}
