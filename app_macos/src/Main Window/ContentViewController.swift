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
}

/**
 * Serves as the content view controller of the main window. It provides an interface for yeeting between the
 * different app modes.
 */
class ContentViewController: NSViewController {
    /// Library that is being browsed
    private var library: LibraryBundle

    // MARK: - Initialization
    /**
     * Initializes a content view controller, using the given library to back all of the views' data.
     */
    init(_ library: LibraryBundle) {
        self.library = library

        super.init(nibName: nil, bundle: nil)
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
    private var transitionFromVc: NSViewController! = nil
    /// Currently displayed app mode
    private var mode: AppMode! = nil

    /// Library controller, if allocated
    private var libraryView: LibraryViewController! = nil
    /// Map view controller, if allocated
    private var mapView: MapViewController! = nil
    /// Edit view controller, if allocated
    private var editView: EditViewController! = nil


    /**
     * Updates the content view to match the given mode.
     */
    func setContent(_ mode: AppMode, completion: (()->Void)! = nil) {
        var next: NSViewController! = nil

        // exit immediately if mode isn't changing
        guard self.mode != mode else {
            if let handler = completion {
                handler()
            }

            return
        }


        // allocate the controller
        switch mode {
            case .Library:
                if self.libraryView == nil {
                    self.libraryView = LibraryViewController(self.library)
                    self.addChild(self.libraryView)
                }
                next = self.libraryView

            case .Edit:
                if self.editView == nil {
                    self.editView = EditViewController(self.library)
                    self.addChild(self.editView)
                }
                next = self.editView

            case .Map:
                if self.mapView == nil {
                    self.mapView = MapViewController(self.library)
                    self.addChild(self.mapView)
                }
                next = self.mapView
        }

        // ensure the next view's size matches the window size
        next.view.frame = self.view.bounds

        // start the animation context for transitioning; update apperaance
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.25
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        if let c = next as? ContentViewChild, let window = self.view.window {
            window.animator().appearance = c.getPreferredApperance()
        }

        // either display the controler w/o transition if no previous
        if self.transitionFromVc == nil {
            // just add the view (controller is already a child)
            self.view.addSubview(next.view)

            // ensure that this controller is the start for the transition next
            self.transitionFromVc = next

            // call completion handler
            if let handler = completion {
                handler()
            }
        }
        // or, perform a fancy transition
        else {
            // determine the animation direction
            var options: NSViewController.TransitionOptions = []

            // if previous mode was higher, animate left-to-right
            if self.mode.rawValue > mode.rawValue {
                options.insert(.slideRight)
            }
            // otherwise, go right
            else {
                options.insert(.slideLeft)
            }

            // perform transition
            self.transition(from: self.transitionFromVc!, to: next,
                            options: options, completionHandler: {
                DDLogVerbose("Content transition done")
                self.transitionFromVc = next

                // chain completion handler
                if let handler = completion {
                    handler()
                }
            })
        }

        // finish animation context
        NSAnimationContext.endGrouping()

        // store the app mode for later
        self.mode = mode
    }
}
