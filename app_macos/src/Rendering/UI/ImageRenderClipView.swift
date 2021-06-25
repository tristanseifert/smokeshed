//
//  ImageRenderClipView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200807.
//

import Cocoa

/**
 * This clip view subclass implements drag scrolling for the image view.
 */
internal class ImageRenderClipView: NSClipView {
    private var clickPoint: NSPoint!
    private var originalOrigin: NSPoint!

    /**
     * Set the document cursor to the grabby hand type.
     */
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.documentCursor = NSCursor.openHand
    }
    
    /**
     * Begin the drag scrolling event on mouse down.
     */
    override func mouseDown(with event: NSEvent) {
        clickPoint = event.locationInWindow
        originalOrigin = bounds.origin
        
        self.documentCursor = NSCursor.closedHand
    }

    /**
     * As the mouse is dragged, move the content.
     */
    override func mouseDragged(with event: NSEvent) {
        // Account for a magnified parent scrollview.
        let scale = self.enclosingScrollView?.magnification ?? 1.0
        let newPoint = event.locationInWindow
        let newOrigin = NSPoint(x: originalOrigin.x + (clickPoint.x - newPoint.x) / scale,
                                y: originalOrigin.y + (clickPoint.y - newPoint.y) / scale)
        let constrainedRect = constrainBoundsRect(NSRect(origin: newOrigin, size: bounds.size))
        self.scroll(to: constrainedRect.origin)
        self.superview?.reflectScrolledClipView(self)
    }

    /**
     * End the drag scrolling session.
     */
    override func mouseUp(with event: NSEvent) {
        clickPoint = nil
        
        self.documentCursor  = NSCursor.openHand
    }
}
