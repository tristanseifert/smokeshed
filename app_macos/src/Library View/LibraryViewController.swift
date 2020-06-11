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
                             NSFetchedResultsControllerDelegate,
                             ContentViewChild {
    /// Library that is being browsed
    private var library: LibraryBundle
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
     * Initializes a new library view controller, browsing the contents of the provided library.
     */
    init(_ library: LibraryBundle) {
        // set up view controller and copy library reference
        self.library = library

        super.init(nibName: nil, bundle: nil)

        // initialize fetch request
        self.initFetchReq()
    }
    /// Decoding is not supported
    required init?(coder: NSCoder) {
        return nil
    }
    func getPreferredApperance() -> NSAppearance? {
        return nil
    }

    // MARK: View Lifecycle
    /**
     * Initiaizes CoreData contexts for displaying data once the view has loaded.
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        // reset constraints to the initial state
        self.isFilterVisible = false
        self.filter.enclosingScrollView?.isHidden = true

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

    // MARK: Collection layout
    /// Number of columns of images to display. Fractional values supported.
    @objc dynamic private var imagesPerRow: CGFloat = 4 {
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
        let width = floor(size.width / self.imagesPerRow)
        let height = ceil(width * 1.25)

        layout.itemSize = NSSize(width: width, height: height)
    }

    // MARK: - Filter bar UI
    /// Predicate editor for the filters
    @IBOutlet private var filter: NSPredicateEditor! = nil
    /// Size constraint for the filter predicate editor
    @IBOutlet private var filterHeightConstraint: NSLayoutConstraint! = nil
    /// Is the filter predicate editor visible?
    @objc dynamic private var isFilterVisible: Bool = false {
        // update the UI if needed
        didSet {
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
                if self.isFilterVisible {

                } else {
                    self.filter.enclosingScrollView?.isHidden = true
                }
            })
        }
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
