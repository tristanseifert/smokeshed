//
//  LibraryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryViewController: LibraryBrowserBase, MainWindowContent {
    /// Context menu controller for the collection view
    @IBOutlet private var menuController: LibraryViewMenuProvider!

    /// Sidebar filter
    var sidebarFilters: NSPredicate? = nil {
        didSet {
            // we MUST have a library at this point
            guard self.library != nil else {
                return
            }
            
            // update fetch request with new predicate and re-fetch
            self.fetchReq.predicate = self.sidebarFilters
            
            self.animateDataSourceUpdates = false
            self.fetchReqChanged = true
            self.fetch()
        }
    }
    
    // MARK: - Initialization
    /**
     * Fetch cache name
     */
    override var fetchCacheName: String? {
        return "LibraryViewController"
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
        
    }

    /**
     * Encodes the current view state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
    }

    /**
     * Restores the view state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
    }

    // MARK: Sort, grouping filters
    /// Display string for the bottom bar "Sort By" menu
    @objc dynamic private var sortMenuTitle: String {
        get {
            let order = (self.sortByOrder == .ascending) ? "↑" : "↓"
            let fmt = Bundle.main.localizedString(forKey: "sort.title", value: nil, table: "LibraryBrowserBase")

            return String.localizedStringWithFormat(fmt,
                    self.sortByKey.localizedName, order)

        }
    }
    @objc public class func keyPathsForValuesAffectingSortMenuTitle() -> Set<String> {
        return [
            #keyPath(LibraryBrowserBase.sortByKey),
            #keyPath(LibraryBrowserBase.sortByOrder)
        ]
    }

    /// Display string for the bottom bar "Group By" menu
    @objc dynamic private var groupMenuTitle: String {
        get {
            let order = (self.groupOrder == .ascending) ? "↑" : "↓"
            var fmt = ""
            
            if self.groupBy == .none {
                fmt = Bundle.main.localizedString(forKey: "group.title.none", value: nil,
                                                  table: "LibraryBrowserBase")
            } else {
                fmt = Bundle.main.localizedString(forKey: "group.title", value: nil,
                                                  table: "LibraryBrowserBase")
            }
            
            return String.localizedStringWithFormat(fmt,
                    self.groupBy.localizedName, order)
        }
    }
    @objc public class func keyPathsForValuesAffectingGroupMenuTitle() -> Set<String> {
        return [
            #keyPath(LibraryBrowserBase.groupBy),
            #keyPath(LibraryBrowserBase.groupOrder)
        ]
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
        
        // save library; this guards against images not yet having permanent ids
        do {
            try self.library.store.save()
        } catch {
            DDLogError("Failed to save library prior to deletion: \(error)")
            self.presentError(error)
            return
        }

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
    
    /**
     * Updates thumbnails for all selected images.
     */
    @IBAction func updateThumbs(_ sender: Any?) {
        let paths = self.collection.selectionIndexPaths
        let images = paths.map(self.fetchReqCtrl.object)
    
        ThumbHandler.shared.generate(images)
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
        
        // thumb specific options are always available
        if menuItem.action == #selector(updateThumbs(_:)) {
            // but for now only when there's a selection
            return !self.collection!.selectionIndexPaths.isEmpty
        }

        // we do not handle it
        return super.validateMenuItem(menuItem)
    }
}
