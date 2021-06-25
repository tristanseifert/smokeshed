//
//  DeluxeOutlineView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Cocoa

/**
 * Implements some common behaviors for an outline view we might desire.
 */
class DeluxeOutlineView: NSOutlineView {
    /// Bonus delegate™
    weak open var kushDelegate: DeluxeOutlineViewDelegate?
    
    // MARK: Menu support
    /**
     * Returns the appropriate menu for whatever cell is underneath the cursor.
     */
    override func menu(for event: NSEvent) -> NSMenu? {
        // get the default menu
        var menu = super.menu(for: event)

        // query delegate
        let pt = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: pt)

        if let delegate = self.kushDelegate {
            menu = delegate.outlineView(self, menu: menu, at: row)
        }

        // return the final menu
        return menu
    }
}


/**
 * Additional delegate methods used by the deluxe outline view.
 */
protocol DeluxeOutlineViewDelegate: NSObjectProtocol {
    func outlineView(_ outlineView: NSOutlineView, menu: NSMenu?, at row: Int) -> NSMenu?
}
