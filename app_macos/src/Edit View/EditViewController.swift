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
                
                self.updateScrollSize(image)
                self.updateDisplay(image)
            }
            // no selection
            else {
                self.noSelectionVisible = true
            }
        }
    }
    
    // MARK: Initialization
    /**
     * Remove various observers when deallocating.
     */
    deinit {
        self.deinitDisplay()
        self.cleanUpScrollView()
    }

    // MARK: View Lifecycle
    /// Whether the secondary view should be restored when the view appears
    private var shouldOpenSecondaryView: Bool = false
    
    /**
     * Initiaizes CoreData contexts for displaying data once the view has loaded.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setUpNoSelectionUI()
        self.setUpLoadingUI()
        self.initDisplay()
        self.setUpScrollView()
        
        self.isLoading = false
        self.noSelectionVisible = true
    }

    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        self.showEditSidebar()
        self.restoreSecondaryState()
    }

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {
        self.hideEditSidebar()
        
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
        /// Whether the edit controls view  is open
        static let controlsVisible = "EditViewController.controlsVisible"
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
        
        // edit controls
        if let controls = self.editWc, let window = controls.window {
            controls.encodeRestorableState(with: coder)
            
            // TODO: better
            coder.encode(window.isVisible, forKey: StateKeys.controlsVisible)
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
        
        // restore state of the edit controls
        self.editWc.restoreState(with: coder)
        
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
    private lazy var secondaryWc: NSWindowController! = {
        // get the window controller
        guard let sb = self.storyboard,
              let wc = sb.instantiateController(withIdentifier: "secondaryWindowController") as? NSWindowController else {
            fatalError("Failed to instantiate secondary window controller")
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
    
    // MARK: - Editing sidebar
    /// Edit tools window controller
    private lazy var editWc: NSWindowController! = {
        guard let sb = self.storyboard,
              let wc = sb.instantiateController(withIdentifier: "editToolsWindow") as? EditSidebarWindowController else {
            fatalError("Failed to instantiate edit window controller")
        }
        
        wc.editView = self
        
        return wc
    }()
    
    /**
     * Shows the edit-specific split controls on the right side of the split view.
     *
     * This should be called immediately before the view is to appear.
     */
    private func showEditSidebar() {
        // show that bitch
        self.editWc.showWindow(self)
    }
    
    /**
     * Hides the edit-specific sidebar on the right.
     *
     * This should be called immediately before the view is to disappear.
     */
    private func hideEditSidebar() {
        if let wc = self.editWc, let window = wc.window, window.isVisible {
            window.orderOut(self)
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
        
        // debug item
        if menuItem.action == #selector(toggleEditDebugWindow(_:)) {
            menuItem.state = (self.debugWc?.window?.isVisible ?? false) ? .on : .off
            return true
        }
        
        return false
    }
    
    // MARK: - Image Display
    /// Image render view
    @IBOutlet internal var renderView: ImageRenderView! = nil
    
    /**
     * Sets up for image display.
     */
    private func initDisplay() {
        
    }
    
    /**
     * Cleans up image display.
     */
    private func deinitDisplay() {
        
    }
    
    /**
     * Updates the displayed image.
     *
     * If no image is selected, the "no selection" indicator is displayed. If an image is selected, get a thumb to draw blurred behind all the
     * things until the renderer draws a full size image.
     */
    private func updateDisplay(_ image: Image) {
        // request render
        self.renderView.setImage(self.library, image) { res in
            do {
                let _ = try res.get()
                
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } catch {
                DDLogError("Failed to update image: \(error)")
            }
        }
        
        // display loading indicator
        self.isLoading = true
    }
    
    /**
     * Clears the display state.
     */
    private func clearDisplay() {
        self.isLoading = false
    }
    
    // MARK: Scroll View
    @IBOutlet private var scrollView: NSScrollView! = nil
    
    /// Scroll view observers
    private var scrollViewObservers: [NSObjectProtocol] = []
    
    /**
     * Sets up the scroll view observation.
     */
    private func setUpScrollView() {
        let c = NotificationCenter.default
        
        // observe the bounds of the scroll view
        self.scrollView.contentView.postsBoundsChangedNotifications = true
        let o = c.addObserver(forName: NSView.boundsDidChangeNotification,
                              object: self.scrollView.contentView,
                              queue: OperationQueue.main, using: self.scrollViewBoundsChanged)
        scrollViewObservers.append(o)
    }
    
    /**
     * Handles a bounds change notification for the scroll view.
     */
    private func scrollViewBoundsChanged(_ note: Notification) {
        guard let content = note.object as? NSClipView else {
            DDLogError("Invalid notification object: \(note)")
            return
        }
        
        // the render view operates in backing pixels
        var viewport = content.documentVisibleRect
        viewport = content.convertToBacking(viewport)
        
        // apply scale for magnification
        let zoomScale = self.scrollView.magnification
        if zoomScale != 1 {
            viewport.size.width /= zoomScale
            viewport.size.height /= zoomScale
        }
        
//        DDLogVerbose("Viewport after scaling by \(zoomScale): \(viewport)")
        
        // update the render view
        self.renderView.viewport = viewport
    }
    
    /**
     * Cleans up scroll view observations.
     */
    private func cleanUpScrollView() {
        // remove the bounds observer of the clip view
        self.scrollView.contentView.postsBoundsChangedNotifications = false
        
        // clear all notification handlers
        self.scrollViewObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        self.scrollViewObservers.removeAll()
    }
    
    /**
     * Updates the scroll view for the given image.
     */
    private func updateScrollSize(_ image: Image) {
        let newSize = image.imageSize
        
        // resize content view
        guard let content = self.scrollView.documentView else {
            return
        }
        
        self.scrollView.magnification = 1
        content.setFrameSize(newSize)
        DDLogVerbose("New scroll content view size: \(newSize)")
    }
    
    // MARK: No Selection
    /// Effect view holding the no selection UI
    @IBOutlet private var noSelectionContainer: NSVisualEffectView! = nil
    
    /// Whether the "no selection" UI is visible
    @objc dynamic private var noSelectionVisible: Bool = true {
        didSet {
            if !Thread.isMainThread {
                DispatchQueue.main.async {
                    self.updateNoSelection()
                }
            } else {
                self.updateNoSelection()
            }
        }
    }
    
    /**
     * Sets up the no selection UI.
     */
    private func setUpNoSelectionUI() {
        self.noSelectionContainer.layer?.cornerRadius = 10
    }
    
    /**
     * Updates the "no selection" UI
     */
    private func updateNoSelection() {
        // show view if needed
        if self.noSelectionVisible {
            self.noSelectionContainer.isHidden = false
            self.scrollView.isHidden = true
        } else {
            self.scrollView.isHidden = false
        }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            // set animation style
            ctx.duration = 0.33
            ctx.timingFunction = CAMediaTimingFunction.init(name: .easeInEaseOut)
            
            // animate opacity in or out
            if self.noSelectionVisible {
                self.noSelectionContainer.animator().alphaValue = 1
            } else {
                self.noSelectionContainer.animator().alphaValue = 0
            }
        }) {
            if !self.noSelectionVisible {
                self.noSelectionContainer.isHidden = true
            }
        }
    }
    
    // MARK: Loading indicator
    /// Effect view holding the loading indicator
    @IBOutlet private var loadingContainer: NSVisualEffectView! = nil
    
    /// Whether the loading indicator is visible
    @objc dynamic private var isLoading: Bool = false {
        didSet {
            if !Thread.isMainThread {
                DispatchQueue.main.async {
                    self.updateLoadingUI()
                }
            } else {
                self.updateLoadingUI()
            }
        }
    }
    
    /**
     * Sets up the loading UI.
     */
    private func setUpLoadingUI() {
        self.loadingContainer.layer?.cornerRadius = 10
    }
    
    /**
     * Updates the loading UI.
     *
     * - Note: This must be run from the main thread.
     */
    private func updateLoadingUI() {
        if self.isLoading {
            self.loadingContainer.isHidden = false
        }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            // set animation style
            ctx.duration = 0.33
            ctx.timingFunction = CAMediaTimingFunction.init(name: .easeInEaseOut)
            
            // animate opacity in or out
            if self.isLoading {
                self.loadingContainer.animator().alphaValue = 1
            } else {
                self.loadingContainer.animator().alphaValue = 0
            }
        }) {
            if !self.isLoading {
                self.loadingContainer.isHidden = true
            }
        }
    }
    
    // MARK: - Debugging support
    /// Debug window controller
    private var debugWc: NSWindowController? = nil
    
    /**
     * Toggles the debug controller's visibility.
     */
    @IBAction private func toggleEditDebugWindow(_ sender: Any) {
        // close window if open
        if (self.debugWc?.window?.isVisible ?? false) {
            self.debugWc?.close()
        }
        // otherwise, create and/or show it
        else {
            if self.debugWc == nil {
                self.debugWc = self.storyboard!.instantiateController(identifier: .editViewDebugWindow, creator: {
                    return EditViewDebugWindowController(coder: $0)
                })
                
                guard let wc = self.debugWc as? EditViewDebugWindowController else {
                    DDLogError("Failed to cast debug window: \(String(describing: self.debugWc))")
                    return
                }
                wc.editView = self.renderView
            }
            
            self.debugWc?.showWindow(sender)
        }
    }
    
    // MARK: - XPC Connection
}

extension NSStoryboard.SceneIdentifier {
    static let editViewDebugWindow = "editViewDebug"
}
