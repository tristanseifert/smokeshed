//
//  JPEGScan.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200616.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Represents a single scan in a JPEG file. Scans are synonymous with passes through compressed data.
 *
 * Most files will only have a single scan.
 */
internal class JPEGScan: CustomStringConvertible {
    /// Decoder that is reading this frame
    private weak var jpeg: JPEGDecoder?

    /// Pretty description string
    var description: String {
        return String(format: "<scan: predictor %u, pt transform %u, components: %@>",
                      self.predictor, self.ptTransform, self.components)
    }

    // MARK: - Properties
    /// Predictor type
    private(set) internal var predictor: Int = 0
    /// Point transform
    private(set) internal var ptTransform: Int = 0

    /// Components consumed by the scan
    private(set) internal var components: [Component] = []

    // MARK: - Initialization
    /**
     * Creates a new JPEG scan tied to the given decoder.
     */
    internal init(_ decoder: JPEGDecoder) {
        self.jpeg = decoder
    }

    // MARK: - SOS marker
    /**
     * Reads the SOS marker from the given file offset.
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

        // decode scan info
        try self.decodeSoS(chunk)

        return (offset + 2 + Int(length))
    }

    /**
     * Decodes the start of scan header provided in the data object.
     */
    private func decodeSoS(_ data: Data) throws {
        // read the number of components
        let numComponents: UInt8 = data.read(Self.offsetNumComponents)

        guard numComponents >= 1 && numComponents <= 4 else {
            throw ReadError.invalidComponentCount(numComponents)
        }

        var componentData = data.advanced(by: Self.offsetComponentInfo)

        // decode each component
        for _ in 0..<numComponents {
            self.components.append(try self.componentFrom(chunk: componentData))

            // slice off the bytes for this component
            if componentData.count > 3 {
                componentData = componentData.advanced(by: Self.componentSize)
            }
        }

        // read the predictor value
        let Ss: UInt8 = componentData.read(Self.offsetSs)

        guard Ss >= 1 && Ss <= 7 else {
            throw ReadError.invalidPredictor(Ss)
        }

        self.predictor = Int(Ss)

        // end of spectral selection must be 0
        let Se: UInt8 = componentData.read(Self.offsetSe)

        guard Se == 0 else {
            throw ReadError.invalidSe(Se)
        }

        // get point transform
        let Ahl: UInt8 = componentData.read(Self.offsetAhl)
        self.ptTransform = Int((Ahl & 0x0F))

        // TODO: checking if we read the right amount of data
        DDLogVerbose("Decoded SoS: \(String(describing: self))")
    }

    /**
     * Decodes a component descriptor from the provided data.
     */
    private func componentFrom(chunk data: Data) throws -> Component {
        var c = Component()

        // input component value
        c.inComponent = data.read(Self.offsetComponentId)

        // read the table identifier
        let tables: UInt8 = data.read(Self.offsetTableIds)

        let Tdj = ((tables & 0xF0) >> 4)
        let Taj = (tables & 0x0F)

        // dc coding table must be 0-3
        guard let dcTable = JPEGDecoder.TableId(rawValue: Tdj) else {
            throw ReadError.invalidDcTable(Int(Tdj))
        }
        c.dcTable = dcTable

        // ac coding table must be 0 for lossless
        guard Taj == 0 else {
            throw ReadError.invalidAcTable(Int(Taj))
        }

        return c
    }

    // MARK: - Types
    /**
     * Represents a single component that will be scanned
     */
    internal struct Component: CustomStringConvertible {
        /// Pretty description string
        var description: String {
            return String(format: "<input component: %02x, dc table: %d, ac table: %d>",
                          self.inComponent, self.dcTable.rawValue,
                          self.acTable.rawValue)
        }

        /// Unique component identifier from which to read
        fileprivate(set) internal var inComponent: UInt8 = 0
        /// Table to use for DC entropy coding
        fileprivate(set) internal var dcTable: JPEGDecoder.TableId = .table0
        /// Table to use for AC entropy coding
        fileprivate(set) internal var acTable: JPEGDecoder.TableId = .table0
    }

    // MARK: - Offsets
    /// Length field (including two bytes for length)
    static let offsetLength: Int = 2
    /// Offset to the first byte of component information
    static let offsetTableStart: Int = 4

    // Offsets below are relative to the first byte of payload
    /// Total number of image components
    static let offsetNumComponents: Int = 0
    /// First byte of component info
    static let offsetComponentInfo: Int = 1

    // Offsets below are relative to the first byte of component data
    /// Offset to the component identifier field
    static let offsetComponentId: Int = 0
    /// Entropy coding table indices
    static let offsetTableIds: Int = 1

    // Offsets below are relative to the first byte after component data
    /// Start of spectral / predictor selection; 1-7 for lossless
    static let offsetSs: Int = 0
    /// End of spectral / predictor selection; 0
    static let offsetSe: Int = 1
    /// Point transform in low 4 bits (0-15)
    static let offsetAhl: Int = 2

    /// Length of a component descriptor
    static let componentSize: Int = 2

    // MARK: - Errors
    /**
     * Decoding errors
     */
    private enum ReadError: Error {
        /// Invalid number of components (must be 1-4)
        case invalidComponentCount(_ actual: UInt8)
        /// Invalid predictor value (must be 1-7)
        case invalidPredictor(_ actual: UInt8)
        /// End of spectral selection field is invalid (must be 0)
        case invalidSe(_ actual: UInt8)
        /// DC coding table is invalid (must be 0-3)
        case invalidDcTable(_ actual: Int)
        /// AC coding table is invalid (must be 0 for lossless)
        case invalidAcTable(_ actual: Int)
    }
}
