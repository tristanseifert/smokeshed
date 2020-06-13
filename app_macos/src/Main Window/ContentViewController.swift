//
//  ContentViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

protocol ContentViewChild {
    func getPreferredApperance() -> NSAppearance?
    func getBottomBorderThickness() -> CGFloat
}

/**
 * Serves as the content view controller of the main window. It provides an interface for yeeting between the
 * different app modes.
 */
class ContentViewController: NSViewController, NSMenuItemValidation {
    /// Library that is being browsed
    public var library: LibraryBundle! = nil {
        didSet {
            // update library for all content controllers
            self.libraryView?.library = self.library
            self.editView?.library = self.library
            self.mapView?.library = self.library
        }
    }

    /**
     * Errors that may take place during transitioning or in transition actions.
     */
    enum TransitionError: Error {
        /// Another transition is already taking place.
        case alreadyTransitioning
        /// Failed to determine the mode to switch to. Check sender type is supported.
        case failedToRetrieveTag
        /// The raw mode value retrieved was invalid.
        case invalidTag(_ retrievedTag: Int)
    }

    // MARK: - Initialization
    /**
     * Initializes a content view controller.
     */
    init() {
        super.init(nibName: nil, bundle: nil)
        self.identifier = .contentViewController
    }
    /// Decoding is not supported
    required init?(coder: NSCoder) {
        return nil
    }

    /**
     * Provide an empty view as the content of this controller.
     */
    override func loadView() {
        self.view = NSView()
    }

    // MARK: - Child controller handling
    /// Previously displayed controller
    @objc dynamic private var currentVc: NSViewController! = nil
    /// Currently displayed app mode
    private var mode: AppMode! = nil {
        didSet {
            self.rawMode = self.mode.rawValue
            self.invalidateRestorableState()
        }
    }

    /// Raw value of the app mode
    @objc dynamic var rawMode: Int = 0

    /// Is a transition in progress?
    private var isTransitioning: Bool = false

    /// Library controller, if allocated
    private var libraryView: LibraryViewController! = nil
    /// Map view controller, if allocated
    private var mapView: MapViewController! = nil
    /// Edit view controller, if allocated
    private var editView: EditViewController! = nil

    /// KVO observers for each of the views' represented objects
    private var kvos: [AppMode: NSKeyValueObservation] = [:]


    /**
     * Updates the content view to match the given mode.
     */
    func setContent(_ mode: AppMode, withAnimation animate: Bool = false, andCompletion completion: (()->Void)! = nil) {
        var next: NSViewController! = nil

        // exit immediately if mode isn't changing
        guard self.mode != mode else {
            if let handler = completion {
                handler()
            }

            return
        }

        self.isTransitioning = true


        // allocate the controller
        switch mode {
            case .Library:
                if self.libraryView == nil {
                    self.libraryView = LibraryViewController()
                    self.libraryView.library = self.library
                    self.kvos[.Library] = self.libraryView.observe(\.representedObject, changeHandler: { object, _ in
                        self.childRepresentedObjChanged(object)
                    })

                    self.addChild(self.libraryView)
                }
                next = self.libraryView

            case .Edit:
                if self.editView == nil {
                    self.editView = EditViewController()
                    self.editView.library = self.library
                    self.kvos[.Edit] = self.editView.observe(\.representedObject, changeHandler: { object, _ in
                        self.childRepresentedObjChanged(object)
                    })

                    self.addChild(self.editView)
                }
                next = self.editView

            case .Map:
                if self.mapView == nil {
                    self.mapView = MapViewController()
                    self.mapView.library = self.library
                    self.kvos[.Map] = self.mapView.observe(\.representedObject, changeHandler: { object, _ in
                        self.childRepresentedObjChanged(object)
                    })

                    self.addChild(self.mapView)
                }
                next = self.mapView
        }

        // ensure the next view's size matches the window size
        next.view.frame = self.view.bounds

        // start the animation context for transitioning; update apperaance
        if animate {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.25
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }

        if let c = next as? ContentViewChild, let window = self.view.window {
            if animate {
                window.animator().appearance = c.getPreferredApperance()
                window.animator().setContentBorderThickness(c.getBottomBorderThickness(), for: .minY)
            } else {
                window.appearance = c.getPreferredApperance()
                window.setContentBorderThickness(c.getBottomBorderThickness(), for: .minY)
            }
        }

        // either display the controler w/o transition if no previous
        if self.currentVc == nil {
            // just add the view (controller is already a child)
            self.view.addSubview(next.view)

            // call completion handler
            self.isTransitioning = false
            if let handler = completion {
                handler()
            }
        }
        // or, perform a fancy transition
        else {
            // determine the animation direction
            var options: NSViewController.TransitionOptions = []

            if animate {
                // if previous mode was higher, animate left-to-right
                if self.mode.rawValue > mode.rawValue {
                    options.insert(.slideRight)
                }
                // otherwise, go right
                else {
                    options.insert(.slideLeft)
                }
            }

            // perform transition
            self.transition(from: self.currentVc!, to: next,
                            options: options, completionHandler: {
                // update post-transition state
                self.isTransitioning = false

                // chain completion handler
                if let handler = completion {
                    handler()
                }
            })
        }

        // finish animation context
        NSAnimationContext.endGrouping()

        // store the app mode for later
        self.currentVc = next
        self.mode = mode
        
        self.updateRepresentedObj()
    }

    // MARK: - Mode switching actions
    /**
     * Action method to change the app mode. The sender's tag, or in the case of a segmented control, the
     * selected tag, is used to get the app mode. Tag values must match those defined in the AppMode
     * enum.
     */
    func changeAppModeUnsafe(_ sender: Any) throws {
        var newMode = 0

        // ensure we're not mid transition
        guard !self.isTransitioning else {
            throw TransitionError.alreadyTransitioning
        }

        // determine mode to switch to based on sender's tag
        if let segment = sender as? NSSegmentedControl {
            newMode = segment.selectedTag()
        } else if let item = sender as? NSMenuItem {
            newMode = item.tag
        } else {
            throw TransitionError.failedToRetrieveTag
        }

        // get the new mode
        guard let mode = AppMode(rawValue: newMode) else {
            throw TransitionError.invalidTag(newMode)
        }

        // perform mode switch
        self.setContent(mode, withAnimation: true)
    }

    /**
     * Wraps the change action in error handling.
     */
    @IBAction func changeAppMode(_ sender: Any) {
        do {
            try self.changeAppModeUnsafe(sender)
        } catch {
            DDLogError("Failed to change app mode: \(error)")
        }
    }

    // MARK: - Message forwarding
    /**
     * Claim that we can respond to a particular selector, if the currently active view controller can. This way
     * we can forward messages to it.
     */
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        else if let content = self.currentVc,
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
        // can the currently active controller respond to this message?
        if let content = self.currentVc, content.responds(to: aSelector) {
            return self.currentVc
        }

        // nothing supports this message
        return nil
    }
    /**
     * Returns the method implementation for the given selector. If we don't implement the method, provide
     * the implementation provided by the content controller.
     */
    override func method(for aSelector: Selector!) -> IMP! {
        let sig = super.method(for: aSelector)

        // forward to content if not supported
        if sig == nil, let newTarget = self.currentVc,
            newTarget.responds(to: aSelector) {
            return newTarget.method(for: aSelector)
        }

        return sig
    }

    // MARK: - Menu item handling
    /**
     * Validates a menu item's action. This is used to support checking the menu item corresponding to the
     * current app mode.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // is it the app mode item?
        if menuItem.action == #selector(changeAppMode(_:)) {
            // it's on if its tag matches the current mode raw value
            if let mode = self.mode {
                menuItem.state = (menuItem.tag == mode.rawValue) ? .on : .off
            }

            return true
        }

        // does the currently visible controller support menu validation?
        if let mv = self.currentVc as? NSMenuItemValidation {
            return mv.validateMenuItem(menuItem)
        }

        // unhandled
        return false
    }

    // MARK: - Represented object bindings
    /**
     * Represented object change handler for children
     */
    private func childRepresentedObjChanged(_ child: Any?) {
        self.updateRepresentedObj()
    }

    /**
     * Updates the represented object of this view controller to match that of the active view controller.
     */
    private func updateRepresentedObj() {
        guard let mode = self.mode else {
            self.representedObject = nil
            return
        }

        switch mode {
            case .Library:
                self.representedObject = self.libraryView.representedObject
            case .Map:
                self.representedObject = self.mapView.representedObject
            case .Edit:
                self.representedObject = self.editView.representedObject
        }
    }


    // MARK: - State restoration
    private struct StateKeys {
        /// Current app mode (raw value)
        static let mode = "ContentViewController.mode"

        /// Did we encode state for the library view?
        static let hasLibraryState = "ContentViewController.hasLibraryState"
        /// Did we encode state for the map view?
        static let hasMapState = "ContentViewController.hasMapState"
        /// Did we encode state for the edit view?
        static let hasEditState = "ContentViewController.hasEditState"
    }

    /**
     * Encodes state needed to get back to the current UI state.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // save the app mode
        coder.encode(self.mode.rawValue, forKey: StateKeys.mode)

        // save state of each child controller
        if let library = self.libraryView {
            library.encodeRestorableState(with: coder)
            coder.encode(true, forKey: StateKeys.hasLibraryState)
        }
        if let map = self.mapView {
            map.encodeRestorableState(with: coder)
            coder.encode(true, forKey: StateKeys.hasMapState)
        }
        if let edit = self.editView {
            edit.encodeRestorableState(with: coder)
            coder.encode(true, forKey: StateKeys.hasEditState)
        }
    }

    /**
     * Decodes state that was previously archived.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // decode state for view controllers
        if coder.decodeBool(forKey: StateKeys.hasLibraryState) {
            self.libraryView = LibraryViewController()
            self.libraryView.library = self.library
            self.kvos[.Library] = self.libraryView.observe(\.representedObject, changeHandler: { object, _ in
                self.childRepresentedObjChanged(object)
            })

            self.addChild(self.libraryView)

            self.libraryView.restoreState(with: coder)
        }

        if coder.decodeBool(forKey: StateKeys.hasMapState) {
            self.mapView = MapViewController()
            self.mapView.library = self.library
            self.kvos[.Map] = self.mapView.observe(\.representedObject, changeHandler: { object, _ in
                self.childRepresentedObjChanged(object)
            })

            self.addChild(self.mapView)

            self.mapView.restoreState(with: coder)
        }

        if coder.decodeBool(forKey: StateKeys.hasEditState) {
            self.editView = EditViewController()
            self.editView.library = self.library
            self.kvos[.Edit] = self.editView.observe(\.representedObject, changeHandler: { object, _ in
                self.childRepresentedObjChanged(object)
            })

            self.addChild(self.editView)

            self.editView.restoreState(with: coder)
        }

        // restore the app mode
        let rawMode = coder.decodeInteger(forKey: StateKeys.mode)
        if let mode = AppMode(rawValue: rawMode) {
            self.setContent(mode, withAnimation: false)
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Content view controller (restoration)
    static let contentViewController = NSUserInterfaceItemIdentifier("contentViewController")
}
