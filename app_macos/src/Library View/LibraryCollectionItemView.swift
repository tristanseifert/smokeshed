//
//  LibraryCollectionItemView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Cocoa

import Smokeshop

/**
 * Renders a single image in the library view collection. For performance reasons, this is done entirely using
 * CALayers rather than views.
 */
class LibraryCollectionItemView: NSView {
    // MARK: - Layer setup
    /// Ensure the layer is drawn as opaque so we get font smoothing.
    override var isOpaque: Bool {
        return true
    }

    /// Request AppKit uses layers exclusively.
    override var wantsUpdateLayer: Bool {
        return true
    }

    /**
     * Initializes the view's properties for layer rendering.
     */
    private func optimizeForLayer() {
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    /**
     * Sets up the layers that make up the cell view.
     */
    private func setUpLayers() {

    }

    // MARK: - State updating
    /**
     * View is about to appear; finalize the UI prior to display.
     */
    func prepareForDisplay() {

    }

    /**
     * Clears UI state and cancels any outstanding thumb requests.
     */
    override func prepareForReuse() {

    }
}
