//
//  JPEGFrame.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200615.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Represents a single frame in a JPEG image.
 */
internal class JPEGFrame: CustomStringConvertible {
    /// Decoder that is reading this frame
    private weak var jpeg: JPEGDecoder?

    /// Pretty description string
    var description: String {
        return String(format: "<frame: %u bit components, %u lines, %u samples per line, components: %@>",
                      self.precision, self.numLines, self.samplesPerLine,
                      self.components)
    }

    // MARK: - Properties
    /// Precision of each sample, in bits
    private(set) internal var precision: UInt8 = 0
    /// Vertical resolution (number of lines)
    private(set) internal var numLines: UInt16 = 0
    /// Horizontal resolution (samples/line)
    private(set) internal var samplesPerLine: UInt16 = 0

    /// Components in this frame
    private(set) internal var components: [Component] = []

    // MARK: - Initialization
    /**
     * Creates a new JPEG frame tied to the given decoder.
     */
    internal init(_ decoder: JPEGDecoder) {
        self.jpeg = decoder
    }

    // MARK: - SOF marker
    /**
     * Reads the SOF marker from the given file offset.
     *
     * - Returns: Offset to the next marker
     */
    internal func readMarker(atOffset offset: Int) throws -> Int? {
        // read the length of the payload and extract it
        let length: UInt16 = self.jpeg!.readEndian(offset + Self.offsetLength)
        let tableBytes = Int(length) - 2

        let tableOffset = offset + Self.offsetTableStart
        let tableRange = tableOffset..<(tableOffset+tableBytes)
        let chunk = self.jpeg!.readRange(tableRange)

        // decode frame info
        try self.decodeSoF(chunk)

        return (offset + 2 + Int(length))
    }

    /**
     * Decodes the start of frame header provided in the data object.
     */
    private func decodeSoF(_ data: Data) throws {
        // read precision
        self.precision = data.read(Self.offsetPrecision)

        guard self.precision >= 2 && self.precision <= 16 else {
            throw ReadError.invalidPrecision(precision)
        }

        // horizontal and vertical resolution
        self.numLines = data.readEndian(Self.offsetY, .big)
        self.samplesPerLine = data.readEndian(Self.offsetX, .big)

        // number of components
        let numComponents: UInt8 = data.read(Self.offsetNumComponents)
        var componentData = data.advanced(by: Self.offsetComponentInfo)

        // decode each component
        for _ in 0..<numComponents {
            self.components.append(try self.componentFrom(chunk: componentData))

            // slice off the bytes for this component
            if componentData.count > 3 {
                componentData = componentData.advanced(by: Self.componentSize)
            }
        }

        // TODO: checking if we read the right amount of data
        DDLogVerbose("Decoded SoF: \(String(describing: self))")
    }

    /**
     * Decodes a component descriptor from the provided data.
     */
    private func componentFrom(chunk data: Data) throws -> Component {
        var c = Component()

        // read identifier
        c.id = data.read(Self.offsetIdent)

        // read the Hi/Vi field
        let factors: UInt8 = data.read(Self.offsetFactors)

        c.xFactor = Int((factors & 0xF0) >> 4)
        c.yFactor = Int((factors & 0x0F))

        return c
    }

    // MARK: - Types
    /**
     * Represents a single component in the image.
     */
    internal struct Component: CustomStringConvertible {
        /// Pretty description string
        var description: String {
            return String(format: "<component %02x: x sampling: %d, y sampling: %d>", self.id, self.xFactor, self.yFactor)
        }

        /// Unique component identifier
        fileprivate(set) internal var id: UInt8 = 0
        /// Horizontal sampling factor
        fileprivate(set) internal var xFactor: Int = 0
        /// Vertical sampling factor
        fileprivate(set) internal var yFactor: Int = 0

        // We don't read the quantaziation table field; it must be 0 for lossless
    }

    // MARK: - Offsets
    /// Length field (including two bytes for length)
    static let offsetLength: Int = 2
    /// Offset to the first byte of frame information
    static let offsetTableStart: Int = 4

    // Offsets below are relative to the first data byte
    /// Offset to sample precision field
    static let offsetPrecision: Int = 0
    /// Number of lines (Y)
    static let offsetY: Int = 1
    /// Number of samples per line (X)
    static let offsetX: Int = 3
    /// Total number of image components
    static let offsetNumComponents: Int = 5
    /// Start of image component data
    static let offsetComponentInfo: Int = 6

    // Offsets below are relative to the first byte of a component descriptor
    /// Identifier of the component
    static let offsetIdent: Int = 0
    /// Sampling factors
    static let offsetFactors: Int = 1

    /// Length of a component descriptor
    static let componentSize: Int = 3

    // MARK: - Errors
    /**
     * Decoding errors
     */
    private enum ReadError: Error {
        /// Invalid precision value (must be 2-16)
        case invalidPrecision(_ actual: UInt8)
    }
}
