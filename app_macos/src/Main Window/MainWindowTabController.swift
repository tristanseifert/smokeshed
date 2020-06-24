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
class MainWindowTabController: NSTabViewController {
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
}
