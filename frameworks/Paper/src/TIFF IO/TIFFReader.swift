//
//  TIFFReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

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
    public init(withData data: inout Data, _ config: TIFFReaderConfig) throws {
        self.config = config
        self.data = data

        // validate the image is TIFF
        try self.readHeader()
    }

    // MARK: External API
    /**
     * Decodes the next IFD. If nil is returned, all IFDs were decoded.
     */
    public func decode() throws -> IFD? {
        // guard against no IFDs existing
        guard self.firstDir != 0 else {
            return nil
        }

        // try the next offset
        guard let offset = self.currentOffset else {
            return nil
        }

        let next = try self.readIfd(from: offset)
        self.currentOffset = next.nextOff
        return next
    }

    // MARK: - Decoding
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

        if self.firstDir != 0 {
            self.currentOffset = Int(self.firstDir)
        }

        if self.firstDir > self.data.count {
            throw HeaderError.invalidIfdOffset(self.firstDir)
        }
    }

    // MARK: IFDs
    /**
     * Decodes the IFD at the given byte offset; the decoded object is published. The offset of the next IFD
     * is returned.
     */
    private func readIfd(from offset: Int) throws -> IFD{
        // attempt to create the IFD
        let ifd = try IFD(inFile: self, offset, index: self.ifdIndex, single: false)
        try ifd.decode()

        self.ifdIndex += 1

        return ifd
    }

    // MARK: - Reading
    /// Byte order of the loaded file
    private var order: Data.ByteOrder = .little
    /// File offset of the first IFD
    private var firstDir: UInt32 = 0
    /// Index of the current IFD
    private var ifdIndex: Int = 0
    /// Current decoding offset
    private var currentOffset: Int? = nil

    /**
     * Reads a given type from the internal buffer taking into account endianness.
     */
    internal func readEndian<T>(_ offset: Int) -> T where T: EndianConvertible {
        return self.data.readEndian(offset, self.order)
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
