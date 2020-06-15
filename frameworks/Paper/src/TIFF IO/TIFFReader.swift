//
//  TIFFReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation
import Combine

import CocoaLumberjackSwift

/**
 * Provides an event-driven TIFF format parser.
 */
public class TIFFReader {
    /// Reader configuration
    private(set) internal var config: TIFFReaderConfig
    /// Data containing file contents
    private var data: Data

    /// Total number of TIFF file bytes read
    internal var length: Int {
        get {
            return data.count
        }
    }

    // MARK: - Initialization
    /**
     * Initializes a TIFF reader with the provided image data and configuration.
     */
    public init(withData data: Data, _ config: TIFFReaderConfig) throws {
        self.config = config
        self.data = data

        // validate the image is TIFF
        try self.readHeader()
    }

    /**
     * Initializes a TIFF reader for reading from the provided URL. The contents are loaded (using memory
     * mapped IO if available) automatically, and parsed with the specified configuration.
     */
    public convenience init(fromUrl url: URL, _ config: TIFFReaderConfig) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(withData: data, config)
    }

    /**
     * Initializes a TIFF reader for reading from the provided URL. The contents are loaded (using memory
     * mapped IO if available) automatically.
     */
    public convenience init(fromUrl url: URL) throws {
        try self.init(fromUrl: url, TIFFReaderConfig.standard)
    }

    // MARK: External API
    /**
     * Reads the file, following the chain of IFDs to the end. Each discovered IFD is published to the
     * publisher. Once this call returns, all IFDs will have been discovered.
     */
    public func decode() {
        // guard against no IFDs existing
        guard self.firstDir != 0 else {
            return
        }

        // decode each IFD
        do {
            var offset: Int? = Int(self.firstDir)

            while let i = offset {
                offset = try self.readIfd(from: i)
            }
        } catch {
            return self.publisher.send(completion: .failure(error))
        }

        // if we get here, we completed successfully
        self.publisher.send(completion: .finished)
    }

    // MARK: - Decoding
    /// Publisher for decoded image directories
    private(set) public var publisher = PassthroughSubject<IFD, Error>()

    // MARK: Header
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
        self.firstDir = self.readEndian(4)

        if self.firstDir > self.data.count {
            throw HeaderError.invalidIfdOffset(self.firstDir)
        }
    }

    // MARK: IFDs
    /**
     * Decodes the IFD at the given byte offset; the decoded object is published. The offset of the next IFD
     * is returned.
     */
    private func readIfd(from offset: Int) throws -> Int? {
        // attempt to create the IFD
        let ifd = try IFD(inFile: self, offset, index: self.ifds.count)
        try ifd.decode()

        self.ifds.append(ifd)
        self.publisher.send(ifd)

        return ifd.nextOff
    }

    // MARK: - Reading
    enum ByteOrder {
        case little
        case big
    }

    /// Byte order of the loaded file
    private var order: ByteOrder = .little
    /// File offset of the first IFD
    private var firstDir: UInt32 = 0

    /// All IFDs in this file
    private var ifds: [IFD] = []

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

    /**
     * Returns a subset of the file's data.
     */
    internal func readRange(_ range: Range<Data.Index>) -> Data {
        return self.data.subdata(in: range)
    }

    // MARK: - Errors
    /**
     * Header errors
     */
    enum HeaderError: Error {
        /// Unsupported endianness
        case unsupportedEndian(_ read: UInt16)
        /// Unknown version
        case unknownVersion(_ read: UInt16)
        /// The offset to the first IFD is invalid
        case invalidIfdOffset(_ read: UInt32)
    }
}

/// Provide initializers for converting from big/little endian types
public protocol EndianConvertible: ExpressibleByIntegerLiteral {
    init(littleEndian: Self)
    init(bigEndian: Self)
}

extension Int16: EndianConvertible {}
extension UInt16: EndianConvertible {}
extension Int32: EndianConvertible {}
extension UInt32: EndianConvertible {}
