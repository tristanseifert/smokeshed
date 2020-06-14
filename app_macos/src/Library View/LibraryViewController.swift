//
//  LibraryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryViewController: LibraryBrowserBase, NSSplitViewDelegate, ContentViewChild {
    /// Context menu controller for the collection view
    private var menuController: LibraryViewMenuProvider!

    // MARK: - Initialization
    /**
     * Fetch cache name
     */
    override var fetchCacheName: String? {
        return "LibraryViewController"
    }

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
        // load the view controller with default nib name
        super.init(nibName: nil, bundle: nil)

        self.menuController = LibraryViewMenuProvider(self)

        // configure restoration
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

        // connect up the sub controllers
        self.collection.kushDelegate = self.menuController

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
    }

    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        super.viewWillAppear()

        // ensure the grid is updated properly
        self.reflowContent()
        self.fetch()
    }
    /**
     * Adds an observer on window size changes. This is used to reflow the content grid as needed.
     */
    override func viewDidAppear() {
        super.viewDidAppear()
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
        super.viewWillDisappear()
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
        /// Position of the sidebar splitter
        static let sidebarPosition = "LibraryViewController.sidebarPosition"
    }

    /**
     * Encodes the current view state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // save the filter visibility
        coder.encode(self.isFilterVisible, forKey: StateKeys.filterVisibility)

        // save split view state
        let splitPos = self.sidebarContainer.frame.width
        coder.encode(Double(splitPos), forKey: StateKeys.sidebarPosition)
    }

    /**
     * Restores the view state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // read values
        let isVisible = coder.decodeBool(forKey: StateKeys.filterVisibility)

        let shouldRestoreSplit = coder.containsValue(forKey: StateKeys.sidebarPosition)
        let splitPos = coder.decodeDouble(forKey: StateKeys.sidebarPosition)

        // set the restoration block
        self.restoreBlock.append({
            self.isFilterVisible = isVisible

            if shouldRestoreSplit {
                self.splitter.setPosition(CGFloat(splitPos), ofDividerAt: 0)
            }
        })
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

    // MARK: - Menu actions
    /**
     * Removes the selected image(s) from the library.
     */
    @IBAction func removeSelectedImages(_ sender: Any?) {
        let paths = self.collection.selectionIndexPaths
        let images = paths.map(self.fetchReqCtrl.object)

        self.removeImagesWithConfirmation(images)
    }
    /**
     * Opens the edit view for the selected images. If the selection contains multiple images, the first one
     * is opened, while the small grid is opened with these images selected.
     */
    @IBAction func editSelectedImages(_ sender: Any?) {
        let paths = self.collection.selectionIndexPaths
        let images = paths.map(self.fetchReqCtrl.object)

        self.openEditorForImages(images)
    }

    /**
     * Displays the delete prompt for the provided images. That message allows the user to decide if the
     * images should be removed only from the library, or also deleted from disk.
     */
    func removeImagesWithConfirmation(_ images: [Image]) {
        let alert = NSAlert()

        alert.showsHelp = true

        // format the alert title
        let fmt = Bundle.main.localizedString(forKey: "delete.title", value: nil, table: "LibraryViewController")
        alert.messageText = String.localizedStringWithFormat(fmt, images.count)

        // format the subtitle
        alert.informativeText = Bundle.main.localizedString(forKey: "delete.informative", value: nil, table: "LibraryViewController")

        // keep files is the first option
        alert.addButton(withTitle: Bundle.main.localizedString(forKey: "delete.leave_files", value: nil, table: "LibraryViewController"))

        // add the cancel button
        alert.addButton(withTitle: Bundle.main.localizedString(forKey: "delete.cancel", value: nil, table: "LibraryViewController"))

        // lastly, add the "remove files" button
        alert.addButton(withTitle: Bundle.main.localizedString(forKey: "delete.remove_files", value: nil, table: "LibraryViewController"))

        // show it
        alert.beginSheetModal(for: self.view.window!, completionHandler: { r in
            self.removeAlertCompletion(result: r, images: images)
        })
    }
    /**
     * Completion handler for the deletion alert.
     */
    private func removeAlertCompletion(result: NSApplication.ModalResponse, images: [Image]) {
        // bail out if it was the cancel option
        guard result != .alertSecondButtonReturn else {
            return
        }

        let trashFiles = (result == .alertThirdButtonReturn)

        // run the deletion
        guard let wc = self.view.window?.windowController as? MainWindowController else {
            DDLogError("Failed to get window controller")
            return
        }

        wc.importer.deleteImages(images, shouldDelete: trashFiles, self.removeCompletionHandler)
    }
    /**
     * Remove action completion handler
     */
    private func removeCompletionHandler(_ result: Result<Void, Error>) {
        switch result {
            // Deletion completed
            case .success():
                DDLogInfo("Finished removing images")

            // Something went wrong
            case .failure(let error):
                DispatchQueue.main.async {
                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                }
        }
    }

    /**
     * Switches to the edit view. The first image is displayed as active, while all are shown in the selection
     * inspector.
     */
    func openEditorForImages(_ images: [Image]) {
        DDLogDebug("Switching to editor for: \(images)")
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // call into context menu handler
        if self.menuController.validateMenuItem(menuItem) {
            return true
        }

        // allow open/remove/edit options if there's a selection
        if menuItem.action == #selector(removeSelectedImages(_:)) ||
            menuItem.action == #selector(editSelectedImages(_:)) {
            return !self.collection!.selectionIndexPaths.isEmpty
        }

        // we do not handle it
        return super.validateMenuItem(menuItem)
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Library view controller (restoration)
    static let libraryViewController = NSUserInterfaceItemIdentifier("libraryViewController")
}
