//
//  SidebarShortcutsController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200624.
//

import Foundation
import CoreData

import Smokeshop
import CocoaLumberjackSwift

/**
 * Manages the "all photos" and "last import"  sidebar items.
 */
internal class SidebarShortcutsController {
    /// Library being displayed by this sidebar
    internal var library: LibraryBundle! {
        didSet {
            self.removeMOCObservers()
            
            // set up fetch request
            if self.library != nil {
                self.addMOCObservers()
                
                self.mainCtx.perform {
                    self.updateImageCount()
                    self.updateRecentImportCount()
                }
            }
            // clean up CoreData interfaces
            else {
                self.allItem.badgeValue = 0
            }
        }
    }
    /// Managed object context for main thread
    private var mainCtx: NSManagedObjectContext! {
        return self.library.store.mainContext!
    }
    
    /// "All images" item
    internal var allItem: SidebarController.OutlineItem!
    /// "Last import" item
    internal var lastImportItem: SidebarController.OutlineItem!
    
    deinit {
        self.removeMOCObservers()
    }
    
    // MARK: - Change observing
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
            
            // require there to have been either added or removed images
            var imagesAddedRemoved = false
            
            if let objects = (changes[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.compactMap({ $0 as? Image }),
               !objects.isEmpty {
                imagesAddedRemoved = true
            } else if let objects = (changes[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.compactMap({ $0 as? Image }),
              !objects.isEmpty {
                imagesAddedRemoved = true
           }
            
            if imagesAddedRemoved {
                // run the functions in the context queue
                self?.mainCtx.perform {
                    self?.updateImageCount()
                    self?.updateRecentImportCount()
                }
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
    
    // MARK: - All images
    /// Fetch request used to count the total number of images in the library
    private var allImagesFetchReq: NSFetchRequest<NSFetchRequestResult> = {
        let req: NSFetchRequest<NSFetchRequestResult> = Image.fetchRequest()
        req.resultType = .countResultType
        return req
    }()
    
    /**
     * Refetches the image count.
     */
    private func updateImageCount() {
        guard self.library != nil else {
            return
        }
        
        // count the images
        do {
            let count = try self.mainCtx.fetch(self.allImagesFetchReq).first!
            
            DispatchQueue.main.async { [weak self] in
                self?.allItem?.badgeValue = count as! Int
            }
        } catch {
            DDLogError("Failed to count images: \(error)")
            return
        }
    }
    
    // MARK: - Last import
    /// Fetch request to retrieve the image with the most recent import date
    private var mostRecentlyImportedFetchReq: NSFetchRequest<NSFetchRequestResult> = {
        let req: NSFetchRequest<NSFetchRequestResult> = Image.fetchRequest()
        
        req.sortDescriptors = [
            NSSortDescriptor(key: "dateImported", ascending: false)
        ]
        req.fetchLimit = 1
        req.propertiesToFetch = [
            "dateImported"
        ]
        req.shouldRefreshRefetchedObjects = true
        
        return req
    }()
    /// Date of the most recent import
    private var mostRecentImport: Date! = nil
    
    /**
     * Attempts to determine the most recent import and counts the number of images that were imported
     * at that time.
     */
    private func updateRecentImportCount() {
        guard self.library != nil else {
            return
        }
        
        // get the latest import date
        do {
            let res = try self.mainCtx.fetch(self.mostRecentlyImportedFetchReq)
            
            guard let obj = res.first as? Image else {
                DDLogError("Failed to convert results for latest import date: \(res)")
                return
            }
            self.mostRecentImport = obj.dateImported
        } catch {
            DDLogError("Failed to retrieve latest import date: \(error)")
            return
        }
        
        // if we have an import date, count how many images were imported then
        guard let date = self.mostRecentImport else {
            DispatchQueue.main.async { [weak self] in
                self?.lastImportItem?.badgeValue = 0
            }
            
            return
        }
        
        let req: NSFetchRequest<NSFetchRequestResult> = Image.fetchRequest()
        req.resultType = .countResultType
        req.predicate = NSPredicate(format: "%K == %@", "dateImported",
                                    date as CVarArg)
        
        do {
            let count = try self.mainCtx.fetch(req).first!
            DispatchQueue.main.async { [weak self] in
                self?.lastImportItem?.badgeValue = count as! Int
            }
        } catch {
            DDLogError("Failed to count images in last import: \(error)")
            return
        }
    }
}
