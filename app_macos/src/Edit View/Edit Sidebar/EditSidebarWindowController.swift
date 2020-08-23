//
//  EditSidebarWindowController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200820.
//

import Cocoa

import CocoaLumberjackSwift

class EditSidebarWindowController: NSWindowController {
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
            DDLogError("Failed to instantiate controller")
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
    
    // MARK: - Edit view sync
    /**
     * The edit view that this sidebar belongs to has updated its contents texture, because the render service has finished rendering
     * new data.
     */
    private func imageDidRender(_ note: Notification) {
        DDLogVerbose("Render view rendered: \(note)")
    
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
