//
//  EditSidebarWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200820.
//

import Cocoa
import OSLog

class EditSidebarWindowController: NSWindowController {
    fileprivate static var logger = Logger(subsystem: Bundle(for: EditSidebarWindowController.self).bundleIdentifier!,
                                         category: "EditSidebarWindowController")
    
    // MARK: - State restoration
    private struct StateKeys {
        /// Window location (frame)
        static let frame = "EditSidebarWindowController.window.frame"
    }
    
    /// Inspector container
    private var inspector: InspectorContainerViewController!
    
    /// Notification observers to be removed on dealloc
    private var noteObs: [NSObjectProtocol] = []
    
    /// Edit view controller this sidebar belongs to
    internal var editView: EditViewController! = nil {
        didSet {
            let c = NotificationCenter.default
            
            // remove old observations
            self.noteObs.forEach(c.removeObserver)
            self.noteObs.removeAll()
            
            // observe rendering on the content view
            if let view = self.editView?.renderView {
                self.noteObs.append(c.addObserver(forName: .renderViewUpdatedImage,
                                                  object: view, queue: nil,
                                                  using: self.imageDidRender(_:)))
            }
        }
    }
    
    /**
     * Initializes the views for the inspector.
     */
    override func windowDidLoad() {
        // create inspector
        self.inspector = InspectorContainerViewController()
        self.window?.contentViewController = self.inspector
        
        // create item for histogram
        let histoVc = self.storyboard!.instantiateController(withIdentifier: "inspector.histogram") as! EditSidebarHistogramViewController
        
        let histoItem = InspectorItemViewController(content: histoVc, title: "Histogram")
        self.inspector.addItem(histoItem)
        
        
        // create a bullshit item
        guard let sb = self.storyboard,
              let vc = sb.instantiateController(withIdentifier: "bitch") as? NSViewController else {
            Self.logger.error("Failed to instantiate controller")
            return
        }

        let item = InspectorItemViewController(content: vc, title: "bitch controller")
        self.inspector.addItem(item)
    }
    
    /**
     * Removes all notification observers.
     */
    deinit {
        self.noteObs.forEach(NotificationCenter.default.removeObserver)
    }
    
    // MARK: - State restoration
    /**
     * Encodes the size and position of the window.
     */
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
    
        if self.window?.isVisible ?? false {
            Self.logger.trace("Encoding edit controls window size: \(self.window!.frame.debugDescription)")
            coder.encode(self.window!.frame, forKey: StateKeys.frame)
        }
    }
    
    /**
     * Restores the size/position of the window.
     */
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        
        // restore window position
        let frame = coder.decodeRect(forKey: StateKeys.frame)
        Self.logger.trace("Restored edit controls window size: \(frame.debugDescription)")
        
        if frame != .zero, let minSize = self.window?.minSize, frame.width > minSize.width,
           frame.height > minSize.height {
            self.window?.setFrame(frame, display: false)
        }
    }
    
    // MARK: - Edit view sync
    /**
     * The edit view that this sidebar belongs to has updated its contents texture, because the render service has finished rendering
     * new data.
     */
    private func imageDidRender(_ note: Notification) {
        Self.logger.trace("Render view rendered: \(note)")
    
        // call into all inspector items
        self.inspector.items.forEach {
            if let sidebarItem = $0.content as? EditSidebarItem {
                DispatchQueue.main.async {
                    sidebarItem.imageRendered(note)
                }
            }
        }
    }
}
