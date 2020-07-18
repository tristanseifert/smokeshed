//
//  MainWindowViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import CocoaLumberjackSwift

class MainWindowViewController: NSSplitViewController, NSMenuItemValidation, NSToolbarDelegate {
    /// Filter for the sidebar selection
    @objc dynamic var sidebarFilter: NSPredicate?
    
    /**
     * When the view is about to appear, add the toolbar item if it doesn't already exist.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        // bind the sidebar's filter
        guard let sidebar = self.splitViewItems.first?.viewController as? SidebarController else {
            fatalError("Failed to get sidebar controller")
        }
        
        self.bind(NSBindingName("sidebarFilter"), to: sidebar,
                  withKeyPath: #keyPath(SidebarController.filter),
                  options: nil)
        
        if let window = self.view.window, let toolbar = window.toolbar {
            if !toolbar.items.contains(where: { $0.itemIdentifier == .sidebarTrackingSeparatorItemIdentifier }) {
                toolbar.delegate = self
                toolbar.insertItem(withItemIdentifier: .sidebarTrackingSeparatorItemIdentifier, at: 1)
            }
        }
    }
    
    // MARK: - Toolbar delegate
    /**
     * Creates toolbar items.
     *
     * In this implementation, we only create the sidebar tracking space item.
     */
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .sidebarTrackingSeparatorItemIdentifier {
            return NSTrackingSeparatorToolbarItem(identifier: .sidebarTrackingSeparatorItemIdentifier,
                                                  splitView: self.splitView,
                                                  dividerIndex: 0)
        }
        
        // not supported
        return nil
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
