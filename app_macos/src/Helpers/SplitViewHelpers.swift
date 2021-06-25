//
//  SplitViewHelpers.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

internal extension NSViewController {
    /**
     * Attempts to find the closest parent to this view controller, which is a split view controller.
     */
    var enclosingSplitViewController: NSSplitViewController? {
        var parent: NSViewController? = self.parent
        
        while parent != nil {
            if let split = parent as? NSSplitViewController {
                return split
            } else {
                parent = parent?.parent
            }
        }
        
        return nil
    }
}
