//
//  ImportViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200827.
//

import Cocoa
import ImageCaptureCore

import Smokeshop
import CocoaLumberjackSwift

/**
 * Drives the main import window UI, enumerating connected devices.
 */
class ImportViewController: NSViewController {
    /// Whether we're currently enumerating devices (used to drive UI)
    @objc dynamic internal var enumeratingDevices: Bool = false
    
    // MARK: - Initialization
    /// Sidebar controller
    private var sidebar: ImportSidebarController! = nil
    /// Preview controller
    private var preview: ImportPreviewController! = nil
    
    /// Whether late initialization has taken place yet
    private var needsLateInit: Bool = true
    
    /**
     * Finds the sidebar and preview controllers
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        if self.needsLateInit {
            self.doLateInit()
            self.needsLateInit = false
        }
    }
    
    /**
     * One-time late initalization. This has to be called from `viewWillAppear()` since we rely on some child view controllers having
     * been loaded from the storyboard.
     */
    private func doLateInit() {
        // find the sidebar and preview controllers
        if let split = self.children.first as? NSSplitViewController {
            for child in split.splitViewItems.compactMap({$0.viewController}) {
                if let sidebar = child as? ImportSidebarController {
                    self.sidebar = sidebar
                }
                else if let preview = child as? ImportPreviewController {
                    self.preview = preview
                }
            }
        }
        
        // bind sidebar selection
        self.preview.bind(NSBindingName(rawValue: "representedObject"), to: self.sidebar!,
                          withKeyPath: #keyPath(ImportSidebarController.representedObject),
                          options: nil)
    }
    
    
    // MARK: - UI Actions
    /**
     * Import button action
     */
    @IBAction private func importAction(_ sender: Any) {
        
    }
}
