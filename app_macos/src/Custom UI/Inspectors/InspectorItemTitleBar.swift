//
//  InspectorItemTitleBar.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa
import CocoaLumberjackSwift

/**
 * Renders the title bar for an inspector item.
 */
class InspectorItemTitleBar: NSView {
    /// Displayed title
    @objc dynamic var title: String = "<no title>" {
        didSet {
            self.needsDisplay = true
        }
    }
    
    /// Height of the title bar
    static let height: CGFloat = 24
    
    // MARK: - Initialization
    /// Item controller to which the title bar belongs
    private weak var controller: InspectorItemViewController? = nil
    
    /// Tracking area that observes the cursor entering the view
    private var cursorTracking: NSTrackingArea!
    /// Label for the title
    private var titleLabel: NSTextField!
    
    init(item: InspectorItemViewController) {
        super.init(frame: .zero)
        self.controller = item
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        
        // set up a tracking area to update the cursor
        self.cursorTracking = NSTrackingArea(rect: .zero,
                                             options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate],
                                             owner: self, userInfo: nil)
        self.addTrackingArea(self.cursorTracking)
        
        // add a height constraint
        let c = NSLayoutConstraint(item: self, attribute: .height, relatedBy: .equal, toItem: nil,
                                   attribute: .notAnAttribute, multiplier: 0,
                                   constant: Self.height)
        c.priority = .required
        self.addConstraint(c)
        
        // create the title text field
        self.titleLabel = NSTextField()
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        self.titleLabel.isBezeled = false
        self.titleLabel.isBordered = false
        self.titleLabel.drawsBackground = false
        self.titleLabel.isEditable = false
        self.titleLabel.isSelectable = false
        
        self.titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.titleLabel.textColor = NSColor.labelColor
        
        // bind it to our parent's title
        self.titleLabel.stringValue = "<no title>"
        self.titleLabel.bind(NSBindingName("stringValue"), to: item, withKeyPath: "title", options: nil)
        
        self.addSubview(self.titleLabel)
        
        // set up constraints for title label
        let leading = NSLayoutConstraint(item: self.titleLabel!, attribute: .leading,
                                         relatedBy: .equal, toItem: self, attribute: .leading,
                                         multiplier: 1, constant: 5)
        leading.priority = .required
        leading.isActive = true
        
        let trailing = NSLayoutConstraint(item: self.titleLabel!, attribute: .trailing,
                                          relatedBy: .greaterThanOrEqual, toItem: self,
                                          attribute: .trailing, multiplier: 1, constant: -5)
        trailing.priority = .defaultLow
//        trailing.isActive = true

        let centerY = NSLayoutConstraint(item: self.titleLabel!, attribute: .centerY,
                                         relatedBy: .equal, toItem: self, attribute: .centerY,
                                         multiplier: 1, constant: -1)
        centerY.priority = .required
        centerY.isActive = true
        
        // update initial tooltip
        self.updateTooltip()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Drawing
    /// Whether we're using the active drawing style or not
    private var activeStyle: Bool = false
    /// Whether the view is expanded: if so, the bottom separator is drawn.
    private var expandedStyle: Bool = true
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // fill background
        if self.activeStyle {
            NSColor(named: "InspectorItemTitleBarBackground")?.setFill()
        } else {
            NSColor(named: "InspectorItemActiveTitleBarBackground")?.setFill()
        }
        self.bounds.fill()
        
        // draw top and bottom separator
        NSColor(named: "InspectorItemTitleBarBorder")?.setStroke()
        
        let top = NSBezierPath(rect: NSRect(x: 0, y: self.bounds.height+0.5,
                                            width: self.bounds.width, height: 1))
        top.stroke()
        
        if self.expandedStyle {
            let bottom = NSBezierPath(rect: NSRect(x: 0, y: -0.5, width: self.bounds.width,
                                                   height: 1))
            bottom.stroke()
        }
    }
    
    // MARK: - Events
    /**
     * On mouse down, start using the active style of drawing.
     */
    override func mouseDown(with event: NSEvent) {
        self.activeStyle = true
        self.needsDisplay = true
    }
    
    /**
     * On mouse up, restore the regular appearance and invoke the event.
     */
    override func mouseUp(with event: NSEvent) {
        self.activeStyle = false
        self.needsDisplay = true
        
        if self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
            self.controller?.toggleContent(self)
            self.expandedStyle = self.controller?.contentVisible ?? false
            self.updateTooltip()
        }
    }
    
    /**
     * Sets the cursor to the pointer (to indicate the title bar can collapse/expand)
     */
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    // MARK: - Helpers
    /**
     * Updates the tool tip of the title bar.
     */
    private func updateTooltip() {
        if self.controller?.contentVisible ?? false {
            self.toolTip = String(format: Self.localized("title.tooltip.expanded"),
                                  self.titleLabel.stringValue)
        } else {
            self.toolTip = String(format: Self.localized("title.tooltip.collapsed"),
                                  self.titleLabel.stringValue)
        }
    }
    
    /**
     * Returns a localized string for the inspector items.
     */
    internal class func localized(_ key: String) -> String {
        return Bundle.main.localizedString(forKey: key, value: nil, table: "InspectorItem")
    }
}
