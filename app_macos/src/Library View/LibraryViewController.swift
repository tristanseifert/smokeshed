//
//  LibraryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryViewController: NSViewController, NSMenuItemValidation, ContentViewChild {
    /// Library that is being browsed
    private var library: LibraryBundle

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var nibName: NSNib.Name? {
        return "LibraryViewController"
    }

    /**
     * Initializes a new library view controller, browsing the contents of the provided library.
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

        // reset constraints to the initial state
        self.isFilterVisible = false
        self.filter.enclosingScrollView?.isHidden = true

        // register the collection view class
        self.collection.register(LibraryCollectionItem.self,
                                 forItemWithIdentifier: .init("RegularImageItem"))
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

    // MARK: - Collection view
    @IBOutlet private var collection: NSCollectionView! = nil

    // MARK: - Fetching
    /// Helper to get the view context
    @objc dynamic private var viewContext: NSManagedObjectContext {
        return self.library.store.mainContext!
    }
    /// Filter predicate for what's being displayed
    @objc dynamic private var filterPredicate: NSPredicate! = nil
    /// Sort descriptors for the results
    @objc dynamic private var sort: [NSSortDescriptor] = [NSSortDescriptor]()

    // MARK: - Filter bar UI
    /// Predicate editor for the filters
    @IBOutlet private var filter: NSPredicateEditor! = nil
    /// Size constraint for the filter predicate editor
    @IBOutlet private var filterHeightConstraint: NSLayoutConstraint! = nil
    /// Is the filter predicate editor visible?
    @objc dynamic private var isFilterVisible: Bool = false {
        // update the UI if needed
        didSet {
            NSAnimationContext.runAnimationGroup({ (ctx) in
                ctx.duration = 0.125
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                self.filter.enclosingScrollView?.isHidden = false

                if self.isFilterVisible {
                    self.filter.enclosingScrollView?.animator().alphaValue = 1
                    self.filterHeightConstraint.animator().constant = 192
                } else {
                    self.filter.enclosingScrollView?.animator().alphaValue = 0
                    self.filterHeightConstraint.animator().constant = 0
                }
            }, completionHandler: {
                if self.isFilterVisible {

                } else {
                    self.filter.enclosingScrollView?.isHidden = true
                }
            })
        }
    }

    // MARK: - Lens/Camera Filters
    /// Lens filter pulldown
    @IBOutlet private var lensFilter: NSPopUpButton! = nil
    /// Menu displayed by the lens filter pulldown
    @objc dynamic private var lensMenu: NSMenu = NSMenu() {
        didSet {
            if let btn = self.lensFilter {
                btn.menu = lensMenu
            }
        }
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return false
    }
}
