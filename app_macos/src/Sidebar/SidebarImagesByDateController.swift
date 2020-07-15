//
//  SidebarImagesByDateController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import CoreData

import Smokeshop
import CocoaLumberjackSwift

/**
 * Handles the tree of images displayed as the year > date structure in the sidebar.
 *
 * TODO: Speed this up by caching dates and counts for each date
 */
internal class SidebarImagesByDateController {
    /// Library being displayed by this sidebar
    internal var library: LibraryBundle! {
        didSet {
            self.removeMOCObservers()
            
            // set up fetch request
            if self.library != nil {
                self.addMOCObservers()
                
                self.mainCtx.perform {
                    self.fetchCaptureDays()
                }
            }
        }
    }
    /// Managed object context for main thread
    private var mainCtx: NSManagedObjectContext! {
        return self.library.store.mainContext!
    }
    
    /// Group item under which all images are shown
    internal var groupItem: SidebarController.OutlineItem!
    /// Outline view containing the sidebar (allows for refreshing)
    internal var outline: NSOutlineView!
    
    // MARK: - Initialization
    /**
     * Ensure notification observers are removed when deallocating
     */
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
            
            // require that images were deleted, inserted or modified
            var updateTree = false
            
            if let objects = (changes[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.compactMap({ $0 as? Image }),
               !objects.isEmpty {
                updateTree = true
                
                // invalidate count cache for date this image was captured
                for image in objects {
                    if let day = image.dayCaptured {
                        self?.invalidateCountCache(for: day)
                    }
                }
            } else if let objects = (changes[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.compactMap({ $0 as? Image }),
                      !objects.isEmpty {
                updateTree = true
                
                // invalidate count cache for date this image was captured
                for image in objects {
                    if let day = image.dayCaptured {
                        self?.invalidateCountCache(for: day)
                    }
                }
            } else if let objects = (changes[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?.compactMap({ $0 as? Image }),
                      !objects.isEmpty {
                updateTree = true
                
                // TODO: determine if capture date changed
            }
            
            if updateTree {
                // run the functions in the context queue
                self?.mainCtx.perform {
                    self?.fetchCaptureDays()
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
    
    // MARK: - Fetching
    /// Fetch request for retrieving unique capture dates
    private var fetchReq: NSFetchRequest<NSFetchRequestResult> = {
        let req: NSFetchRequest<NSFetchRequestResult> = Image.fetchRequest()
        req.propertiesToFetch = ["dayCaptured"]
        req.sortDescriptors = [
            NSSortDescriptor(key: "dayCaptured", ascending: true)
        ]
        req.resultType = .dictionaryResultType
        req.returnsDistinctResults = true
        req.shouldRefreshRefetchedObjects = true
        req.includesPendingChanges = true
        return req
    }()
    
    /**
     * Fetch unique values of capture dates.
     */
    private func fetchCaptureDays() {
        var dates: [Date]!
        
        guard self.library != nil else {
            return
        }
        
        // get the latest import dates
        do {
            let res = try self.mainCtx.fetch(self.fetchReq) as! [NSDictionary]
            dates = res.compactMap({ $0["dayCaptured"] as? Date })
        } catch {
            DDLogError("Failed to retrieve distinct capture dates: \(error)")
            return
        }
        
        self.updateTreeWithDates(dates)
    }
    
    // MARK: - Tree management
    /// Calendar for working with date components
    private var calendar: Calendar = {
        var cal = Calendar.autoupdatingCurrent
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()
    
    /**
     * Given an array of unique dates, build the tree of images for it.
     */
    private func updateTreeWithDates(_ dates: [Date]) {
        // get unique years
        let years = Set(dates.compactMap({
            return self.calendar.component(.year, from: $0)
        })).sorted(by: <)
        
        // handle the parent items for each year
        for year in years {
            // get all dates on this year
            let dates = dates.filter({
                self.calendar.component(.year, from: $0) == year
            }).sorted(by: <)
            
            // update that year's items
            self.updateParentForYear(year, childDates: dates)
        }
        
        // refresh the tree view
        self.updateTree()
    }
    
    /**
     * Updates a year item's children.
     *
     * - Returns: Whether the parent should be refreshed (children were added/removed)
     */
    @discardableResult private func updateChildren(_ parent: YearItem, _ childDates: [Date]) -> Bool {
        var changedStructure = false
        var createdOrRemoved = false
        
        // check if we've an item for each of the dates
        for date in childDates {
            // is there such a child item?
            let child = self.groupItem.children.first(where: {
                if let item = $0 as? DayItem {
                    return item.date == date
                }
                return false
            })
            
            // if so, update it
            if let item = child as? DayItem {
                self.updateDayItem(item)
            }
            // otherwise, create one
            else {
                self.createDayItemFor(date: date, parent)
                changedStructure = true
                createdOrRemoved = true
            }
        }
        
        // sort by child date
        parent.children.sort(by: {
            if let first = $0 as? DayItem, let second = $1 as? DayItem {
                return first.date < second.date
            } else {
                return $0.title < $1.title
            }
        })
        
        // post notification
        if createdOrRemoved {
            NotificationCenter.default.post(name: .sidebarItemUpdated, object: parent)
        }
        
        // update badge count
        parent.updateCountFromChildren()
        
        return changedStructure
    }
    
    /**
     * Updates the entire tree.
     */
    private func updateTree() {
        DispatchQueue.main.async { [weak self] in
            self?.outline.reloadItem(self?.groupItem)
            self?.outline.expandItem(self?.groupItem, expandChildren: false)
        }
    }
    
    // MARK: Year items
    /**
     * Updates or creates the parent item for the given year, creating children for each of the provided dates.
     *
     * Assumes the input array of dates is sorted in the desired display order.
     */
    private func updateParentForYear(_ year: Int, childDates dates: [Date]) {
        // create a date from that year
        let yearDate = self.dateFromYear(year)
        
        // do we already have a parent for this?
        let parent = self.groupItem.children.first(where: {
            if let item = $0 as? YearItem {
                return item.year == yearDate
            }
            return false
        })
        
        // if so, update all of its children
        if let item = parent {
            // update existing items
            for child in item.children {
                if let day = child as? DayItem {
                    self.updateDayItem(day)
                }
            }
            
            // remove items with a count of zero
            item.children.removeAll(where: { $0.badgeValue == 0 })
            
            // update the count
            parent?.updateCountFromChildren()
        }
        // create a new parent item
        else {
            self.createYearItemFor(year: yearDate, dates)
        }
    }
    
    /**
     * Creates and inserts a year parent item.
     */
    private func createYearItemFor(year: Date, _ childDates: [Date]) {
        // create the year item (parent)
        let parent = YearItem()
        parent.year = year
        
        self.groupItem.children.append(parent)
        
        // calculate start date
        var comps = self.calendar.dateComponents([.year], from: year)
        comps.timeZone = TimeZone(secondsFromGMT: 0)!
        comps.month = 1
        comps.day = 1
        
        let start = self.calendar.date(from: comps)!
        
        // end date is just one year added to this
        let end = self.calendar.date(byAdding: .year, value: 1, to: start)!
        
        // create predicate start <= dateCaptured < end
        parent.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K >= %@", "dateCaptured", start as CVarArg),
            NSPredicate(format: "%K < %@", "dateCaptured", end as CVarArg),
        ])
        
        // update children on the item
        self.updateChildren(parent, childDates)
    }
    
    // MARK: Day items
    /// Cache containing the number of images for a particular date
    private var dayCountCache: [Date: Int] = [:]
    
    /**
     * Creates and inserts a new day item into the given year item.
     */
    private func createDayItemFor(date: Date, _ parent: YearItem) {
        // create item
        let item = DayItem()
        item.date = date
        
        // create a predicate checking against the day captured
        item.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", "dayCaptured", date as CVarArg)
        ])

        // update it
        self.updateDayItem(item)
        
        // insert it
        parent.children.append(item)
    }
    
    /**
     * Updates a date item; this will refresh the count of images on that date.
     */
    private func updateDayItem(_ item: DayItem) {
        guard let date = item.date else {
            fatalError("Day item with missing date")
        }
        
        // is there a value in the cache?
        if let count = self.dayCountCache[date] {
            item.badgeValue = count
        }
        // there is not, so we need to count images with this date
        else {
            let req: NSFetchRequest<NSFetchRequestResult> = Image.fetchRequest()
            req.resultType = .countResultType
            req.predicate = NSPredicate(format: "%K == %@", "dayCaptured",
                                        date as CVarArg)
            
            do {
                let count = try self.mainCtx.fetch(req).first as! NSNumber
                self.dayCountCache[date] = count.intValue
                
                item.badgeValue = count.intValue
            } catch {
                DDLogError("Failed to update image count for \(date): \(error)")
            }
        }
    }
    
    /**
     * Invalidates the count cache for the given value.
     */
    private func invalidateCountCache(for date: Date) {
        self.dayCountCache.removeValue(forKey: date)
    }
    
    // MARK: Date helpers
    /**
     * Creates a date representing a year; any components beyond the year are undefined.
     */
    private func dateFromYear(_ yearNum: Int) -> Date {
        var comps = DateComponents()
        comps.year = yearNum
        comps.month = 1
        comps.day = 3
        return self.calendar.date(from: comps)!
    }
    
    // MARK: - Tree items
    /**
     * Outline item representing a single year in the library.
     */
    @objc private class YearItem: SidebarController.OutlineItem {
        /// Initialize with the correct cell type
        override init() {
            super.init()
            
            self.viewIdentifier = NSUserInterfaceItemIdentifier("ImagesYear")
        }
        
        /// The year that is displayed
        @objc dynamic var year: Date! {
            didSet {
                self.title = Self.yearFormatter.string(from: self.year)
            }
        }
        
        /// Date formatter for years
        private static let yearFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(secondsFromGMT: 0)!
            f.dateFormat = "YYYY"
            return f
        }()
    }
    
    /**
     * A single day of pictures
     */
    @objc private class DayItem: SidebarController.OutlineItem {
        /// Initialize with the correct cell type
        override init() {
            super.init()
            
            self.viewIdentifier = NSUserInterfaceItemIdentifier("ImagesDay")
        }
        
        /// The date that is displayed
        @objc dynamic var date: Date! {
            didSet {
                self.title = Self.dateFormatter.string(from: self.date)
            }
        }
        
        /// Date formatter for years
        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeZone = TimeZone(secondsFromGMT: 0)!
            f.dateStyle = .short
            return f
        }()
    }
}
