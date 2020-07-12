//
//  EditViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class EditViewController: NSViewController, NSMenuItemValidation, MainWindowContent {
    /// Library that is being browsed
    public var library: LibraryBundle! {
        didSet {
            if let vc = self.secondaryWc?.contentViewController as? EditSecondaryViewController {
                vc.library = self.library
            }
        }
    }
    /// Sidebar filter
    @objc dynamic var sidebarFilters: NSPredicate? = nil
    
    /// Image currently being edited
    override var representedObject: Any? {
        didSet {
            // new image was set
            if let image = self.representedObject as? Image {
                
            }
            // no selection
            else {
                
            }
        }
    }

    // MARK: View Lifecycle
    /// Whether the secondary view should be restored when the view appears
    private var shouldOpenSecondaryView: Bool = false
    
    /**
     * Initiaizes CoreData contexts for displaying data once the view has loaded.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        // restore secondary view if desired
        if self.shouldOpenSecondaryView {
            self.shouldOpenSecondaryView = false
            self.toggleSecondaryView(self)
        }
    }

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {
        // hide secondary view
        let secondaryVisible = self.secondaryWc?.window?.isVisible ?? false
        
        if secondaryVisible {
            self.secondaryWc?.close()
        }
        
        self.shouldOpenSecondaryView = secondaryVisible
    }
    
    // MARK: - State restoration
    struct StateKeys {
        /// Whether the secondary view  is open
        static let secondaryVisible = "EditViewController.secondaryVisible"
    }
    
    /**
     * Encode state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        
        // secondary view
        if let secondary = self.secondaryWc, let window = secondary.window {
            secondary.encodeRestorableState(with: coder)
            coder.encode(window.isVisible, forKey: StateKeys.secondaryVisible)
        }
    }
    
    /**
     * Restore state
     */
    override func restoreState(with coder: NSCoder) {
        // re-open inspector if it was open last time
        if coder.decodeBool(forKey: StateKeys.secondaryVisible) {
            self.loadSecondaryController()
            self.secondaryWc!.restoreState(with: coder)
            
            self.shouldOpenSecondaryView = true
        }

        super.restoreState(with: coder)
    }
    
    // MARK: - Secondary view
    /// Window controller for the secondary view controller
    private var secondaryWc: NSWindowController? = nil
    
    /**
     * Loads the secondary window controller from the storyboard.
     */
    private func loadSecondaryController() {
        // get the window controller
        guard let sb = self.storyboard,
              let wc = sb.instantiateController(withIdentifier: "secondaryWindowController") as? NSWindowController else {
            return
        }
        
        self.secondaryWc = wc
        
        // set up some initial state of the secondary controller
        if let vc = wc.contentViewController as? EditSecondaryViewController {
            vc.library = self.library
            
            // create bindings
            vc.sidebarFilters = self.sidebarFilters
            vc.bind(NSBindingName(rawValue: "sidebarFilters"), to: self,
                    withKeyPath: #keyPath(EditViewController.sidebarFilters), options: nil)
        }
    }
    
    /**
     * Toggles display of the secondary window controller.
     */
    @IBAction func toggleSecondaryView(_ sender: Any?) {
        // load the window controller if needed
        if self.secondaryWc == nil {
            self.loadSecondaryController()
        }
        
        // toggle window
        if (self.secondaryWc?.window?.isVisible ?? false) {
            self.secondaryWc?.close()
        } else {
            self.secondaryWc?.showWindow(sender)
        }
    }
    
    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // secondary view
        if menuItem.action == #selector(toggleSecondaryView(_:)) {
            menuItem.state = (self.secondaryWc?.window?.isVisible ?? false) ? .on : .off
            return true
        }
        
        return false
    }
    
    // MARK: - XPC Connection
}
