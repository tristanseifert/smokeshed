//
//  JPEGMarker.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200615.
//

import Foundation

extension JPEGDecoder {
    // MARK: - Base marker
    /**
     * Represents a single marker, as read from the JPEG stream.
     */
    internal class BaseMarker {
        /// Type of marker
        private(set) internal var type: MarkerType
        /// File offset to the first byte of the marker
        private(set) internal var offset: Int
        /// Decoder that read this marker
        private(set) internal weak var decoder: JPEGDecoder?

        /// File offset of the next marker, if any
        private(set) internal var next: Int? = nil

        /**
         * Allocates a new marker.
         */
        fileprivate init(_ owner: JPEGDecoder, _ offset: Int, type: MarkerType) throws {
            self.decoder = owner
            self.offset = offset
            self.type = type
        }

        /**
         * Instantiates a new marker.
         */
//        internal class func make(_ decoder: JPEGDecoder, _ offset: Int) throws -> MarkerType {
//
//        }
    }

    // MARK: - Enums
    /**
     * Markers that we understand how to parse
     */
    internal enum MarkerType: UInt16 {
        /// Start of the image
        case imageStart = 0xFFD8
        /// End of the image
        case imageEnd = 0xFFD9

        /// Start of a losslessly encoded frame
        case frameStartLossless = 0xFFC3

        /// Start of an image frame scan
        case scanStart = 0xFFDA

        /// Huffman table definition
        case defineHuffmanTable = 0xFFC4
    }
}
