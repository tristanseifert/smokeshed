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
    @objc dynamic internal var enumeratingDevices: Bool = true
    
    // MARK: - UI Actions
    /**
     * Import button action
     */
    @IBAction private func importAction(_ sender: Any) {
        
    }
}
