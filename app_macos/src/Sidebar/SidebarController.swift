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
class SidebarController: NSViewController, MainWindowContent, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Currently opened library
    internal var library: LibraryBundle! {
        didSet {
            self.shortcutsController.library = self.library
            self.imagesController.library = self.library
        }
    }
    /// Declare sidebar filter (we don't use it)
    weak var sidebarFilters: NSPredicate? = nil
    
    /// Outline view for sidebar
    @IBOutlet private var outline: NSOutlineView! {
        didSet {
            self.imagesController.outline = self.outline
        }
    }
    
    /// Controller for the all images items
    private var shortcutsController = SidebarShortcutsController()
    /// Image date tree controller
    private var imagesController = SidebarImagesByDateController()
    
    // MARK: - Initialization
    /**
     * Remove observers for notifications on dealloc.
     */
    deinit {
        self.tearDownNotifications()
    }
    
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
        allImages.allowsMultipleSelect = false
        
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
        self.imagesController.groupItem = images
        
        // update the view
        self.outline.reloadData()
        
        // install the notification observers
        self.setUpNotifications()
    }

    /**
     * Attempts to restore the selected sidebar item.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        if self.outline.selectedRowIndexes.isEmpty {
            self.outline.selectRowIndexes(IndexSet(integer: 0),
                                          byExtendingSelection: false)
        }
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
     * Validates the selection; this ensures that all items selected allow multiple selection, and that no group
     * item headers are selected.
     */
    func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection indices: IndexSet) -> IndexSet {
        // convert selection to items
        let items = indices.compactMap({
            return outlineView.item(atRow: $0) as? OutlineItem
        })
        
        // find the first non-multiselect item
        for item in items {
            // if we've found one, return a set containing only its index
            if !item.allowsMultipleSelect, !item.isGroupItem {
                let index = outlineView.row(forItem: item)
                return IndexSet(integer: index)
            }
        }
        
        // remove indices of any group headers
        return IndexSet(indices.filter({
            if let item = outlineView.item(atRow: $0) as? OutlineItem {
                return !item.isGroupItem
            }
            return true
        }))
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
    
    // MARK: Selection
    /// Predicate for filtering images to match the sidebar selection; may be nil if no filter needed
    @objc dynamic var filter: NSPredicate? = nil
    
    /**
     * The outline view's selection changed; build a new compound predicate.
     */
    func outlineViewSelectionDidChange(_: Notification) {
        var predicates: [NSPredicate] = []
        
        // get all selected items and their predicates
        let items = self.outline.selectedRowIndexes.compactMap({
            return self.outline.item(atRow: $0) as? OutlineItem
        })
        
        for item in items {
            if let pred = item.predicate {
                predicates.append(pred)
            }
        }
        
        // if no predicates, remove filter
        guard !predicates.isEmpty else {
            self.filter = nil
            return
        }
        
        // create a compound OR predicate
        self.filter = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
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
    
    // MARK: - Notifications
    /// Installed notification observers
    private var noteObservers: [NSObjectProtocol] = []
    
    /**
     * Installs notification handlers.
     */
    private func setUpNotifications() {
        let nc = NotificationCenter.default
        
        // sidebar item updated
        let o1 = nc.addObserver(forName: .sidebarItemUpdated, object: nil, queue: nil,
                                using: self.handleItemChangedNotif(_:))
        self.noteObservers.append(o1)
    }
    
    /**
     * Tears down all notification handlers we previously installed.
     */
    private func tearDownNotifications() {
        for observer in self.noteObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /**
     * Notification handler for "sidebar item updated" notification. The object of the notification is the item, if any.
     */
    private func handleItemChangedNotif(_ note: Notification) {
        guard let updated = note.object as? OutlineItem else {
            return
        }
        
        // see if there is an intersection between the selected items and the changed item
        let selected = self.outline.selectedRowIndexes.compactMap({
            return self.outline.item(atRow: $0) as? OutlineItem
        })
        
        if selected.contains(updated) {
            // if so, force an update of the current filters
            self.outlineViewSelectionDidChange(note)
        }
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
        var isGroupItem: Bool = false {
            didSet {
                // enable group item specific behaviors
                if self.isGroupItem {
                    // you cannot multiselect group items
                    self.allowsMultipleSelect = false
                    // they are expanded by default
                    self.expandedByDefault = true
                }
            }
        }
        /// Can this item participate in multiple selection?
        var allowsMultipleSelect: Bool = true
        /// Should this item be expanded by default?
        var expandedByDefault: Bool = false
        
        /// Filter predicate to use to filter images when this item is selected
        var predicate: NSPredicate!
        
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
    }
}

extension Notification.Name {
    /**
     * A sidebar item was modified.
     *
     * The sidebar filters will be updated accordingly if the item is currently selected.
     */
    internal static let sidebarItemUpdated = Notification.Name("me.tseifert.smokeshed.sidebar.item.updated")
}

