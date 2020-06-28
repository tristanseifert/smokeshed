//
//  ThumbPreferencesViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200626.
//

import Cocoa

import Bowl
import CocoaLumberjackSwift

class ThumbPreferencesViewController: NSViewController {
    /// User defaults controller bound to the thumb shared defaults
    @objc dynamic lazy var userDefaultsController: NSUserDefaultsController = {
        let c = NSUserDefaultsController(defaults: UserDefaults.thumbShared,
                                         initialValues: nil)
        c.appliesImmediately = true
        return c
    }()
    
    /// Maintenance endpoint of the thumb service
    @objc dynamic weak private var maintenance: ThumbXPCMaintenanceEndpoint!
    
    // MARK: - View lifecycle
    /**
     * When the view has appeared, establish a connection to the maintenance endpoint in the thumb
     * service.
     */
    override func viewDidAppear() {
        super.viewDidAppear()
        
        ThumbHandler.shared.getMaintenanceEndpoint() { ep in
            self.maintenance = ep
            
            // calculate values displayed in the ui
            self.getSpaceUsed(nil)
        }
    }
    
    /**
     * When the view is disappearing, make sure we close the maintenance endpoint connection.
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // save preferences
        self.userDefaultsController.save(nil)
        self.maintenance.reloadConfiguration()
    
        // invalidate management connection and any cached values
        ThumbHandler.shared.closeMaintenanceEndpoint()
        
        self.dataSpaceUsedAvailable = false
    }
    
    // MARK: - Preferences
    /// Whether the thumb generator work queue size is automatically managed
    @objc dynamic private var autoSizeGeneratorQueue: Bool {
        get {
            return UserDefaults.thumbShared.thumbWorkQueueSizeAuto
        }
        set {
            UserDefaults.thumbShared.thumbWorkQueueSizeAuto = newValue
        }
    }
    
    // MARK: - Stats
    /// Is thumbnail cache size information available?
    @objc dynamic private var dataSpaceUsedAvailable: Bool = false
    /// Bytes on disk taken up by the thumbnail data
    @objc dynamic private var dataSpaceUsed: UInt = 0
    
    /**
     * Fetches the size of the thumbnail cache.
     */
    @IBAction private func getSpaceUsed(_ sender: Any?) {
        // clear out the available flag
        DispatchQueue.main.async {
            self.dataSpaceUsedAvailable = false
        }
        
        // abort previous delayed fetches
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(self.querySpaceUsed),
                                               object: nil)
        
        // add a small delay if the sender was a button
        if let _ = sender as? NSButton {
            self.perform(#selector(self.querySpaceUsed), with: nil,
                         afterDelay: 0.2)
        } else {
            self.querySpaceUsed()
        }
    }
    
    /**
     * Reveal the thumb storage directory.
     */
    @IBAction private func revealThumbStorageDir(_ sender: Any?) {
        self.maintenance.getStorageDir() { (url) in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    /**
     * Queries the maintenance endpoint to determine how much storage space is used by thumbnail
     * data.
     */
    @objc private func querySpaceUsed() {
        self.maintenance.getSpaceUsed() { (size, error) in
            // present error
            if let error = error {
                DDLogError("Failed to size cache: \(error)")
                self.presentError(error, modalFor: self.view.window!,
                                  delegate: nil, didPresent: nil,
                                  contextInfo:nil)
            }
            // we got the size
            else {
                DispatchQueue.main.async {
                    self.dataSpaceUsed = size
                    self.dataSpaceUsedAvailable = true
                }
            }
        }
    }
}
