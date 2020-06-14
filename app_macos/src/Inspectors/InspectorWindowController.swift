//
//  InspectorWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200612.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Provides the primary image inspector controller, which automatically binds to the selected images.
 */
class InspectorWindowController: NSWindowController {
    /// Selected object of the active controller
    @objc dynamic public var selection: Any? = nil {
        didSet{
            // update metadata data source
            if let array = selection as? [Image] {
                self.metadataSource.image = array.first
            } else {
                self.metadataSource.image = nil
            }
        }
    }

    /// Metadata data source for outline view
    private var metadataSource = MetadataOutlineDataSource()
    /// Outline view to show raw image metadata
    @IBOutlet private var metadataOutline: NSOutlineView! = nil

    // MARK: - Initialization
    override var windowNibName: NSNib.Name? {
        return "InspectorWindowController"
    }

    /**
     * Finishes setting up the UI.
     */
    override func windowDidLoad() {
        super.windowDidLoad()

        // set up metadata source
        self.metadataSource.view = self.metadataOutline
        self.metadataOutline.dataSource = self.metadataSource
        self.metadataOutline.delegate = self.metadataSource
    }

    // MARK: - State restoration
    struct StateKeys {
        /// Screen location of the window
        static let frame = "InspectorWindowController.frame"
    }

    /**
     * Encodes the current state of the inspector.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // store the window frame
        coder.encode(self.window!.frameDescriptor, forKey: StateKeys.frame)
    }

    /**
     * Decodes the state of the inspector.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)

        // restore window position
        if let desc = coder.decodeObject(forKey: StateKeys.frame) as? String {
            self.window!.setFrame(from: desc)
        }
    }
}
