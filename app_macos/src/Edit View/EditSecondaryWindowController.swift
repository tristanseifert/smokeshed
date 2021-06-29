//
//  EditSecondaryWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200712.
//

import Cocoa

class EditSecondaryWindowController: NSWindowController {
    // MARK: - State restoration
    private struct StateKeys {
        /// Window location (frame)
        static let frame = "EditSecondaryWindowController.window.frame"
    }
    
    /**
     * Save the frame of the window.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        
        if let frame = self.window?.frame {
            coder.encode(frame, forKey: StateKeys.frame)
        }
    }
    
    /**
     * Restores the window's frame.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        
        let frame = coder.decodeRect(forKey: StateKeys.frame)
        
        if frame != .zero, let minSize = self.window?.minSize, frame.width > minSize.width,
           frame.height > minSize.height {
            // TODO: handle if it's off screen?
            self.window?.setFrame(frame, display: false)
        }
    }
}
