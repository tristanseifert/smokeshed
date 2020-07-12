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
        self.restoreSecondaryState()
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
        /// Reference to secondary window controller
        static let secondaryWC = "EditViewController.secondaryWC"
    }
    
    /**
     * Encode state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        
        // secondary view
        if let secondary = self.secondaryWc, let window = secondary.window {
            secondary.encodeRestorableState(with: coder)
            
            if self.view.superview != nil {
                coder.encode(window.isVisible, forKey: StateKeys.secondaryVisible)
                DDLogVerbose("View is in hierarchy, using window visible flag: \(window.isVisible)")
            } else {
                coder.encode(self.shouldOpenSecondaryView, forKey: StateKeys.secondaryVisible)
                DDLogVerbose("View not in hierarchy, should open: \(self.shouldOpenSecondaryView)")
            }
        }
    }
    
    /**
     * Restore state
     */
    override func restoreState(with coder: NSCoder) {
        // re-open inspector if it was open last time
        if coder.decodeBool(forKey: StateKeys.secondaryVisible) {
            self.secondaryWc?.restoreState(with: coder)
            self.shouldOpenSecondaryView = true
        }

        super.restoreState(with: coder)
        
        // re-open the secondary view if visible
        if self.view.superview != nil {
            self.restoreSecondaryState()
        }
    }
    
    // MARK: - Secondary view
    /// Window controller for the secondary view controller
    private lazy var secondaryWc: NSWindowController? = {
        // get the window controller
        guard let sb = self.storyboard,
              let wc = sb.instantiateController(withIdentifier: "secondaryWindowController") as? NSWindowController else {
            DDLogError("Failed to instantiate secondary window controller")
            return nil
        }
        
        // set up some initial state of the secondary controller
        if let vc = wc.contentViewController as? EditSecondaryViewController {
            vc.library = self.library
            
            // create bindings
            vc.sidebarFilters = self.sidebarFilters
            vc.bind(NSBindingName(rawValue: "sidebarFilters"), to: self,
                    withKeyPath: #keyPath(EditViewController.sidebarFilters), options: nil)
        }
        
        // done!
        return wc
    }()
    
    /**
     * Toggles display of the secondary window controller.
     */
    @IBAction func toggleSecondaryView(_ sender: Any?) {
        // toggle window
        if self.secondaryWc != nil, (self.secondaryWc?.window?.isVisible ?? false) {
            self.secondaryWc?.close()
        } else {
            self.secondaryWc?.showWindow(sender)
        }
        
        self.invalidateRestorableState()
    }
    
    /**
     * If the secondary view needs to be shown, this handles that.
     */
    private func restoreSecondaryState() {
        if self.shouldOpenSecondaryView {
            self.secondaryWc?.showWindow(self)
            self.shouldOpenSecondaryView = false
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
