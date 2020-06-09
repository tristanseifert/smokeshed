//
//  MainWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class MainWindowController: NSWindowController, NSMenuItemValidation {
    /// Library file that was opened for this window
    private var library: LibraryBundle
    /// CoreData store in the library
    private var store: LibraryStore {
        return self.library.store!
    }

    /// Content view controller
    @objc dynamic private var content: ContentViewController! = nil

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var windowNibName: NSNib.Name? {
        return "MainWindowController"
    }

    /**
     * Initializes a new main window controller with the given library bundle and data store.
     */
    init(_ library: LibraryBundle) {
        self.library = library
        
        super.init(window: nil)
    }
    /**
     * Decoding the controller is not supported
     */
    required init?(coder: NSCoder) {
        return nil
    }

    /**
     * Once the window has loaded, add the child window controllers as needed.
     */
    override func windowDidLoad() {
        super.windowDidLoad()

        // set represented file
        self.window?.representedURL = self.library.getURL()

        // also, create the content view controller
        self.content = ContentViewController(library)
        self.window?.contentViewController = self.content

        // open in the library mode
        self.content!.setContent(.Library)
    }

    // MARK: - State restoration
    /**
     * Restores previously encoded state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
    }

    /**
     * Saves the current user interface state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // encode the URL of the library
        coder.encode(self.library.getURL(), forKey: "LibraryURL")
    }

    // MARK: - Activity Popover
    /// Popover controller for activity UI
    @IBOutlet var activityPopover: NSPopover! = nil
    /// Activity view controller
    @IBOutlet var activityController: ActivityViewController! = nil

    /**
     * Toggles the activity popover.
     */
    @IBAction func toggleActivityPopover(_ sender: Any) {
        // close popover if shown already
        if self.activityPopover.isShown {
            return self.activityPopover.performClose(sender)
        }

        // convert sender to view and display the popover
        guard let view = sender as? NSView else {
            DDLogError("Failed to convert sender \(sender) to NSView")
            return
        }

        self.activityPopover.show(relativeTo: NSZeroRect, of: view,
                                  preferredEdge: .maxY)
    }

    // MARK: - Container support
    /**
     * Claim that we can respond to a particular selector, if our content claims to. This is necessary to allow
     * forwarding invocations (for first responder) to content windows.
     */
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        else if let content = self.content,
            content.responds(to: aSelector) {
            return true
        }

        // nobody supports this selector :(
        return false
    }
    /**
     * Returns the new target for the given selector. If the content controller implements the given action, we
     * forward directly to it.
     */
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        // can the content controller respond to this message?
        if let content = self.content, content.responds(to: aSelector) {
            return self.content
        }

        // nobody supports this selector :(
        return nil
    }
    /**
     * Returns the method implementation for the given selector. If we don't implement the method, provide
     * the implementation provided by the content controller.
     */
    override func method(for aSelector: Selector!) -> IMP! {
        let sig = super.method(for: aSelector)

        // forward to content if not supported
        if sig == nil, let newTarget = self.content,
            newTarget.responds(to: aSelector) {
            return newTarget.method(for: aSelector)
        }

        return sig
    }

    // MARK: - Importing, Library UI
    /// Library options controller, if allocated
    private var libraryOptions: LibraryOptionsController! = nil
    /// Import controller
    private var importer: ImportHandler! = nil

    /**
     * Opens the "import from device" view.
     */
    @IBAction func importFromDevice(_ sender: Any) {

    }

    /**
     * Opens the "import directory" view.
     */
    @IBAction func importDirectory(_ sender: Any) {
        // prepare an open panel
        let panel = NSOpenPanel()

        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = NSLocalizedString("Import", comment: "import directory open panel title")

        panel.allowedFileTypes = ["public.image"]

        panel.beginSheetModal(for: self.window!, completionHandler: { (res) in
            // ensure user clicked the "import" button
            guard res == .OK else {
                return
            }

            // pass the URLs to the importer
            self.prepareImporter()

            self.importer!.importFrom(panel.urls)
        })
    }

    /**
     * Sets up the importer to prepare for an import job.
     */
    private func prepareImporter() {
        if self.importer == nil {
            self.importer = ImportHandler(self.library)
        }
    }

    /**
     * Opens the library options view controller. It is presented as a sheet on this window.
     */
    @IBAction func openLibraryOptions(_ sender: Any) {
        if self.libraryOptions == nil {
            self.libraryOptions = LibraryOptionsController(self.library)
        }

        self.libraryOptions!.present(self.window!)
    }

    // MARK: - Menu item support
    /**
     * Validates a menu action. Anything we don't handle gets forwarded to the content controller.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // always allow importing
        if menuItem.action == #selector(importFromDevice(_:)) ||
            menuItem.action == #selector(importDirectory(_:)) ||
            menuItem.action == #selector(openLibraryOptions(_:)) {
            return true
        }

        // forward unhandled calls to the content controller
        if self.content != nil {
            return self.content!.validateMenuItem(menuItem)
        }

        return false
    }
}
