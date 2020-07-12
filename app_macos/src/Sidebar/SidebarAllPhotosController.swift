//
//  SidebarAllPhotosController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200624.
//

import Foundation
import CoreData

import Smokeshop
import CocoaLumberjackSwift

/**
 * Manages the "all photos" sidebar item.
 */
internal class SidebarShortcutsController {
    /// Library being displayed by this sidebar
    internal var library: LibraryBundle! {
        didSet {
            // set up fetch request
            if self.library != nil {
                self.removeMOCObservers()
                self.addMOCObservers()
                self.updateImageCount()
            }
            // clean up CoreData interfaces
            else {
                self.item.badgeValue = 0
            }
        }
    }
    /// Managed object context for main thread
    private var mainCtx: NSManagedObjectContext! {
        return self.library.store.mainContext!
    }
    
    /// Outline item
    internal var item: SidebarController.OutlineItem!
    
    deinit {
        self.removeMOCObservers()
    }
    
    // MARK: - Fetching
    /// Fetch request used to count the total number of images in the library
    private var fetchReq: NSFetchRequest<Image> = Image.fetchRequest()
    /// Observers we've registered for queue changes
    private var observers: [NSObjectProtocol] = []
    
    /**
     * Subscribes to changes on the library's context
     */
    private func addMOCObservers() {
        let c = NotificationCenter.default
        
        let o = c.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                              object: self.mainCtx,
                              queue: nil)
        { [weak self] notification in
            guard let changes = notification.userInfo else {
                fatalError("Received NSManagedObjectContext.didChangeObjectsNotification without user info")
            }
            
            // require there to have been either added or removed objects
            var updateCount = false
            
            if let objects = changes[NSDeletedObjectsKey] as? Set<NSManagedObject>,
               !objects.isEmpty {
                updateCount = true
            } else if let objects = changes[NSInsertedObjectsKey] as? Set<NSManagedObject>,
              !objects.isEmpty {
               updateCount = true
           }
            
            if updateCount {
                self?.updateImageCount()
            }
        }
        self.observers.append(o)
    }
    
    /**
     * Removes all old observers we've added to the library context.
     */
    private func removeMOCObservers() {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observers.removeAll()
    }
    
    /**
     * Refetches the image count.
     */
    private func updateImageCount() {
        guard self.library != nil else {
            return
        }
        
        // count the images
        do {
            let count = try self.mainCtx.count(for: self.fetchReq)
            
            DispatchQueue.main.async {
                self.item?.badgeValue = count
            }
        } catch {
            DDLogError("Failed to count images: \(error)")
        }
    }
}
