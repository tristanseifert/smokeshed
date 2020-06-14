//
//  MetadataKeyDisplayNameTransformer.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

/**
 * Translates keys from an ImageIO metadata dictionary into more human-readable keys.
 */
public class MetadataKeyDisplayNameTransformer: ValueTransformer {
    /**
     * Builds a map of dictionary keys -> localizable strings.
     */
    private static let map: [String:String] = [
        (kCGImagePropertyExifDictionary as String) : "dicts.exif",
        (kCGImagePropertyTIFFDictionary as String) : "dicts.tiff",
        (kCGImagePropertyExifAuxDictionary as String) : "dicts.exifaux",
        (kCGImagePropertyGPSDictionary as String) : "dicts.gps",
        (kCGImagePropertyIPTCDictionary as String) : "dicts.iptc",

        (kCGImagePropertyPixelWidth as String) : "keys.width.pixels",
        (kCGImagePropertyPixelHeight as String) : "keys.height.pixels",
        (kCGImagePropertyDPIWidth as String) : "keys.width.dpi",
        (kCGImagePropertyDPIHeight as String) : "keys.height.dpi",
        (kCGImagePropertyProfileName as String) : "keys.color.profile",
        (kCGImagePropertyColorModel as String) : "keys.color.model",
        (kCGImagePropertyDepth as String) : "keys.depth",

        (kCGImagePropertyExifFNumber as String) : "keys.exif.fstop",
        (kCGImagePropertyExifISOSpeed as String) : "keys.exif.iso",
        (kCGImagePropertyExifExposureTime as String) : "keys.exif.exposureTime",
        (kCGImagePropertyExifExposureBiasValue as String) : "keys.exif.exposureCompensation",
        (kCGImagePropertyExifLensMake as String) : "keys.exif.lens.make",
        (kCGImagePropertyExifLensModel as String) : "keys.exif.lens.model",
        (kCGImagePropertyExifLensSerialNumber as String) : "keys.exif.lens.serial",
        (kCGImagePropertyExifFocalLength as String) : "keys.exif.focalLength",
        (kCGImagePropertyExifFocalLenIn35mmFilm as String) : "keys.exif.focalLength.35mm",
    ]

    /// Output is a string
    class public override func transformedValueClass() -> AnyClass {
        return NSString.self
    }
    /// Reverse transformations are a no go
    class public override func allowsReverseTransformation() -> Bool {
        return false
    }

    /**
     * Performs transformation. This just checks if the key is in our internal dictionary, then pulls the
     * localized name from a strings table.
     */
    public override func transformedValue(_ value: Any?) -> Any? {
        guard let key = value as? String else {
            return nil
        }

        // localize it if it's in our grand ol table
        if let localizableKey = MetadataKeyDisplayNameTransformer.map[key] {
            return Bundle.main.localizedString(forKey: localizableKey,
                       value: nil, table: "MetadataKeyDisplayNameTransformer")
        }

        // return the key as-is
        return key
    }

    /**
     * Registers the transformer.
     */
    public class func register() {
        if !self.hasRegistered {
            ValueTransformer.setValueTransformer(MetadataKeyDisplayNameTransformer(), forName: .metadataKeyDisplayName)
            self.hasRegistered = true
        }
    }

    private static var hasRegistered: Bool = false
}

extension NSValueTransformerName {
    /// Converts ImageIO dictionary keys to localized names
    static let metadataKeyDisplayName = NSValueTransformerName("MetadataKeyDisplayNameTransformer")
}
