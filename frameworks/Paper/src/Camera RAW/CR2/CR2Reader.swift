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

    /// Main metadata chunk
    private var metadata: TIFFReader.IFD!
    /// Canon MakerNotes tags (this contains info relevant for RAW decoding)
    private var canon: TIFFReader.IFD!

    /// Sensor size and borders
    private var sensor: SensorInfo!

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
            0x927C,
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
        } else if minor != 0 {
            DDLogWarn("Minor version is not 0 - this has not been tested!")
            throw HeaderError.unsupportedVersion(fileMajor: major, fileMinor: minor)
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
        self.metadata = ifd

        // grab the exif chunk
        guard let exifTag = ifd.getTag(byId: 0x8769) as? TIFFReader.TagSubIfd,
              let exif = exifTag.value.first else {
            throw RawError.missingTag(0x8769)
        }
        self.image.exif = exif

        // grab the markernote chunk
        guard let mnTag = exif.getTag(byId: 0x927C) as? TIFFReader.TagSubIfd,
              let mn = mnTag.value.first else {
            throw RawError.missingTag(0x927C)
        }
        self.canon = mn

        DDLogDebug("Canon MakerNotes: \(String(describing: self.canon))")

        // identify the camera from the model ID
        try self.identifyModel()

        // read some metadata into a more digestible format
        try self.decodeSensorInfo()
        try self.decodeColorData()
        try self.readDustRecords()

    }

    /**
     * Identifies the camera based on the model ID value in the maker notes. This will validate that the
     * camera type is in fact supported.
     */
    private func identifyModel() throws {
        // read model ID value
        guard let idTag = self.canon.getTag(byId: 0x0010) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0010)
        }

        DDLogDebug("Model id: 0x\(String(idTag.value, radix: 16))")

        // only 6Dii is supported atm
        guard idTag.value == 0x80000406 else {
            throw RawError.unsupportedModel(idTag.value)
        }
    }

    /**
     * Reads information about sensor borders from the maker notes.
     *
     * This is tag 0x00E0 in the makernotes info bundle, an array of integer values:
     * - 1..2: Sensor width and height
     * - 5..8: Data borders (left going clockwise)
     */
    private func decodeSensorInfo() throws {
        // get the SensorInfo array
        guard let i = self.canon.getTag(byId: 0x00E0) as? TIFFReader.TagUnsignedArray else {
            throw RawError.missingTag(0x00E0)
        }

        var sensor = SensorInfo()

        // copy the sensor size
        sensor.width = Int(i.value[1])
        sensor.height = Int(i.value[2])

        // borders
        sensor.borderLeft = Int(i.value[5])
        sensor.borderTop = Int(i.value[6])
        sensor.borderRight = Int(i.value[7])
        sensor.borderBottom = Int(i.value[8])

        // done
        self.sensor = sensor
        DDLogDebug("Sensor info: \(String(describing: self.sensor))")
    }

    /**
     * Attempts to read the color data information; the value contains the version of the record.
     */
    private func decodeColorData() throws {
        // get ColorData blob
        guard let i = self.canon.getTag(byId: 0x4001) as? TIFFReader.TagUnsignedArray else {
            throw RawError.missingTag(0x4001)
        }

        // get version
        let vers = i.value[0]
        DDLogDebug("ColorData version: \(vers)")
    }

    /**
     * Reads the dust records table
     */
    private func readDustRecords() throws {
        // get dust delete data blob
        guard let i = self.canon.getTag(byId: 0x0097) as? TIFFReader.TagByteSeq else {
            throw RawError.missingTag(0x0097)
        }

        // get version
        let data = i.value
        let vers: UInt8 = data.read(0)
        DDLogDebug("Dust Delete Data version: \(vers)")
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
        DDLogDebug("Raw data IFD: \(ifd)")

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

        // read the location of the raw image data
        guard let offset = ifd.getTag(byId: 0x0111) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0111)
        }
        guard let length = ifd.getTag(byId: 0x0117) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0117)
        }

        // try to decompress it, followed by de-slicing
        try self.decompressRawData(Int(offset.value),
                                   length: Int(length.value))

        if slices.value[0] != 0 {
            // TODO: de-slicing
            DDLogError("Requested deslicing: \(slices)")
        }



        // convert it into one contiguous plane of sensor data
        let bytes = Int(width.value * height.value * 2)
        let data = NSMutableData(length: bytes)

        for i in 0...3 {
            if let plane = self.jpeg.getPlane(i) {
                self.image.rawPlanes.append(plane)
            }
        }

        self.image.rawValues = data as Data?
    }

    /**
     * Decompresses raw data.
     *
     * In the CR2 file, raw pixel data is compressed using the JPEG lossless (ITU-T81) algorithm.
     */
    private func decompressRawData(_ offset: Int, length: Int) throws {
        self.jpeg = try JPEGDecoder(withData: &self.data, offset: offset)
        try self.jpeg.decode()
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
        /// The camera model is not supported
        case unsupportedModel(_ modelId: UInt32)
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
