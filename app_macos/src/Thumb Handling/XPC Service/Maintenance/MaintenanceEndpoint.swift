//
//  MaintenanceEndpoint.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200627.
//

import Foundation
import CoreData
import OSLog

import Bowl

/**
 * Implements an endpoint usable by the app to provide information about the thumbnail handler, as well as
 * perform some thumbnail maintenance and optimization.
 */
class MaintenanceEndpoint: NSObject, ThumbXPCMaintenanceEndpoint, NSXPCListenerDelegate {
    fileprivate static var logger = Logger(subsystem: Bundle(for: MaintenanceEndpoint.self).bundleIdentifier!,
                                         category: "MaintenanceEndpoint")
    
    /// Directory storing thumbnail data
    private var directory: ThumbDirectory!
    /// Queue for XPC listening
    private var listenQueue = DispatchQueue(label: "Maintenance Endpoint")
    
    // MARK: - Initialization
    /**
     * Initializes a new maintenance endpoint with the given directory.
     */
    init(_ directory: ThumbDirectory) {
        super.init()
        
        self.directory = directory
        
        // create XPC listener
        self.listener = NSXPCListener.anonymous()
        self.listener.delegate = self
        
        self.listenQueue.async {
            self.listener.resume()
        }
    }
    
    /**
     * On deallocation, ensure the listener is stopped.
     */
    deinit {
        self.listener.invalidate()
    }
    
    // MARK: - XPC Delegate
    /// XPC endpoint on which the maintenance endpoint is listening
    internal var endpoint: NSXPCListenerEndpoint! {
        return self.listener.endpoint
    }
    /// Listener for the maintenance endpoint
    private var listener: NSXPCListener!
    
    /// Bundle identifiers of allowed clients
    private static let allowedIdentifiers: [String] = [
        "me.tseifert.SmokeShed"
    ]
    
    
    /**
     * Determines if the caller is allowed to access this interface.
     *
     * As with the main interface, we check that the code signature matches our team id, but we also ensure
     * that the bundle id is in a hardcoded list.
     */
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection new: NSXPCConnection) -> Bool {
        Self.logger.debug("Connection to maintenance endpoint: \(new)")
        
        // create the connection
        new.exportedInterface = ThumbXPCProtocolHelpers.makeMaintenanceEndpoint()
        new.exportedObject = self
        new.resume()
        
        return true
    }
    
    
    // MARK: - External Interface
    /**
     * Gets the current XPC service configuration.
     */
    func getConfig(withReply reply: @escaping ([String : Any]) -> Void) {
        var rep = UserDefaults.standard.dictionaryRepresentation()
        rep = rep.filter({
            return (ThumbXPCConfigKey(rawValue: $0.key) != nil)
        })
        
        reply(rep)
    }
    
    /**
     * Updates the xpc service configuration.
     */
    func setConfig(_ config: [String : Any]) {
        let values = config.filter({
            return (ThumbXPCConfigKey(rawValue: $0.key) != nil)
        })
        
        UserDefaults.standard.setValuesForKeys(values)
    }
    
    /**
     * Calculate the total amount of disk space used by the chunk storage.
     */
    func getSpaceUsed(withReply reply: @escaping (UInt, Error?) -> Void) {
        // get chunk directory url
        let url = self.directory.chonker.chunkDir!
        
        do {
            let size = try FileManager.default.directorySize(url)
            return reply(size, nil)
        } catch {
            return reply(0, error)
        }
    }
    
    /**
     * Queries the chonker for its storage directory.
     */
    func getStorageDir(withReply reply: @escaping (URL) -> Void) {
        reply(self.directory.chonker.thumbBundle)
    }
    
    
    /**
     * Requests thumbnail data to be moved to the specified url.
     *
     * The callback is executed at least once indicating any setup errors or a progress object on which the move can be tracked.
     */
    func moveThumbStorage(to: URL, copyExisting: Bool, deleteExisting: Bool, withReply reply: @escaping(Error?) -> Void) {
        // bail if old url is the same as new
        guard to != UserDefaults.standard.thumbStorageUrl else {
            Self.logger.warning("Ignoring moveThunbStorage request; origin and destination are identical")
            return reply(nil)
        }
        
        do {
            let fm = FileManager.default
            let old = UserDefaults.standard.thumbStorageUrl
            let main = Progress(totalUnitCount: 2)
            
            self.directory.chonker.beginMoveTransaction()
            
            // if old thumb directory is inaccessible, just move directly to using the new one
            if !fm.fileExists(atPath: old.path) {
                main.becomeCurrent(withPendingUnitCount: 2)
                
                // create the new directory
                if !fm.fileExists(atPath: to.path) {
                    try fm.createDirectory(at: to, withIntermediateDirectories: true, attributes: nil)
                }
                
                // save the new location
                UserDefaults.standard.thumbStorageUrl = to

                main.completedUnitCount += 2
                main.resignCurrent()
            }
            // otherwise, move and/or delete old data
            else {
                // do we need to copy the files?
                main.becomeCurrent(withPendingUnitCount: 1)
                if copyExisting {
                    let progress = Progress(totalUnitCount: 1)
                    progress.localizedDescription = Self.localized("thumb.copy")
                    progress.becomeCurrent(withPendingUnitCount: 1)
                    
                    try fm.copyItem(at: old, to: to)
                    progress.completedUnitCount += 1
        
                    progress.resignCurrent()
                }
                main.resignCurrent()
                
                // create directory if needed
                if !fm.fileExists(atPath: to.path) {
                    try fm.createDirectory(at: to, withIntermediateDirectories: true, attributes: nil)
                }
                
                // update the storage url
                UserDefaults.standard.thumbStorageUrl = to
                
                // should the original files be deleted?
                main.becomeCurrent(withPendingUnitCount: 1)
                if deleteExisting {
                    let progress = Progress(totalUnitCount: 1)
                    progress.localizedDescription = Self.localized("thumb.trash")
                    progress.becomeCurrent(withPendingUnitCount: 1)
                    
                    try fm.trashItem(at: old, resultingItemURL: nil)
                    progress.completedUnitCount += 1
                    
                    progress.resignCurrent()
                }
                main.resignCurrent()
            }
            
            // run success callback
            reply(nil)
        } catch {
            Self.logger.error("Failed to move thumb storage to '\(to)': \(error.localizedDescription)")
            reply(error)
        }
        
        // we always must resume chonkery
        self.directory.chonker.endMoveTransaction()
    }
    
    // MARK: - Helpers
    /**
     * Returns a localized string.
     */
    private static func localized(_ key: String) -> String {
        let bundle = Bundle(for: Self.self)
        return bundle.localizedString(forKey: key, value: nil, table: "MaintenanceProgress")
    }
    
    // MARK: - Errors
    enum MaintenanceErrors: Error {
        /// Connecting client isn't allowed
        case connectionForbidden(_ identifier: Any?)
    }
}
