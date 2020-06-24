//
//  MainWindowViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import CocoaLumberjackSwift

class MainWindowViewController: NSSplitViewController {
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
}
