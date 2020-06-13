//
//  EditViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class EditViewController: NSViewController, NSMenuItemValidation, ContentViewChild {
    /// Library that is being browsed
    public var library: LibraryBundle! {
        didSet {

        }
    }

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var nibName: NSNib.Name? {
        return "EditViewController"
    }

    /**
     * Initializes a new edit view controller.
     */
    init() {
        super.init(nibName: nil, bundle: nil)
        self.identifier = .editViewController
    }
    
    /// Decoding is not supported
    required init?(coder: NSCoder) {
        return nil
    }

    /**
     * Edit view is DARK MODE™ zone
     */
    func getPreferredApperance() -> NSAppearance? {
        return NSAppearance(named: .darkAqua)
    }
    func getBottomBorderThickness() -> CGFloat {
        return 0
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
        self.view.window?.appearance = nil
    }

    // MARK: - Menu item handling
    /**
     * Ensures menu items that affect our state are always up-to-date.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return false
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Edit view controller (restoration)
    static let editViewController = NSUserInterfaceItemIdentifier("editViewController")
}
