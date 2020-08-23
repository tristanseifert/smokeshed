//
//  InspectorContainerViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

/**
 * Serves as a container for multiple inspector items, each of which has its own title bar and content controller. Inspector items can be
 * torn off into their own windows, if desired.
 */
class InspectorContainerViewController: NSViewController {
    /// Inspector items currently in this container
    @objc dynamic private(set) internal var items: [InspectorItemViewController] = []
    
    // MARK: - View lifecycle
    /// Scroll view
    private var scroll: NSScrollView!
    /// Content stack view
    private var stack: NSStackView!
    
    /**
     * Initializes the content view: a scroll view, which in turn contains a vertical stack view as its document view.
     */
    override func loadView() {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // set up content stack view
        self.stack = NSStackView()
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        
        self.stack.orientation = .vertical
        self.stack.alignment = .leading
        self.stack.distribution = .fill
        
        self.stack.detachesHiddenViews = true
        self.stack.spacing = 0
        
        self.stack.setHuggingPriority(.defaultLow, for: .horizontal)
        self.stack.setHuggingPriority(.defaultHigh, for: .vertical)
        
        // then, create the scroll view
        self.scroll = NSScrollView()
        self.scroll.translatesAutoresizingMaskIntoConstraints = false
        
        self.scroll.contentView = FlippedClipView()
        self.scroll.documentView = self.stack
        self.scroll.drawsBackground = false
        
        wrapper.addSubview(self.scroll)
        
        // line up the scroll view
        NSLayoutConstraint(item: self.scroll!, attribute: .top, relatedBy: .equal, toItem: wrapper,
                           attribute: .top, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: self.scroll!, attribute: .bottom, relatedBy: .equal,
                           toItem: wrapper, attribute: .bottom, multiplier: 1,
                           constant: 0).isActive = true
        
        NSLayoutConstraint(item: self.scroll!, attribute: .trailing, relatedBy: .equal,
                toItem: wrapper, attribute: .trailing, multiplier: 1,
                constant: 0).isActive = true
        NSLayoutConstraint(item: self.scroll!, attribute: .leading, relatedBy: .equal,
                toItem: wrapper, attribute: .leading, multiplier: 1,
                constant: 0).isActive = true
        
        
        // update constraints so the stack fills the scroll view
        let width = NSLayoutConstraint(item: self.stack!, attribute: .width, relatedBy: .equal,
                                       toItem: self.scroll!, attribute: .width, multiplier: 1,
                                       constant: 0)
        width.priority = .defaultHigh
        width.isActive = true
        
        // done!
        self.view = wrapper
    }
    
    // MARK: - Item management
    /**
     * Inserts an item at the end of the list of items.
     */
    public func addItem(_ item: InspectorItemViewController) {
        self.items.append(item)
        self.stack.addView(item.view, in: .center)
    
        self.addedItem(item)
    }
    
    /**
     * Inserts an item at the given index into the list of items.
     */
    public func insertItem(_ item: InspectorItemViewController, at: Int) {
        self.items.insert(item, at: at)
        self.stack.insertView(item.view, at: at, in: .center)
        
        self.addedItem(item)
    }
    
    /**
     * Removes an item, if it exists, from the view.
     */
    public func removeItem(_ item: InspectorItemViewController) {
        if let index = self.items.firstIndex(of: item) {
            self.items.remove(at: index)
            
            // TODO: remove width constraints
            
            self.stack.removeView(item.view)
        }
    }
    
    /**
     * Adds constraints to the view to make sure it's the same width as the inspector.
     */
    private func addedItem(_ item: InspectorItemViewController) {
        NSLayoutConstraint(item: item.view, attribute: .width, relatedBy: .equal, toItem: self.view,
                           attribute: .width, multiplier: 1, constant: 0).isActive = true
    }
}
