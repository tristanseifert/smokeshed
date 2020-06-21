//
//  ImageIOMetadataReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200620.
//

import Foundation

import ImageIO

/**
 * Gets image metadata using the system's ImageIO framework.
 */
public class ImageIOMetadataReader {
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
            if let exifAux = imageInfo[kCGImagePropertyExifAuxDictionary as String] {
                try self.readExifBodyLensInfo(exif, &obj)
            }
            
            meta.exif = obj
        }
        
        if let dict = imageInfo[kCGImagePropertyGPSDictionary as String],
           let gps = dict as? [String: AnyObject] {
            
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
        if let string = dict[kCGImagePropertyExifDateTimeOriginal as String] as? String,
           let date = self.tiffDates.date(from: string) {
            exif.captured = date
        }
        
        if let string = dict[kCGImagePropertyExifDateTimeDigitized as String] as? String,
           let date = self.tiffDates.date(from: string) {
            exif.digitized = date
        }
        
        // subseconds for capture and digitization date
        if let string = dict[kCGImagePropertyExifSubsecTimeOriginal as String] as? String,
           let value = Double(string) {
            exif.captured?.addTimeInterval(TimeInterval(1/value))
        }
        
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
    
    // MARK: - Errors
    private enum Errors: Error {
        /// Couldn't open the image
        case sourceCreateFailed
        /// Getting image properties failed
        case copyPropertiesFailed
        
        /// Failed to get some required properties
        case missingKey(_ key: CFString)
    }
}
