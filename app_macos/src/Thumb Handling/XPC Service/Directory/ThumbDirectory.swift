//
//  ThumbDirectory.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//

import Foundation
import CoreData

import Bowl

import CocoaLumberjackSwift

/**
 * Persistent store for thumbnail metadata
 */
internal class ThumbDirectory {
    /// Chunk manager
    private var chonker: ChunkManager!
    
    // MARK: - Initialization
    /**
     * Initializes a new thumb directory, opening the persistent store and creating the main context.
     */
    init() throws {
        try self.loadModel()
        try self.createPersistentStore()
        try self.createContext()
        
        self.chonker = try ChunkManager(withDirectory: self)
    }
    
    // MARK: - CoreData stack setup
    /// Object model for data store
    private var model: NSManagedObjectModel! = nil
    /// Persistent store coordinator (backed by metadata file in group container)
    private var psc: NSPersistentStoreCoordinator! = nil
    /// Main context
    private(set) internal var mainCtx: NSManagedObjectContext! = nil
    
    /**
     * Loads the model used to represent thumbnail data.
     */
    private func loadModel() throws {
        let bundle = Bundle.init(for: Self.self)
        guard let modelUrl = bundle.url(forResource: "ThumbDirectory", withExtension: "momd") else {
            throw ThumbDirectoryErrors.failedToLoadModel
        }
        guard let model = NSManagedObjectModel(contentsOf: modelUrl) else {
            throw ThumbDirectoryErrors.failedToLoadModel
        }

        self.model = model
    }
    
    /**
     * Sets up the persistent store.
     */
    private func createPersistentStore() throws {
        // create the PSC
        self.psc = NSPersistentStoreCoordinator(managedObjectModel: self.model)
        
        // URL to the store in the app directory
        let base = ContainerHelper.groupAppData
        let url = base.appendingPathComponent("ThumbDirectory.sqlite",
                                              isDirectory: false)
        
        DDLogVerbose("Loading thumb directory from '\(url)'")
        
        // create a store description
        let opts = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        
        // add it :)
        let store = try self.psc.addPersistentStore(ofType: NSSQLiteStoreType,
                                                    configurationName: nil,
                                                    at: url,
                                                    options: opts)
        DDLogInfo("Added persistent store: \(store)")
    }
    
    /**
     * Creates the main context. Since we won't have a main run loop, this context has a private work
     * queue. Each connection should create its own sub-context.
     */
    private func createContext() throws {
        self.mainCtx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        
        self.mainCtx.name = "ThumbDirectory Main"
        self.mainCtx.persistentStoreCoordinator = self.psc
        
        self.mainCtx.automaticallyMergesChangesFromParent = true
        self.mainCtx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
    
    // MARK: - Library Handling
    /**
     * Prepares the directory for accesses to the library with the provided identifier.
     *
     * If the library does not exist, it is created. Otherwise, this is a no-op.
     */
    func openLibrary(_ id: UUID) throws {
        var tempErr: Error? = nil
        
        // ask for such a library from the store
        let req: NSFetchRequest<Library> = Library.fetchRequest()
        req.predicate = NSPredicate(format: "%K == %@", "identifier", id as CVarArg)
        
        self.mainCtx.performAndWait {
            do {
                let count = try self.mainCtx.count(for: req)
                
                if count == 0 {
                    try self.newLibrary(id)
                }
            } catch {
                tempErr = error
            }
        }
        
        // rethrow error
        if let err = tempErr {
            throw err
        }
    }
    
    /**
     * Creates a new library with the given uuid.
     */
    private func newLibrary(_ id: UUID) throws {
        DDLogVerbose("Creating library \(id)")
        
        // create a new library and populate its properties
        guard let new = NSEntityDescription.insertNewObject(forEntityName: "Library",
                                                            into: self.mainCtx) as? Library else {
            throw ThumbDirectoryErrors.failedToCreateLibrary
        }
        
        new.identifier = id
        
        // save it
        try self.mainCtx.save()
        
        DDLogInfo("Created library for id \(id): \(new.objectID)")
    }
    
    // MARK: - Thumbnails
    /**
     * Returns the thumbnail object for the given library and image ids, if it exists.
     */
    internal func getThumb(libraryId: UUID, _ thumbId: UUID) throws -> Thumbnail? {
        var tempErr: Error? = nil
        var thumb: Thumbnail? = nil
        
        // ask for such a library from the store
        let req: NSFetchRequest<Thumbnail> = Thumbnail.fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", "imageIdentifier", thumbId as CVarArg),
            NSPredicate(format: "%K == %@", "library.identifier", libraryId as CVarArg)
        ])
        req.fetchLimit = 1
        req.relationshipKeyPathsForPrefetching = ["chunk"]
        
        self.mainCtx.performAndWait {
            do {
                let result: [Thumbnail] = try self.mainCtx.fetch(req)
                thumb = result.first
            } catch {
                tempErr = error
            }
        }
        
        // rethrow errors or return object
        if let err = tempErr {
            throw err
        }
        
        return thumb
    }
    
    // MARK: - Errors
    enum ThumbDirectoryErrors: Error {
        /// CoreData model failed to load
        case failedToLoadModel
        /// Failed to create a library object
        case failedToCreateLibrary
    }
}
