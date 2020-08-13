//
//  InspectorItemViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

import CocoaLumberjackSwift

/**
 * This view controller wraps another view controller (the actual content of an inspector item) and adds a "title bar" that allows the item to
 * be expanded/collapsed and dragged.
 */
class InspectorItemViewController: NSViewController {
    /// Whether content is visible or not
    private(set) public var contentVisible: Bool = true
    
    // MARK: - Initialization
    /// Content view controller
    private var content: NSViewController!
    
    /// Height of the content view, prior to collapsing
    private var restoreContentHeight: CGFloat = 0
    
    /// Image containing snapshot of the sidebar view as it's collapsing
    private var collapseSnapshot: NSImage? = nil
    /// Image view in which the collapse snapshot is shown
    private var collapseSnapshotView: NSImageView! = nil
    /// Constraint for the height of the content
    private var contentHeightConstraint: NSLayoutConstraint!
    
    /**
     * Instantiates a new inspector view controller.
     */
    init(content: NSViewController, title: String) {
        super.init(nibName: nil, bundle: nil)
        
        self.content = content
        self.addChild(content)
        
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View lifecycle
    /**
     * Creates the split view that houses the content of the view controller.
     */
    override func loadView() {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        
        // add title bar
        let titleBar = InspectorItemTitleBar(item: self)
        wrapper.addSubview(titleBar)
        
        // constraints for title bar
        let titleTop = NSLayoutConstraint(item: titleBar, attribute: .top,
                                          relatedBy: .equal, toItem: wrapper,
                                          attribute: .top, multiplier: 1, constant: 0)
        titleTop.priority = .required
        titleTop.isActive = true
        
        let titleLeading = NSLayoutConstraint(item: titleBar, attribute: .leading,
                                              relatedBy: .equal, toItem: wrapper,
                                              attribute: .leading, multiplier: 1, constant: 0)
        titleLeading.priority = .required
        titleLeading.isActive = true
        
        let titleTrailing = NSLayoutConstraint(item: titleBar, attribute: .trailing,
                                               relatedBy: .equal, toItem: wrapper,
                                               attribute: .trailing, multiplier: 1, constant: 0)
        titleTrailing.priority = .required
        titleTrailing.isActive = true
        
        // add content view
        self.content.view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(self.content.view)
        
        // then the content controller (constrain it to its desired height)
//        let desiredHeight = self.content.preferredContentSize.height
        let desiredHeight = CGFloat(200)
        
        let contentHeight = NSLayoutConstraint(item: self.content.view, attribute: .height,
                                               relatedBy: .equal, toItem: nil,
                                               attribute: .notAnAttribute, multiplier: 0,
                                               constant: desiredHeight)
        contentHeight.priority = .required
        contentHeight.isActive = true
        self.contentHeightConstraint = contentHeight
        
        // content view directly under title bar
        let contentTop = NSLayoutConstraint(item: self.content.view, attribute: .top,
                                            relatedBy: .equal, toItem: titleBar, attribute: .bottom,
                                            multiplier: 1, constant: 0)
        contentTop.priority = .required
        contentTop.isActive = true
        
        // content view fills the width
        let contentLeading = NSLayoutConstraint(item: self.content.view, attribute: .leading,
                                                relatedBy: .equal, toItem: wrapper,
                                                attribute: .leading, multiplier: 1, constant: 0)
        contentLeading.priority = .required
        contentLeading.isActive = true
        
        let contentTrailing = NSLayoutConstraint(item: self.content.view, attribute: .trailing,
                                                 relatedBy: .equal, toItem: wrapper,
                                                 attribute: .trailing, multiplier: 1, constant: 0)
        contentTrailing.priority = .required
        contentTrailing.isActive = true
        
        // last, pin the bottom of the content to the container
        let contentBottom = NSLayoutConstraint(item: self.content.view, attribute: .bottom,
                                               relatedBy: .equal, toItem: wrapper,
                                               attribute: .bottom, multiplier: 1, constant: 0)
        contentBottom.priority = .required
        contentBottom.isActive = true
        
        // create the image view that covers everything (for the snapshot)
        self.collapseSnapshotView = NSImageView()
        self.collapseSnapshotView.imageAlignment = .alignTopLeft
        self.collapseSnapshotView.imageScaling = .scaleNone
        self.collapseSnapshotView.isEditable = false
        self.collapseSnapshotView.imageFrameStyle = .none
        self.collapseSnapshotView.isHidden = true
        
        wrapper.addSubview(self.collapseSnapshotView)
        
        // done!
        self.view = wrapper
    }
    
    /**
     * Toggles the visibility of the content view controller.
     */
    internal func toggleContent(_ sender: Any?) {
        self.contentVisible.toggle()
        
        if self.contentVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                self.collapseSnapshotView.animator().bounds.size.height = self.restoreContentHeight
                self.contentHeightConstraint.animator().constant = self.restoreContentHeight
                
                self.collapseSnapshotView?.animator().alphaValue = 1
            }, completionHandler: {
                self.collapseSnapshotView?.isHidden = true
                self.content.view.isHidden = false
                
                self.collapseSnapshot = nil
            })
        } else {
            // create the snapshot image and prepare the image view
            self.makeContentSnapshot()
            self.collapseSnapshotView?.image = self.collapseSnapshot
            
            self.collapseSnapshotView?.isHidden = false
            self.content.view.isHidden = true
            
            self.restoreContentHeight = self.content.view.frame.height
            
            self.collapseSnapshotView.frame = self.content.view.frame
            self.collapseSnapshotView.bounds.size.height = self.restoreContentHeight
            
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                self.collapseSnapshotView.animator().bounds.size.height = 0
                self.contentHeightConstraint.animator().constant = 0
                
                self.collapseSnapshotView.animator().alphaValue = 0
            }, completionHandler: {
                
            })
        }
    }
    
    /**
     * Takes a snapshot of the content view. This is used to have an image representation that's used during the collapse animation.
     */
    private func makeContentSnapshot() {
        guard let rep = self.content.view.bitmapImageRepForCachingDisplay(in: self.content.view.visibleRect) else {
            DDLogError("Failed to create snapshot for \(self.content.view) (\(self)")
            self.collapseSnapshot = nil
            return
        }
        
        self.content.view.cacheDisplay(in: self.content.view.visibleRect, to: rep)
        
        // create the image
        let image = NSImage(size: self.content.view.visibleRect.size)
        image.addRepresentation(rep)
        
        self.collapseSnapshot = image
    }
}
