//
//  ImportSidebarController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Cocoa
import ImageCaptureCore

import CocoaLumberjackSwift

/**
 * Drives a sidebar for the import window that allows device selection.
 *
 * The sidebar is divided into two sections: Devices, and Files.
 */
internal class ImportSidebarController: NSViewController, NSOutlineViewDataSource,
                                        NSOutlineViewDelegate, DeluxeOutlineViewDelegate {
    private var devicesController: ImportDevicesController!
    
    /// Source list type view that contains devices/files
    @IBOutlet private var outlineView: DeluxeOutlineView!
    
    /// Context menu template for devices
    @IBOutlet private var deviceContextMenu: NSMenu!
    
    // MARK: - Initialization
    /**
     * Prepares the device browser.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.outlineView.kushDelegate = self
        
        // create the devices import controller
        self.devicesController = ImportDevicesController(self)
        self.devicesController.menuTemplate = self.deviceContextMenu
        
        self.rootItems.append(self.devicesController.sidebarItem)
        
        // create the files section
        
        // update the outline view
        self.outlineView.reloadData()
        
        self.outlineView.expandItem(self.devicesController.sidebarItem)
    }
    
    // MARK: - View lifecycle
    /**
     * Begins device browsing when the view is about to appear.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.devicesController.startBrowsing()
    }
    
    /**
     * Ends device browsing after the view has disappeared.
     */
    override func viewDidDisappear() {
        super.viewDidDisappear()
        
        self.devicesController.stopBrowsing()
    }
    
    // MARK: - Sidebar outline data source
    /// Sidebar root objects
    private var rootItems: [SidebarItem] = []
    
    /// Generic sidebar item
    @objc internal class SidebarItem: NSObject {
        /// Raw object this item represents
        var representedObject: Any? = nil
        
        /// Title (if needed for display)
        @objc dynamic var title: String = "<no title>"
        /// Badge count
        @objc dynamic var badgeValue: Int = 0 {
            didSet {
                let num = NSNumber(value: self.badgeValue)
                self.badgeString = Self.numberFormatter.string(from: num)
            }
        }
        /// Icon
        @objc dynamic var icon: NSImage? = nil
        
        /// Tint color of icon
        @objc dynamic var tint: NSTintConfiguration? = nil
        
        /// Should the badge be displayed?
        @objc dynamic var showBadge: Bool {
            return (self.badgeValue !=  0)
        }
        /// Dependent key paths for `showBadge` key
        @objc public class func keyPathsForValuesAffectingShowBadge() -> Set<String> {
            return [#keyPath(SidebarItem.badgeValue)]
        }
        /// Stringified badge value
        @objc dynamic private var badgeString: String! = nil
        
        /// Should this item be expanded by default?
        var expandedByDefault: Bool = false
        
        /// Identifier of the cell view to render this item
        var viewIdentifier = NSUserInterfaceItemIdentifier(rawValue: "none")
        /// Is this a group item (source list title)?
        var isGroupItem: Bool = false {
            didSet {
                // automatically apply group row stylings
                if self.isGroupItem {
                    self.viewIdentifier = Self.groupItemType
                    self.expandedByDefault = true
                }
            }
        }
        
        /// Number formatter for badge values
        private static let numberFormatter: NumberFormatter = {
            let f = NumberFormatter()
            f.localizesFormat = true
            f.formattingContext = .standalone
            f.numberStyle = .decimal
            return f
        }()
        
        /**
         * Recalculates the count displayed by summing the count of all children.
         *
         * - NOTE: This does not take into account children that may have further children.
         */
        func updateCountFromChildren() {
            self.badgeValue = self.children.reduce(0, { $0 + $1.badgeValue })
        }
        
        /// Children in the item
        var children: [SidebarItem] = []
        
        /// Menu provider callback
        var menuProvider: ((SidebarItem, NSMenu?) -> NSMenu?)?
        /// Data source provider; invoked when the item is selected and we want to show its contents
        var sourceProvider: ((SidebarItem) -> ImportSource)?
        
        /// Group item type
        static let groupItemType = NSUserInterfaceItemIdentifier(rawValue: "GroupItem")
        /// Device item
        static let deviceItemType = NSUserInterfaceItemIdentifier(rawValue: "DeviceItem")
    }
    
    /**
     * Returns the number of items for a particular child.
     */
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let item = item as? SidebarItem {
            return item.children.count
        } else {
            return self.rootItems.count
        }
    }
    
    /**
     * Returns the object for the given row in the sidebar.
     */
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? SidebarItem {
            return item.children[index]
        } else {
            return self.rootItems[index]
        }
    }
    
    /**
     * Is the item expandable?
     */
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let item = item as? SidebarItem {
            return !item.children.isEmpty
        }
        
        return false
    }
    
    /**
     * Validates the selection; this ensures that no group headers are selected.
     */
    func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection indices: IndexSet) -> IndexSet {
        // remove indices of any group headers
        return IndexSet(indices.filter({
            if let item = outlineView.item(atRow: $0) as? SidebarItem {
                return !item.isGroupItem
            }
            return true
        }))
    }
    
    // MARK: Sidebar outline delegate
    /**
     * Instantiates an cell view, based on the view identifier provided in the item.
     */
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item inItem: Any) -> NSView? {
        guard let item = inItem as? SidebarItem else {
            return nil
        }
        
        return self.cell(outlineView, item.viewIdentifier, item)
    }
    
    /**
     * Determines whether the given row should be drawn as a title/group row; this is true only if the item is
     * one of the root items.
     */
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let item = item as? SidebarItem {
            return item.isGroupItem
        }
        
        return false
    }
    
    /**
     * Returns the tint desired by the item.
     */
    func outlineView(_ outlineView: NSOutlineView, tintConfigurationForItem item: Any) -> NSTintConfiguration? {
        if let item = item as? SidebarItem {
            return item.tint
        }
        
        return nil
    }
    
    /**
     * Returns the menu item for the given row. This invokes the menu provider that the item has registered.
     */
    func outlineView(_ outlineView: NSOutlineView, menu: NSMenu?, at row: Int) -> NSMenu? {
        guard let item = outlineView.item(atRow: row) as? SidebarItem,
              let provider = item.menuProvider else {
            return menu
        }
        
        return provider(item, menu)
    }
    
    /**
     * On changed selection, invoke the source provider of the selected item and use it to populate the content list.
     */
    func outlineViewSelectionDidChange(_ notification: Notification) {
        // get the item provider and invoke it
        guard let item = self.outlineView.item(atRow: self.outlineView.selectedRow) as? SidebarItem,
              let provider = item.sourceProvider
              else {
            self.representedObject = nil
            return
        }
        
        self.representedObject = provider(item)
    }
    
    // MARK: Sidebar helpers
    /**
     * Creates a cell for the given identifier and object.
     */
    private func cell(_ outline: NSOutlineView, _ ident: NSUserInterfaceItemIdentifier, _ value: Any) -> NSView? {
        let view = outline.makeView(withIdentifier: ident, owner: self) as? NSTableCellView
        view?.objectValue = value
        return view
    }
    
    /**
     * Updates the given sidebar item and its children
     */
    internal func updateItem(_ item: SidebarItem) {
        self.outlineView.reloadItem(item)
        
        if item.expandedByDefault {
            self.outlineView.expandItem(item)
        }
    }
    
    // MARK: - Helpers
    static func localized(_ key: String) -> String {
        return Bundle.main.localizedString(forKey: key, value: nil, table: "Importing")
    }    
}
