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
    private var content: ContentViewController! = nil

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

        // if no app mode has been set, choose a default
        if self.currentMode == nil {
            self.currentMode = .Library
        }
    }

    // MARK: - State restoration
    /**
     * Restores previously encoded state.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // get app mode
        if let mode = AppMode(rawValue: coder.decodeInteger(forKey: "AppMode")) {
            DDLogVerbose("Restored app mode: \(mode)")
            self.currentMode = mode
        }
    }

    /**
     * Saves the current user interface state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // encode the URL of the library
        coder.encode(self.library.getURL(), forKey: "LibraryURL")

        // save our app mode
        coder.encode(self.currentMode, forKey: "AppMode")
    }

    // MARK: - View type switching
    /// Is mode switching inhibited?
    private var inhibitModeSwitch: Bool = false
    /// Currently active mode
    private var currentMode: AppMode! = nil {
        didSet {
            if let mode = self.currentMode {
                self.modeSwitcher.selectSegment(withTag: mode.rawValue)

                self.inhibitModeSwitch = true
                self.content!.setContent(mode, completion: {
                    self.inhibitModeSwitch = false
                })
            }
        }
    }
    /// Segmented control at the top of the window, used for switching app modes
    @IBOutlet var modeSwitcher: NSSegmentedControl! = nil

    /**
     * Action method for the mode switcher.
     */
    @IBAction func changeAppMode(_ sender: Any) {
        var newMode = 0

        // ensure we're not inhibiting mode switching
        guard !self.inhibitModeSwitch else {
            return
        }

        // was the sender the segmented control?
        if let segment = sender as? NSSegmentedControl {
            newMode = segment.selectedTag()
        }
        // otherwise, was it a menu item?
        else if let item = sender as? NSMenuItem {
            newMode = item.tag
        }
        // unknown sender
        else {
            return DDLogError("Unknown sender type for changeAppMode: \(sender)")
        }

        // get the new mode
        guard let mode = AppMode(rawValue: newMode) else {
            return DDLogError("Unknown raw mode '\(newMode)'")
        }

        DDLogVerbose("Switching app mode to \(mode)")
        self.currentMode = mode
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

    // MARK: - Menu item support
    /**
     * Validates a menu item's action. This is used to support checking the menu item corresponding to the
     * current app mode.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // is it the app mode item?
        if menuItem.action == #selector(changeAppMode(_:)) {
            // it's on if its tag matches the current mode raw value
            menuItem.state = (menuItem.tag == self.currentMode.rawValue) ? .on : .off

            return true
        }

        // unhandled
        return false
    }
}
