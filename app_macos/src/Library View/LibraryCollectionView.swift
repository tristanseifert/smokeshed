//
//  LibraryCollectionView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200613.
//

import Cocoa

import CocoaLumberjackSwift

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
    
    // MARK: - Keyboard events
    /**
     * Inspects the pressed key to see if we handle it.
     *
     * This function handles Page Up/Down as well as Home/End.
     */
    override func keyDown(with event: NSEvent) {
        // we only care about function keys
        guard event.modifierFlags.contains(.function),
              let str = event.charactersIgnoringModifiers,
              str.count == 1 else {
            return
        }
        
        // check out what character it is
        switch str.first! {
        case Character(Unicode.Scalar(NSPageUpFunctionKey)!):
            self.enclosingScrollView?.pageUp(self)
            
        case Character(Unicode.Scalar(NSPageDownFunctionKey)!):
            self.enclosingScrollView?.pageDown(self)
            
        case Character(Unicode.Scalar(NSHomeFunctionKey)!):
            self.enclosingScrollView?.documentView?.scroll(.zero)
            
        case Character(Unicode.Scalar(NSEndFunctionKey)!):
            let doc = self.enclosingScrollView!.documentView!
            doc.scroll(NSPoint(x: 0, y: doc.bounds.height))
            
        default:
            return
        }
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
