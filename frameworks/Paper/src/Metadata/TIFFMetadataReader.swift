//
//  TIFFMetadataReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200619.
//

import Foundation

/**
 * Consumes TIFF IFDs and extracts any known metadata out of them.
 */
internal class TIFFMetadataReader {
    /// Metadata object that we're building up
    private var meta = ImageMeta()
    
    /// Date formatter for reading TIFF dates
    private var tiffDates = DateFormatter()
    /// Formatter for parsing GPS date string (yyyy:mm:dd)
    private var dayFormatter = DateFormatter()
    
    internal init() {
        self.tiffDates.locale = Locale(identifier: "en_US_POSIX")
        self.tiffDates.dateFormat = "yyyy:MM:dd HH:mm:ss"
        self.tiffDates.timeZone = TimeZone(secondsFromGMT: 0)
        
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.dateFormat = "yyyy:MM:dd"
        self.dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }
    
    // MARK: - Public interface
    /**
     * Extracts metadata from the given IFD. This should be a root IFD, from which we find information such
     * as EXIF directories.
     */
    internal func addIfd(_ ifd: TIFFReader.IFD) throws {
        // tiff-specific data
        self.meta.tiff = try self.getTiffData(ifd)
        
        // grab exif data
        if let exifTag = ifd.getTag(byId: 0x8769) as? TIFFReader.TagSubIfd,
           let exif = exifTag.value.first {
            self.meta.exif = try self.getExifData(exif)
        }
        
        // grab GPS data
        if let gpsTag = ifd.getTag(byId: 0x8825) as? TIFFReader.TagSubIfd,
           let gps = gpsTag.value.first {
            self.meta.gps = try self.getGpsData(gps)
        }
    }
    
    /**
     * Finalizes metadata parsing and returns the finished object.
     */
    internal func finalize() -> ImageMeta {
        return self.meta
    }
    
    // MARK: - IFD Parsing
    // MARK: TIFF
    /**
     * Gets TIFF-specific information from the IFD.
     *
     * This requires all baseline fields to exist, but anything beyond that won't cause errors if the fields are
     * missing from the file. Hopefully most raw files that use TIFF adhere to that…
     */
    private func getTiffData(_ ifd: TIFFReader.IFD) throws -> ImageMeta.TIFF {
        var tiff = ImageMeta.TIFF()
        
        // image size (baseline)
        guard let width = ifd.getTag(byId: 0x0100) as? TIFFReader.TagUnsigned else {
            throw Errors.missingTiffTag(0x0100)
        }
        guard let height = ifd.getTag(byId: 0x0101) as? TIFFReader.TagUnsigned else {
            throw Errors.missingTiffTag(0x0101)
        }
        
        tiff.width = Int(width.value)
        tiff.height = Int(height.value)
        
        // orientation (baseline)
        guard let orientationTag = ifd.getTag(byId: 0x0112) as? TIFFReader.TagUnsigned,
            let orientation = ImageMeta.TIFF.Orientation(rawValue: orientationTag.value) else {
            throw Errors.missingTiffTag(0x0112)
        }
        
        tiff.orientation = orientation
        
        // make and model strings
        if let make = ifd.getTag(byId: 0x010F) as? TIFFReader.TagString {
            tiff.make = make.value
        }
        if let model = ifd.getTag(byId: 0x0110) as? TIFFReader.TagString {
            tiff.model = model.value
        }
        
        // X and Y resolutions
        if let xRes = ifd.getTag(byId: 0x011A) as? TIFFReader.TagRational<UInt32> {
            tiff.xResolution = xRes.value
        }
        if let yRes = ifd.getTag(byId: 0x011B) as? TIFFReader.TagRational<UInt32> {
            tiff.yResolution = yRes.value
        }
        if let unit = ifd.getTag(byId: 0x0128) as? TIFFReader.TagUnsigned,
            let val = ImageMeta.TIFF.ResUnit(rawValue: unit.value) {
            tiff.resolutionUnits = val
        }
        
        // Software and host system strings
        if let software = ifd.getTag(byId: 0x0131) as? TIFFReader.TagString {
            tiff.software = software.value
        }
        if let host = ifd.getTag(byId: 0x013C) as? TIFFReader.TagString {
            tiff.system = host.value
        }
        
        // Creator name and copyright strings
        if let creator = ifd.getTag(byId: 0x013B) as? TIFFReader.TagString {
            tiff.artist = creator.value
        }
        if let copy = ifd.getTag(byId: 0x8298) as? TIFFReader.TagString {
            tiff.copyright = copy.value
        }
        
        // creation date
        if let dateStr = ifd.getTag(byId: 0x0132) as? TIFFReader.TagString,
            let date = self.tiffDates.date(from: dateStr.value) {
            tiff.created = date
        }
        
        return tiff
    }
    
    // MARK: EXIF
    /**
     * Builds the EXIF image data object.
     */
    private func getExifData(_ ifd: TIFFReader.IFD) throws -> ImageMeta.EXIF {
        var exif = ImageMeta.EXIF()
        
        // get the EXIF version: should start off with ASCII "02"
        guard let vers = ifd.getTag(byId: 0x9000) as? TIFFReader.TagByteSeq,
            vers.value.count == 4 else {
            throw Errors.missingExifTag(0x0112)
        }
        guard vers.value.readEndian(0, .little) == UInt16(0x3230) else {
            throw Errors.unsupportedExifVersion(UInt32(bitPattern: vers.value.read(0)))
        }
        
        // get pieces of the EXIF data
        try self.readExifExposure(ifd, &exif)
        try self.readExifDates(ifd, &exif)
        try self.readImageSize(ifd, &exif)
        try self.readBodyLensInfo(ifd, &exif)
        
        return exif
    }
    /**
     * Reads exposure-releated parameters from the EXIF directory.
     */
    private func readExifExposure(_ ifd: TIFFReader.IFD, _ exif: inout ImageMeta.EXIF) throws {
        // exposure time
        if let rat = ifd.getTag(byId: 0x829A) as? TIFFReader.TagRational<UInt32> {
            exif.exposureTime = Fraction(numerator: Int(rat.numerator),
                                         denominator: Int(rat.denominator))
        }
        
        // F number
        if let value = ifd.getTag(byId: 0x829D) as? TIFFReader.TagRational<UInt32> {
            exif.fNumber = Fraction(numerator: Int(value.numerator),
                                  denominator: Int(value.denominator))
        }
        
        // Exposure program
        if let rawValue = ifd.getTag(byId: 0x8822) as? TIFFReader.TagUnsigned,
           let program = ImageMeta.EXIF.ProgramType(rawValue: rawValue.value) {
            exif.programType = program
        }
        
        // ISO (single value)
        if let iso = ifd.getTag(byId: 0x8827) as? TIFFReader.TagUnsigned {
            exif.iso = [UInt(iso.value)]
        }
        // ISO (multiple values)
        if let iso = ifd.getTag(byId: 0x8827) as? TIFFReader.TagUnsignedArray {
            exif.iso = iso.value.map(UInt.init)
        }
        // How ISO values should be interpreted
        if let rawValue = ifd.getTag(byId: 0x8830) as? TIFFReader.TagUnsigned,
           let type = ImageMeta.EXIF.SensitivityType(rawValue: rawValue.value) {
            exif.isoType = type
        }
        
        // exposure bias
        if let value = ifd.getTag(byId: 0x9204) as? TIFFReader.TagRational<Int32> {
            exif.exposureCompesation = Fraction(numerator: Int(value.numerator),
                                                denominator: Int(value.denominator))
        }
    }
    /**
     * Gets the image original (capture) and creation dates.
     */
    private func readExifDates(_ ifd: TIFFReader.IFD, _ exif: inout ImageMeta.EXIF) throws {
        // capture date
        if let captured = ifd.getTag(byId: 0x9003) as? TIFFReader.TagString {
            var date: AnyObject! = nil
            try self.tiffDates.getObjectValue(&date, for: captured.value, range: nil)
            
            if let date = date as? Date {
                // read subseconds
                if let tag = ifd.getTag(byId: 0x9291) as? TIFFReader.TagString,
                   let value = Double(tag.value), value != 0 {
                    exif.captured = date.advanced(by: TimeInterval(1.0/value))
                } else {
                    exif.captured = date
                }
            }
        }
        // Digitization date
        if let digitized = ifd.getTag(byId: 0x9004) as? TIFFReader.TagString {
           var date: AnyObject! = nil
           try self.tiffDates.getObjectValue(&date, for: digitized.value, range: nil)
           
           if let date = date as? Date {
                // read subseconds
                if let tag = ifd.getTag(byId: 0x9292) as? TIFFReader.TagString,
                   let value = Double(tag.value), value != 0 {
                    exif.digitized = date.advanced(by: TimeInterval(1.0/value))
                } else {
                    exif.digitized = date
                }
           }
        }
    }
    /**
     * Gets the image's output size.
     */
    private func readImageSize(_ ifd: TIFFReader.IFD, _ exif: inout ImageMeta.EXIF) throws {
        // width
        if let width = ifd.getTag(byId: 0xA002) as? TIFFReader.TagUnsigned {
            exif.width = Int(width.value)
        }
        // height
        if let height = ifd.getTag(byId: 0xA003) as? TIFFReader.TagUnsigned {
            exif.height = Int(height.value)
        }
    }
    /**
     * Gets info about the camera body and lens used to capture this image.
     */
    private func readBodyLensInfo(_ ifd: TIFFReader.IFD, _ exif: inout ImageMeta.EXIF) throws {
        // body serial number
        if let serial = ifd.getTag(byId: 0xA431) as? TIFFReader.TagString {
            exif.bodySerial = serial.value
        }
        
        // Lens model string
        if let model = ifd.getTag(byId: 0xA434) as? TIFFReader.TagString {
            exif.lensModel = model.value
        }
        // Lens serial number
        if let serial = ifd.getTag(byId: 0xA435) as? TIFFReader.TagString {
            exif.lensSerial = serial.value
        }
    }
    
    // MARK: GPS
    /**
     * Retrieves the GPS information from the given IFD.
     */
    private func getGpsData(_ ifd: TIFFReader.IFD) throws -> ImageMeta.GPS? {
        var gps = ImageMeta.GPS()
        
        // measurement must be valid
        guard let tag = ifd.getTag(byId: 0x0009) as? TIFFReader.TagString,
              tag.value.first == "A" else {
            return nil
        }
        
        // altitude and altitude reference
        if let altitude = ifd.getTag(byId: 0x0006) as? TIFFReader.TagRational<UInt32>,
           let ref = ifd.getTag(byId: 0x0005) as? TIFFReader.TagUnsigned{
            if ref.value == 0 {
                gps.altitude = altitude.value
            } else {
                gps.altitude = altitude.value * -1.0
            }
        }
        
        // DoP
        if let dop = ifd.getTag(byId: 0x000B) as? TIFFReader.TagRational<UInt32> {
            gps.dop = dop.value
        }
        
        // latitude
        if let lat = ifd.getTag(byId: 0x0002) as? TIFFReader.TagRationalArray<UInt32>,
           let ref = ifd.getTag(byId: 0x0001) as? TIFFReader.TagString {
            let values = lat.value.map({ $0.value })
            let degrees = values[0] + (values[1] / 60) + (values[2] / 3600)
            
            if ref.value.first == "S" {
                gps.latitude = degrees * -1.0
            } else if ref.value.first == "N" {
                gps.latitude = degrees
            } else {
                throw Errors.invalidLatitudeRef(ref.value)
            }
        }
        
        // longitude
        if let lng = ifd.getTag(byId: 0x0004) as? TIFFReader.TagRationalArray<UInt32>,
           let ref = ifd.getTag(byId: 0x0003) as? TIFFReader.TagString {
            let values = lng.value.map({ $0.value })
            let degrees = values[0] + (values[1] / 60) + (values[2] / 3600)
            
            if ref.value.first == "W" {
                gps.longitude = degrees * -1.0
            } else if ref.value.first == "E" {
                gps.longitude = degrees
            } else {
                throw Errors.invalidLongitudeRef(ref.value)
            }
        }
        
        // reference model
        if let ref = ifd.getTag(byId: 0x0012) as? TIFFReader.TagString {
            gps.reference = ref.value
        }
        
        // GPS fix date/time
        let cal = NSCalendar.init(calendarIdentifier: .ISO8601)
        cal?.timeZone = TimeZone(secondsFromGMT: 0)!
        
        var comp = DateComponents()
        var compValid = false
        
        if let fixTime = ifd.getTag(byId: 0x0007) as? TIFFReader.TagRationalArray<UInt32> {
            let values = fixTime.value.map({ $0.value })
            
            comp.hour = Int(values[0])
            comp.minute = Int(values[1])
            comp.second = Int(values[2])
            compValid = true
        }
        
        if let fixDate = ifd.getTag(byId: 0x001d) as? TIFFReader.TagString {
            var date: AnyObject! = nil
            try self.dayFormatter.getObjectValue(&date, for: fixDate.value, range: nil)
            
            if let date = date as? Date,
               let dayComps = cal?.components([.day, .month, .year], from: date) {
                comp.day = dayComps.day
                comp.month = dayComps.month
                comp.year = dayComps.year
                compValid = true
            }
        }
        
        if compValid {
            gps.utcTimestamp = cal?.date(from: comp)
        }
        
        return gps
    }
    
    // MARK: - Errors
    private enum Errors: Error {
        /// Missing TIFF metadata field
        case missingTiffTag(_ tagId: UInt16)
        
        /// Missing mandatory EXIF metadata field
        case missingExifTag(_ tagId: UInt16)
        /// Unsupported EXIF version
        case unsupportedExifVersion(_ version: UInt32)
        
        /// Invalid latitude reference
        case invalidLatitudeRef(_ ref: String)
        /// Invalid longitude reference
        case invalidLongitudeRef(_ ref: String)
    }
}
