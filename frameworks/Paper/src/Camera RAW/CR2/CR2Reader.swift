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
    /// White balance and other color info
    private var color: ColorInfo!
    
    /// Whether raw image data should be decoded
    private var shouldDecodeRaw: Bool = false
    /// Should thumbnails be decoded?
    private var shouldDecodeThumbs: Bool = false

    // MARK: - Initialization
    /**
     * Creates a Canon RAW file with an in-memory data object.
     *
     * This initializer will validate that the file is, in fact, a CR2 file by reading some values from the first
     * few bytes of the file.
     */
    public init(withData data: Data, decodeRawData: Bool, decodeThumbs: Bool) throws {
        self.data = data
        
        self.shouldDecodeRaw = decodeRawData
        self.shouldDecodeThumbs = decodeThumbs

        // TIFF reading config
        var cfg = TIFFReaderConfig()

        cfg.subIfdUnsignedOverrides.append(contentsOf: [
            // EXIF
            0x8769,
            // GPS
            0x8825,
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
    public convenience init(fromUrl url: URL, decodeRawData: Bool, decodeThumbs: Bool) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(withData: data, decodeRawData: decodeRawData,
                      decodeThumbs: decodeThumbs)
    }

    // MARK: - Decoding
    /// File offset to the IFD representing raw data
    private var rawIfdFileOff: Int = -1
    /// Image file we build up during processing
    private var image: CR2Image = CR2Image()
    /// TIFF metadata parser
    private var meta = TIFFMetadataReader()
    
    /**
     * Decodes the RAW image.
     */
    public func decode() throws -> CR2Image {
        // read tiff blocks until no more come back
        while let ifd = try self.tiff.decode() {
            try self.handleIfd(ifd)
        }
        
        // get metadata
        self.image.meta = self.meta.finalize()
        try self.updateExif()

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
            try self.meta.addIfd(ifd)
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
     * Grabs various metadata from the Canon-specific metadata fields.
     */
    private func extractMetadata(_ ifd: TIFFReader.IFD) throws {
        // just copy the object
        self.metadata = ifd

        // grab the exif chunk, and from it, the MakerNote field
        guard let exifTag = ifd.getTag(byId: 0x8769) as? TIFFReader.TagSubIfd,
              let exif = exifTag.value.first else {
            throw RawError.missingTag(0x8769)
        }
        guard let mnTag = exif.getTag(byId: 0x927C) as? TIFFReader.TagSubIfd,
              let mn = mnTag.value.first else {
            throw RawError.missingTag(0x927C)
        }
        self.canon = mn

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
    }

    /**
     * Attempts to read the color data information; the value contains the version of the record.
     */
    private func decodeColorData() throws {
        // get ColorData blob
        guard let tag = self.canon.getTag(byId: 0x4001) as? TIFFReader.TagUnsignedArray else {
            throw RawError.missingTag(0x4001)
        }

        // get version
        let vers = tag.value[0]
        
        guard vers == 15 else {
            DDLogWarn("Unsupported ColorData version: \(vers)")
            return
        }
        
        var color = ColorInfo()
        
        // read the WB_RGGBLevelsAsShot field (4 signed 16 bit ints)
        for i in 63..<67 {
            let read = Int16(tag.value[i])
            color.wbRggbLevelsAsShot.append(read)
        }
        
        // done
        self.color = color
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
    }
    
    /**
     * Updates the EXIF dictionary with some information from the MakerNote field.
     */
    private func updateExif() throws {
        // camera settings
        if let settings = self.canon.getTag(byId: 0x0001) as? TIFFReader.TagUnsignedArray {
            // lens ID is at index 22
            self.image.meta.exif!.lensId = UInt(settings.value[22])
        }
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
        guard self.shouldDecodeThumbs else { return }
        
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
    /// Destination buffer for unslicing
    private var unsliceBuf: NSMutableData!
    /// Unslicing implementation (ObjC wrapper around the C functions)
    private var unslicer: CR2Unslicer!

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

        // read the raw image size
        guard let width = ifd.getTag(byId: 0x0100) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0100)
        }
        guard let height = ifd.getTag(byId: 0x0101) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0101)
        }

        self.image.rawSize = CGSize(width: Int(width.value),
                                    height: Int(height.value))

        // bail out if we don't actually want raw data decompressed
        guard self.shouldDecodeRaw else {
            return
        }

        // read the de-slicing information for later
        guard let slices = ifd.getTag(byId: 0xc640) as? TIFFReader.TagUnsignedArray else {
            throw RawError.missingTag(0xc640)
        }
        
        // read the location of the raw image data
        guard let offset = ifd.getTag(byId: 0x0111) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0111)
        }
        guard let length = ifd.getTag(byId: 0x0117) as? TIFFReader.TagUnsigned else {
            throw RawError.missingTag(0x0117)
        }

        // decompress lossless JPEG data
        try self.decompressRawData(Int(offset.value),
                                   length: Int(length.value))

        // allocate output buffer and unslice image
        let bytes = Int(width.value * height.value * 2)
        self.unsliceBuf = NSMutableData(length: bytes)

        try self.unslice(slices.value)

        self.image.rawValues = self.unsliceBuf as Data?
        
        // calculate the vshift for the raw image
        self.image.rawValuesVshift = self.calculateRawVshift()

        // copy the output plane
        self.image.rawPlanes.append(self.jpeg.decompressor.output as Data)
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

    /**
     * Converts raw data from its sliced format into one big plane containing the RG/GB values.
     */
    private func unslice(_ sliceInfo: [UInt32]) throws {

        // create and configure unslicer
        var slicingInfo: [NSNumber] = []
        for x in sliceInfo {
            slicingInfo.append(NSNumber(value: x))
        }

        let size = CGSize(width: self.sensor.width, height: self.sensor.height)

        self.unslicer = CR2Unslicer(input: self.jpeg.decompressor,
                                    andOutput: self.unsliceBuf,
                                    slicingInfo: slicingInfo, sensorSize: size)

        // let er rip
        self.unslicer.unslice()
    }
    
    /**
     * Determine whether the first row of image data is likely to be the RG row of the Bayer array, or if it is
     * shifted by one and is the GB row.
     */
    private func calculateRawVshift() -> Int {
        let borders: [Int] = [
            self.sensor.borderTop, self.sensor.borderRight,
            self.sensor.borderBottom, self.sensor.borderLeft
        ]
        
        return self.unslicer.calculateBayerShift(withBorders: borders as [NSNumber])
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
