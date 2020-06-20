//
//  TIFFMetadataReader.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200619.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Consumes TIFF IFDs and extracts any known metadata out of them.
 */
internal class TIFFMetadataReader {
    /// Metadata object that we're building up
    private var meta = ImageMeta()
    
    /// Date formatter for reading TIFF dates
    private var tiffDates = DateFormatter()
    
    internal init() {
        self.tiffDates.locale = Locale(identifier: "en_US_POSIX")
        self.tiffDates.dateFormat = "yyyy:MM:dd HH:mm:ss"
        self.tiffDates.timeZone = TimeZone(secondsFromGMT: 0)
    }
    
    // MARK: - Public interface
    /**
     * Extracts metadata from the given IFD. This should be a root IFD, from which we find information such
     * as EXIF directories.
     */
    internal func addIfd(_ ifd: TIFFReader.IFD) throws {
        DDLogVerbose("IFD: \(ifd)")
        
        // tiff-specific data
        self.meta.tiff = try self.getTiffData(ifd)
        
        // grab exif data
        if let exifTag = ifd.getTag(byId: 0x8769) as? TIFFReader.TagSubIfd,
           let exif = exifTag.value.first {
            self.meta.exif = try self.getExifData(exif)
        }
    }
    
    /**
     * Finalizes metadata parsing and returns the finished object.
     */
    internal func finalize() -> ImageMeta {
        DDLogVerbose("Meta: \(self.meta.exif!)")
        
        return self.meta
    }
    
    // MARK: - IFD Parsing
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
                exif.captured = date
            }
        }
        // Digitization date
        if let digitized = ifd.getTag(byId: 0x9004) as? TIFFReader.TagString {
           var date: AnyObject! = nil
           try self.tiffDates.getObjectValue(&date, for: digitized.value, range: nil)
           
           if let date = date as? Date {
               exif.digitized = date
           }
        }
        
        // Subseconds for capture date
        if let tag = ifd.getTag(byId: 0x9291) as? TIFFReader.TagString,
            let value = Double(tag.value) {
            exif.captured?.addTimeInterval(TimeInterval(1/value))
        }
        // Subseconds for digitization date
        if let tag = ifd.getTag(byId: 0x9292) as? TIFFReader.TagString,
            let value = Double(tag.value) {
            exif.digitized?.addTimeInterval(TimeInterval(1/value))
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
    
    // MARK: - Errors
    private enum Errors: Error {
        /// Missing TIFF metadata field
        case missingTiffTag(_ tagId: UInt16)
        
        /// Missing mandatory EXIF metadata field
        case missingExifTag(_ tagId: UInt16)
        /// Unsupported EXIF version
        case unsupportedExifVersion(_ version: UInt32)
    }
}
