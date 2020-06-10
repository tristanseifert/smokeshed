//
//  LibraryStore.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation
import CoreData

import CocoaLumberjackSwift

/**
 * Provides an interface to the CoreData store embedded in the library.
 */
public class LibraryStore {
    /// Library corresponding to this store
    private var library: LibraryBundle! = nil

    /**
     * Initializes a library store with the given library. If the library was just created (and does not yet have
     * an initialized store) this will be done as well.
     *
     * Note that migration is a potentially lengthy operation, so we defer for later. Check whether you need
     * to migrate before attempting to access the data, and provide an user interface to view the prgoress
     * of that operation.
     */
    public init(_ lib: LibraryBundle) throws {
        self.library = lib

        // register value transformers for the first time
        SizeTransformer.register()

        // initialize the pieces of the CoreData stack
        try self.initModelAndStoreCoordinator()
        try self.initPersistentStore()

        // create context if migration is not required
        if self.deferredMigrationNeeded {
            return
        }

        self.initContext()
    }

    // MARK: - CoreData stack setup
    /// Object model for our library data store
    private var model: NSManagedObjectModel! = nil
    /// Persistent store coordinator
    private var psc: NSPersistentStoreCoordinator! = nil
    /// Main context
    private var mainCtx: NSManagedObjectContext! = nil

    /// Whether migration is required at a later time
    private var deferredMigrationNeeded: Bool = false

    /**
     * Initializes the model and persistent store coordinator.
     */
    private func initModelAndStoreCoordinator() throws {
        // create the model
        let bundle = Bundle.init(for: LibraryStore.self)
        guard let modelUrl = bundle.url(forResource: "Library", withExtension: "momd") else {
            throw LibraryStoreError.modelFailedToLoad
        }
        guard let model = NSManagedObjectModel(contentsOf: modelUrl) else {
            throw LibraryStoreError.modelFailedToLoad
        }

        self.model = model

        // create a persistent store coordinator based off of this
        self.psc = NSPersistentStoreCoordinator(managedObjectModel: self.model)
    }

    /**
     * Attempts to attach the persistent store inside the library.
     */
    private func initPersistentStore(_ migrate: Bool = false) throws {
        var addError: Error! = nil

        // create a store description
        guard let url = self.library.storeUrl else {
            throw LibraryStoreError.invalidStoreUrl
        }

        let desc = NSPersistentStoreDescription(url: url)

        desc.shouldAddStoreAsynchronously = false
        desc.type = NSSQLiteStoreType
        desc.shouldMigrateStoreAutomatically = migrate

        // add it
        self.psc.addPersistentStore(with: desc, completionHandler: { (desc, error) in
            // failed to add the store
            if let error = error {
                DDLogError("Failed to add persistent store '\(url)': \(error)")

                // is migration required?
                let nsErr = error as NSError

                if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSPersistentStoreIncompatibleVersionHashError {
                    self.deferredMigrationNeeded = true
                } else {
                    // otherwise, rethrow the error later
                    addError = error
                }
            }
            // success! no migration required
            else {
                DDLogDebug("Added persistent store from '\(url)'")
            }
        })

        // rethrow any errors that took place during adding
        if let error = addError {
            throw error
        }
    }

    /**
     * Create the main context.
     */
    private func initContext() {
        // create context
        self.mainCtx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)

        self.mainCtx.persistentStoreCoordinator = self.psc
        self.mainCtx.name = "Smokeshop Main Context"
    }

    // MARK: Deferred migrations
    /**
     * Determines whether migration is required. If so, the you must call the migration function to perform
     * migration and complete the stack setup.
     */
    public var migrationRequired: Bool {
        return self.deferredMigrationNeeded
    }

    /**
     * Perform migration to bring the store up to date. This function will return after the initial migration
     * compatibility checks complete, but migration itself will continue in the background. The returned
     * progress object can be used to observe the state of the migration.
     */
    public func migrate() throws -> Progress {
        let b = Bundle(for: LibraryStore.self)

        // TODO: implement

        // create progress ig
        let progress = Progress()
        progress.localizedDescription = NSLocalizedString("Migrating library",
                                            tableName: nil, bundle: b,
                                            value: "",
                                            comment: "LibraryStore migration progress description")

        return progress
    }

    // MARK: - Saving,  Change Notifications
    /**
     * Saves the primary persistent store synchronously.
     */
    public func save() throws {
        try self.mainCtx.save()
    }

    /**
     * Whether the main queue is dirty and requires saving.
     */
    public var isDirty: Bool {
        return self.mainCtx.hasChanges
    }

    // MARK: - Context handling
    /**
     * Returns a reference to the main thread context.
     */
    public var mainContext: NSManagedObjectContext! {
        return self.mainCtx
    }
}
