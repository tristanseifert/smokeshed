//
//  EditSidebarViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

import CocoaLumberjackSwift

/**
 * View controller subclass for the controls sidebar shown on the right of the edit view.
 */
internal class EditSidebarViewController: NSViewController {
    /// Edit view controller this sidebar belongs to
    internal var editView: EditViewController! = nil

    // MARK: - View Lifecycle
    /// Notification observers to be removed on dealloc
    private var noteObs: [NSObjectProtocol] = []
    
    /// Inspector container
    private var inspector: InspectorContainerViewController!
    /// View that shall contain the inspectors
    @IBOutlet private var inspectorContainer: NSStackView!
    
    /**
     * Initializes the inspectors.
     */
    override func viewDidLoad() {
        let c = NotificationCenter.default
        
        // observe rendering on the content view
        self.noteObs.append(c.addObserver(forName: .renderViewUpdatedImage,
                                          object: self.editView.renderView, queue: nil,
                                          using: self.imageDidRender(_:)))
        
        // create an inspector controller
        self.inspector = InspectorContainerViewController()
        
        self.addChild(self.inspector)
        self.inspectorContainer.addView(self.inspector.view, in: .center)
        
        // set the constraints on it
        let width = NSLayoutConstraint(item: self.inspector.view, attribute: .width,
                                       relatedBy: .equal, toItem: self.inspectorContainer!,
                                       attribute: .width, multiplier: 1, constant: 0)
        width.priority = .defaultHigh
        width.isActive = true
        
        // create a bullshit item
        guard let sb = self.storyboard,
              let vc = sb.instantiateController(withIdentifier: "bitch") as? NSViewController else {
            DDLogError("Failed to instantiate controller")
            return
        }

        let item = InspectorItemViewController(content: vc, title: "bitch controller")
        self.inspector.addItem(item)
    }
    
    // MARK: - Edit view sync
    /**
     * The edit view that this sidebar belongs to has updated its contents texture, because the render service has finished rendering
     * new data.
     */
    private func imageDidRender(_ note: Notification) {
        DDLogVerbose("Render view rendered: \(note)")
    }
}
