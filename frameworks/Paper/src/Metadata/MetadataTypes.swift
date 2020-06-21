//
//  MetadataTypes.swift
//  Paper (macOS)
//
//  Types to describe image metadata
//
//  Created by Tristan Seifert on 20200619.
//

import Foundation

/**
 * Represents all known metadata about a particular image.
 */
public struct ImageMeta: CustomStringConvertible, Codable {
    // MARK: - Exif data
    /// EXIF tags
    internal(set) public var exif: EXIF?
    
    /**
     * Contains information about how the image was captured.
     */
    public struct EXIF: CustomStringConvertible, Codable {
        /// Exposure time, in seconds
        internal(set) public var exposureTime: Fraction? = nil
        /// F number
        internal(set) public var fNumber: Fraction? = nil
        
        /// ISO values
        internal(set) public var iso: [UInt]? = nil
        /// How to interpret the ISO value
        internal(set) public var isoType: SensitivityType = .unknown
        
        /// Exposure compensation (bias)
        internal(set) public var exposureCompesation: Fraction? = nil
        
        /// Exposure program
        internal(set) public var programType: ProgramType = .undefined
        
        /// When was the image captured?
        internal(set) public var captured: Date? = nil
        /// When was the image digitized/recorded?
        internal(set) public var digitized: Date? = nil
        
        /// Width of final image
        internal(set) public var width: Int? = nil
        /// Height of the decompressed image
        internal(set) public var height: Int? = nil
        
        /// Serial number of the camera body
        internal(set) public var bodySerial: String? = nil
        
        /// Vendor-specific lens ID
        internal(set) public var lensId: UInt? = nil
        /// Lens manufacturer
        internal(set) public var lensMake: String? = nil
        /// Lens model
        internal(set) public var lensModel: String? = nil
        /// Serial number of the lens
        internal(set) public var lensSerial: String? = nil
        
        /// Sensitivity types (how to interpret the ISO field)
        public enum SensitivityType: UInt32, Codable {
            /// Unknown (default)
            case unknown = 0
            /// Standard output sensitivity
            case standardOutputSensitivity = 1
            /// Reccomended Exposure Index
            case reccomendedExposureIndex = 2
            /// Regular ISO value
            case iso = 3
            /// Both standard output sensitivity and REI
            case sosAndRei = 4
            /// Standard output sensitivity and ISO
            case sosAndIso = 5
            /// Reccomended exposure index and ISO
            case reiAndIso = 6
            /// All three of them hoes
            case all = 7
        }
        /// Exposure program types as defined by EXIF standard
        public enum ProgramType: UInt32, Codable {
            /// Undefined program type (default)
            case undefined = 0
            /// Full manual
            case manual = 1
            /// Normal program
            case program = 2
            /// Aperture priority
            case aperturePriority = 3
            /// Shutter priority
            case shutterPriority = 4
            /// Creative program (low DoF)
            case creativeProgram = 5
            /// Action program (fast shutter speed)
            case actionProgram = 6
            /// Portrait mode (close-up with shallow DoF background)
            case portrait = 7
            /// Landscape (background in focus)
            case landscape = 8
        }
        
        internal init() {}
        
        public var description: String {
            return String(format: "<EXIF: exposure: %@ fnum: %@ iso: %@ (type %@); program type: %@; captured: %@ digitized: %@; body serial: %@; lens: %@ (id %@), serial: %@>",
                          String(describing: self.exposureTime),
                          String(describing: self.fNumber),
                          String(describing: self.iso),
                          String(describing: self.isoType),
                          String(describing: self.programType),
                          String(describing: self.captured),
                          String(describing: self.digitized),
                          String(describing: self.bodySerial),
                          String(describing: self.lensModel),
                          String(describing: self.lensId),
                          String(describing: self.lensSerial))
        }
    }
    
    // MARK: - Geolocation
    /// GPS information
    internal(set) public var gps: GPS?
    
    /**
     * Geolocation information
     */
    public struct GPS: CustomStringConvertible, Codable {
        /// Latitude
        internal(set) public var latitude: Double = Double.nan
        /// Longitude
        internal(set) public var longitude: Double = Double.nan
        /// Altitude relative to sea level (negative is below, positive above) in meters
        internal(set) public var altitude: Double = Double.nan
        
        /// Reference model (usually WGS-84)
        internal(set) public var reference: String = "WGS-84"
        
        /// UTC timestamp of this sample
        internal(set) public var utcTimestamp: Date? = nil
        
        /// Dilution of Precision (DoP)
        internal(set) public var dop: Double = Double.nan
        
        internal init() {}
        
        public var description: String {
            return String(format: "<GPS: (%f, %f) ref: %@ alt: %gm; timestamp: %@; dop: %g>",
                          self.latitude, self.longitude, self.reference,
                          self.altitude, String(describing: self.utcTimestamp),
                          self.dop)
        }
    }
    
    // MARK: - TIFF
    /// TIFF specific metadata
    internal(set) public var tiff: TIFF?
    
    /**
     * Metadata specific to a TIFF image
     */
    public struct TIFF: CustomStringConvertible, Codable {
        /// Width of image
        internal(set) public var width: Int = 0
        /// Height of image
        internal(set) public var height: Int = 0
        
        /// Manufacturer of capture device
        internal(set) public var make: String? = nil
        /// Capture device model
        internal(set) public var model: String? = nil
        
        /// Image orientation
        internal(set) public var orientation: Orientation = .topLeft
        
        /// Unit for resolution values
        internal(set) public var resolutionUnits: ResUnit = .none
        /// Horizontal physical resolution (pixels per resolution unit)
        internal(set) public var xResolution: Double? = nil
        /// Vertical physical resolution (pixels per resolution unit)
        internal(set) public var yResolution: Double? = nil
        
        /// Software that created this image
        internal(set) public var software: String? = nil
        /// System on which this image was created
        internal(set) public var system: String? = nil
        
        /// Artist name
        internal(set) public var artist: String? = nil
        /// Copyright information
        internal(set) public var copyright: String? = nil
        
        /// Image creation date
        internal(set) public var created: Date? = nil
        
        /// Possible image orientations
        public enum Orientation: UInt32, Codable {
            case topLeft = 1
            case topRight = 2
            case bottomRight = 3
            case bottomLeft = 4
            case leftTop = 5
            case rightTop = 6
            case rightBottom = 7
            case leftBottom = 8
        }
        /// Resolution units
        public enum ResUnit: UInt32, Codable {
            case none = 1
            case inch = 2
            case centimeter = 3
        }
        
        public var description: String {
            return String(format: "<TIFF %dx%d; make '%@', model '%@'; orientation: '%@'; artist: '%@', copyright: '%@'; created: %@>",
                          self.width, self.height, self.make ?? "(null)",
                          self.model ?? "(null)",
                          String(describing: self.orientation),
                          self.artist ?? "(null)", self.copyright ?? "(null)",
                          String(describing: self.created))
        }
        
        internal init() {}
    }
    
    // MARK: - Convenience
    /// Camera make
    public var cameraMake: String? {
        if let make = self.tiff?.make {
            return make
        }
        return nil
    }
    /// Camera model
    public var cameraModel: String? {
        if let model = self.tiff?.model {
            return model
        }
        return nil
    }
    
    /// Lens model
    public var lensModel: String? {
        if let model = self.exif?.lensModel {
            return model
        }
        return nil
    }
    /// Lens id
    public var lensId: UInt? {
        if let id = self.exif?.lensId {
            return id
        }
        return nil
    }
    
    /// Capture date
    public var captureDate: Date? {
        if let captured = self.exif?.captured {
            return captured
        } else if let digitized = self.exif?.digitized {
            return digitized
        } else if let created = self.tiff?.created {
            return created
        }
        return nil
    }
    
    /// Physical image size
    public var size: CGSize? {
        // get size from TIFF
        if let width = self.tiff?.width, let height = self.tiff?.height {
            return CGSize(width: width, height: height)
        }
        // get size from EXIF
        if let width = self.exif?.width, let height = self.exif?.height {
            return CGSize(width: width, height: height)
        }
        // really shouldn't get here
        return nil
    }

    // MARK: - Helpers
    public var description: String {
        return String(format: "ImageMetadata:\n\tTIFF %@\n\tEXIF %@\n\tGPS %@",
                      String(describing: self.tiff),
                      String(describing: self.exif),
                      String(describing: self.gps))
    }
}
