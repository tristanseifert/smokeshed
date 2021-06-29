//
//  EditSecondaryViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200712.
//

import Cocoa

/**
 * View controller responsible for the edit view's secondary display, which is a grid of images from the library, filtered according to the
 * current sidebar filters.
 */
class EditSecondaryViewController: LibraryBrowserBase {
    /// Sidebar filter
    @objc dynamic var sidebarFilters: NSPredicate? = nil {
        didSet {
            // we MUST have a library at this point
            guard self.library != nil else {
                return
            }
            
            // update fetch request with new predicate and re-fetch
            self.fetchReq.predicate = self.sidebarFilters
            
            self.animateDataSourceUpdates = false
            self.fetchReqChanged = true
            self.fetch()
        }
    }
    
    // MARK: - View lifecycle
    /**
     * Register the cell classes with the collection view.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // register the collection view classes
        self.collection.register(LibraryCollectionItem.self,
                                 forItemWithIdentifier: .libraryCollectionItem)

        self.collection.register(LibraryCollectionHeaderView.self,
                                 forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                 withIdentifier: .libraryCollectionHeader)
    }
    
    /**
     * Reflow content as the view is about to appear.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        // reflow content manually
        self.reflowContent()
        
        // add observers for the size of the content
        let c = NotificationCenter.default

        c.addObserver(forName: NSWindow.didResizeNotification,
                      object: self.view.window!, queue: nil, using: { (n) in
            self.reflowContent()
        })

        c.addObserver(forName: NSView.frameDidChangeNotification,
                      object: self.collection!, queue: nil, using: { (n) in
            self.reflowContent()
        })
        self.collection.postsFrameChangedNotifications = true
    }
    
    /**
     * Removes content size observers when the view is about to be disappeared.
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()

        // remove observers for content size
        let c = NotificationCenter.default

        c.removeObserver(self, name: NSWindow.didResizeNotification,
                         object: self.view.window!)

        self.collection.postsFrameChangedNotifications = false
        c.removeObserver(self, name: NSView.boundsDidChangeNotification,
                         object: self.collection!)
    }
}
