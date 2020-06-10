//
//  LibraryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryViewController: NSViewController, NSMenuItemValidation, NSCollectionViewDataSource, ContentViewChild {
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

        // register the collection view class
        self.collection.register(LibraryCollectionItem.self,
                                 forItemWithIdentifier: .libraryCollectionItem)
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

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {

    }

    // MARK: - Fetching
    /// Fetch request used to get data
    private var fetchReq: NSFetchRequest<Image>! = NSFetchRequest()
    /// Array of returned data
    private var fetchedData: [Image]! = nil

    /**
     * Initializes the fetch request.
     */
    private func initFetchReq() {
        // get full managed objects
        self.fetchReq.entity = Image.entity()
        self.fetchReq.resultType = .managedObjectResultType

        // batch results for better performance; and also fetch subentities
        self.fetchReq.fetchBatchSize = 50
        self.fetchReq.includesSubentities = true
    }

    /**
     * On window resize, we may need to increase (or decrease) the batch size of the fetch request. We
     * should try to keep it around twice the number of images per row.
     */
    private func updateFetchBatchSize() {
        self.fetchReq.fetchBatchSize = Int(ceil(self.imagesPerRow * 2.0))
    }

    /**
     * Updates the fetch request with any filters. This prepares it to be executed.
     */
    private func updateFetchReq() {

    }

    /**
     * Performs the fetch.
     */
    private func fetch() {
        self.updateFetchReq()

        do {
            self.fetchedData = try self.ctx.fetch(self.fetchReq)
            self.collection.reloadData()
        } catch {
            DDLogError("Failed to execute fetch request: \(error)")
            self.presentError(error, modalFor: self.view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    // MARK: - Collection view data source
    /**
     * Returns the number of images in each group.
     */
    func collectionView(_ view: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        // if no fetched data exists, there's 0 items
        guard let data = self.fetchedData else {
            return 0
        }
        // otherwise, return exactly as many items as there is data
        return data.count
    }

    /**
     * Instantiates a cell to display the image.
     */
    func collectionView(_ view: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        let idx = path[1]

        // get us a reuseable cell™
        let cell = view.makeItem(withIdentifier: .libraryCollectionItem,
                                 for: path) as! LibraryCollectionItem

        // update its object
        cell.representedObject = self.fetchedData[idx]
        cell.sequenceNumber = (idx + 1)

        return cell
    }

    // MARK: - Collection view UI
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

        // at this time, update fetch request batch size for later
        self.updateFetchBatchSize()
    }

    // MARK: - Fetching
    /// Helper to get the view context
    @objc dynamic private var viewContext: NSManagedObjectContext {
        return self.library.store.mainContext!
    }
    /// Filter predicate for what's being displayed
    @objc dynamic private var filterPredicate: NSPredicate! = nil
    /// Sort descriptors for the results
    @objc dynamic private var sort: [NSSortDescriptor] = [NSSortDescriptor]()

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
