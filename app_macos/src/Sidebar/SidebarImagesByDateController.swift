//
//  SidebarImagesByDateController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200625.
//

import Foundation
import AppKit
import CoreData
import OSLog

import Bowl
import Smokeshop

/**
 * Handles the tree of images displayed as the year > date structure in the sidebar.
 *
 * TODO: Speed this up by caching dates and counts for each date
 */
internal class SidebarImagesByDateController {
    fileprivate static var logger = Logger(subsystem: Bundle(for: SidebarImagesByDateController.self).bundleIdentifier!,
                                         category: "SidebarImagesByDateController")
    
    /// Library being displayed by this sidebar
    internal var library: LibraryBundle! {
        didSet {
            self.removeMOCObservers()
            self.dayCountCache.removeAll()
            self.updateCacheUrl()
            
            // set up for getting library info if non-nil
            if self.library != nil {
                self.addMOCObservers()
                
                // read date cache; if invalid, fetch data
                if !self.readDatesCache() {
                    self.mainCtx.perform {
                        self.fetchCaptureDays()
                        
                        DispatchQueue.global(qos: .background).async {
                            self.saveCache()
                        }
                    }
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
                    
                    DispatchQueue.global(qos: .background).async {
                        self?.saveCache()
                    }
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
            Self.logger.error("Failed to retrieve distinct capture dates: \(error.localizedDescription)")
            return
        }
        
        self.updateTreeWithDates(dates)
    }
    
    // MARK: Cache
    /// URL of the cache file for the current library
    private var cacheUrl: URL? = nil
    
    /**
     * Structure serialized to disk in sidebar caches
     */
    private struct CacheRoot: Codable {
        /// Cache version
        var version: UInt = Self.currentVersion
        /// When the cache was last modified
        var lastUpdated: Date? = Date()
        
        /// An array of dates (ignoring time component) on which this library has images
        var dates: [Date] = []
        /// Map of dates to counts
        var counts: [Date: Int] = [:]
        
        
        /// Current cache version
        static let currentVersion: UInt = 1
    }
    
    /**
     * Updates the cache url for the given library.
     */
    private func updateCacheUrl() {
        // get handle to the library
        guard let library = self.library else {
            self.cacheUrl = nil
            return
        }
        
        let name = String(format: "SidebarImagesByDateController-%@.plist", library.identifier.uuidString)
        let url = ContainerHelper.appCache?.appendingPathComponent(name, isDirectory: false)
        
        self.cacheUrl = url
    }
    
    /**
     * Attempts to load the capture dates cache from disk.
     *
     * - Returns: Whether the dates cache was loaded.
     */
    private func readDatesCache() -> Bool {
        // does the cache file exist?
        guard let url = self.cacheUrl,
              FileManager.default.fileExists(atPath: url.path) else {
                  Self.logger.debug("Not loading sidebar dates cache because cache doesn't exist (url \(String(describing: self.cacheUrl)))")
            return false
        }
        
        // read cache and decode it
        var cache: CacheRoot! = nil
        
        do {
            let data = try Data(contentsOf: url)
            
            let reader = PropertyListDecoder()
            cache = try reader.decode(CacheRoot.self, from: data)
        } catch {
            Self.logger.error("Failed to read/decode cache from \(url): \(error.localizedDescription)")
            return false
        }
        
        // validate the read data and copy what we can
        guard cache.version == CacheRoot.currentVersion else {
            Self.logger.warning("Ignoring cache file '\(url)' due to invalid version \(cache.version) (expected \(CacheRoot.currentVersion)")
            return false
        }
        
        guard cache.dates.count > 0 else {
            Self.logger.warning("Ignoring cache file '\(url)' because date count is 0")
            return false
        }
        
        if cache.counts.count > 0 {
            self.dayCountCache = cache.counts
        }
        
        // update the tree
        self.updateTreeWithDates(cache.dates)
        
        return true
    }
    
    /**
     * Save the sidebar cache.
     */
    private func saveCache() {
        // ensure there's a cache url
        guard let url = self.cacheUrl else {
            Self.logger.error("Request to save sidebar cache with no url (library \(String(describing: self.library)))")
            return
        }
        
        // create a cache struct
        var cache = CacheRoot()
        cache.dates = self.dates
        cache.counts = self.dayCountCache
        
        // encode data and write to disk
        do {
            // encode as a bplist
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            
            let data = try encoder.encode(cache)
            
            // then, write the data blob to disk
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to write sidebar cache to \(url): \(error.localizedDescription)")
            return
        }
    }
    
    // MARK: - Tree management
    /// Dates on which we have images
    private var dates: [Date] = []
    
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
        self.dates = dates
        
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
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateTree()
            }
        } else {
            self.outline.reloadItem(self.groupItem)
            self.outline.expandItem(self.groupItem, expandChildren: false)
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
                Self.logger.error("Failed to update image count for \(date): \(error.localizedDescription)")
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
                
                self.selectionIdentifier = String(format: "SidebarImagesByDate.YearItem.%.0f",
                                                  self.year.timeIntervalSinceReferenceDate)
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
                
                self.selectionIdentifier = String(format: "SidebarImagesByDate.DayItem.%.0f",
                                                  self.date.timeIntervalSinceReferenceDate)
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
