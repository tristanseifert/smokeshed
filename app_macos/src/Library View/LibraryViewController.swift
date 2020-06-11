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
                             NSCollectionViewDataSource,
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
        // get dictionary representations of objects; only properties displayed
//        self.fetchReq.resultType = .dictionaryResultType
//        self.fetchReq.propertiesToFetch = ["name", "dateCaptured", "identifier", "pvtImageSize", "camera", "lens"]
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

        // do the fetch (automagically updates view)
        do {
            try self.fetchReqCtrl.performFetch()
            self.collection?.reloadData()
        } catch {
            DDLogError("Failed to execute fetch request: \(error)")
            self.presentError(error, modalFor: self.view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    // MARK: Fetch controller delegate
    /**
     * Handles section changes in the fetched results.
     */
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange sectionInfo: NSFetchedResultsSectionInfo,
                    atSectionIndex sectionIndex: Int,
                    for type: NSFetchedResultsChangeType) {
        switch type {
            case .insert:
                self.collection?.insertSections(IndexSet(integer: sectionIndex))

            case .delete:
                self.collection?.deleteSections(IndexSet(integer: sectionIndex))

            default:
                DDLogError("Unknown section change type: \(type)")
        }
    }

    /**
     * Handles changes to particular objects in a section.
     */
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch type {
            case .insert:
                self.collection?.insertItems(at: [newIndexPath!])

            case .delete:
                self.collection?.deleteItems(at: [indexPath!])

            // on updates, grab the cell and update it ourselves
            case .update:
                guard let item = self.collection?.item(at: indexPath!),
                 let i = item as? LibraryCollectionItem else {
                    DDLogError("Failed to get item for object at \(indexPath!)")
                    return
                }

                i.sequenceNumber = indexPath![1]
                i.representedObject = controller.object(at: indexPath!)

            // remove the old item and insert the new one
            case .move:
                self.collection?.deleteItems(at: [indexPath!])
                self.collection?.insertItems(at: [newIndexPath!])

            // unknown; for future compatibility
            @unknown default:
                DDLogError("Unhandled change type: \(type)")
        }
    }

    // MARK: - Collection: images
    /**
     * Returns the number of sections in the grid. If the fetch controller has no sections provided, assume
     * we just have one.
     */
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        if let fq = self.fetchReqCtrl {
            return fq.sections!.count
        }

        return 0
    }

    /**
     * Returns the number of images in each group.
     */
    func collectionView(_ view: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sections = self.fetchReqCtrl?.sections else {
            fatalError("Failed to get sections from fetched results controller")
        }

        return sections[section].numberOfObjects
    }

    /**
     * Instantiates a cell to display the image.
     */
    func collectionView(_ view: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        // get a copy of the dictionary for this image
        guard let image = self.fetchReqCtrl?.object(at: path) else {
            fatalError("Failed to get object at path \(path)")
        }

        // get us a reuseable cell™
        let cell = view.makeItem(withIdentifier: .libraryCollectionItem,
                                 for: path) as! LibraryCollectionItem

        // update its object
        cell.sequenceNumber = (path[1] + 1)
        cell.representedObject = image

        return cell
    }

    // MARK: Collection: Section headers
    /**
     * Gets a supplemental view. We only support headers.
     */
    func collectionView(_ collectionView: NSCollectionView,
                        viewForSupplementaryElementOfKind
        kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        switch kind {
            case NSCollectionView.elementKindSectionHeader:
                // create the header
                let view = collectionView.makeSupplementaryView(ofKind: kind,
                           withIdentifier: .libraryCollectionHeader,
                           for: indexPath)

                if let header = view as? LibraryCollectionHeaderView {
                    header.collection = collectionView
                    header.section = self.fetchReqCtrl.sections![indexPath[0]]
                }

                return view

            default:
                fatalError("Unsupported supplemental view type: \(kind)")
        }
        
    }

    // MARK: - Collection view: UI
    /// Number of columns of images to display. Fractional values supported.
    @objc dynamic private var imagesPerRow: CGFloat = 4 {
        didSet {
            self.reflowContent()
        }
    }
    /// This is the collection view that holds the library images.
    @IBOutlet private var collection: NSCollectionView! = nil

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
