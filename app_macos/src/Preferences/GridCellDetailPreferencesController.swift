//
//  GridCellDetailPreferencesController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200627.
//

import Cocoa
import OSLog

import Smokeshop

/**
 * Allows editing the detail information shown in the grid cells.
 */
class GridCellDetailPreferencesController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    fileprivate static var logger = Logger(subsystem: Bundle(for: GridCellDetailPreferencesController.self).bundleIdentifier!,
                                         category: "GridCellDetailPreferencesController")
    
    /**
     * Registers the cell types.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // register cell type
        self.grid.register(LibraryCollectionItem.self,
                           forItemWithIdentifier: .libraryCollectionItem)
    }
    
    /**
     * When the view is about to appear, attempt to find the most recently captured image to display.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        // do kind of a hack to get the library
        guard let ad = NSApp.delegate as? AppDelegate,
              let library = ad.library else {
                  Self.logger.error("Failed to get library from app delegate")
            return
        }
        
        // set up fetch request
        let req: NSFetchRequest<Image> = Image.fetchRequest()
        req.fetchLimit = 1
        req.sortDescriptors = [
            NSSortDescriptor(keyPath: \Image.dateCaptured, ascending: false)
        ]
        
        // execute request and update grid if it changed things
        do {
            // get the first result
            let res = try library.store.mainContext.fetch(req)
            self.image = res.first
            
            // update the grid
            self.grid.reloadData()
        } catch {
            Self.logger.error("Failed to fetch image to show in grid cell detail controller: \(error.localizedDescription)")
            self.image = nil
        }
    }
    
    // MARK: - Grid cell example
    /// Collection view in which the preview cell is shown
    @IBOutlet private var grid: NSCollectionView!
    /// Image that's being shown as an example
    private var image: Image?
    
    // MARK: Collection data source
    /**
     * There is only ever a single section.
     */
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    /**
     * Returns the number of items in a given section; we always only show a single cell.
     */
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }
    
    /**
     * Generates an example cell with the demo image to display.
     */
    func collectionView(_ view: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        let cell = view.makeItem(withIdentifier: .libraryCollectionItem,
                                 for: path) as! LibraryCollectionItem
        
        cell.isEditable = false
        cell.sequenceNumber = (path[1] + 1)
        cell.representedObject = self.image

        return cell
    }
    
    /**
     *All items are exactly the size of the collection view.
     */
    func collectionView(_ collectionView: NSCollectionView, layout
                            collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        return collectionView.bounds.size
    }
}
