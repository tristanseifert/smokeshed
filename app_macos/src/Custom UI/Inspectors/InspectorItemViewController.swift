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
        
        // done!
        self.view = wrapper
    }
    
    /**
     * Toggles the visibility of the content view controller.
     */
    internal func toggleContent(_ sender: Any?) {
        self.contentVisible.toggle()
        
        if self.contentVisible {
            self.content.view.isHidden = false
            
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                self.contentHeightConstraint.animator().constant = 200
                self.content.view.animator().alphaValue = 1
            }, completionHandler: {
                
            })
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                self.contentHeightConstraint.animator().constant = 0
                self.content.view.animator().alphaValue = 0
            }, completionHandler: {
                self.content.view.isHidden = true
            })
        }
    }
}
