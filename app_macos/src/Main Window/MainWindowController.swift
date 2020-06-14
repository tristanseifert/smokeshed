//
//  MainWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    /// Library file that was opened for this window
    public var library: LibraryBundle! = nil {
        didSet {
            // update libraries of all components
            self.content.library = self.library
            self.importer.library = self.library

            // set the window's URL
            if let window = self.window {
                if let library = self.library {
                    window.representedURL = library.getURL()
                } else {
                    window.representedURL = nil
                }
            }

            // we need to persist the library url
            self.invalidateRestorableState()
        }
    }

    /// Content view controller
    @objc dynamic public var content = ContentViewController()

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var windowNibName: NSNib.Name? {
        return "MainWindowController"
    }

    /**
     * Once the window has loaded, add the child window controllers as needed.
     */
    override func windowDidLoad() {
        super.windowDidLoad()

        guard let window = self.window else {
            fatalError()
        }

        // restoration
        window.isRestorable = true
        window.restorationClass = AppDelegate.self
        window.identifier = .mainWindow

        // set represented file if we have a library
        if let library = self.library {
            window.representedURL = library.getURL()
        }

        // update the content
        window.contentViewController = self.content
    }

    /**
     * Displays the main window. This will also set up the UI's default state if no state restoration took place.
     */
    override func showWindow(_ sender: Any?) {
        // show the window
        super.showWindow(sender)

        // if inspector is already allocated, show it too (as it was restored)
        if self.inspector != nil {
            self.inspector!.showWindow(sender)
        }
    }

    // MARK: - State restoration
    /// Whether state was restored or not
    private var didRestoreState = false

    struct StateKeys {
        /// Bookmark data representing the location of the library.
        static let libraryBookmark = "MainWindowController.libraryBookmark"
        /// Absolute URL string for the currently loaded library
        static let libraryUrl = "MainWindowController.libraryURL"
        /// Whether the inspector is open
        static let inspectorVisible = "MainWindowController.inspectorVisible"
    }

    /**
     * Saves the current user interface state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // get a bookmark to the url
        do {
            let url = self.library.getURL()
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: [.nameKey], relativeTo: nil)

            coder.encode(bookmark, forKey: StateKeys.libraryBookmark)
            coder.encode(url.absoluteString, forKey: StateKeys.libraryUrl)
        } catch {
            DDLogError("Failed to archive library url: \(error)")
        }

        // store inspector state
        if let inspector = self.inspector, let window = inspector.window {
            inspector.encodeRestorableState(with: coder)
            coder.encode(window.isVisible, forKey: StateKeys.inspectorVisible)
        }
    }

    /**
     * Restores previously encoded state.
     */
    override func restoreState(with coder: NSCoder) {
        self.didRestoreState = true

        // re-open inspector if it was open last time
        if coder.decodeBool(forKey: StateKeys.inspectorVisible) {
            self.setUpInspector()

            self.inspector!.restoreState(with: coder)
        }

        super.restoreState(with: coder)
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
        else if self.content.responds(to: aSelector) {
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
        if self.content.responds(to: aSelector) {
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
        if sig == nil, self.content.responds(to: aSelector) {
            return self.content.method(for: aSelector)
        }

        return sig
    }

    // MARK: - Importing, Library UI
    /// Library options controller, if allocated
    private var libraryOptions: LibraryOptionsController! = nil
    /// Import controller
    internal var importer = ImportHandler()

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
        panel.prompt = Bundle.main.localizedString(forKey: "import.dir.prompt", value: nil, table: "MainWindowController")

        panel.allowedFileTypes = ["public.image"]

        panel.beginSheetModal(for: self.window!, completionHandler: { (res) in
            // ensure user clicked the "import" button
            guard res == .OK else {
                return
            }

            // pass the URLs to the importer
            self.importer.importFrom(panel.urls)
        })
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

    // MARK: - Inspector support
    /// Inspector
    @objc dynamic private var inspector: InspectorWindowController! = nil

    /**
     * Allocates the inspector, if needed.
     */
    private func setUpInspector() {
        if self.inspector == nil {
            self.inspector = InspectorWindowController()

            self.inspector?.bind(NSBindingName(rawValue: "selection"),
                                 to: self.content,
                                 withKeyPath: #keyPath(ContentViewController.representedObject),
                                 options: nil)
        }
    }

    /**
     * Toggles visibility of the inspector.
     */
    @IBAction func toggleInspector(_ sender: Any) {
        self.setUpInspector()

        // if window is visible, order it out
        if self.inspector!.window!.isVisible {
            self.inspector!.window?.orderOut(sender)
        }
        // it is not, so show it
        else {
            self.inspector!.showWindow(sender)
        }

        self.invalidateRestorableState()
    }

    // MARK: - Autosaving
    /**
     * Saves the context if needed.
     */
    private func saveIfNeeded() {
        if let ctx = self.library.store.mainContext {
            if ctx.hasChanges {
                do {
                    try ctx.save()
                } catch {
                    DDLogError("Failed to save context: \(error)")
                }
            }
        }
    }

    /**
     * When the window loses focus, save changes.
     */
    func windowDidResignMain(_ notification: Notification) {
        self.saveIfNeeded()
    }

    // MARK: - Menu item support
    /**
     * Validates a menu action. Anything we don't handle gets forwarded to the content controller.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // handle inspector item
        if menuItem.action == #selector(toggleInspector(_:)) {
            if let inspector = self.inspector, inspector.window!.isVisible {
                menuItem.title = Bundle.main.localizedString(forKey: "menu.inspector.hide", value: nil, table: "MainWindowController")
            } else {
                menuItem.title = Bundle.main.localizedString(forKey: "menu.inspector.show", value: nil, table: "MainWindowController")
            }

            return true
        }

        // always allow importing
        if menuItem.action == #selector(importFromDevice(_:)) ||
            menuItem.action == #selector(importDirectory(_:)) ||
            menuItem.action == #selector(openLibraryOptions(_:)) {
            return true
        }

        // forward unhandled calls to the content controller
        return self.content.validateMenuItem(menuItem)
    }
}

extension NSUserInterfaceItemIdentifier {
    /// App main window (restoration)
    static let mainWindow = NSUserInterfaceItemIdentifier("mainWindow")
}
