//
//  LibraryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryViewController: NSViewController, NSMenuItemValidation,
                             NSCollectionViewPrefetching,
                             NSCollectionViewDelegate,
                             NSFetchedResultsControllerDelegate,
                             NSSplitViewDelegate,
                             ContentViewChild {
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
    private var ctx: NSManagedObjectContext {
        return library.store.mainContext!
    }

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var nibName: NSNib.Name? {
        return "LibraryViewController"
    }

    /**
     * Initializes the library controller.
     */
    init() {
        super.init(nibName: nil, bundle: nil)
        self.identifier = .libraryViewController
    }

    /// Decoding is not supported
    required init?(coder: NSCoder) {
        return nil
    }
    func getPreferredApperance() -> NSAppearance? {
        return nil
    }
    func getBottomBorderThickness() -> CGFloat {
        return 32
    }

    // MARK: View Lifecycle
    /// Whether animations should be run or not
    private var shouldAnimate: Bool = false

    /**
     * Initiaizes CoreData contexts for displaying data once the view has loaded.
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        // set up filter bar state
        self.isFilterVisible = false
        self.filter.enclosingScrollView?.isHidden = true

        self.setUpFilterAreaHeightNotifications()

        // register the collection view classes
        self.collection.register(LibraryCollectionItem.self,
                                 forItemWithIdentifier: .libraryCollectionItem)

        self.collection.register(LibraryCollectionHeaderView.self,
                                 forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                 withIdentifier: .libraryCollectionHeader)

        // set up the collection view data source
        self.setUpDataSource()
    }

    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        // restore state if needed
        if let restorer = self.restoreBlock {
            restorer()
            self.restoreBlock = nil
        }

        // ensure the grid is updated properly
        self.reflowContent()
        self.fetch()
    }
    /**
     * Adds an observer on window size changes. This is used to reflow the content grid as needed.
     */
    override func viewDidAppear() {
        let c = NotificationCenter.default

        // add the resize handlers
        c.addObserver(forName: NSWindow.didResizeNotification,
                      object: self.view.window!, queue: nil, using: { (n) in
            self.reflowContent()
        })

        c.addObserver(forName: NSView.frameDidChangeNotification,
                      object: self.collection!, queue: nil, using: { (n) in
            self.reflowContent()
        })
        self.collection.postsFrameChangedNotifications = true

        // allow animations
        self.shouldAnimate = true
    }
    /**
     * Removes the window resize observer as we're about to be disappeared.
     */
    override func viewWillDisappear() {
        let c = NotificationCenter.default

        // remove the resize handlers
        c.removeObserver(self, name: NSWindow.didResizeNotification,
                         object: self.view.window!)

        self.collection.postsFrameChangedNotifications = false
        c.removeObserver(self, name: NSView.boundsDidChangeNotification,
                         object: self.collection!)

        // disallow animations
        self.shouldAnimate = false
    }

    // MARK: - State restoration
    private struct StateKeys {
        /// Filter bar visibility state
        static let filterVisibility = "LibraryViewController.isFilterVisible"
        /// Grid zoom level
        static let gridZoom = "LibraryViewController.gridZoom"
        /// URL representation of the IDs of the selected objects
        static let selectedObjectIds = "LibraryViewController.selectedObjectIds"
        /// URL representation of the IDs of all currently visible objects
        static let visibleObjectIds = "LibraryViewController.visibleObjectIds"
        /// Position of the sidebar splitter
        static let sidebarPosition = "LibraryViewController.sidebarPosition"
    }

    /// Block to execute when the view is made displayable to complete state restoration
    private var restoreBlock: (() -> Void)? = nil
    /// Block to execute after initial data fetch to restore selection, etc.
    private var restoreAfterFetchBlock: (() -> Void)? = nil

    /**
     * Encodes the current view state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        coder.encode(self.isFilterVisible, forKey: StateKeys.filterVisibility)
        coder.encode(Double(self.gridZoom), forKey: StateKeys.gridZoom)

        // store the IDs of visible objects
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

        // store the IDs of selected objects
        let selectedIds = self.collection.selectionIndexPaths.map({ path in
            return self.fetchReqCtrl.object(at: path).objectID.uriRepresentation()
        })
        if !selectedIds.isEmpty {
            coder.encode(selectedIds, forKey: StateKeys.selectedObjectIds)
        }

        // save split view state
        let splitPos = self.sidebarContainer.frame.width
        coder.encode(Double(splitPos), forKey: StateKeys.sidebarPosition)
    }

    /**
     * Restores the view state.
     */
    override func restoreState(with coder: NSCoder) {
        // read values
        let isVisible = coder.decodeBool(forKey: StateKeys.filterVisibility)
        let zoom = coder.decodeDouble(forKey: StateKeys.gridZoom)

        let visibleIds = coder.decodeObject(forKey: StateKeys.visibleObjectIds)
        let selectedIds = coder.decodeObject(forKey: StateKeys.selectedObjectIds)

        let shouldRestoreSplit = coder.containsValue(forKey: StateKeys.sidebarPosition)
        let splitPos = coder.decodeDouble(forKey: StateKeys.sidebarPosition)

        // set the restoration block
        self.restoreBlock = {
            self.isFilterVisible = isVisible

            if zoom >= 1 && zoom <= 8 {
                self.gridZoom = CGFloat(zoom)
            } else {
                DDLogWarn("Attempted to restore invalid grid zoom level: \(zoom)")
            }

            // restore split position
            if shouldRestoreSplit {
                self.splitter.setPosition(CGFloat(splitPos), ofDividerAt: 0)
            }
        }

        // restore selection
        self.restoreAfterFetchBlock = {
            // get selection as an array of URL-represented object IDs at first
            if let selected = selectedIds as? [URL] {
                let paths = selected.compactMap(self.urlToImages)

                if !paths.isEmpty {
                    self.collection.selectionIndexPaths = Set(paths)
                    self.updateRepresentedObj()
                }
            }

            // scroll to the visible objects
            if let visible = visibleIds as? [URL] {
                let paths = visible.compactMap(self.urlToImages)

                if !paths.isEmpty {
                    self.collection.scrollToItems(at: Set(paths),
                                                  scrollPosition: [.nearestHorizontalEdge, .nearestVerticalEdge])
                }
            }
        }
    }

    /**
     * Transforms an array of URL objects into an index path.
     */
    private func urlToImages(_ url: URL) -> IndexPath? {
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
    /// Fetch request used to get data
    private var fetchReq: NSFetchRequest<Image>! = NSFetchRequest(entityName: "Image")
    /// Fetched results controller
    private var fetchReqCtrl: NSFetchedResultsController<Image>! = nil
    /// Has the fetch request been changed since the last time? (Used to invalidate cache)
    private var fetchReqChanged: Bool = false

    /// Filter predicate for what's being displayed
    @objc dynamic private var filterPredicate: NSPredicate! = nil
    /// Sort descriptors for the results
    @objc dynamic private var sort: [NSSortDescriptor] = [NSSortDescriptor]()

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

        // sort by date captured
        self.fetchReq.sortDescriptors = [
            NSSortDescriptor(key: "dateCaptured", ascending: false)
        ]
    }

    /**
     * Updates the fetch request with any filters. This prepares it to be executed.
     */
    private func updateFetchReq() {
        // TODO: implement this :)

        // set if the fetch request changed
//        self.fetchReqChanged = true
    }

    /**
     * Performs the fetch.
     */
    private func fetch() {
        // update the fetch request if needed
        self.updateFetchReq()

        // if the fetch request changed, we need to allocate a new fetch ctrl
        if self.fetchReqChanged || self.fetchReqCtrl == nil {
            // it's important the cache is cleared in this case
            NSFetchedResultsController<NSFetchRequestResult>.deleteCache(withName: "LibraryViewCache")

            self.fetchReqCtrl = NSFetchedResultsController(fetchRequest: self.fetchReq,
                                   managedObjectContext: self.ctx,
                                   sectionNameKeyPath: "dayCaptured",
                                   cacheName: "LibraryViewCache")
            self.fetchReqCtrl.delegate = self



            // clear the flag
            self.fetchReqChanged = false
        }

        // do the fetch and update our data source
        do {
            try self.fetchReqCtrl.performFetch()

            if let restorer = self.restoreAfterFetchBlock {
                restorer()
                self.restoreAfterFetchBlock = nil
            }
        } catch {
            DDLogError("Failed to execute fetch request: \(error)")
            self.presentError(error, modalFor: self.view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    // MARK: - Collection data source
    /// This is the collection view that holds the library images.
    @IBOutlet private var collection: NSCollectionView! = nil

    /// Diffable data source for collection view
    private var dataSource: NSCollectionViewDiffableDataSource<String, NSManagedObjectID>! = nil
    /**
     * Whether the data source update is animated or not. There seems to be a bug in the implementation
     * such that the first refresh _must_ not be animated, as it doesn't reload the underlying data model; all
     * subsequent refreshes will then be animated.
     *
     * This is reset when the data source is created, and set once the first update completed.
     */
    private var animateDataSourceUpdates: Bool = false

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
            cell.representedObject = self.fetchReqCtrl.object(at: path)

            return cell
        })

        // give it its section header provider as well
        self.dataSource.supplementaryViewProvider = { (view, kind, path) in
            guard kind == NSCollectionView.elementKindSectionHeader else {
                DDLogError("Unsupported supplementary item kind '\(kind)' for path \(path)")
                return nil
            }

            let header = view.makeSupplementaryView(ofKind: kind,
                                                    withIdentifier: .libraryCollectionHeader,
                                                    for: path) as! LibraryCollectionHeaderView

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
//        DDLogVerbose("Prefetching: \(indexPaths)")

        ThumbHandler.shared.generate(indexPaths.map({ (path) in
            return self.fetchReqCtrl.object(at: path)
        }))
    }

    /**
     * Aborts prefetch of the given rows. Cancel any outstanding thumb requests for those images.
     */
    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
//        DDLogVerbose("Canceling prefetch: \(indexPaths)")

        // TODO: implement this better. this will crash during bulk updates
//        ThumbHandler.shared.cancel(indexPaths.map({ (path) in
//            return self.fetchReqCtrl.object(at: path)
//        }))
    }

    // MARK: Collection layout
    /// Zoom factor
    @objc dynamic private var gridZoom: CGFloat = 5 {
        didSet {
            self.imagesPerRow = 9 - gridZoom
            self.parent?.invalidateRestorableState()
        }
    }
    /// Number of columns of images to display. Fractional values supported.
    private var imagesPerRow: CGFloat = 4 {
        didSet {
            self.reflowContent()
        }
    }

    /**
     * Updates the content size of the content view.
     */
    private func reflowContent() {
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

    // MARK: - Filter bar UI
    /// Container view that holds the filter bar and editor
    @IBOutlet private var filterArea: NSStackView! = nil
    /// Predicate editor for the filters
    @IBOutlet private var filter: NSPredicateEditor! = nil
    /// Size constraint for the filter predicate editor
    @IBOutlet private var filterHeightConstraint: NSLayoutConstraint! = nil
    /// Is the filter predicate editor visible?
    @objc dynamic private var isFilterVisible: Bool = false {
        // update the UI if needed
        didSet {
            if self.shouldAnimate {
                NSAnimationContext.runAnimationGroup({ (ctx) in
                    ctx.duration = 0.125
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                    self.filter.enclosingScrollView?.isHidden = false

                    if self.isFilterVisible {
                        self.filter.enclosingScrollView?.animator().alphaValue = 1
                        self.filterHeightConstraint.animator().constant = 192
                    } else {
                        self.filter.enclosingScrollView?.animator().alphaValue = 0
                        self.filterHeightConstraint.animator().constant = 0
                    }
                }, completionHandler: {
                    if !self.isFilterVisible {
                        self.filter.enclosingScrollView?.isHidden = true
                    }

                    // force grid view to recalculate layout
                    // TODO: improve this, animate headers?
                    self.collection.reloadItems(at: self.collection.indexPathsForVisibleItems())
                })

                self.parent?.invalidateRestorableState()
            } else {
                if self.isFilterVisible {
                    self.filter.enclosingScrollView?.alphaValue = 1
                    self.filterHeightConstraint.constant = 192
                    self.filter.enclosingScrollView?.isHidden = false
                } else {
                    self.filter.enclosingScrollView?.alphaValue = 0
                    self.filterHeightConstraint.constant = 0
                    self.filter.enclosingScrollView?.isHidden = true
                }

                // force grid view to recalculate layout
                // TODO: improve this, animate headers?
                self.collection.reloadItems(at: self.collection.indexPathsForVisibleItems())
            }
        }
    }

    /**
     * Registers for filter area height update notifications.
     */
    private func setUpFilterAreaHeightNotifications() {
        // register for frame change on filter area
        let c = NotificationCenter.default

        c.addObserver(forName: NSView.frameDidChangeNotification,
                      object: self.filterArea, queue: nil, using: { _ in
            self.filterAreaHeightUpdate()
        })

        // enable posting of the notification
        self.filterArea.postsFrameChangedNotifications = true
        // last, manually update to make sure UI is updated
        self.filterAreaHeightUpdate()
    }

    /**
     * Handles the height of the filter area changing. This adjusts the edge insets of the content view
     * accordingly.
     */
    private func filterAreaHeightUpdate() {
        guard let scroll = self.collection?.enclosingScrollView else {
            DDLogError("Failed to get reference to collection scroll view")
            return
        }

        // the height of the filter bounds is the top inset
        let filterBounds = self.filterArea.bounds

        var insets = NSEdgeInsets()
        insets.top = filterBounds.size.height

        scroll.contentInsets = insets
    }

    // MARK: - Split view handling
    /// Main split view
    @IBOutlet private var splitter: NSSplitView! = nil
    /// Sidebar view
    @IBOutlet private var sidebarContainer: NSView! = nil

    /**
     * Ensure that the new split view state is saved when the split changes.
     */
    func splitViewDidResizeSubviews(_ notification: Notification) {
        self.parent!.invalidateRestorableState()
    }

    /**
     * Allow the split view to collapse the sidebar.
     */
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if subview == self.sidebarContainer {
            return true
        }
        return false
    }

    // MARK: - Lens/Camera Filters
    /// Lens filter pulldown
    @IBOutlet private var lensFilter: NSPopUpButton! = nil
    /// Menu displayed by the lens filter pulldown
    @objc dynamic private var lensMenu: NSMenu = NSMenu() {
        didSet {
            if let btn = self.lensFilter {
                btn.menu = lensMenu
            }
        }
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return false
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Library view controller (restoration)
    static let libraryViewController = NSUserInterfaceItemIdentifier("libraryViewController")
}
