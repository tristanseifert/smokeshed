//
//  MainWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa
import OSLog

import Smokeshop

class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    fileprivate static var logger = Logger(subsystem: Bundle(for: MainWindowController.self).bundleIdentifier!,
                                         category: "MainWindowController")
    
    /// Library file that was opened for this window
    public var library: LibraryBundle! = nil {
        didSet {
            // update libraries of all components
            self.importer.library = self.library
            ThumbHandler.shared.library = self.library
            
            if let content = self.contentViewController {
                self.updateChildLibrary(content)
                
            }

            // set the window's URL
            if let library = self.library {
                self.window?.representedURL = library.getURL()
            } else {
                self.window?.representedURL = nil
            }

            // we need to persist the library url
            self.invalidateRestorableState()
        }
    }

    // MARK: - Initialization
    /**
     * Once the window has loaded, add the child window controllers as needed.
     */
    override func windowDidLoad() {
        super.windowDidLoad()

        guard let window = self.window else {
            fatalError()
        }
        
        // cache the tab controller reference
        self.contentTabs = self.findTabController(self.contentViewController!)

        // restoration
        window.isRestorable = true
        window.restorationClass = AppDelegate.self
        window.identifier = .mainWindow

        // set represented file if we have a library
        if let library = self.library {
            window.representedURL = library.getURL()
        }
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
            Self.logger.error("Failed to archive library url: \(error.localizedDescription)")
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
            Self.logger.error("Failed to convert sender \(String(describing: sender)) to NSView")
            return
        }

        self.activityPopover.show(relativeTo: NSZeroRect, of: view,
                                  preferredEdge: .maxY)
    }

    // MARK: - Content containers
    /// Content tab controller
    private var contentTabs: NSTabViewController!
    
    /**
     * Propagates this library object to all child view controllers, recursively.
     */
    private func updateChildLibrary(_ child: NSViewController) {
        // set library if the controller supports it
        if var c = child as? MainWindowContent {
            c.library = self.library
        }
        
        // if there are children to this controller, invoke this on each of them
        if !child.children.isEmpty {
            for child in child.children {
                self.updateChildLibrary(child)
            }
        }
    }
    
    /**
     * Switches to a different app mode, identified by its index 1-3. This is stored in the sender's tag.
     */
    @IBAction func changeAppMode(_ sender: Any) {
        var inTag: Int?
        
        // menu item?
        if let menu = sender as? NSMenuItem {
            inTag = menu.tag
        }
        
        // validate the tag is valid then set selection
        guard let tag = inTag, (1...3).contains(tag) else {
            fatalError("Invalid tag: \(String(describing: inTag))")
        }
        
        self.contentTabs?.selectedTabViewItemIndex = tag - 1
    }
    
    /**
     * Locates the tab controller containing the main view.
     */
    private func findTabController(_ parent: NSViewController) -> NSTabViewController? {        
        // did we find the tab controller?
        if let tab = parent as? NSTabViewController {
            return tab
        }
            
        // if not, check each of its children
        for child in parent.children {
            if let result = self.findTabController(child) {
                return result
            }
        }
        
        // failed to find the controller
        return nil
    }

    // MARK: - Importing, Library UI
    /// Library options controller, if allocated
    private var libraryOptions: LibraryOptionsController! = nil
    /// Import controller
    internal var importer = ImportHandler()
    
    /// From the device importing
    private var deviceImportView: NSViewController? = nil

    /**
     * Opens the "import from device" view.
     */
    @IBAction func importFromDevice(_ sender: Any) {
        // load the device import window controller from storyboard if needed
        if self.deviceImportView == nil {
            let storyboard = NSStoryboard(name: "Importing", bundle: nil)
            self.deviceImportView = storyboard.instantiateInitialController()
        }
        
        // show it
        guard let vc = self.deviceImportView else {
            fatalError("Failed to load device import controller")
        }
        
        self.window?.contentViewController?.presentAsSheet(vc)
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
                                 to: self.contentTabs!,
                                 withKeyPath: #keyPath(MainWindowTabController.representedObject),
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
                    Self.logger.error("Failed to save context: \(error.localizedDescription)")
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
        
        // changing app mode
        if menuItem.action == #selector(changeAppMode(_:)) {
            if let c = self.contentTabs,
               menuItem.tag == (c.selectedTabViewItemIndex + 1) {
                menuItem.state = .on
            } else {
                menuItem.state = .off
            }
            
            return true
        }

        // forward unhandled calls to the content controller
        return false
    }
}

extension NSUserInterfaceItemIdentifier {
    /// App main window (restoration)
    static let mainWindow = NSUserInterfaceItemIdentifier("mainWindow")
}

/**
 * All view controllers shown in the main window as content should implement this protocol.
 */
protocol MainWindowContent {
    /// Currently open library
    var library: LibraryBundle! { get set }
    /// Sidebar filters
    var sidebarFilters: NSPredicate? { get set }
}
