//
//  MetadataTypes+Localization.swift
//  Paper (macOS)
//
//  Provides localization helpers to convert metadata objects into dictionary
//  representations suitable for displaying to the user.
//
//  Created by Tristan Seifert on 20200628.
//

import Foundation

/**
 * Returns the localized string for the given key out of the image metadata table.
 */
fileprivate func localized(_ key: String) -> String {
    let bundle = Bundle(identifier: "me.tseifert.smokeshed.paper")!
    return NSLocalizedString(key, tableName: "MetadataTypes", bundle: bundle,
                             value: "", comment: "")
}

// MARK: - GPS
extension ImageMeta.GPS {
    /**
     * Returns a localized dictionary representation of available GPS metadata.
     */
    public var localizedDictionaryRepresentation: [String: Any] {
        var dict: [String: Any] = [:]
        
        // lat and lng
        if !self.latitude.isNaN {
            dict[localized("gps.lat")] = self.latitude
        }
        if !self.longitude.isNaN {
            dict[localized("gps.lng")] = self.longitude
        }
        
        // Datum used to interpret data
        dict[localized("gps.datum")] = self.reference
        
        // altitude
        if !self.altitude.isNaN {
            let format = localized("gps.altitude.format")
            dict[localized("gps.altitude")] = String(format: format,
                                                     self.altitude)
        }
        
        // Dilution of precision
        if !self.dop.isNaN {
            dict[localized("gps.dop")] = self.dop
        }
        
        // timestamp
        if let date = self.utcTimestamp {
            dict[localized("gps.utcTimestamp")] = date
        }

        return dict
    }
}

// MARK: - TIFF
extension ImageMeta.TIFF {
    /**
     * Returns a localized dictionary representation of available TIFF metadata.
     */
    public var localizedDictionaryRepresentation: [String: Any] {
        var dict: [String: Any] = [:]
        
        // image width/height
        let sizeStr = String(format: localized("tiff.size.format"), self.width,
                             self.height)
        dict[localized("tiff.size")] = sizeStr
        
        // camera info
        if let make = self.make {
            dict[localized("tiff.make")] = make
        }
        if let model = self.model {
            dict[localized("tiff.model")] = model
        }
        
        // system software/hardware used
        if let software = self.software {
            dict[localized("tiff.software")] = software
        }
        if let system = self.system {
            dict[localized("tiff.system")] = system
        }
        
        // Artist and copyright strings
        if let artist = self.artist {
            dict[localized("tiff.artist")] = artist
        }
        if let copyright = self.copyright {
            dict[localized("tiff.copyright")] = copyright
        }
        
        // creation date
        if let created = self.created {
            dict[localized("tiff.created")] = created
        }
        
        // orientation (TODO: localize value)
        dict[localized("tiff.orientation")] = self.orientation.rawValue
        
        // resolution
        var resUnit = ""
        
        if self.resolutionUnits == .inch {
            resUnit = localized("tiff.resolution.inch")
        } else if self.resolutionUnits == .centimeter {
            resUnit = localized("tiff.resolution.centimeter")
        }
        
        let resFormat = localized("tiff.resolution.format")
        
        if let res = self.xResolution {
            dict[localized("tiff.xResolution")] = String(format: resFormat,
                                                         res, resUnit)
        }
        if let res = self.yResolution {
            dict[localized("tiff.yResolution")] = String(format: resFormat,
                                                         res, resUnit)
        }
        
        return dict
    }
}

// MARK: - EXIF
extension ImageMeta.EXIF {
    /**
     * Date component formatter used to display exposure times
     */
    private static var exposureTimeFormatter: DateComponentsFormatter = {
        let fmt = DateComponentsFormatter()
        fmt.allowsFractionalUnits = true
        fmt.collapsesLargestUnit = true
        fmt.unitsStyle = .brief
        fmt.formattingContext = .standalone
        fmt.allowedUnits = [.second, .minute, .hour]
        return fmt
    }()
    
    /**
     * Returns a localized dictionary representation of available EXIF metadata.
     */
    public var localizedDictionaryRepresentation: [String: Any] {
        var dict: [String: Any] = [:]
        
        // image size
        if let width = self.width, let height = self.height {
            let sizeStr = String(format: localized("exif.size.format"),
                                 width, height)
            dict[localized("exif.size")] = sizeStr
        }
        
        // exposure time
        if let expTime = self.exposureTime {
            var formatted = ""
            let val = expTime.value
            
            // less than 1 sec? format as fraction
            if val < 1.0 {
                let format = localized("exif.exposureTime.fraction")
                formatted = String(format: format, expTime.numerator,
                                  expTime.denominator)
            }
            // between 1 and 60 seconds?
            else if (1.0..<60.0).contains(val) {
                let format = localized("exif.exposureTime.seconds")
                formatted = String(format: format, expTime.value)
            }
            // format as a string (x sec, 1.5 min, 2 hours, etc)
            else {
                if let str = Self.exposureTimeFormatter.string(from: val) {
                    let format = localized("exif.exposureTime.formatted")
                    formatted = String(format: format, str)
                }
            }
            
            // if we were able to format it, store it
            if !formatted.isEmpty {
                dict[localized("exif.exposureTime")] = formatted
            }
        }
        
        // f number
        if let fnum = self.fNumber {
            let format = localized("exif.fNumber.format")
            dict[localized("exif.fNumber")] = String(format: format,
                                                          fnum.value)
        }
        
        // sensitivity
        if let sensitivityArr = self.iso, let first = sensitivityArr.first {
            // TODO: get proper sensitivity type
            let type = "ISO"
            
            // format the string
            let format = localized("exif.sensitivity.format")
            dict[localized("exif.sensitivity")] = String(format: format,
                                                              Double(first),
                                                              type)
        }
        
        // exposure bias/compensation
        if let bias = self.exposureCompesation {
            dict[localized("exif.exposureBias")] = bias.value
        }
        
        // exposure program type
        if self.programType != .undefined {
            dict[localized("exif.program")] = self.programType.rawValue
        }
        
        // capture and digitized dates
        if let captured = self.captured {
            dict[localized("exif.capturedDate")] = captured
        }
        if let digitized = self.digitized {
            dict[localized("exif.digitizedDate")] = digitized
        }
        
        // body information
        if let bodySerial = self.bodySerial {
            dict[localized("exif.bodySerial")] = bodySerial
        }
        
        // Lens information
        if let id = self.lensId {
            dict[localized("exif.lensId")] = id
        }
        if let lensMake = self.lensMake {
            dict[localized("exif.lensMake")] = lensMake
        }
        if let lensModel = self.lensModel {
            dict[localized("exif.lensModel")] = lensModel
        }
        if let lensSerial = self.lensSerial {
            dict[localized("exif.lensSerial")] = lensSerial
        }
        
        return dict
    }
}

// MARK: - Overall metadata
extension ImageMeta {
    /**
     * Gets a localized dictionary representation of this image metadata object, suitable for displaying to
     * the user.
     */
    public var localizedDictionaryRepresentation: [String: Any] {
        var dict: [String: Any] = [:]
        
        // get each of the sub-components
        if let exif = self.exif {
            dict[localized("root.exif")] = exif.localizedDictionaryRepresentation
        }
        if let tiff = self.tiff {
            dict[localized("root.tiff")] = tiff.localizedDictionaryRepresentation
        }
        if let gps = self.gps {
            dict[localized("root.gps")] = gps.localizedDictionaryRepresentation
        }
        
        // image size
        if let size = self.size {
            let fmt = localized("root.size.format")
            dict[localized("root.size")] = String(format: fmt, size.width,
                                                  size.height)
        }
        
        return dict
    }
}
