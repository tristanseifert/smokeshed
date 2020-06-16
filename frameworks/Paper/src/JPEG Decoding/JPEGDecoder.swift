//
//  JPEGDecoder.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200615.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Decodes JPEG images encoded using the lossless encoding scheme.
 *
 * Currently, only the Huffman entropy coding scheme is supported. Only very few markers are supported:
 * specifically, no extensions (such as JFIF or Exif) are implemented.
 */
internal class JPEGDecoder {
    /// Data object containing the JPEG file data
    private var data: Data

    /// Huffman coding
    private var huffman: JPEGHuffman!

    // MARK: - Initialization
    /**
     * Creates a JPEG decoder with the given data as input.
     *
     * This will validate that the first two bytes of the blob contain the SOI marker, but performs absolutely
     * zero verification beyond that.
     */
    init(withData data: Data) throws {
        self.data = data

        // create subcomponents of the decoder
        self.huffman = JPEGHuffman(self)

        // try to find the SOI marker
        let head: UInt16 = self.data.readEndian(0, .big)
        if head != MarkerType.imageStart.rawValue {
            throw FormatError.missingSOI(head)
        }
    }

    /**
     * Decodes the previously loaded image.
     *
     * This works by sequentially processing each marker, until we find an end of image marker.
     */
    internal func decode() throws {
        // try to decode each marker
        var offset: Int? = 0

        while let i = offset {
            offset = try self.decodeMarker(atOffset: i)
        }

        // if we didn't reach the end… that's an error
        guard self.reachedEnd else {
            throw DecodeError.noEndOfImage
        }

        // image was decoded, the bitmap will be stored in the decoder
    }

    // MARK: - Markers
    /// All markers decoded out of this image
    private var markers: [BaseMarker] = []
    /// Whether we reached the end of the JPEG stream (encountered EOI marker)
    private var reachedEnd = false

    /// Currently processign frame
    private var currentFrame: JPEGFrame? = nil

    /**
     * Attempts to identify the marker at the given file index, if possible. The offset past the end of this
     * marker is returned, if known.
     */
    private func decodeMarker(atOffset inOff: Int) throws -> Int? {
        // try to read a marker
        let rawMarker: UInt16 = self.data.readEndian(inOff, .big)

        guard (rawMarker & 0xFF00) == 0xFF00 else {
            throw DecodeError.invalidMarker(rawMarker)
        }

        // convert to marker type enum
        guard let type = MarkerType(rawValue: rawMarker) else {
            throw DecodeError.unknownMarker(rawMarker)
        }

        DDLogVerbose("Marker at \(inOff): \(type)")

        // decode the marker
        switch type {
            // start of image: this tag has no data
            case .imageStart:
                return (inOff + 2)
            // end of image: finish up decoding
            case .imageEnd:
                self.reachedEnd = true
                return nil

            // read a Huffman table
            case .defineHuffmanTable:
                return try self.huffman.readTable(atOffset: inOff)

            // start of frame marker
            case .frameStartLossless:
                let frame = JPEGFrame(self)
                let offset = try frame.readMarker(atOffset: inOff)
                self.currentFrame = frame
                return offset

            // uhhhhhhhhh we should NOT get here
            default:
                return nil
        }
    }

    // MARK: - IO
    /**
     * Reads a given type from the internal buffer taking into account endianness.
     */
    internal func readEndian<T>(_ offset: Int) -> T where T: EndianConvertible {
        return self.data.readEndian(offset, .big)
    }

    /**
     * Reads the given type from the internal data buffer at the provided offset.
     */
    internal func read<T>(_ offset: Int) -> T where T: ExpressibleByIntegerLiteral {
        return self.data.read(offset)
    }

    /**
     * Returns a subset of the file's data.
     */
    internal func readRange(_ range: Range<Data.Index>) -> Data {
        return self.data.readRange(range)
    }

    // MARK: - Errors
    /**
     * Error situations during decoding
     */
    enum DecodeError: Error {
        /// Invalid marker encountered (probably implementation error, maybe corrupt file)
        case invalidMarker(_ marker: UInt16)
        /// Unknown/unsupported marker type
        case unknownMarker(_ marker: UInt16)

        /// Failed to reach the end of the image. It may be corrupt
        case noEndOfImage
    }

    /**
     * Issues with the overall data
     */
    enum FormatError: Error {
        /// Failed to find the SOI marker at the start of the file
        case missingSOI(_ actual: UInt16)
    }
}
