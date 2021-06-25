//
//  EditViewDebugViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200805.
//

import Cocoa

import CocoaLumberjackSwift

/**
 * Provides debugging controls for the edit view.
 */
internal class EditViewDebugViewController: NSViewController {
    /// Edit view being observed for changes
    internal var editView: ImageRenderView! = nil {
        didSet {
            // copy viewport from set edit view
            if let view = self.editView {
                self.viewport = view.viewport
            }
        }
    }
    
    // MARK: - Viewport
    /// Viewport
    internal var viewport: CGRect {
        get {
            return CGRect(origin: CGPoint(x: self.originX, y: self.originY),
                            size: CGSize(width: self.sizeW, height: self.sizeH))
        }
        set {
            DispatchQueue.main.async {
                self.originX = newValue.origin.x
                self.originY = newValue.origin.y
                self.sizeW = newValue.size.width
                self.sizeH = newValue.size.height
            }
        }
    }
    
    /// Origin (X)
    @objc dynamic private var originX: CGFloat = 0
    /// Origin (Y)
    @objc dynamic private var originY: CGFloat = 0
    /// Size (width)
    @objc dynamic private var sizeW: CGFloat = 0
    /// Size (height)
    @objc dynamic private var sizeH: CGFloat = 0

    /**
     * Updates the viewport of the render view.
     */
    @IBAction func setViewport(_ sender: Any?) {
        DDLogVerbose("Updating viewport to \(self.viewport)")
        self.editView.viewport = self.viewport
    }
}
