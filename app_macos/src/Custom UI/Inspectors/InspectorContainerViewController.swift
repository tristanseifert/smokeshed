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
    
    /// Layout constraint for the width of the stack view
    private var stackWidthConstraint: NSLayoutConstraint!
    
    /**
     * Initializes the content view: a scroll view, which in turn contains a vertical stack view as its document view.
     */
    override func loadView() {
        let wrapper = NSView()
//        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // set up content stack view
        self.stack = NSStackView()
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        
        self.stack.orientation = .vertical
        self.stack.alignment = .leading
        self.stack.distribution = .fillProportionally
        
        self.stack.detachesHiddenViews = true
        self.stack.spacing = 0
        
        self.stack.setHuggingPriority(.defaultLow, for: .horizontal)
        self.stack.setHuggingPriority(.defaultHigh, for: .vertical)
        
        // create a wrapper for the stack view]
        let stackWrapper = NSView()
        stackWrapper.translatesAutoresizingMaskIntoConstraints = false
        
        stackWrapper.addSubview(self.stack)
        
        NSLayoutConstraint.activate([
            self.stack.topAnchor.constraint(equalTo: stackWrapper.topAnchor),
            self.stack.bottomAnchor.constraint(equalTo: stackWrapper.bottomAnchor),
            self.stack.leadingAnchor.constraint(equalTo: stackWrapper.leadingAnchor),
            self.stack.trailingAnchor.constraint(equalTo: stackWrapper.trailingAnchor)
        ])
        
        // create a width constraint for the stack view
        let width = NSLayoutConstraint(item: self.stack!, attribute: .width, relatedBy: .equal,
                                       toItem: nil, attribute: .notAnAttribute, multiplier: 0,
                                       constant: 0)
        width.priority = .defaultHigh
        width.isActive = true
        
        self.stackWidthConstraint = width
        
        // then, create the scroll view
        self.scroll = NSScrollView()
        self.scroll.translatesAutoresizingMaskIntoConstraints = false
        
        self.scroll.hasHorizontalScroller = false
        self.scroll.hasVerticalScroller = true
        
        self.scroll.contentView = FlippedClipView()
        self.scroll.documentView = stackWrapper
        self.scroll.drawsBackground = false
        
        wrapper.addSubview(self.scroll)
        
        // observe the scroll view's frame to update the stack view width
        self.scroll.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: self.scroll, queue: OperationQueue.main,
                                               using: self.scrollViewFrameDidChange(_:))
        
        // line up the scroll view
        NSLayoutConstraint.activate([
            self.scroll.topAnchor.constraint(equalTo: wrapper.topAnchor),
            self.scroll.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            self.scroll.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            self.scroll.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        
        // done!
        self.view = wrapper
    }
    
    /**
     * Once the frame of the scroll view has changed, we need to update the content view to the appropriate width.
     */
    private func scrollViewFrameDidChange(_ note: Notification?) {
        let width = self.scroll.frame.width
        self.stackWidthConstraint.constant = width
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
        let width = NSLayoutConstraint(item: item.view, attribute: .width, relatedBy: .equal,
                                       toItem: self.stack, attribute: .width, multiplier: 1,
                                       constant: 0)
        width.priority = .dragThatCanResizeWindow
        width.identifier = "InspectorItemWidth"
        width.isActive = true
    }
}
