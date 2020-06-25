//
//  SidebarController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Implements the main window's sidebar: an outline view allowing the user to select from shortcuts, their
 * images sorted by days, and their albums.
 */
class SidebarController: NSViewController, MainWindowLibraryPropagating, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Currently opened library
    internal var library: LibraryBundle! {
        didSet {
            self.shortcutsController.library = self.library
        }
    }
    
    /// Outline view for sidebar
    @IBOutlet private var outline: NSOutlineView!
    
    /// Controller for the all images items
    private var shortcutsController = SidebarShortcutsController()
    
    // MARK: - Initialization
    /**
     * Creates the default items for the sidebar.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // different cell types
        let groupItemType = NSUserInterfaceItemIdentifier(rawValue: "GroupItem")
        let imageCountType = NSUserInterfaceItemIdentifier(rawValue: "ImageCountItem")
        
        // all images item
        let allImages = OutlineItem()
        allImages.viewIdentifier = imageCountType
        allImages.title = NSLocalizedString("images.all.title",
                                          tableName: "Sidebar",
                                          bundle: Bundle.main, value: "",
                                          comment: "All images item")
        allImages.icon = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                accessibilityDescription: "All photos icon")
        
        self.root.append(allImages)
        self.shortcutsController.allItem = allImages
        
        // last import
        let last = OutlineItem()
        last.viewIdentifier = imageCountType
        last.title = NSLocalizedString("images.last_import.title",
                                          tableName: "Sidebar",
                                          bundle: Bundle.main, value: "",
                                          comment: "Last import item")
        last.icon = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                accessibilityDescription: "Last Import icon")
        
        self.root.append(last)
        self.shortcutsController.lastImportItem = last
        
        // albums
        let albums = OutlineItem()
        albums.viewIdentifier = groupItemType
        albums.title = NSLocalizedString("albums.group.title",
                                          tableName: "Sidebar",
                                          bundle: Bundle.main, value: "",
                                          comment: "Albums group title")
        albums.isGroupItem = true
        self.root.append(albums)
        
        // images group
        let images = OutlineItem()
        images.viewIdentifier = groupItemType
        images.title = NSLocalizedString("images.group.title",
                                          tableName: "Sidebar",
                                          bundle: Bundle.main, value: "",
                                          comment: "Images group title")
        images.isGroupItem = true
        self.root.append(images)
        
        // update the view
        self.outline.reloadData()
    }
    
    // MARK: - Outline data source
    /// Root items
    private var root: [OutlineItem] = []

    /**
     * Gets the number of children of a particular item by calling its children property.
     */
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let item = item as? OutlineItem {
            return item.children.count
        } else {
            return self.root.count
        }
    }

    /**
     * Returns the object representing a child of a particular item; nil for the root of the view.
     */
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? OutlineItem {
            return item.children[index]
        } else {
            return self.root[index]
        }
    }

    /**
     * Is the item expandable?
     */
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let item = item as? OutlineItem {
            return !item.children.isEmpty
        }
        
        return false
    }
    
    // MARK: - Outline delegate
    /**
     * Instantiates an cell view, based on the view identifier provided in the item.
     */
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item inItem: Any) -> NSView? {
        guard let item = inItem as? OutlineItem else {
            return nil
        }
        
        return self.cell(outlineView, item.viewIdentifier, item)
    }
    
    /**
     * Determines whether the given row should be drawn as a title/group row; this is true only if the item is
     * one of the root items.
     */
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let item = item as? OutlineItem {
            return item.isGroupItem
        }
        
        return false
    }
    
    /**
     * Allow only non group items to be selected
     */
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let item = item as? OutlineItem {
            return !item.isGroupItem
        }
        
        return false
    }
    
    /**
     * Returns the tint desired by the item.
     */
    func outlineView(_ outlineView: NSOutlineView, tintConfigurationForItem item: Any) -> NSTintConfiguration? {
        if let item = item as? OutlineItem {
            return item.tint
        }
        
        return nil
    }
    
    // MARK: Helpers
    /**
     * Creates a cell for the given identifier and object.
     */
    private func cell(_ outline: NSOutlineView, _ ident: NSUserInterfaceItemIdentifier, _ value: Any) -> NSView? {
        let view = outline.makeView(withIdentifier: ident, owner: self) as? NSTableCellView
        view?.objectValue = value
        return view
    }
    
    // MARK: - Types
    /**
     * Represents a single entry in the sidebar list, which may have children.
     */
    @objc class OutlineItem: NSObject {
        /// Title displayed in the cell
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
            return [#keyPath(OutlineItem.badgeValue)]
        }
        
        /// Stringified badge value
        @objc dynamic private var badgeString: String! = nil
        
        /// Children of this item
        var children: [OutlineItem] = []
        
        /// Identifier of the cell view to render this item
        var viewIdentifier = NSUserInterfaceItemIdentifier(rawValue: "none")
        /// Is this a group item (source list title)?
        var isGroupItem: Bool = false
        
        /// Number formatter for badge values
        private static let numberFormatter: NumberFormatter = {
            let f = NumberFormatter()
            f.localizesFormat = true
            f.formattingContext = .standalone
            f.numberStyle = .decimal
            return f
        }()
    }
}

