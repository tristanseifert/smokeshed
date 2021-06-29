//
//  ThumbPreferencesViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200626.
//

import Cocoa
import UniformTypeIdentifiers
import OSLog

import Bowl

class ThumbPreferencesViewController: NSViewController {
    fileprivate static var logger = Logger(subsystem: Bundle(for: ThumbPreferencesViewController.self).bundleIdentifier!,
                                         category: "ThumbPreferencesViewController")
    
    /// Maintenance endpoint of the thumb service
    @objc dynamic weak private var maintenance: ThumbXPCMaintenanceEndpoint!
    
    // MARK: - View lifecycle
    /// Event observer used to determine if the option key is pressed.
    private var optEventMonitor: Any? = nil
    
    /**
     * When the view has appeared, establish a connection to the maintenance endpoint in the thumb
     * service.
     */
    override func viewDidAppear() {
        super.viewDidAppear()
        
        ThumbHandler.shared.getMaintenanceEndpoint() { ep in
            self.maintenance = ep
            
            // get the storage directory and update used space
            self.getServicePrefs(nil)
        }
        
        // register the event handler for handling the option key
        precondition(self.optEventMonitor == nil)
        
        self.optEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.updateOptPressed(event)
            
            // we have to return the event or it gets A N G E R E Y
            return event
        }
    }
    
    /**
     * When the view is disappearing, make sure we close the maintenance endpoint connection.
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // de-register the option key handler
        if let monitor = self.optEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.optEventMonitor = nil
        }
        self.optPressed = false
        
        // save preferences
        self.saveServicePrefs(nil)
    
        // invalidate management connection and any cached values
        ThumbHandler.shared.closeMaintenanceEndpoint()
        self.maintenance = nil
        
        self.dataSpaceUsedAvailable = false
    }
    
    /**
     * Clean up resources on dealloc.
     */
    deinit {
        // Remove the options key event monitor if we have one
        if let monitor = self.optEventMonitor {
            NSEvent.removeMonitor(monitor)
            self.optEventMonitor = nil
        }
        
        // release maintenance endpoint
        self.maintenance = nil
    }
    
    // MARK: Alternate UI
    /// Is the option key currently pressed?
    @objc dynamic private var optPressed: Bool = false
    
    /**
     * Determines from the event mask whether the option key is pressed.
     */
    private func updateOptPressed(_ event: NSEvent) {
        self.optPressed = event.modifierFlags.contains(.option)
    }
    
    // MARK: - Preferences
    /// Are thumbnail preferences accessible? If not, assume we're loading them
    @objc dynamic private var xpcPrefsAvailable: Bool = false
    
    /// Automatically size the thumb chunk cache
    @objc dynamic private var autoSizeChunkCache: Bool = false
    /// Size of the chunk cache in bytes
    @objc dynamic private var chunkCacheSize: Int64 = 0
    /// Whether the thumb generator work queue size is automatically managed
    @objc dynamic private var autoSizeGeneratorQueue: Bool = true
    /// Number of threads in the work queue
    @objc dynamic private var generatorQueueThreads: Int64 = 0
    
    /**
     * Gets the preferences dictionary from the thumbs endpoint.
     */
    private func getServicePrefs(_ sender: Any?) {
        DispatchQueue.main.async {
            self.xpcPrefsAvailable = false
        }
        
        // TODO
        self.maintenance!.getConfig()
        { config in
            // update the ui
            DispatchQueue.main.async {
                self.autoSizeChunkCache = config[ThumbXPCConfigKey.chunkCacheSizeAuto.rawValue] as! Bool
                self.chunkCacheSize = config[ThumbXPCConfigKey.chunkCacheSize.rawValue] as! Int64
                
                self.autoSizeGeneratorQueue = config[ThumbXPCConfigKey.workQueueSizeAuto.rawValue] as! Bool
                self.generatorQueueThreads = config[ThumbXPCConfigKey.workQueueSize.rawValue] as! Int64
                
                self.xpcPrefsAvailable = true
            }
            
            // get the rest of the values
            self.updateStoragePath(nil)
            self.getSpaceUsed(nil)
        }
    }
    
    /**
     * Saves the preferences back to the xpc service.
     */
    private func saveServicePrefs(_ sender: Any?) {
        // create a settings dict
        let dict: [String: Any] = [
            ThumbXPCConfigKey.chunkCacheSizeAuto.rawValue: self.autoSizeChunkCache,
            ThumbXPCConfigKey.chunkCacheSize.rawValue: self.chunkCacheSize,
            ThumbXPCConfigKey.workQueueSizeAuto.rawValue: self.autoSizeGeneratorQueue,
            ThumbXPCConfigKey.workQueueSize.rawValue: self.generatorQueueThreads
        ]
        
        self.maintenance?.setConfig(dict)
    }
    
    // MARK: - Stats
    /// Is thumbnail cache size information available?
    @objc dynamic private var dataSpaceUsedAvailable: Bool = false
    /// Bytes on disk taken up by the thumbnail data
    @objc dynamic private var dataSpaceUsed: UInt = 0
    
    /**
     * Updates the displayed storage path of the thumbnail data.
     */
    @IBAction private func updateStoragePath(_ sender: Any?) {
        self.maintenance.getStorageDir() { url in
            DispatchQueue.main.async {
                self.storageLocation = url
            }
        }
    }
    
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
                Self.logger.error("Failed to size cache: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    self.presentError(error, modalFor: self.view.window!, delegate: nil,
                                      didPresent: nil, contextInfo:nil)
                }
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
    
    // MARK: - Thumb storage moving
    /// Current storage location
    @objc dynamic private var storageLocation: URL! = nil
    
    /// Storage location open panel accessory view
    @IBOutlet private var storageOpenPanelAccessory: NSView!
    
    /// Should existing thumbnail data be copied when moving thumbnail data?
    @objc dynamic private var shouldCopyThumbData: Bool = true
    /// Should the old thumbnail data be trashed after copying?
    @objc dynamic private var shouldTrashOldThumbData: Bool = true
    
    /**
     * Handles the "change location" button in the preferences window to allow the thumbnail storage to be moved.
     *
     * This will present an open panel where the user can choose a directory in which the thumbnail structure is created. That open
     * panel shows as an accessory a custom view that lets the user choose whether their existing thumbnails are moved or deleted. If
     * the old location was not the default path, an option to keep the files in place is presented as well.
     */
    @IBAction private func changeStorageLocation(_ sender: Any) {
        guard let sender = sender as? NSButton,
              let window = sender.window else {
            return
        }
        
        // prepare the panel
        let panel = NSSavePanel()
        
        panel.allowedContentTypes = [
            UTType("me.tseifert.smokeshed.thumbs")!
        ]
        
        panel.accessoryView = self.storageOpenPanelAccessory
        
        panel.title = Self.localized("picker.title")
        panel.prompt = Self.localized("picker.prompt")
        
        panel.nameFieldStringValue = Self.localized("picker.name.default")
        
        // show it
        panel.beginSheetModal(for: window) {
            self.changeStorageLocationPickerCompletion(panel, $0)
        }
    }
    
    /**
     * Completion handler for the picker open panel
     */
    private func changeStorageLocationPickerCompletion(_ panel: NSSavePanel, _ how: NSApplication.ModalResponse) {
        // user _must_ have pressed OK
        guard how == NSApplication.ModalResponse.OK,
              let url = panel.url else {
            return
        }
        
        // move it
        Self.logger.info("Moving thumbs to: \(url)")
        panel.orderOut(nil)
        
        self.moveLibrary(url, copy: self.shouldCopyThumbData,
                         trashOld: self.shouldTrashOldThumbData)
    }
    
    /**
     * Handles the "reset to default" button for the thumbnail storage location.
     *
     * The user will be presented an alert asking whether their existing thumbnails should be left in place, deleted, or moved to the
     * new default storage location.
     */
    @IBAction private func resetStorageLocation(_ sender: Any) {
        // present an alert
        let alert = NSAlert()
        
        alert.messageText = Self.localized("reset.confirm.title")
        alert.informativeText = Self.localized("reset.confirm.detail")
        
        alert.addButton(withTitle: Self.localized("reset.confirm.btn.cancel"))
        alert.addButton(withTitle: Self.localized("reset.confirm.btn.move"))
        
        alert.beginSheetModal(for: self.view.window!) { resp in
            // ensure that the "move" button was pressed
            guard resp == .alertSecondButtonReturn else {
                return
            }

            // perform the move
            let thumbDir = ContainerHelper.groupAppCache(component: .thumbHandler)
            let bundleUrl = thumbDir.appendingPathComponent("Thumbs.smokethumbs",
                                                            isDirectory: true)
            
            DispatchQueue.main.async {
                self.moveLibrary(bundleUrl, copy: true, trashOld: false)
            }
        }
    }
    
    /**
     * Sets up a progress object, shows the progress status and moves the thumb library to the given url.
     */
    private func moveLibrary(_ url: URL, copy: Bool, trashOld: Bool) {
        // create progress
        self.moveProgress = Progress(totalUnitCount: 1)
        self.moveProgress?.kind = .none
        
        self.progressKvo = self.moveProgress?.observe(\.fractionCompleted, options: .initial)
        { progress, _ in
            DispatchQueue.main.async {
                self.moveProgressPercent = progress.fractionCompleted
            }
        }
        
        // present the progress window
        self.progressWindowAnimating = true
        self.view.window!.beginSheet(self.progressWindow, completionHandler: nil)
        
        // make request to move
        self.moveProgress?.becomeCurrent(withPendingUnitCount: 1)
        self.maintenance.moveThumbStorage(to: url, copyExisting: copy, deleteExisting: trashOld) {
            self.moveCallback($0)
        }
        
        self.moveProgress?.resignCurrent()
    }
    
    // MARK: Progress handling
    /// Progress indicating window
    @IBOutlet private var progressWindow: NSWindow!
    /// Are controls in the progress window animating?
    @objc dynamic private var progressWindowAnimating: Bool = true
    
    /// Progress object that's being observed
    @objc dynamic private var moveProgress: Progress? = nil
    /// Percentage complete with thumb moving
    @objc dynamic private var moveProgressPercent: Double = 0
    
    
    /// KVO on progress completion
    private var progressKvo: NSKeyValueObservation? = nil
    
    /**
     * Request callback
     */
    private func moveCallback(_ error: Error?) {
        // dismiss the progress window
        DispatchQueue.main.async {
            self.view.window!.endSheet(self.progressWindow)
        }
        
        // was there an error?
        if let err = error {
            Self.logger.error("Failed to move thumbs: \(err.localizedDescription)")
            
            DispatchQueue.main.async {
                self.presentError(err, modalFor: self.view.window!, delegate: nil, didPresent: nil,
                                  contextInfo: nil)
            }
        }
        // success?
        else {
            Self.logger.info("Success, finished moving")
            
            self.getSpaceUsed(nil)
            self.updateStoragePath(nil)
        }
        
        // remove kvo
        self.progressKvo = nil
    }
    
    
    // MARK: - Helpers
    /**
     * Returns a localized string.
     */
    private static func localized(_ identifier: String) -> String {
        return Bundle.main.localizedString(forKey: identifier, value: nil,
                                           table: "ThumbPreferencesViewController")
    }
    
}

