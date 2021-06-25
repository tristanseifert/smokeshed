//
//  EditSidebarHistogramViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa
import Metal
import CocoaLumberjackSwift
import Waterpipe
import Smokeshop

/**
 * Handles displaying the histogram in the sidebar of the edit view
 */
class EditSidebarHistogramViewController: NSViewController, EditSidebarItem {
    /// Most recently used Metal device
    private var device: MTLDevice? = nil
    /// Histogram calculator
    private var histographer: HistogramCalculator!

    /// Histogram view
    @IBOutlet private var histoView: HistogramView!
    /// Box showing the "calculating histogram" loading indicator
    @IBOutlet private var calculatingOverlay: NSBox!
    /// Activity indicator for the histogram progress
    @IBOutlet private var calculatingProgressIndicator: NSProgressIndicator!
    
    // MARK: - View lifecycle
    /// Notification observers to be removed on dealloc
    private var noteObs: [NSObjectProtocol] = []
    
    /**
     * Adds an observer for the "image view rendered" notification, such that we can update the histogram as needed.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // default size
        self.preferredContentSize = NSSize(width: 320, height: 194)
        
        // hide the "calculating histogram" box
        self.calculatingOverlay.isHidden = true
        self.calculatingOverlay.alphaValue = 0
    }
    
    /**
     * Removes all notification observers.
     */
    deinit {
        self.noteObs.forEach(NotificationCenter.default.removeObserver)
    }
    
    // MARK: - Notifications
    /**
     * The actively selected image changed changed
     */
    func imageChanged(_ to: Image?) {
        
    }
    
    /**
     * Image view has updated, so update the histogram.
     */
    func imageRendered(_ note: Notification?) {
        if let note = note {
            self.imageDidRender(note)
        }
    }
    
    // MARK: - Edit view sync
    /**
     * The edit view that we observe has updated its image. We should calculate a histogram based on it
     */
    private func imageDidRender(_ note: Notification) {
        guard let image = note.userInfo?["image"] as? TiledImage else {
            self.histoView.setHistogramData(nil)
            return
        }
        
        // show the calculation overlay
        self.calculatingOverlay.isHidden = false
        self.calculatingProgressIndicator.startAnimation(self)
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          
            self.calculatingOverlay.animator().alphaValue = 1
        })
        let animateOutAfter = DispatchTime.now() + .milliseconds(200)
        
        // perform work on background queue
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async {
            do {
                try self.updateHistogram(for: image)
            } catch {
                DDLogError("Failed to update histogram: \(error)")
            }
            
            // hide the calculation overlay (TODO: could be optimized)
            DispatchQueue.main.asyncAfter(deadline: animateOutAfter, execute: {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                  
                    self.calculatingOverlay.animator().alphaValue = 0
                }, completionHandler: {
                    self.calculatingOverlay.isHidden = true
                    self.calculatingProgressIndicator.stopAnimation(self)
                })
            })
        }
    }
    
    /**
     * Calculates the histogram for the given image, and updates the histogram view with it.
     *
     * - Note: This should be called on a background queue.
     */
    private func updateHistogram(for image: TiledImage) throws {
        // allocate new Metal resources if device differs
        if self.device == nil || self.device?.registryID != image.device.registryID {
            try self.allocMetalResources(image.device)
        }
        
        // calculate that shit
        let histogram = try self.histographer.calculateHistogram(image, buckets: 256)
        self.histoView.setHistogramData(histogram)
    }
    
    /**
     * Allocates Metal resources for the given device.
     */
    private func allocMetalResources(_ device: MTLDevice) throws {
        self.device = device
        self.histographer = try HistogramCalculator(device: device)
    }
}
