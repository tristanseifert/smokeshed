//
//  ImageIOMetadataReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200620.
//

import Foundation

import ImageIO

import CocoaLumberjackSwift

/**
 * Gets image metadata using the system's ImageIO framework.
 */
public class ImageIOMetadataReader {
    /// Date formatter for reading TIFF dates
    private var tiffDates = DateFormatter()
    /// Formatter for parsing GPS date string (yyyy:mm:dd)
    private var dayFormatter = DateFormatter()
    /// Formatter for parsing GPS time string (hh:mm:ss)
    private var timeFormatter = DateFormatter()
    
    public init() {
        self.tiffDates.locale = Locale(identifier: "en_US_POSIX")
        self.tiffDates.dateFormat = "yyyy:MM:dd HH:mm:ss"
        self.tiffDates.timeZone = TimeZone(secondsFromGMT: 0)
        
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.dateFormat = "yyyy:MM:dd"
        self.dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        self.timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.timeFormatter.dateFormat = "HH:mm:ss"
        self.timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    // MARK: - Public interface
    /**
     * Loads the file at the given URL and extracts metadata from it.
     */
    public func getMetadata(_ url: URL) throws -> ImageMeta {
        // create image source and get metadata from it
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Errors.sourceCreateFailed
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil),
             let imageInfo = props as? [String: AnyObject] else {
            throw Errors.copyPropertiesFailed
        }
        
        // create image meta
        var meta = ImageMeta()
        
        // extract info for each of the sub keys we might have
        if let dict = imageInfo[kCGImagePropertyTIFFDictionary as String],
           let tiff = dict as? [String: AnyObject] {
            meta.tiff = try self.getTiffData(tiff, root: imageInfo)
        }
        
        if let dict = imageInfo[kCGImagePropertyExifDictionary as String],
           let exif = dict as? [String: AnyObject] {
            var obj = ImageMeta.EXIF()
            
            try self.readExifSize(exif, root: imageInfo, &obj)
            try self.readExifExposure(exif, &obj)
            try self.readExifDates(exif, &obj)
            try self.readExifBodyLensInfo(exif, &obj)
            
            // aux dict contains more lens info
            if let dict = imageInfo[kCGImagePropertyExifAuxDictionary as String],
               let exifAux = dict as? [String: AnyObject]{
                try self.readExifBodyLensInfo(exifAux, &obj)
            }
            
            meta.exif = obj
        }
        
        if let dict = imageInfo[kCGImagePropertyGPSDictionary as String],
           let gps = dict as? [String: AnyObject] {
            meta.gps = try self.getGpsData(gps)
        }
        
        // done!
        return meta
    }
    
    // MARK: - Parsing
    // MARK: TIFF
    /**
     * Uses the TIFF dictionary to construct TIFF metadata.
     */
    private func getTiffData(_ dict: [String: AnyObject], root: [String: AnyObject]) throws -> ImageMeta.TIFF {
        var tiff = ImageMeta.TIFF()
        
        // size is in the root of the info struct
        guard let width = root[kCGImagePropertyPixelWidth as String] as? NSNumber else {
            throw Errors.missingKey(kCGImagePropertyPixelWidth)
        }
        guard let height = root[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            throw Errors.missingKey(kCGImagePropertyPixelHeight)
        }
        
        tiff.width = width.intValue
        tiff.height = height.intValue
        
        // orientation
        if let orientation = root[kCGImagePropertyOrientation as String] as? NSNumber,
           let val = ImageMeta.TIFF.Orientation(rawValue: orientation.uint32Value) {
            tiff.orientation = val
        }
        
        // make and model strings
        if let make = dict[kCGImagePropertyTIFFMake as String] as? String {
            tiff.make = make
        }
        if let model = dict[kCGImagePropertyTIFFModel as String] as? String {
            tiff.model = model
        }
        
        // X/Y resolution
        if let x = dict[kCGImagePropertyTIFFXResolution as String] as? NSNumber {
            tiff.xResolution = x.doubleValue
        }
        if let y = dict[kCGImagePropertyTIFFYResolution as String] as? NSNumber {
            tiff.yResolution = y.doubleValue
        }
        if let unit = dict[kCGImagePropertyTIFFResolutionUnit as String] as? NSNumber,
           let val = ImageMeta.TIFF.ResUnit(rawValue: unit.uint32Value) {
            tiff.resolutionUnits = val
        }
        
        // software and host system strings
        if let software = dict[kCGImagePropertyTIFFSoftware as String] as? String {
            tiff.software = software
        }
        if let host = dict[kCGImagePropertyTIFFHostComputer as String] as? String {
            tiff.system = host
        }
        
        // artist and copyright strings
        if let artist = dict[kCGImagePropertyTIFFArtist as String] as? String {
            tiff.artist = artist
        }
        if let copy = dict[kCGImagePropertyTIFFCopyright as String] as? String {
            tiff.copyright = copy
        }
        
        // capture date
        if let dateStr = dict[kCGImagePropertyTIFFDateTime as String] as? String,
           let date = self.tiffDates.date(from: dateStr) {
            tiff.created = date
        }
        
        return tiff
    }
    
    // MARK: EXIF
    /**
     * Gets the image size from the root info dict into the EXIF dict.
     */
    private func readExifSize(_ dict: [String: AnyObject], root: [String: AnyObject], _ exif: inout ImageMeta.EXIF) throws {
        guard let width = root[kCGImagePropertyPixelWidth as String] as? NSNumber else {
            throw Errors.missingKey(kCGImagePropertyPixelWidth)
        }
        guard let height = root[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            throw Errors.missingKey(kCGImagePropertyPixelHeight)
        }
        
        exif.width = width.intValue
        exif.height = height.intValue
    }
        
    /**
     * Copies exposure information from the EXIF dictionary.
     */
    private func readExifExposure(_ dict: [String: AnyObject], _ exif: inout ImageMeta.EXIF) throws {
        // exposure thyme, aperture, ISO
        if let time = dict[kCGImagePropertyExifExposureTime as String] as? NSNumber {
            exif.exposureTime = Fraction(time.doubleValue)
        }
        if let fnum = dict[kCGImagePropertyExifFNumber as String] as? NSNumber {
            exif.fNumber = Fraction(fnum.doubleValue)
        }
        if let isos = dict[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber] {
            exif.iso = isos.map({ $0.uintValue })
        }
        if let rawValue = dict[kCGImagePropertyExifSensitivityType as String] as? NSNumber,
           let type = ImageMeta.EXIF.SensitivityType(rawValue: rawValue.uint32Value) {
            exif.isoType = type
        }
        
        // exposure bias
        if let bias = dict[kCGImagePropertyExifExposureBiasValue as String] as? NSNumber {
            exif.exposureCompesation = Fraction(bias.doubleValue)
        }
        
        // exposure program
        if let rawValue = dict[kCGImagePropertyExifExposureProgram as String] as? NSNumber,
           let program = ImageMeta.EXIF.ProgramType(rawValue: rawValue.uint32Value) {
            exif.programType = program
        }
    }
    
    /**
     * Copies capture and digitization dates from the EXIF dictionary.
     */
    private func readExifDates(_ dict: [String: AnyObject], _ exif: inout ImageMeta.EXIF) throws {
        // capture and digitization date
        if let string = dict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            var out: AnyObject! = nil
            try self.tiffDates.getObjectValue(&out, for: string, range: nil)
            
            if let date = out as? Date {
                // handle subseconds
                if let string = dict[kCGImagePropertyExifSubsecTimeOriginal as String] as? String,
                   let value = Double(string), value != 0 {
                    exif.captured = date.advanced(by: TimeInterval(1.0/value))
                } else {
                    exif.captured = date
                }
            }
        }
        
        if let string = dict[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            var out: AnyObject! = nil
            try self.tiffDates.getObjectValue(&out, for: string, range: nil)

            if let date = out as? Date {
                // handle subseconds
                if let string = dict[kCGImagePropertyExifSubsecTimeDigitized as String] as? String,
                   let value = Double(string), value != 0 {
                       exif.captured = date.advanced(by: TimeInterval(1.0/value))
                } else {
                    exif.digitized = date
                }
            }
            
        }
        
        // subseconds for capture and digitization date
        if let string = dict[kCGImagePropertyExifSubsecTimeDigitized as String] as? String,
           let value = Double(string) {
            exif.digitized?.addTimeInterval(TimeInterval(1/value))
        }
    }
    
    /**
     * Reads information about the body and lens used to the EXIF structure.
     */
    private func readExifBodyLensInfo(_ dict: [String: AnyObject], _ exif: inout ImageMeta.EXIF) throws {
        // lens kind and serial
        if let serial = dict[kCGImagePropertyExifLensSerialNumber as String] as? String {
            exif.lensSerial = serial
        }
        if let make = dict[kCGImagePropertyExifLensMake as String] as? String {
            exif.lensMake = make
        }
        if let model = dict[kCGImagePropertyExifLensModel as String] as? String {
            exif.lensModel = model
        }
        
        // lens id
        if let id = dict[kCGImagePropertyExifAuxLensID as String] as? NSNumber {
            exif.lensId = id.uintValue
        }
    }
    
    // MARK: GPS
    /**
     * Parses the GPS dictionary into a GPS struct.
     */
    private func getGpsData(_ dict: [String: AnyObject]) throws -> ImageMeta.GPS {
        var gps = ImageMeta.GPS()
        
        // altitude and altitude reference
        if let alt = dict[kCGImagePropertyGPSAltitude as String] as? NSNumber,
           let ref = dict[kCGImagePropertyGPSAltitudeRef as String] as? NSNumber {
            if ref.intValue == 0 {
                gps.altitude = alt.doubleValue
            } else {
                gps.altitude = alt.doubleValue * -1.0
            }
        }
        
        // dilution of precision
        if let dop = dict[kCGImagePropertyGPSDOP as String] as? NSNumber {
            gps.dop = dop.doubleValue
        }
        
        // latitude
        if let lat = dict[kCGImagePropertyGPSLatitude as String] as? NSNumber,
           let ref = dict[kCGImagePropertyGPSLatitudeRef as String] as? String {
            if ref.first == "S" {
                gps.latitude = lat.doubleValue * -1.0
            } else if ref.first == "N" {
                gps.latitude = lat.doubleValue
            } else {
              throw Errors.invalidLatitudeRef(ref)
          }
        }
        
        // longitude
        if let lng = dict[kCGImagePropertyGPSLongitude as String] as? NSNumber,
           let ref = dict[kCGImagePropertyGPSLongitudeRef as String] as? String {
            if ref.first == "W" {
                gps.longitude = lng.doubleValue * -1.0
            } else if ref.first == "E" {
                gps.longitude = lng.doubleValue
            } else {
                throw Errors.invalidLongitudeRef(ref)
            }
        }
        
        // reference model (map datum)
        if let datum = dict[kCGImagePropertyGPSMapDatum as String] as? String {
            gps.reference = datum
        }
        
        // fix date and time
        let cal = NSCalendar.init(calendarIdentifier: .ISO8601)
        cal?.timeZone = TimeZone(secondsFromGMT: 0)!
        
        var comp = DateComponents()
        var compValid = false
        
        if let fixTime = dict[kCGImagePropertyGPSTimeStamp as String] as? String {
            var date: AnyObject! = nil
            try self.timeFormatter.getObjectValue(&date, for: fixTime, range: nil)

            if let date = date as? Date,
               let timeComps = cal?.components([.hour, .minute, .second], from: date) {
                comp.hour = timeComps.hour
                comp.minute = timeComps.minute
                comp.second = timeComps.second
                compValid = true
            }
        }
        
        if let fixDate = dict[kCGImagePropertyGPSDateStamp as String] as? String {
            var date: AnyObject! = nil
            try self.dayFormatter.getObjectValue(&date, for: fixDate, range: nil)
            
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
        
        // done
        return gps
    }
    
    // MARK: - Errors
    private enum Errors: Error {
        /// Couldn't open the image
        case sourceCreateFailed
        /// Getting image properties failed
        case copyPropertiesFailed
        
        /// Failed to get some required properties
        case missingKey(_ key: CFString)
        
        /// Invalid latitude reference
        case invalidLatitudeRef(_ ref: String)
        /// Invalid longitude reference
        case invalidLongitudeRef(_ ref: String)
    }
}
