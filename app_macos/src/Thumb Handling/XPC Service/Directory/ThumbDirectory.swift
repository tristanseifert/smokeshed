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
    private(set) internal var chonker: ChunkManager!
    
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
        
        // create data directory if needed
        let base = ContainerHelper.groupAppData(component: .thumbHandler)
        if !FileManager.default.fileExists(atPath: base.path) {
            do {
                try FileManager.default.createDirectory(at: base,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            } catch {
                DDLogError("Failed to create thumb container at '\(base)': \(error)")
            }
        }
        
        // URL to the store in the app directory
        let url = base.appendingPathComponent("ThumbDirectory.sqlite",
                                              isDirectory: false)
        
        DDLogVerbose("Loading thumb directory from '\(url)'")
        
        // create a store description
        let opts = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        
        // add it :)
        try self.psc.addPersistentStore(ofType: NSSQLiteStoreType,
                                        configurationName: nil, at: url,
                                        options: opts)
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
    
    // MARK: - Persistence
    /**
     * Saves the thumb directory.
     */
    internal func save() throws {
        var res: Result<Void, Error>!
        
        guard self.mainCtx.hasChanges else {
            return
        }
        
        self.mainCtx.performAndWait {
            do {
                try self.mainCtx.save()
                res = .success(Void())
            } catch {
                res = .failure(error)
            }
        }
        
        try res.get()
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
                    try self.mainCtx.save()
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
     *
     * - Note: This must be called from the object context's queue.
     */
    private func newLibrary(_ id: UUID) throws {
        DDLogVerbose("Creating library \(id)")
        
        // create a new library and populate its properties
        guard let new = NSEntityDescription.insertNewObject(forEntityName: "Library",
                                                            into: self.mainCtx) as? Library else {
            throw ThumbDirectoryErrors.failedToCreateLibrary
        }
        
        new.identifier = id
        
        // ensure it has a permanent id
        try self.mainCtx.obtainPermanentIDs(for: [new])
        
        DDLogInfo("Created library for id \(id): \(new.objectID)")
    }
    
    /**
     * Fetches the library for the given uuid.
     *
     * - Note: This must be called from the object context's queue.
     */
    private func getLibrary(_ id: UUID) throws -> Library {
        let req: NSFetchRequest<Library> = Library.fetchRequest()
        req.predicate = NSPredicate(format: "%K == %@", "identifier", id as CVarArg)
        req.fetchLimit = 1
        
        let res = try self.mainCtx.fetch(req)
        
        guard !res.isEmpty, let lib = res.first else {
            throw ThumbDirectoryErrors.noSuchLibrary
        }
        
        return lib
    }
    
    // MARK: - Thumbnails
    /**
     * Returns the thumbnail object for the given library and image ids, if it exists.
     */
    internal func getThumb(libraryId: UUID, _ thumbId: UUID) throws -> Thumbnail? {
        var result: Result<Thumbnail?, Error>!
        
        // ask for such a library from the store
        self.mainCtx.performAndWait {
            do {
                let req: NSFetchRequest<Thumbnail> = Thumbnail.fetchRequest()
                req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "%K == %@", "imageIdentifier", thumbId as CVarArg),
                    NSPredicate(format: "%K == %@", "library.identifier", libraryId as CVarArg)
                ])
                req.fetchLimit = 1
                req.includesPendingChanges = true
                req.relationshipKeyPathsForPrefetching = ["chunk"]
                
                let res = try self.mainCtx.fetch(req)
                result = .success(res.first)
            } catch {
                result = .failure(error)
            }
        }
        
        return try result.get()
    }
    
    /**
     * Gets a thumb corresponding to the given thumb request, if we have one.
     */
    internal func getThumb(request: ThumbRequest) throws -> Thumbnail? {
        return try self.getThumb(libraryId: request.libraryId, request.imageId)
    }
    
    /**
     * Makes a new thumbnail for the given request.
     */
    internal func makeThumb(request: ThumbRequest) throws -> Thumbnail {
        var result: Result<Thumbnail, Error>!
        
        self.mainCtx.performAndWait {
            do {
                // get library
                let lib = try self.getLibrary(request.libraryId)
                
                // ensure there are no duplicates
                let req: NSFetchRequest<NSFetchRequestResult> = Thumbnail.fetchRequest()
                req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "%K == %@", "imageIdentifier", request.imageId as CVarArg),
                    NSPredicate(format: "%K == %@", "library", lib)
                ])
                req.fetchLimit = 1
                req.includesPendingChanges = true
                req.resultType = .countResultType
                
                let count = (try self.mainCtx.fetch(req).first as? NSNumber)?.intValue
                guard count == 0 else {
                    throw ThumbDirectoryErrors.duplicateThumb
                }
                
                // create new thumb object
                let thumb = Thumbnail(context: self.mainCtx)
                
                thumb.imageIdentifier = request.imageId
                thumb.library = lib
                
                // obtain permanent id
                try self.mainCtx.obtainPermanentIDs(for: [thumb])
                
                result = .success(thumb)
            } catch {
                result = .failure(error)
            }
        }
        
        return try result.get()
    }
    
    // MARK: - Chunks
    /**
     * Returns an existing chunk or creates a new one, given an uuid.
     */
    internal func makeOrGetChunk(for id: UUID) throws -> Chunk {
        var result: Result<Chunk, Error>!
        
        self.mainCtx.performAndWait {
            do {
                // is there a chunk with this identifier?
                let req: NSFetchRequest<Chunk> = Chunk.fetchRequest()
                req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "%K == %@", "identifier", id as CVarArg),
                ])
                req.fetchLimit = 1
                req.includesPendingChanges = true
                
                let res = try self.mainCtx.fetch(req)
                
                if let chunk = res.first {
                    result = .success(chunk)
                    return
                }
                
                // create a new chunk
                let new = Chunk(context: self.mainCtx)
                
                new.identifier = id
                
                // obtain permanent id
                try self.mainCtx.obtainPermanentIDs(for: [new])
                
                result = .success(new)
            } catch {
                result = .failure(error)
            }
        }
        
        return try result.get()
    }
    
    // MARK: - Errors
    enum ThumbDirectoryErrors: Error {
        /// CoreData model failed to load
        case failedToLoadModel
        /// Failed to create a library object
        case failedToCreateLibrary
        /// The thumbnail already exists
        case duplicateThumb
        /// No library was found for the provided identifier
        case noSuchLibrary
    }
}
