//
//  EditSidebarWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200820.
//

import Cocoa

class EditSidebarWindowController: NSWindowController {
    /// Edit view controller this sidebar belongs to
    internal var editView: EditViewController! = nil {
        didSet {
            // update content view controller
            if let content = self.contentViewController as? EditSidebarViewController {
                content.editView = self.editView
            }
        }
    }
}
