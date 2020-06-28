//
//  MetadataOutlineDataSource.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200613.
//

import Cocoa

import Smokeshop
import Paper
import CocoaLumberjackSwift

/**
 * Provides a read-only data source for an outline view to display an image's metadata.
 *
 * This does not support multiple selection.
 */
class MetadataOutlineDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Image for which metadata is to be displayed
    internal var image: Image? = nil {
        didSet {
            self.meta = self.image?.metadata
            self.updateRoot()
            self.view?.reloadData()
        }
    }
    /// Metadata being displayed
    private var meta: ImageMeta? = nil
    /// Container for the image metadata
    private var root: [AnyHashable: Any]? = nil
    
    /// Outline view backed by this data source
    internal var view: NSOutlineView! = nil

    // MARK: - Initialization
    override init() {
        super.init()
    }

    // MARK: - Types
    /**
     * Base object for key/value pair types. This provides just the value.
     */
    @objc private class ValueContainer: NSObject {
        @objc dynamic var value: Any? = nil

        @objc dynamic var numChildren: Int {
            if let array = self.value as? [Any] {
                return array.count
            } else if let dict = self.value as? [AnyHashable: Any] {
                return dict.count
            }
            return 0
        }

        init(_ value: Any) {
            self.value = value
        }

        // Ensure KVO for the numChildren parameter works.
        @objc public class func keyPathsForValuesAffectingGroupNumChildren() -> Set<String> {
            return [#keyPath(ValueContainer.value)]
        }
    }

    /**
     * A single key/value pair from a dictionary.
     */
    @objc private class KeyValuePair: ValueContainer {
        @objc dynamic var key: String? = nil

        init(_ key: String, _ value: Any) {
            super.init(value)
            self.key = key
        }
    }

    /**
     * An index/value pair from an array
     */
    @objc private class IndexValuePair: ValueContainer {
        @objc dynamic var index: Int = -1

        init(_ index: Int, _ value: Any) {
            super.init(value)
            self.index = index
        }
    }

    // MARK: - Data source
    /**
     * Returns the number of objects.
     */
    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        // is it a value container?
        if let container = item as? ValueContainer {
            return container.numChildren
        }
        // are we at the root of the tree?
        else if item == nil {
            return self.root?.count ?? 0
        }

        // no data otherwise
        return 0
    }

    /**
     * Gets the object for a particular index.
     */
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let container = item as? ValueContainer {
            // is it an array?
            if let array = container.value as? [Any] {
                return IndexValuePair(index, array[index])
            }
            // is it a dictionary?
            else if let dict = container.value as? [AnyHashable: Any] {
                let keyIdx = dict.index(dict.startIndex, offsetBy: index)
                let key = dict.keys[keyIdx] as! String

                return KeyValuePair(key, dict[key]!)
            }
            // this should NOT happen
            else {
                DDLogError("Unknown container type with children: \(container)")
                return NSNull()
            }
        }

        // read from the root object
        let keyIdx = self.root!.index(self.root!.startIndex, offsetBy: index)
        let key = self.root!.keys[keyIdx] as! String

        return KeyValuePair(key, self.root![key]!)
    }

    /**
     * Expand all array/dictionary type items.
     */
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let container = item as? ValueContainer {
            return (container.numChildren > 0)
        }

        return false
    }

    // MARK: - Delegate
    /**
     * Provide the appropriate cell view for the item.
     */
    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {

        // is this for the key column?
        if tableColumn!.identifier == .keyColumn {
            return self.keyView(outlineView, item: item)
        }
        // is it for the value column?
        else if tableColumn!.identifier == .valueColumn {
            return self.valueView(outlineView, item: item)
        }

        // unknown type
        return nil
    }

    /**
     * Given an object, return a cell view to display in the key column.
     */
    private func keyView(_ outline: NSOutlineView, item: Any) -> NSView? {
        // is it a key/value pair?
        if let pair = item as? KeyValuePair {
            return self.cell(outline, .metaCellKey, pair)
        }
        // is it a index/value pair?
        else if let pair = item as? IndexValuePair {
            return self.cell(outline, .metaCellIndex, pair)
        }

        // can't handle this type of object
        return nil
    }

    /**
     * Given an object, return a cell view to display in the value column.
     */
    private func valueView(_ outline: NSOutlineView, item: Any) -> NSView? {
        // get it as a value container
        if let container = item as? ValueContainer {
            // if this entry contains children, show a count cell
            if container.numChildren > 0 {
                return self.cell(outline, .metaCellCount, container)
            }
            // is the content a string?
            else if container.value is String {
                return self.cell(outline, .metaCellStringValue, container)
            }
            // is the content an integer?
            else if container.value is Int {
                return self.cell(outline, .metaCellIntValue, container)
            }
            // is the content a floating point value?
            else if (container.value is Double) || (container.value is Float) {
                return self.cell(outline, .metaCellDoubleValue, container)
            }
            // is the content a date value?
            else if container.value is Date {
                return self.cell(outline, .metaCellDateValue, container)
            }
            // dictionary or array with no children
            else if (container.value is [Any]) || (container.value is [AnyHashable: Any]) {
                return self.cell(outline, .metaCellCount, container)                
            }

            // unknown
            DDLogWarn("Unknown object type: \(container) \(String(describing: container.value))")
        }

        // can't handle this type of object
        return nil
    }

    /**
     * Creates a cell for the given identifier and object.
     */
    private func cell(_ outline: NSOutlineView, _ ident: NSUserInterfaceItemIdentifier, _ value: Any) -> NSView? {
        let view = outline.makeView(withIdentifier: ident, owner: self) as? NSTableCellView
        view?.objectValue = value
        return view
    }
    
    // MARK: - Metadata conversion
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
     * Updates the root object of the inspector based on the currently set metadata.
     */
    private func updateRoot() {
        // ensure we've got actual metadata to display
        guard let meta = self.meta else {
            self.root = nil
            return
        }
        
        // build a dictionary for each metadata key
        var dict: [AnyHashable: Any] = [:]
        
        if let exif = meta.exif {
            dict[Self.localized("root.exif")] = self.localizedExifDict(exif)
        }
        if let tiff = meta.tiff {
            dict[Self.localized("root.tiff")] = self.localizedTiffDict(tiff)
        }
        if let gps = meta.gps {
            dict[Self.localized("root.gps")] = self.localizedGpsDict(gps)
        }
        
        // image size
        if let size = meta.size {
            let fmt = Self.localized("root.size.format")
            dict[Self.localized("root.size")] = String(format: fmt, size.width,
                                                       size.height)
        }
        
        self.root = dict
    }
    
    /**
     * Creates a localized dictionary representation of an EXIF metadata object.
     */
    private func localizedExifDict(_ exif: ImageMeta.EXIF) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // image size
        if let width = exif.width, let height = exif.height {
            let sizeStr = String(format: Self.localized("exif.size.format"),
                                 width, height)
            dict[Self.localized("exif.size")] = sizeStr
        }
        
        // exposure time
        if let expTime = exif.exposureTime {
            var formatted = ""
            let val = expTime.value
            
            // less than 1 sec? format as fraction
            if val < 1.0 {
                let format = Self.localized("exif.exposureTime.fraction")
                formatted = String(format: format, expTime.numerator,
                                  expTime.denominator)
            }
            // between 1 and 60 seconds?
            else if (1.0..<60.0).contains(val) {
                let format = Self.localized("exif.exposureTime.seconds")
                formatted = String(format: format, expTime.value)
            }
            // format as a string (x sec, 1.5 min, 2 hours, etc)
            else {
                if let str = Self.exposureTimeFormatter.string(from: val) {
                    let format = Self.localized("exif.exposureTime.formatted")
                    formatted = String(format: format, str)
                }
            }
            
            // if we were able to format it, store it
            if !formatted.isEmpty {
                dict[Self.localized("exif.exposureTime")] = formatted
            }
        }
        
        // f number
        if let fnum = exif.fNumber {
            let format = Self.localized("exif.fNumber.format")
            dict[Self.localized("exif.fNumber")] = String(format: format,
                                                          fnum.value)
        }
        
        // sensitivity
        if let sensitivityArr = exif.iso, let first = sensitivityArr.first {
            // TODO: get proper sensitivity type
            let type = "ISO"
            
            // format the string
            let format = Self.localized("exif.sensitivity.format")
            dict[Self.localized("exif.sensitivity")] = String(format: format,
                                                              Double(first),
                                                              type)
        }
        
        // exposure bias/compensation
        if let bias = exif.exposureCompesation {
            dict[Self.localized("exif.exposureBias")] = bias.value
        }
        
        // exposure program type
        if exif.programType != .undefined {
            dict[Self.localized("exif.program")] = exif.programType.rawValue
        }
        
        // capture and digitized dates
        if let captured = exif.captured {
            dict[Self.localized("exif.capturedDate")] = captured
        }
        if let digitized = exif.digitized {
            dict[Self.localized("exif.digitizedDate")] = digitized
        }
        
        // body information
        if let bodySerial = exif.bodySerial {
            dict[Self.localized("exif.bodySerial")] = bodySerial
        }
        
        // Lens information
        if let id = exif.lensId {
            dict[Self.localized("exif.lensId")] = id
        }
        if let lensMake = exif.lensMake {
            dict[Self.localized("exif.lensMake")] = lensMake
        }
        if let lensModel = exif.lensModel {
            dict[Self.localized("exif.lensModel")] = lensModel
        }
        if let lensSerial = exif.lensSerial {
            dict[Self.localized("exif.lensSerial")] = lensSerial
        }
        
        return dict
    }
    
    /**
     * Creates a localized dictionary representation of a TIFF metadata object.
     */
    private func localizedTiffDict(_ tiff: ImageMeta.TIFF) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // image width/height
        let sizeStr = String(format: Self.localized("tiff.size.format"),
                             tiff.width, tiff.height)
        dict[Self.localized("tiff.size")] = sizeStr
        
        // camera info
        if let make = tiff.make {
            dict[Self.localized("tiff.make")] = make
        }
        if let model = tiff.model {
            dict[Self.localized("tiff.model")] = model
        }
        
        // system software/hardware used
        if let software = tiff.software {
            dict[Self.localized("tiff.software")] = software
        }
        if let system = tiff.system {
            dict[Self.localized("tiff.system")] = system
        }
        
        // Artist and copyright strings
        if let artist = tiff.artist {
            dict[Self.localized("tiff.artist")] = artist
        }
        if let copyright = tiff.copyright {
            dict[Self.localized("tiff.copyright")] = copyright
        }
        
        // creation date
        if let created = tiff.created {
            dict[Self.localized("tiff.created")] = created
        }
        
        // orientation (TODO: localize value)
        dict[Self.localized("tiff.orientation")] = tiff.orientation.rawValue
        
        // resolution
        var resUnit = ""
        
        if tiff.resolutionUnits == .inch {
            resUnit = Self.localized("tiff.resolution.inch")
        } else if tiff.resolutionUnits == .centimeter {
            resUnit = Self.localized("tiff.resolution.centimeter")
        }
        
        let resFormat = Self.localized("tiff.resolution.format")
        
        if let res = tiff.xResolution {
            dict[Self.localized("tiff.xResolution")] = String(format: resFormat,
                                                              res, resUnit)
        }
        if let res = tiff.yResolution {
            dict[Self.localized("tiff.yResolution")] = String(format: resFormat,
                                                              res, resUnit)
        }
        
        return dict
    }
    
    /**
     * Creates a localized dictionary representation of a GPS metadata object.
     */
    private func localizedGpsDict(_ gps: ImageMeta.GPS) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // lat and lng
        if !gps.latitude.isNaN {
            dict[Self.localized("gps.lat")] = gps.latitude
        }
        if !gps.longitude.isNaN {
            dict[Self.localized("gps.lng")] = gps.longitude
        }
        
        // Datum used to interpret data
        dict[Self.localized("gps.datum")] = gps.reference
        
        // altitude
        if !gps.altitude.isNaN {
            let format = Self.localized("gps.altitude.format")
            dict[Self.localized("gps.altitude")] = String(format: format,
                                                          gps.altitude)
        }
        
        // Dilution of precision
        if !gps.dop.isNaN {
            dict[Self.localized("gps.dop")] = gps.dop
        }
        
        // timestamp
        if let date = gps.utcTimestamp {
            dict[Self.localized("gps.utcTimestamp")] = date
        }

        return dict
    }
    
    // MARK: - Helpers
    /**
     * Returns a localized string with the given identifier.
     */
    private static func localized(_ identifier: String) -> String {
        return NSLocalizedString(identifier,
                                 tableName: "InspectorMetaKeys",
                                 bundle: Bundle.main,
                                 value: "",
                                 comment: "")
    }
}

// Provide identifiers for the various cell types
extension NSUserInterfaceItemIdentifier {
    /// Dictionary key cell
    static let metaCellKey = NSUserInterfaceItemIdentifier("metaCellKey")
    /// Array index cell
    static let metaCellIndex = NSUserInterfaceItemIdentifier("metaCellIndex")
    /// Value cell displaying the number of children of an object
    static let metaCellCount = NSUserInterfaceItemIdentifier("metaCellCount")

    /// Value cell for displaying a string value
    static let metaCellStringValue = NSUserInterfaceItemIdentifier("metaCellStringValue")
    /// Value cell for displaying an integer value
    static let metaCellIntValue = NSUserInterfaceItemIdentifier("metaCellIntValue")
    /// Value cell for displaying a floating point value
    static let metaCellDoubleValue = NSUserInterfaceItemIdentifier("metaCellDoubleValue")
    /// Value cell for displaying a date
    static let metaCellDateValue = NSUserInterfaceItemIdentifier("metaCellDateValue")

    /// Key column
    static let keyColumn = NSUserInterfaceItemIdentifier("keyColumn")
    /// Value column
    static let valueColumn = NSUserInterfaceItemIdentifier("valueColumn")
}
