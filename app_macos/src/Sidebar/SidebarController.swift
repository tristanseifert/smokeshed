//
//  SidebarController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa
import OSLog

import Smokeshop

/**
 * Implements the main window's sidebar: an outline view allowing the user to select from shortcuts, their
 * images sorted by days, and their albums.
 */
class SidebarController: NSViewController, MainWindowContent, NSOutlineViewDataSource, NSOutlineViewDelegate {
    fileprivate static var logger = Logger(subsystem: Bundle(for: SidebarController.self).bundleIdentifier!,
                                         category: "SidebarController")
    
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
        
        // shortcut items
        self.shortcutsController.createItems(&self.root)
        
        // albums
        let albums = OutlineItem()
        albums.viewIdentifier = OutlineItem.groupItemType
        albums.title = NSLocalizedString("albums.group.title",
                                          tableName: "Sidebar",
                                          bundle: Bundle.main, value: "",
                                          comment: "Albums group title")
        albums.isGroupItem = true
        self.root.append(albums)
        
        // images group
        let images = OutlineItem()
        images.viewIdentifier = OutlineItem.groupItemType
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
    
    // MARK: - State restoration
    private struct StateKeys {
        /// Array of expanded item identifiers
        static let expandedIdentifiers = "SidebarController.expanded"
        /// Array of selected item identifiers
        static let selectionIdentifiers = "SidebarController.selection"
    }
    
    /// Array containing identifiers of all expanded items
    private var expandedItemIdentifiers: [String] = []
    
    /**
     * Attempt to restore the sidebar selection.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        
        // restore expanded items
        if let obj = coder.decodeObject(forKey: StateKeys.expandedIdentifiers),
           let identifiers = obj as? [String] {
            Self.logger.trace("Expanding sidebar items: \(identifiers)")
            
            for identifier in identifiers {
                for item in self.root {
                    // is it this item or one of its children?
                    if let found = item.itemForSelectionIdentifier(identifier) {
                        self.outline.expandItem(found)
                    }
                }
            }
        }
        
        // try to read the string identifiers
        if let obj = coder.decodeObject(forKey: StateKeys.selectionIdentifiers),
              let identifiers = obj as? [String] {
            var indices: [Int] = []
            
            for identifier in identifiers {
                // check each root item
                for item in self.root {
                    // is it this item or one of its children?
                    if let found = item.itemForSelectionIdentifier(identifier) {
                        let row = self.outline.row(forItem: found)
                        if row >= 0 {
                            indices.append(row)
                        }
                        
                        break
                    }
                }
            }
            
            Self.logger.debug("Selected sidebar items: \(identifiers) (indices \(indices))")
            self.outline.selectRowIndexes(IndexSet(indices), byExtendingSelection: false)
        }
    }
    
    /**
     * Saves the current sidebar selection.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        
        // save identifiers of all selected items
        var identifiers: [String] = []
        
        for index in self.outline.selectedRowIndexes {
            if let item = self.outline.item(atRow: index) as? OutlineItem,
               let identifier = item.selectionIdentifier {
                identifiers.append(identifier)
            }
        }
        
        if !identifiers.isEmpty {
            Self.logger.debug("Selected sidebar items: \(identifiers)")
            coder.encode(identifiers, forKey: StateKeys.selectionIdentifiers)
        }
        
        // save identifiers of all expanded item
        if !self.expandedItemIdentifiers.isEmpty {
            Self.logger.debug("Expanded sidebar items: \(self.expandedItemIdentifiers)")
            coder.encode(self.expandedItemIdentifiers, forKey: StateKeys.expandedIdentifiers)
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
    
    /**
     * Notes that the given outline item was expanded.
     */
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let obj = notification.userInfo?["NSObject"] else {
            return
        }
        
        if let item = obj as? OutlineItem,
           let identifier = item.selectionIdentifier {
            self.expandedItemIdentifiers.append(identifier)
            self.invalidateRestorableState()
        }
    }
    
    /**
     * Notes that the given outline item is no longer expanded.
     */
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let obj = notification.userInfo?["NSObject"] else {
            return
        }
        
        if let item = obj as? OutlineItem,
           let identifier = item.selectionIdentifier {
            self.expandedItemIdentifiers.removeAll(where: { $0 == identifier })
            self.invalidateRestorableState()
        }
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
        
        self.invalidateRestorableState()
        
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
        
        /// Identifier for selection restoration (if nil, do not persist selection)
        @objc dynamic var selectionIdentifier: String? = nil
        
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
        
        /**
         * Recursively searches all child items for an item with the given selection identifier.
         */
        func itemForSelectionIdentifier(_ identifier: String) -> OutlineItem? {
            // does the identifier match ours?
            if self.selectionIdentifier == identifier {
                return self
            }
            
            // search all children
            for child in self.children {
                // check that child
                if let found = child.itemForSelectionIdentifier(identifier) {
                    return found
                }
            }
            
            // failed to find it
            return nil
        }
        
        /// Group item type
        static let groupItemType = NSUserInterfaceItemIdentifier(rawValue: "GroupItem")
        /// Name, icon, with badge cell
        static let imageCountType = NSUserInterfaceItemIdentifier(rawValue: "ImageCountItem")
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

