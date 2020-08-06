//
//  EditViewDebugWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200805.
//

import Cocoa

class EditViewDebugWindowController: NSWindowController {
    /// Edit view
    internal var editView: ImageRenderView! = nil {
        didSet {
            if let content = self.contentViewController as? EditViewDebugViewController {
                content.editView = self.editView
            }
        }
    }

}
