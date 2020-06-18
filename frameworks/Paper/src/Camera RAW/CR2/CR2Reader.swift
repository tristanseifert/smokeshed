//
//  CR2Reader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation
import CoreGraphics

import CocoaLumberjackSwift

/**
 * Implements an event-driven reader for the Canon RAW version 2 files.
 *
 * Based mostly on [previous documentation](http://lclevy.free.fr/cr2/) of the file format, and
 * the existing TIFF file reader.
 */
public class CR2Reader {
    /// Data object containing the RAW file data
    private var data: Data

    /// TIFF reader used to access the raw file
    private var tiff: TIFFReader

    /// JPEG decoder for the RAW data
    private var jpeg: JPEGDecoder!

    // MARK: - Initialization
    /**
     * Creates a Canon RAW file with an in-memory data object.
     *
     * This initializer will validate that the file is, in fact, a CR2 file by reading some values from the first
     * few bytes of the file.
     */
    public init(withData data: Data) throws {
        self.data = data

        // TIFF reading config
        var cfg = TIFFReaderConfig()

        cfg.subIfdUnsignedOverrides.append(contentsOf: [
            // EXIF
            0x8769
        ])
        cfg.subIfdByteSeqOverrides.append(contentsOf: [
            // MakerNotes
            0x927c
        ])

        // set up TIFF reader and validate CR2 header
        self.tiff = try TIFFReader(withData: &self.data, cfg)
        try self.readHeader()
    }

    /**
     * Creates a Canon RAW file by reading from the given URL.
     */
    public convenience init(fromUrl url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(withData: data)
    }

    // MARK: - Decoding
    /// File offset to the IFD representing raw data
    private var rawIfdFileOff: Int = -1
    /// Image file we build up during processing
    private var image: CR2Image = CR2Image()

    /**
     * Decodes the RAW image.
     */
    public func decode() throws -> CR2Image {
        // read tiff blocks until no more come back
        while let ifd = try self.tiff.decode() {
            try self.handleIfd(ifd)
        }

        // return the image (fully decoded by now)
        return self.image
    }

    /**
     * Reads the CR2 header from offset 0x08 in the file, and validates the version number matches.
     */
    private func readHeader() throws {
        // read the 'CR' signature
        let sig: UInt16 = self.tiff.read(Self.signatureOffset)

        if sig != 0x5243 {
            throw HeaderError.invalidHeader(fileHeader: sig)
        }

        // major version MUST be 2
        let major: UInt8 = self.tiff.read(Self.majVersionOffset)
        let minor: UInt8 = self.tiff.read(Self.minVersionOffset)

        if major != 2 {
            throw HeaderError.unsupportedVersion(fileMajor: major, fileMinor: minor)
        }

        if minor != 0 {
            DDLogWarn("Minor version is not 0 - this has not been tested!")
        }

        // read the raw data IFD file offset
        let off: UInt32 = self.tiff.readEndian(Self.rawIfdAddressOffset)
        self.rawIfdFileOff = Int(off)
    }

    /**
     * Handles a new IFD from the TIFF decoder.
     *
     * CR2 files typically contain four IFDs:
     * - IFD0: Contains most metadata, including EXIF, and a 1/4 size JPEG thumb.
     * - IFD1: A much smaller (160x120) JPEG encoded thumb
     * - IFD2: Uncompressed planar RGB thumbnail
     * - IFD3: RAW image data (lossless JPEG compression)
     *
     * - Parameter ifd: Image directory block to get data from
     */
    private func handleIfd(_ ifd: TIFFReader.IFD) throws {
        // Is it the raw image ifd?
        if ifd.headerOff == self.rawIfdFileOff {
            try self.extractRawData(ifd)
        }
        // Is it the first ifd (by index)?
        else if ifd.index == 0 {
            try self.extractMetadata(ifd)
            try self.extractJpegThumb(ifd)
        }
        // Is it the second ifd (by index)?
        else if ifd.index == 1 {
            try self.extractJpegThumb(ifd)
        }
    }

    // MARK: - Metadata
    /**
     * Extracts EXIF metadata from the given IFD.
     */
    private func extractMetadata(_ ifd: TIFFReader.IFD) throws {
        // just copy the object
        self.image.metaIfd = ifd
    }

    // MARK: - Thumbnails
    /**
     * Extracts JPEG thumbnail data from the given IFD.
     *
     * This attempts to read JPEG compressed thumb data from several properties: first, `stripOffset`
     * and `stripByteCounts` are checked to see if they point to a sensible thumb image. If they are
     * missing or otherwise point to invalid data, the `thumbnailOffset` and `thumbnailLength`
     * tags are checked.
     */
    private func extractJpegThumb(_ ifd: TIFFReader.IFD) throws {
        // IFD0 has the `stripOffset` and `stripByteCounts` tags
        if let offset = ifd.getTag(byId: 0x0111) as? TIFFReader.TagUnsigned,
           let length = ifd.getTag(byId: 0x0117) as? TIFFReader.TagUnsigned {
            let range = Int(offset.value)..<Int(offset.value + length.value)
            var data = self.tiff.readRange(range)
            try self.decodeJpegThumb(withJpegData: &data)
        }
        // IFD1 has the `thumbnailOffset` and `thumbnailLength` tags
        else if let offset = ifd.getTag(byId: 0x0201) as? TIFFReader.TagUnsigned,
                let length = ifd.getTag(byId: 0x0202) as? TIFFReader.TagUnsigned {
            let range = Int(offset.value)..<Int(offset.value + length.value)
            var data = self.tiff.readRange(range)
            try self.decodeJpegThumb(withJpegData: &data)
        }
        // unknown JPEG thumbnail
        else {
            throw ThumbError.missingThumb(ifdIndex: ifd.index)
        }
     }

    /**
     * Decodes a JPEG thumbnail from the specified data.
     */
    private func decodeJpegThumb(withJpegData data: inout Data) throws {
        // attempt to create an image data provider
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw ThumbError.failedToCreateProvider
        }

        // decode the image and add it to the thumbs array
        guard let img = CGImage(jpegDataProviderSource: provider, decode: nil,
                                shouldInterpolate: false,
                                intent: .perceptual) else {
            throw ThumbError.failedToDecodeJPEG
        }

        self.image.thumbs.append(img)
    }

    // MARK: - Raw data
    /**
     * Extracts the raw pixel data from the image file.
     */
    private func extractRawData(_ ifd: TIFFReader.IFD) throws {
        // compression type must be "old JPEG" (6)
        guard let compression = ifd.getTag(byId: 0x0103) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0103)
        }
        if compression.value != 6 {
            throw RawError.unsupportedCompression(compression.value)
        }

        // read the de-slicing information for later
        guard let slices = ifd.getTag(byId: 0xc640) as? TIFFReader.TagUnsignedArray else {
            throw RawError.missingTag(0xc640)
        }

        // read the raw image size
        guard let width = ifd.getTag(byId: 0x0100) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0100)
        }
        guard let height = ifd.getTag(byId: 0x0101) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0101)
        }

        self.image.rawSize = CGSize(width: Int(width.value),
                                    height: Int(height.value))

        // extract the raw image data
        guard let offset = ifd.getTag(byId: 0x0111) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0111)
        }
        guard let length = ifd.getTag(byId: 0x0117) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0117)
        }

        // try to decompress it
        try self.decompressRawData(Int(offset.value),
                                   length: Int(length.value))

        // de-slice if needed
        if slices.value[0] != 0 {
            // TODO: de-slicing
        }
    }

    /**
     * Decompresses raw data.
     *
     * In the CR2 file, raw pixel data is compressed using the JPEG lossless (ITU-T81) algorithm.
     */
    private func decompressRawData(_ offset: Int, length: Int) throws {
        // create a decoder and perform decoding
        self.jpeg = try JPEGDecoder(withData: &self.data, offset: offset)
        try self.jpeg.decode()

        // process the JPEG decoded planes
        for i in 0...3 {
            if let plane = self.jpeg.getPlane(i) {
                self.image.rawPlanes.append(plane)
            }
        }
    }

    // MARK: - Errors
    enum HeaderError: Error {
        /// The Canon RAW header is invalid. ('CR' signature missing)
        case invalidHeader(fileHeader: UInt16)
        /// File version is not supported
        case unsupportedVersion(fileMajor: UInt8, fileMinor: UInt8)
    }

    enum ThumbError: Error {
        /// No thumbnail in a block we expected to have one
        case missingThumb(ifdIndex: Int)
        /// Failed to create an image data provider
        case failedToCreateProvider
        /// Couldn't decode JPEG data
        case failedToDecodeJPEG
    }

    enum RawError: Error {
        /// Required tags were missing; most likely incompatible file
        case missingTag(_ requiredTagId: UInt16)
        /// Raw data is compressed with an unsupported algorithm
        case unsupportedCompression(_ method: UInt32)
    }

    // MARK: - File offsets
    /// Location of the 'CR' signature
    static let signatureOffset: Int = 8
    /// Canon RAW version, major
    static let majVersionOffset: Int = 10
    /// Canon RAW version, minor
    static let minVersionOffset: Int = 11
    /// File offset to the RAW image IFD
    static let rawIfdAddressOffset: Int = 12
}
