//
//  ImportPreviewCollectionItem.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Cocoa

/**
 * UI for a single import preview image
 */
class ImportPreviewCollectionItem: NSCollectionViewItem {
    /// Image being displayed
    internal var item: ImportSourceItem? = nil {
        didSet {
            self.updateFromItem()
        }
    }
    
    /// Image view for thumbnail
    @IBOutlet private var thumbView: NSImageView!
    
    /// Display name for the image
    @objc dynamic private var displayName: String? = nil
    
    /**
     * Cleans up the UI in prepearation for reuse.
     */
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.thumbView.image = nil
    }
    
    /**
     * Updates the UI with the new item state.
     */
    private func updateFromItem() {
        guard let item = self.item else {
            self.displayName = nil
            return
        }
        
        self.displayName = item.displayName
    }
}
