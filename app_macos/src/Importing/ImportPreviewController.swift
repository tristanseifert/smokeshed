//
//  ImportPreviewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Cocoa
import OSLog

/**
 * Handles displaying a grid of images to the user from an import source.
 */
class ImportPreviewController: NSViewController, NSCollectionViewDataSource {
    fileprivate static var logger = Logger(subsystem: Bundle(for: ImportPreviewController.self).bundleIdentifier!,
                                         category: "ImportPreviewController")
    
    /// Grid view in which the thumbs from the device are shown
    @IBOutlet private var collection: NSCollectionView!
    
    /// Import source providing the images displayed
    override var representedObject: Any? {
        didSet {
            self.updateSource()
        }
    }
    
    // MARK: - Configuration
    /// Whether duplicate images are hidden
    @objc dynamic private var hideDuplicates: Bool = false
    
    /**
     * Performs initial setup of the collection view.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // register our cell class
        let nib = NSNib(nibNamed: "ImportPreviewCollectionItem", bundle: nil)
        self.collection.register(nib, forItemWithIdentifier: .importPreviewItem)
    }
    
    // MARK: - Source handling
    /// Images retrieved from the import source
    private var sourceImages: [ImportSourceItem] = []
    
    /**
     * Updates the UI to reflect the state of a new source.
     */
    private func updateSource() {
        Self.logger.trace("Updating source: \(String(describing: self.representedObject))")
        
        // clean up previous source state
        self.sourceImages.removeAll()
        
        // set up state for new source
        if let source = self.representedObject as? ImportSource {
            do {
                self.sourceImages = try source.getImages()
            } catch {
                Self.logger.error("Failed to get images from source \(String(describing: source)): \(error.localizedDescription)")
            }
        }
        
        // update the UI
        self.collection.reloadData()
    }
    
    // MARK: Collection data source
    /**
     * Returns the number of items to display.
     */
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.sourceImages.count
    }
    
    /**
     * Generates a preview cell for the given image.
     */
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let cell = collectionView.makeItem(withIdentifier: .importPreviewItem,
                                                 for: indexPath) as? ImportPreviewCollectionItem else {
            fatalError()
        }
        cell.item = self.sourceImages[indexPath.item]
        
        return cell
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Image collection view section header
    static let importPreviewItem = NSUserInterfaceItemIdentifier("importPreviewItem")
}
