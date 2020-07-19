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
        didSet(oldValue) {
            // clear out old state
            self.clearDisplay()
            
            // new image was set
            if let images = self.representedObject as? [Image],
               let image = images.first {
                self.noSelectionVisible = false
                self.updateNoSelection()
                
                self.updateDisplay(image)
            }
            // no selection
            else {
                self.noSelectionVisible = true
                self.updateNoSelection()
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
        
        self.setUpLoadingUI()
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
            self.removeSecondarySelectionObservers()
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
    
    // MARK: - Editing entry
    /// If the secondary view is getting restored, this is the image that will be selected in it.
    private var secondaryImageToSelect: Image? = nil
    
    /**
     * Prepares the editing view to edit the given image.
     */
    internal func openImage(_ image: Image) {
        // ensure secondary view is updated appropriately
        self.secondaryImageToSelect = image
        self.representedObject = [image]
    }
    
    // MARK: - Secondary view
    /// Selection observer
    private var secondarySelectionObs: NSKeyValueObservation? = nil
    
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
            
            // propagate initial selection
            if let images = self.representedObject as? [Image] {
                vc.select(images)
            }
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
            self.removeSecondarySelectionObservers()
        } else {
            self.observeSecondarySelection()
            self.secondaryWc?.showWindow(sender)
        }
        
        self.invalidateRestorableState()
    }
    
    /**
     * If the secondary view needs to be shown, this handles that.
     */
    private func restoreSecondaryState() {
        if self.shouldOpenSecondaryView {
            // prepare some state on the secondary view
            if let vc = self.secondaryWc?.contentViewController as? EditSecondaryViewController {
                // restore the image selection if needed
                if let image = self.secondaryImageToSelect {
                    vc.select([image])
                    self.secondaryImageToSelect = nil
                }
            }
            
            // add observers and show
            self.observeSecondarySelection()
            
            self.secondaryWc?.showWindow(self)
            self.shouldOpenSecondaryView = false
        }
    }
    
    /**
     * Adds observers for the selection of the secondary view.
     */
    private func observeSecondarySelection() {
        if let vc = self.secondaryWc?.contentViewController as? EditSecondaryViewController {
            self.secondarySelectionObs = vc.observe(\.representedObject, options: []) { _, _ in
                if let images = vc.representedObject as? [Image],
                   let image = images.first {
                    // this ensures there's always only one selection
                    self.representedObject = [image]
                } else {
                    self.representedObject = nil
                }
            }
        }
    }
    
    /**
     * Removes secondary selection observers.
     */
    private func removeSecondarySelectionObservers() {
        self.secondarySelectionObs = nil
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
    
    // MARK: - Image Display
    /// Image render view
    @IBOutlet private var renderView: ImageRenderView! = nil
    
    /**
     * Updates the displayed image.
     *
     * If no image is selected, the "no selection" indicator is displayed. If an image is selected, get a thumb to draw blurred behind all the
     * things until the renderer draws a full size image.
     */
    private func updateDisplay(_ image: Image) {
        // request render
        self.renderView.image = image
        
        // get a thumb image to show blurred while loading
        ThumbHandler.shared.get(image) { imageId, res in
            switch res {
            case .failure(let err):
                DDLogWarn("Failed to get edit view thumb: \(err)")
                
            case .success(let surface):
                do {
                    try self.renderView.updateThumb(surface)
                } catch {
                    DDLogError("Failed to update thumb: \(error)")
                }
            }
        }
        
        // display loading indicator
        self.isLoading = true
    }
    
    /**
     * Clears the display state.
     */
    private func clearDisplay() {
        self.renderView.image = nil

        self.isLoading = false
    }
    
    // MARK: No Selection
    /// Whether the "no selection" UI is visible
    @objc dynamic private var noSelectionVisible: Bool = true
    
    /**
     * Updates the "no selection" UI
     */
    private func updateNoSelection() {
        
    }
    
    // MARK: Loading indicator
    /// Effect view holding the loading indicator
    @IBOutlet private var loadingContainer: NSVisualEffectView! = nil
    
    /// Whether the loading indicator is visible
    @objc dynamic private var isLoading: Bool = false
    
    /**
     * Sets up the loading UI.
     */
    private func setUpLoadingUI() {
        self.loadingContainer.wantsLayer = true
        self.loadingContainer.layer?.cornerRadius = 10
    }
    
    // MARK: - XPC Connection
}
