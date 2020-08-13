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

/**
 * Handles displaying the histogram in the sidebar of the edit view
 */
class EditSidebarHistogramViewController: NSViewController {
    /// Most recently used Metal device
    private var device: MTLDevice? = nil
    /// Histogram calculator
    private var histographer: HistogramCalculator!

    /// Histogram view
    @IBOutlet private var histoView: HistogramView!
    
    // MARK: - View lifecycle
    /// Notification observers to be removed on dealloc
    private var noteObs: [NSObjectProtocol] = []
    
    /**
     * Adds an observer for the "image view rendered" notification, such that we can update the histogram as needed.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    /**
     * Associates the histogram controller with the given edit sidebar.
     */
    internal func associate(sidebar: EditSidebarViewController) {
        let c = NotificationCenter.default
        self.noteObs.append(c.addObserver(forName: .renderViewUpdatedImage,
                                          object: sidebar.editView.renderView, queue: nil,
                                          using: self.imageDidRender(_:)))
    }
    
    /**
     * Removes all notification observers.
     */
    deinit {
        self.noteObs.forEach(NotificationCenter.default.removeObserver)
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
        
        // perform work on background queue
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async {
            do {
                try self.updateHistogram(for: image)
            } catch {
                DDLogError("Failed to update histogram: \(error)")
            }
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
