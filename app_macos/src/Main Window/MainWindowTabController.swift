//
//  MainWindowTabController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import CocoaLumberjackSwift

/**
 * Main window content tab controller: this provides an easy way to get at the represented object of the
 * currently selected controller.
 */
class MainWindowTabController: NSTabViewController, NSMenuItemValidation {
    /// Observers placed on previous tab items
    var kvos: [NSKeyValueObservation] = []
    
    /**
     * When an item is about to be selected, remove the old observers and add new ones on the object
     * of the new view controller.
     */
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {        
        // remove old observers
        self.kvos.removeAll()
        
        // create a new observer
        let vc = tabViewItem!.viewController!
        
        let obs = vc.observe(\NSViewController.representedObject) { (controller, change) in
            self.representedObject = controller.representedObject
        }
        self.kvos.append(obs)
        
        self.representedObject = vc.representedObject
        
        // perform superclass implementation
        super.tabView(tabView, willSelect: tabViewItem)
    }
    
    // MARK: - Child message handling
    /**
     * Forward messages to child controllers as needed
     */
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        // check each child
        if let child = self.tabViewItems[self.selectedTabViewItemIndex].viewController {
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
        if let child = self.tabViewItems[self.selectedTabViewItemIndex].viewController {
            // does it support menu item validation?
            guard let validator = child as? NSMenuItemValidation else {
                return false
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
