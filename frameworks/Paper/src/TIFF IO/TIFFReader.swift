//
//  TIFFReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Provides an event-driven TIFF format parser.
 */
internal class TIFFReader {
    /// Data containing file contents
    private var data: Data

    // MARK: - Initialization
    /**
     * Initializes a TIFF reader with the provided image data.
     */
    init(withData data: Data) {
        self.data = data
    }

    /**
     * Initializes a TIFF reader for reading from the provided URL. The contents are loaded (using memory
     * mapped IO if available) automatically.
     */
    convenience init(fromUrl url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        self.init(withData: data)
    }

    // MARK: External API
    /**
     *
     */

    // MARK: Reading
    enum ByteOrder {
        case little
        case big
    }

    /// Byte order of the loaded file
    private var order: ByteOrder = .little

    /**
     * Decodes the header of the file to read endianness and version. This also provides the offset to the
     * first IFD.
     */
    private func readHeader() throws {
        // read byte order marker
        let bom: UInt16 = self.read(0)

        if bom == 0x4949 {
            self.order = .little
        } else if bom == 0x4D4D {
            self.order = .big
        } else {
            throw HeaderError.unsupportedEndian(bom)
        }

        // validate version
        let vers: UInt16 = self.readEndian(2)

        if vers != 42 {
            throw HeaderError.unknownVersion(vers)
        }

        // offset of first IFD
        let off: UInt32 = self.readEndian(4)

        DDLogVerbose("First IFD offset: \(off)")
    }

    // MARK: Data reading
    /**
     * Reads a given type from the internal buffer taking into account endianness.
     */
    internal func readEndian<T>(_ offset: Int) -> T where T: EndianConvertible {
        let v: T = self.read(offset)

        switch self.order {
            case .little:
                return T(littleEndian: v)
            case .big:
                return T(bigEndian: v)
        }
    }

    /**
     * Reads the given type from the internal data buffer at the provided offset.
     */
    internal func read<T>(_ offset: Int) -> T where T: ExpressibleByIntegerLiteral {
        var v: T = 0
        let len = MemoryLayout<T>.size

        _ = Swift.withUnsafeMutableBytes(of: &v, {
            self.data.copyBytes(to: $0, from: offset..<(offset+len))
        })

        return v
    }

    // MARK: Errors
    /**
     * Header errors
     */
    enum HeaderError: Error {
        /// Unsupported endianness
        case unsupportedEndian(_ read: UInt16)
        /// Unknown version
        case unknownVersion(_ read: UInt16)
    }
}

protocol EndianConvertible: ExpressibleByIntegerLiteral {
    init(littleEndian: Self)
    init(bigEndian: Self)
}

extension UInt16: EndianConvertible {}
extension UInt32: EndianConvertible {}
