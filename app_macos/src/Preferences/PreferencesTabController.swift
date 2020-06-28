//
//  PreferencesTabController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200627.
//

import Cocoa

/**
 * Tab controller that resizes the containing window to exactly fit a tab view item.
 */
class PreferencesTabController: NSTabViewController {
    /// Cache of sizes for tab view
    private lazy var tabViewSizes: [NSTabViewItem: NSSize] = [:]

    /**
     * When the view appears, ensure that the size of the window is updated to fit.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        let tabViewItem = self.tabViewItems[self.selectedTabViewItemIndex]
        tabView.window?.subtitle = tabViewItem.label
        self.resizeWindowToFit(tabViewItem: tabViewItem, animate: false)
    }
    
    // MARK: - Selection
    /**
     * Resizes a window once a tab item was selected.
     */
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)

        if let tabViewItem = tabViewItem {
            tabView.window?.subtitle = tabViewItem.label
            self.resizeWindowToFit(tabViewItem: tabViewItem,
                                   animate: (tabView.window != nil))
        }
    }

    /**
     * Cache the size of a tab view right as it's about to be selected.
     */
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        
        if let tabViewItem = tabViewItem, let size = tabViewItem.view?.frame.size {
            tabViewSizes[tabViewItem] = size
        }
    }

    /**
     * Resize the enclosing window to fit exactly the currently selected view controller.
     */
    private func resizeWindowToFit(tabViewItem: NSTabViewItem, animate: Bool) {
        guard let size = tabViewSizes[tabViewItem], let window = self.view.window else {
            return
        }

        let contentRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let contentFrame = window.frameRect(forContentRect: contentRect)
        let toolbarHeight = window.frame.size.height - contentFrame.size.height
        let newOrigin = NSPoint(x: window.frame.origin.x, y: window.frame.origin.y + toolbarHeight)
        let newFrame = NSRect(origin: newOrigin, size: contentFrame.size)
        
        window.setFrame(newFrame, display: false, animate: animate)
    }}
