//
//  LibraryBrowserBase.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200613.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * This is a basic view controller subclass that's controls display of a collection of images in a grid view.
 */
class LibraryBrowserBase: NSViewController, NSMenuItemValidation,
    NSCollectionViewPrefetching, NSCollectionViewDelegate,
NSFetchedResultsControllerDelegate {
    /// Library that is being browsed
    public var library: LibraryBundle! = nil {
        didSet {
            // if library was set, update the coredata stuff
            if let _ = self.library {
                self.initFetchReq()
            }
            // otherwise, destroy the fetch requests and whatnot
            else {
                self.dataSource = nil
                self.fetchReqCtrl = nil
                self.fetchReq = nil
            }
        }
    }
    /// Convenience helper for accessing the view context of the library store
    internal var ctx: NSManagedObjectContext {
        return library.store.mainContext!
    }

    // MARK: - View Lifecycle
    /**
     * Sets up the data source when the view has loaded.
     */
    override func viewDidLoad() {
        self.setUpDataSource()
    }

    /**
     * Updates the size of cells when the view is about to appear.
     */
    override func viewWillAppear() {
        self.reflowContent()
    }

    /**
     * When the view has appeared, perform state restoration.
     */
    override func viewDidAppear() {
        self.restoreBlock.forEach{ block in
            block()
        }
        self.restoreBlock.removeAll()
    }

    // MARK: - State restoration
    /// Should the viewport of the collection be encoded?
    internal var restoreViewport = false
    /// Should the selected objects be encoded?
    internal var restoreSelection = true
    /// Should the sort/group state be restored?
    internal var restoreSort = true

    private struct StateKeys {
        /// Grid zoom level
        static let gridZoom = "LibraryBrowserBase.gridZoom"
        /// URL representation of the IDs of the selected objects
        static let selectedObjectIds = "LibraryBrowserBase.selectedObjectIds"
        /// URL representation of the IDs of all currently visible objects
        static let visibleObjectIds = "LibraryBrowserBase.visibleObjectIds"
        /// Key by which images are sorted
        static let sortKey = "LibraryBrowserBase.sortKey"
        /// Order in which images are sorted
        static let sortOrder = "LibraryBrowserBase.sortOrder"
        /// Key by which images are grouped
        static let groupKey = "LibraryBrowserBase.groupKey"
        /// Order in which the grouping key is ordered
        static let groupOrder = "LibraryBrowserBase.groupOrder"
    }

    /// Blocks to execute when the view is made displayable to complete state restoration
    internal var restoreBlock: [(() -> Void)] = []
    /// Block to execute after initial data fetch to restore selection, etc.
    internal var restoreAfterFetchBlock: [(() -> Void)] = []

    /**
     * Encodes the current view state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // encode the zoom level
        coder.encode(Double(self.gridZoom), forKey: StateKeys.gridZoom)

        // store the IDs of visible objects
        if self.restoreViewport {
            let visibleIds = self.collection.indexPathsForVisibleItems().compactMap({ path -> URL? in
                // get the layout attributes of the item (for the frame)
                guard let attribs = self.collection.layoutAttributesForItem(at: path) else {
                    return nil
                }

                // ensure it's actually visible
                if attribs.frame.intersects(self.collection.visibleRect) {
                    return self.fetchReqCtrl.object(at: path).objectID.uriRepresentation()
                }
                // not visible
                return nil
            })
            if !visibleIds.isEmpty {
                coder.encode(visibleIds, forKey: StateKeys.visibleObjectIds)
            }
        }

        // store the IDs of selected objects
        if self.restoreSelection {
            let selectedIds = self.collection.selectionIndexPaths.map({ path in
                return self.fetchReqCtrl.object(at: path).objectID.uriRepresentation()
            })
            if !selectedIds.isEmpty {
                coder.encode(selectedIds, forKey: StateKeys.selectedObjectIds)
            }
        }

        // store sort properties
        if self.restoreSort {
            coder.encode(self.sortByKey.rawValue, forKey: StateKeys.sortKey)
            coder.encode(self.sortByOrder.rawValue, forKey: StateKeys.sortOrder)
            coder.encode(self.groupBy.rawValue, forKey: StateKeys.groupKey)
            coder.encode(self.groupOrder.rawValue, forKey: StateKeys.groupOrder)
        }
    }

    /**
     * Restores the view state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // read values
        let visibleIds = coder.decodeObject(forKey: StateKeys.visibleObjectIds)
        let selectedIds = coder.decodeObject(forKey: StateKeys.selectedObjectIds)

        // restore zoom level
        let zoom = coder.decodeDouble(forKey: StateKeys.gridZoom)

        if zoom >= 1 && zoom <= 8 {
            self.gridZoom = CGFloat(zoom)
        }

        // restore selection and visible objects
        self.restoreAfterFetchBlock.append({
            // get selection as an array of URL-represented object IDs at first
            if let selected = selectedIds as? [URL] {
                let paths = selected.compactMap(self.urlToImages)

                if !paths.isEmpty {
                    let pathSet = Set(paths)
                    self.collection.selectItems(at: pathSet, scrollPosition: [.centeredVertically])

                    self.updateRepresentedObj()
                }

            }

            // scroll to the visible objects
            if let visible = visibleIds as? [URL] {
                let paths = visible.compactMap(self.urlToImages)

                if !paths.isEmpty {
                    self.collection.scrollToItems(at: Set(paths),
                                                  scrollPosition: [.centeredVertically])
                }
            }
        })

        // restore sort properties
        if let key = SortKey(rawValue: coder.decodeInteger(forKey: StateKeys.sortKey)) {
            self.sortByKey = key
        }
        if let order = SortOrder(rawValue: coder.decodeInteger(forKey: StateKeys.sortOrder)) {
            self.sortByOrder = order
        }

        if let key = GroupByKey(rawValue: coder.decodeInteger(forKey: StateKeys.groupKey)) {
            self.groupBy = key
        }
        if let order = SortOrder(rawValue: coder.decodeInteger(forKey: StateKeys.groupOrder)) {
            self.groupOrder = order
        }

        self.updateSortDescriptors()
    }

    /**
     * Transforms an array of URL objects into an index path.
     */
    internal func urlToImages(_ url: URL) -> IndexPath? {
        // get persistent store coordinator
        guard let psc = self.ctx.persistentStoreCoordinator else {
            DDLogError("Persistent store coordinator is required")
            return nil
        }

        // get an object id for it
        guard let id = psc.managedObjectID(forURIRepresentation: url) else {
            DDLogInfo("Failed to get object id from '\(url)'")
            return nil
        }

        // get an object
        guard let image = self.ctx.object(with: id) as? Image else {
            DDLogInfo("Failed to get image for id \(id)")
            return nil
        }

        // lastly, try to convert it to an index path
        return self.fetchReqCtrl.indexPath(forObject: image)
    }

    // MARK: - Fetching
    /// Name of the cache used for the fetch controller
    internal var fetchCacheName: String? {
        return "LibraryBrowserBase"
    }

    /// Fetch request used to get data
    internal var fetchReq: NSFetchRequest<Image>! = Image.fetchRequest()
    /// Fetched results controller
    internal var fetchReqCtrl: NSFetchedResultsController<Image>! = nil
    /// Has the fetch request been changed since the last time? (Used to invalidate cache)
    internal var fetchReqChanged: Bool = false
    /// Does the fetch controller specifically need to be recreated (e.g. because section changes?)
    internal var recreateFetchRequest: Bool = false
    
    /**
     * Initializes the fetch request.
     */
    private func initFetchReq() {
        // only fetch some properties now
        self.fetchReq.propertiesToFetch = ["name", "dateCaptured", "identifier", "pvtImageSize", "camera", "lens"]
        //        self.fetchReq.relationshipKeyPathsForPrefetching = ["camera", "lens"]

        // batch results for better performance; and also fetch subentities
        self.fetchReq.fetchBatchSize = 25
        self.fetchReq.includesSubentities = true

        // update sorting
        self.updateSortDescriptors()
    }

    /**
     * Performs the fetch.
     */
    internal func fetch() {
        // if the fetch request changed, we need to allocate a new fetch ctrl
        if self.fetchReqChanged || self.fetchReqCtrl == nil {
            // it's important the cache is cleared in this case
            NSFetchedResultsController<NSFetchRequestResult>.deleteCache(withName: self.fetchCacheName)

            if self.fetchReqCtrl == nil || self.recreateFetchRequest {
                self.fetchReqCtrl = NSFetchedResultsController(fetchRequest: self.fetchReq,
                                       managedObjectContext: self.ctx,
                                       sectionNameKeyPath: self.groupBy.keyPath,
                                       cacheName: self.fetchCacheName)
                self.fetchReqCtrl.delegate = self
                
                self.recreateFetchRequest = false
            }

            // clear the flag
            self.fetchReqChanged = false
        }

        // do the fetch and update our data source
        do {
            try self.fetchReqCtrl.performFetch()

            self.restoreAfterFetchBlock.forEach{ block in
                block()
            }
            self.restoreAfterFetchBlock.removeAll()
        } catch {
            DDLogError("Failed to execute fetch request: \(error)")
            self.presentError(error, modalFor: self.view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    // MARK: Sorting and grouping
    @objc internal enum SortKey: Int {
        case dateCaptured = 1
        case dateImported = 2
        case rating = 3

        var keyPath: String {
            get {
                switch self {
                    case .dateCaptured:
                        return #keyPath(Image.dateCaptured)
                    case .dateImported:
                        return #keyPath(Image.dateImported)
                    case .rating:
                        return #keyPath(Image.rating)
                }
            }
        }

        /// Localized display string
        var localizedName: String {
            return Bundle.main.localizedString(forKey: "sort.key.\(self.rawValue)", value: nil, table: "LibraryBrowserBase")
        }
    }

    @objc internal enum SortOrder: Int {
        case ascending = 1
        case descending = 2

        /// Localized display string
        var localizedName: String {
            return Bundle.main.localizedString(forKey: "sort.order.\(self.rawValue)", value: nil, table: "LibraryBrowserBase")
        }
    }

    @objc internal enum GroupByKey: Int {
        case none = -1
        case dateCaptured = 1
        case dateImported = 2
        case rating = 3

        /// Key path to use for grouping
        var keyPath: String? {
            get {
                switch self {
                    case .none:
                        return nil
                    case .dateCaptured:
                        return #keyPath(Image.dayCaptured)
                    case .dateImported:
                        return #keyPath(Image.dateImported)
                    case .rating:
                        return #keyPath(Image.rating)
                }
            }
        }

        /// Key path to use for sorting
        var sortKeyPath: String? {
            get {
                switch self {
                    case .none:
                        return nil
                    case .dateCaptured:
                        return #keyPath(Image.dateCaptured)
                    case .dateImported:
                        return #keyPath(Image.dateImported)
                    case .rating:
                        return #keyPath(Image.rating)
                }
            }
        }

        /// Localized display string
        var localizedName: String {
            return Bundle.main.localizedString(forKey: "group.key.\(self.rawValue)", value: nil, table: "LibraryBrowserBase")
        }
    }

    /// If side effects should be suppressed for sort/order key sets
    private var suppressOrderKeySet = false

    /// What key to sort by
    @objc dynamic internal var sortByKey: SortKey = .dateCaptured {
        didSet {
            // if sort and group keys are the same, sync sort orders
            if self.sortByKey.rawValue == self.groupBy.rawValue {
                self.suppressOrderKeySet = true
                self.groupOrder = self.sortByOrder
                self.suppressOrderKeySet = false
            }
        }
    }
    /// Sort order
    @objc dynamic internal var sortByOrder: SortOrder = .descending {
        didSet {
            // bail if suppressing order changes
            if self.suppressOrderKeySet {
                return
            }
            // if sort and group keys are the same, sync sort orders
            if self.sortByKey.rawValue == self.groupBy.rawValue {
                self.suppressOrderKeySet = true
                self.groupOrder = self.sortByOrder
                self.suppressOrderKeySet = false
            }
        }
    }

    /// What results are grouped by
    @objc dynamic internal var groupBy: GroupByKey = .dateCaptured {
        didSet {
            // if sort and group keys are the same, sync sort orders
            if self.sortByKey.rawValue == self.groupBy.rawValue {
                self.suppressOrderKeySet = true
                self.sortByOrder = self.groupOrder
                self.suppressOrderKeySet = false
            }
            
            // hide headers if no grouping, show otherwise
            guard let l = self.collection!.collectionViewLayout,
                  let layout = l as? NSCollectionViewFlowLayout else {
                    return
            }
            
            if self.groupBy == .none {
                layout.headerReferenceSize = .zero
            } else {
                layout.headerReferenceSize = NSSize(width: 0, height: 30)
            }
        }
    }
    /// Grouping order
    @objc dynamic internal var groupOrder: SortOrder = .descending {
        didSet {
            // bail if suppressing order changes
            if self.suppressOrderKeySet {
                return
            }
            // if sort and group keys are the same, sync sort orders
            if self.sortByKey.rawValue == self.groupBy.rawValue {
                self.suppressOrderKeySet = true
                self.sortByOrder = self.groupOrder
                self.suppressOrderKeySet = false
            }
        }
    }

    /**
     * Updates the sort descriptors based on the sort properties and grouping keys.
     */
    private func updateSortDescriptors() {
        // default: just use the sort by keys
        var sortDescs = [
            NSSortDescriptor(key: self.sortByKey.keyPath,
                             ascending: (self.sortByOrder == .ascending)),
        ]
        
        // ensure the group by and sort by keys are different
        if self.groupBy.rawValue != self.sortByKey.rawValue {
            // if we've a valid group sort key, sort by that first
            if let groupByKey = self.groupBy.sortKeyPath {
                let desc = NSSortDescriptor(key: groupByKey,
                                            ascending: (self.groupOrder == .ascending))
                sortDescs.insert(desc, at: 0)
            }
        }

        // ensure fetch controller is updated
        self.fetchReq.sortDescriptors = sortDescs
        self.fetchReqChanged = true
    }
    /**
     * Sets the sorting key based on the tag of the given view/menu item.
     */
    @IBAction func setLibrarySortKey(_ sender: Any?) {
        // get the tag of the sender
        var tag: Int = -1
        if let menu = sender as? NSMenuItem {
            tag = menu.tag
        }
        guard let key = SortKey(rawValue: tag) else {
            fatalError("Failed to get sort key from tag \(tag)")
        }

        // update sort descriptor
        self.sortByKey = key

        self.updateSortDescriptors()
        self.fetch()
        
        self.invalidateRestorableState()
    }
    /**
     * Sets the sort order based on the tag of the sender.
     */
    @IBAction func setLibrarySortOrder(_ sender: Any?) {
        // get the tag of the sender
        var tag: Int = -1
        if let menu = sender as? NSMenuItem {
            tag = menu.tag
        }
        guard let order = SortOrder(rawValue: tag) else {
            fatalError("Failed to get sort order from tag \(tag)")
        }

        // update sort descriptor
        self.sortByOrder = order

        self.updateSortDescriptors()
        self.fetch()
        
        self.invalidateRestorableState()
    }

    /**
     * Sets the field by which results are grouped based on the tag of the sender.
     */
    @IBAction func setLibraryGroupKey(_ sender: Any?) {
        // get the tag of the sender
        var tag: Int = -1
        if let menu = sender as? NSMenuItem {
            tag = menu.tag
        }
        guard let key = GroupByKey(rawValue: tag) else {
            fatalError("Failed to get grouping key from tag \(tag)")
        }

        // update sort descriptor
        self.groupBy = key
        self.recreateFetchRequest = true

        self.updateSortDescriptors()
        self.setUpDataSource()
        self.fetch()
        
        self.invalidateRestorableState()
    }
    /**
     * Sets the sort order for the result grouping..
     */
    @IBAction func setLibraryGroupOrder(_ sender: Any?) {
        // get the tag of the sender
        var tag: Int = -1
        if let menu = sender as? NSMenuItem {
            tag = menu.tag
        }
        guard let order = SortOrder(rawValue: tag) else {
            fatalError("Failed to get group order from tag \(tag)")
        }

        // update sort descriptor
        self.groupOrder = order

        self.updateSortDescriptors()
        self.fetch()
        
        self.invalidateRestorableState()
    }

    // MARK: - Collection data source
    /// This is the collection view that holds the library images.
    @IBOutlet internal var collection: LibraryCollectionView! = nil

    /// Diffable data source for collection view
    private var dataSource: NSCollectionViewDiffableDataSource<String, NSManagedObjectID>! = nil
    /**
     * Whether the data source update is animated or not. There seems to be a bug in the implementation
     * such that the first refresh _must_ not be animated, as it doesn't reload the underlying data model; all
     * subsequent refreshes will then be animated.
     *
     * This is reset when the data source is created, and set once the first update completed.
     */
    internal var animateDataSourceUpdates: Bool = false

    /**
     * Initializes the diffable data source. This is done instead of a standard data source pattern so that
     * we can mopre easily handle CoreData changes.
     */
    private func setUpDataSource() {
        // create the data source with the item provider
        self.dataSource = NSCollectionViewDiffableDataSource(collectionView: self.collection!, itemProvider: { (view, path, id) -> NSCollectionViewItem in
            let cell = view.makeItem(withIdentifier: .libraryCollectionItem,
                                     for: path) as! LibraryCollectionItem
            cell.sequenceNumber = (path[1] + 1)
            cell.libraryUrl = self.library.url
            cell.representedObject = self.fetchReqCtrl.object(at: path)

            return cell
        })

        // give it its section header provider as well
        self.dataSource.supplementaryViewProvider = { (view, kind, path) in
            guard kind == NSCollectionView.elementKindSectionHeader else {
                DDLogError("Unsupported supplementary item kind '\(kind)' for path \(path)")
                return nil
            }
            // ensure we want grouping (otherwise we get a single ugly 'unknown' header)
            guard self.groupBy != .none else {
                return nil
            }

            let header = view.makeSupplementaryView(ofKind: kind,
                                                    withIdentifier: .libraryCollectionHeader,
                                                    for: path) as! LibraryCollectionHeaderView

            header.owner = self
            header.collection = view
            header.section = self.fetchReqCtrl.sections![path[0]]

            return header
        }

        // it's configured, so set it on the collection view
        self.animateDataSourceUpdates = false
        self.collection.dataSource = self.dataSource
    }

    /**
     * Applies data source changes to the data source.
     */
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        self.dataSource.apply(snapshot, animatingDifferences: self.animateDataSourceUpdates)
        self.animateDataSourceUpdates = true
    }

    // MARK: Collection prefetching
    /**
     * Prefetch data for the given rows. This kicks off a thumb request so that the image can be generated if
     * it is not already available.
     */
    func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        ThumbHandler.shared.prefetch(indexPaths.map({ (path) in
            return self.fetchReqCtrl.object(at: path)
        }))
    }

    /**
     * Aborts prefetch of the given rows. Cancel any outstanding thumb requests for those images.
     */
    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // TODO: implement this better. this will crash during bulk updates
        //        ThumbHandler.shared.cancel(indexPaths.map({ (path) in
        //            return self.fetchReqCtrl.object(at: path)
        //        }))
    }

    // MARK: Collection layout
    /// Zoom factor
    @objc dynamic internal var gridZoom: CGFloat = 5 {
        didSet {
            self.imagesPerRow = 9 - gridZoom

            self.invalidateRestorableState()
            self.parent?.invalidateRestorableState()
        }
    }
    /// Number of columns of images to display.
    internal var imagesPerRow: CGFloat = 4 {
        didSet {
            if (self.collection != nil) {
                self.reflowContent()
            }
        }
    }

    /**
     * Updates the item size used to lay out the collection view.
     */
    internal func reflowContent() {
        let size = self.collection.bounds.size

        // get a reference to the flow layout (set in IB)
        guard let l = self.collection!.collectionViewLayout,
            let layout = l as? NSCollectionViewFlowLayout else {
                return
        }

        // calculate the new size
        let width = min(floor(size.width / self.imagesPerRow), size.width)
        let height = ceil(width * 1.25)

        layout.itemSize = NSSize(width: width, height: height)
    }

    // MARK: Collection delegate
    /**
     * One or more items were selected.
     */
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        self.updateRepresentedObj()
        self.parent?.invalidateRestorableState()
    }

    /**
     * One or more items were deselected.
     */
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        self.updateRepresentedObj()
        self.parent?.invalidateRestorableState()
    }

    /**
     * Updates the represented object of the view controller; this is set to an array encompassing the
     * selection of the collection view.
     */
    private func updateRepresentedObj() {
        self.representedObject = self.collection.selectionIndexPaths.map(self.fetchReqCtrl.object)
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // sort order
        if menuItem.action == #selector(setLibrarySortOrder(_:)) {
            menuItem.state = (menuItem.tag == self.sortByOrder.rawValue) ? .on : .off
            return true
        }
        // sort key
        if menuItem.action == #selector(setLibrarySortKey(_:)) {
            menuItem.state = (menuItem.tag == self.sortByKey.rawValue) ? .on : .off
            return true
        }
        // group sort order
        if menuItem.action == #selector(setLibraryGroupOrder(_:)) {
            menuItem.state = (menuItem.tag == self.groupOrder.rawValue) ? .on : .off
            return (self.groupBy != .none)
        }
        // group by key
        if menuItem.action == #selector(setLibraryGroupKey(_:)) {
            menuItem.state = (menuItem.tag == self.groupBy.rawValue) ? .on : .off
            return true
        }

        // we do not handle it
        return false
    }
}
