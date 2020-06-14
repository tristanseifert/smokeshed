//
//  LibraryCollectionView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200613.
//

import Cocoa

/**
 * Provides some custom behaviors required for the library view
 */
class LibraryCollectionView: NSCollectionView {
    /// Bonus delegate™
    weak open var kushDelegate: LibraryCollectionViewDelegate?


    // MARK: Initialization
    override func awakeFromNib() {
        self.identifier = .libraryCollectionView
    }

    // MARK: Menu support
    /**
     * Returns the appropriate menu for whatever cell is underneath the cursor.
     */
    override func menu(for event: NSEvent) -> NSMenu? {
        // get the default menu
        var menu = super.menu(for: event)

        // query delegate
        let pt = self.convert(event.locationInWindow, from: nil)
        let path = self.indexPathForItem(at: pt)

        if let delegate = self.kushDelegate {
            menu = delegate.collectionView(self, menu: menu, at: path)
        }

        // return the final menu
        return menu
    }
}

extension NSUserInterfaceItemIdentifier {
    static let libraryCollectionView = NSUserInterfaceItemIdentifier("libraryCollectionView")
}

/**
 * Additional delegate methods used by the library collection view.
 */
protocol LibraryCollectionViewDelegate: NSObjectProtocol {
    func collectionView(_ collectionView:NSCollectionView, menu:NSMenu?, at indexPath: IndexPath?) -> NSMenu?
}
