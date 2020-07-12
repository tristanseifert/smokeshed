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
            self.root = self.meta?.localizedDictionaryRepresentation
            
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
