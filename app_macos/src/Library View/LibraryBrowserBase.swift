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
    internal var restoreViewport = true
    /// Should the selected objects be encoded?
    internal var restoreSelection = true

    private struct StateKeys {
        /// Grid zoom level
        static let gridZoom = "LibraryBrowserBase.gridZoom"
        /// URL representation of the IDs of the selected objects
        static let selectedObjectIds = "LibraryBrowserBase.selectedObjectIds"
        /// URL representation of the IDs of all currently visible objects
        static let visibleObjectIds = "LibraryBrowserBase.visibleObjectIds"
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
    }

    /**
     * Restores the view state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // read values
        let zoom = coder.decodeDouble(forKey: StateKeys.gridZoom)

        let visibleIds = coder.decodeObject(forKey: StateKeys.visibleObjectIds)
        let selectedIds = coder.decodeObject(forKey: StateKeys.selectedObjectIds)

        // set the restoration block
        self.restoreBlock.append({
            if zoom >= 1 && zoom <= 8 {
                self.gridZoom = CGFloat(zoom)
            }
        })

        // restore selection
        self.restoreAfterFetchBlock.append({
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
                                                  scrollPosition: [.centeredVertically])
                }
            }
        })
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
    internal var fetchReq: NSFetchRequest<Image>! = NSFetchRequest(entityName: "Image")
    /// Fetched results controller
    internal var fetchReqCtrl: NSFetchedResultsController<Image>! = nil
    /// Has the fetch request been changed since the last time? (Used to invalidate cache)
    internal var fetchReqChanged: Bool = false

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
    internal func fetch() {
        // update the fetch request if needed
        self.updateFetchReq()

        // if the fetch request changed, we need to allocate a new fetch ctrl
        if self.fetchReqChanged || self.fetchReqCtrl == nil {
            // it's important the cache is cleared in this case
            NSFetchedResultsController<NSFetchRequestResult>.deleteCache(withName: self.fetchCacheName)

            self.fetchReqCtrl = NSFetchedResultsController(fetchRequest: self.fetchReq,
                                                           managedObjectContext: self.ctx,
                                                           sectionNameKeyPath: "dayCaptured",
                                                           cacheName: self.fetchCacheName)
            self.fetchReqCtrl.delegate = self



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
        ThumbHandler.shared.generate(indexPaths.map({ (path) in
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
            self.reflowContent()
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

    // MARK: - Convenience
    /**
     * Deletes all of the given images from the library, optionally removing the files from disk as well.
     */
    internal func deleteImages(_ images: [Image], deleteFiles: Bool = false) throws {
        // TODO: implement
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // sort order

        // sort key

        // we do not handle it
        return false
    }
}
