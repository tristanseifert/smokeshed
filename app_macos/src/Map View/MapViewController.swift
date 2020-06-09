//
//  MapViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class MapViewController: NSViewController, NSMenuItemValidation, ContentViewChild {
    /// Library that is being browsed
    private var library: LibraryBundle

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var nibName: NSNib.Name? {
        return "MapViewController"
    }

    /**
     * Initializes a new map view controller, displaying the contents of the provided library.
     */
    init(_ library: LibraryBundle) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    /// Decoding is not supported
    required init?(coder: NSCoder) {
        return nil
    }
    func getPreferredApperance() -> NSAppearance? {
        return nil
    }

    // MARK: View Lifecycle
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

    }

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {

    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return false
    }
}
