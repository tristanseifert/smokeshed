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
            // decode markers by default
            if !self.isDecoding {
                offset = try self.decodeMarker(atOffset: i)
            }
            // otherwise, decompress image data until the next non-0xFF00 marker
            else {
                offset = try self.decompress(startingAt: i)
            }
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

    /// Is the next token to be read a part of image data that must be decoded?
    private var isDecoding: Bool = false
    /// Currently processing frame
    private var currentFrame: JPEGFrame? = nil
    /// Scan descriptor that's currently being used
    private var currentScan: JPEGScan? = nil

    /**
     * Attempts to identify the marker at the given file index, if possible. The offset past the end of this
     * marker is returned, if known.
     */
    private func decodeMarker(atOffset inOff: Int) throws -> Int? {
        var outOffset: Int? = nil

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
                outOffset = (inOff + 2)
            // end of image: finish up decoding
            case .imageEnd:
                self.reachedEnd = true

            // read a Huffman table
            case .defineHuffmanTable:
                outOffset = try self.huffman.readTable(atOffset: inOff)

            // start of frame marker
            case .frameStartLossless:
                let frame = JPEGFrame(self)
                outOffset = try frame.readMarker(atOffset: inOff)
                self.currentFrame = frame

            // start of scan marker: next byte is image data
            case .scanStart:
                let scan = JPEGScan(self)
                outOffset = try scan.readMarker(atOffset: inOff)

                self.currentScan = scan

                // set up decoder if required
                if !self.isDecoding {
                    try self.prepareForDecompression()
                }
                self.isDecoding = true

            // escape code (for 0xFF input data) should never happen here
            case .ffEscape:
                throw DecodeError.unexpectedMarker(rawMarker)
        }

        // return the next offset to read from
        return outOffset
    }

    // MARK: - Image decoding
    /// Output bit planes for each component
    private var planes: [UInt8: [UInt16]] = [:]

    /// Line being decompressed
    private var currentLine: Int = 0
    /// Column being decompressed
    private var currentSample: Int = 0

    /**
     * Prepares to decode pixel data.
     *
     * The file format is validated to make sure it fits within the constraints of this decoder; then, bit planes
     * are allocated for each of the components output values.
     */
    private func prepareForDecompression() throws {
        guard let frame = self.currentFrame else {
            throw DecompressError.invalidState
        }

        // each component must have x/y sampling of 1
        for component in frame.components {
            guard component.xFactor == 1 && component.yFactor == 1 else {
                throw DecompressError.invalidSampling(component)
            }
        }

        // great, allocate the output bit planes
        let numPixels = Int(frame.samplesPerLine) * Int(frame.numLines)

        for component in self.currentFrame!.components {
            let data = [UInt16](repeating: 0, count: numPixels)
            self.planes[component.id] = data
        }

        // clear the row/line counters
        self.currentLine = 0
        self.currentSample = 0
    }

    /**
     * Decompresses image data until the next marker, starting at the provided file offset.
     *
     * - Returns: Offset of next marker, if not EoF
     */
    private func decompress(startingAt: Int) throws -> Int? {
        // decompress data from the stream
        let stream = JPEGBitstream(withData: self.data.advanced(by: startingAt))

        do {
            try self.actuallyDecompress(stream)
        }
        // failed to read a Huffman code; probably found a marker
        catch HuffmanTree<UInt8>.TreeErrors.bitReadFailed {
            self.isDecoding = false
            return (startingAt + stream.rdOffset)
        }

        // return input offset plus the number of bytes read
        return (startingAt + stream.rdOffset)
    }

    /**
     * Inner decompression loop
     */
    private func actuallyDecompress(_ stream: JPEGBitstream) throws {
        guard let frame = self.currentFrame, let scan = self.currentScan else {
            throw DecompressError.invalidState
        }

        // read all line
        while self.currentLine < frame.numLines {
            // offset into the current row in the plane
            let rowOff = self.currentLine * Int(frame.samplesPerLine)

            // read all samples in each line
            while self.currentSample < frame.samplesPerLine {
                // offset into the current column
                let off = rowOff + self.currentSample

                // read data for each component
                for c in scan.components {
                    // read the Huffman encoded bit length
                    let bits = try self.huffman.decodeValue(fromTable: c.dcTable, stream)

                    // then, read that amount of data
                    guard let value = stream.readString(Int(bits)) else {
                        throw HuffmanTree<UInt8>.TreeErrors.bitReadFailed
                    }

                    // shove it into the Predictor™
                    let delta = UInt16(value)

                    // store the value
                    self.planes[c.inComponent]![off] = delta
                }

                // move on to the next sample
                self.currentSample += 1
            }

            // end of column
            DDLogVerbose("Finished line \(self.currentLine)")

            self.currentSample = 0
            self.currentLine += 1
        }

        // finished decoding
        self.isDecoding = false
    }

    // MARK: - Accessing
    /**
     * Returns the plane for the component with the given index.
     */
    public func getPlane(_ index: Int) -> [UInt16]? {
        // get the plane's identifier
        guard let id = self.currentFrame?.components[index].id else {
            return nil
        }

        // return the plane itself
        return self.planes[id]
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

    // MARK: - Types
    /**
     * A Huffman table slot
     */
    internal enum TableId: UInt8 {
        case table0 = 0
        case table1 = 1
        case table2 = 2
        case table3 = 3
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
        /// The read marker was recognized, but read in an unexpected location.
        case unexpectedMarker(_ marker: UInt16)

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

    /**
     * Image data decompression errors
     */
    enum DecompressError: Error {
        /// The decompressor is in an invalid state
        case invalidState
        /// Invalid sampling factor for the provided component
        case invalidSampling(_ component: JPEGFrame.Component)
    }
}
