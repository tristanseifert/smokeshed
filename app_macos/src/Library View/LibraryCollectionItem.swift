//
//  LibraryCollectionItem.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Each image in the library is rendered by one of these bad boys.
 */
class LibraryCollectionItem: NSCollectionViewItem {
    /// Sequence number of this item, i.e. its index
    public var sequenceNumber: Int = 0 {
        didSet {
            if let view = self.view as? LibraryCollectionItemView {
                view.sequenceNumber = self.sequenceNumber
            }
        }
    }

    /// Image represented by this cell
    override var representedObject: Any? {
        /**
         * When the represented object (the image) is changed, propagate that change to the view; this
         * will cause it to redraw with new data.
         */
        didSet {
            if let view = self.view as? LibraryCollectionItemView {
                if let image = self.representedObject as? Image {
                    view.image = image
                } else {
                    view.sequenceNumber = 0
                    view.image = nil
                }
            }
        }
    }

    /// Whether the context menu outline is drawn on the cell
    public var drawContextOutline: Bool = false {
        didSet {
            if let view = self.view as? LibraryCollectionItemView {
                view.drawContextOutline = self.drawContextOutline
            }
        }
    }

    // MARK: - Initialization
    /**
     * Creates the content view.
     */
    override func loadView() {
        self.view = LibraryCollectionItemView()
    }

    // MARK: - View lifecycle
    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        if let view = self.view as? LibraryCollectionItemView {
            view.prepareForDisplay()
        }
    }

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {
        if let view = self.view as? LibraryCollectionItemView {
            view.didDisappear()
        }
    }

    // MARK: Selection
    /// Whether the item is selected
    override var isSelected: Bool {
        didSet {
            if let view = self.view as? LibraryCollectionItemView {
                view.isSelected = self.isSelected
            }
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Standard image collection view item
    static let libraryCollectionItem = NSUserInterfaceItemIdentifier("LibraryCollectionItem")
}
