//
//  MainWindowViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import CocoaLumberjackSwift

class MainWindowViewController: NSSplitViewController, NSMenuItemValidation {
    /**
     * When the view is about to appear, add the toolbar item if it doesn't already exist.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
//        if let window = self.view.window, let toolbar = window.toolbar {
//            if !toolbar.items.contains(where: { $0.itemIdentifier == .sidebarTrackingSeparatorItemIdentifier }) {//
//                var items = toolbar.items
//
//                // add the separator
//                let s = NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparatorItemIdentifier,
//                                                       splitView: self.splitView,
//                                                       dividerIndex: 1)
//                items.insert(s, at: 0)
//
//                // restore toolbar items
//                toolbar.items = items
//            }
//        }
    }
    
    // MARK: - Child message handling
    /**
     * Forward messages to child controllers as needed
     */
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {        
        // check each child
        for child in self.children {
            // does it directly support this action?
            if child.responds(to: action) {
                return child
            }
            // does it provide a supplemental target?
            else if let target = child.supplementalTarget(forAction: action,
                                                          sender: sender) {
                return target
            }
        }
        
        // no controller supports this method
        return super.supplementalTarget(forAction: action, sender: sender)
    }
    
    /**
     * Requests child controllers validate menu items
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        for child in self.children {
            // does it support menu item validation?
            guard let validator = child as? NSMenuItemValidation else {
                continue
            }
            
            // if handled, return
            if validator.validateMenuItem(menuItem) {
                return true
            }
        }
        
        // not handled
        return false
    }
}
