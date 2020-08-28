//
//  ImportViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200827.
//

import Cocoa
import ImageCaptureCore

import Smokeshop
import CocoaLumberjackSwift

/**
 * Drives the main import window UI, enumerating connected devices.
 */
class ImportViewController: NSViewController, ICDeviceBrowserDelegate, NSMenuDelegate {
    // MARK: - Initialization
    /**
     * Prepares the device browser.
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.initDeviceBrowser()
    }
    
    /**
     * Begins device browsing when the view is about to appear.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.startBrowsing()
    }
    
    /**
     * Ends device browsing after the view has disappeared.
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        self.stopBrowsing()
    }
    
    /**
     * Clear the cached list of devices.
     */
    override func viewDidDisappear() {
        super.viewDidDisappear()
        
        self.devices.removeAll()
    }
    
    // MARK: - UI Actions
    /**
     * Import button action
     */
    @IBAction private func importAction(_ sender: Any) {
        
    }
    
    // MARK: - Device browsing
    /// Device browser
    private var browser: ICDeviceBrowser! = nil
    
    /**
     * Creates the device brwoser.
     */
    private func initDeviceBrowser() {
        self.browser = ICDeviceBrowser()
        self.browser.delegate = self
        self.browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue:
                                                                ICDeviceLocationTypeMask.local.rawValue |
                                                                    ICDeviceLocationTypeMask.shared.rawValue |
                                                                    ICDeviceLocationTypeMask.bonjour.rawValue |
                                                                    ICDeviceLocationTypeMask.remote.rawValue |
                                                                    ICDeviceLocationTypeMask.bluetooth.rawValue |
                                                                ICDeviceTypeMask.camera.rawValue)!
    }
    
    /**
     * Begins browsing devices.
     */
    private func startBrowsing() {
        DDLogInfo("Starting device browsing: \(self.browser)")
        
        self.enumeratingDevices = true
        self.browser.start()
    }
    
    /**
     * Stops browsing for devices.
     */
    private func stopBrowsing() {
        DDLogInfo("Stopping device browsing: \(self.browser) (devices: \(self.browser.devices))")
        
        self.enumeratingDevices = false
        self.browser.stop()
    }
    
    // MARK: Device browser delegate
    /// Whether we're currently enumerating devices (used to drive UI)
    @objc dynamic private var enumeratingDevices: Bool = false
    
    /**
     * A new device was located
     */
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        DDLogInfo("Discovered device: \(device) (more: \(moreComing))")
        self.addDevice(device)
    }
    
    /**
     * Device was disappeared
     */
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        DDLogInfo("Disappeared device: \(device) (more disappearing: \(moreGoing))")
    }
    
    /**
     * Enumeration of devices has completed.
     */
    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        DDLogInfo("Finished device enumeration")
        
        DispatchQueue.main.async {
            self.enumeratingDevices = false
        }
    }
    
    // MARK: Device list UI
    /// Device info structs
    @objc dynamic private var devices: [DeviceInfo] = []

    /**
     * Adds/updates the device info entry for this device
     */
    private func addDevice(_ device: ICDevice) {
        let info = DeviceInfo()
        info.device = device
        info.name = device.name ?? Self.localized("device.name.unknown")
        
        if let icon = device.icon {
            info.icon = NSImage(cgImage: icon, size: .zero)            
        }
        
        self.devices.append(info)
    }
    
    /**
     * Properly display each of the device menu items.
     */
    func menuNeedsUpdate(_ menu: NSMenu) {
        var i = 0
        
        for item in menu.items {
            let device = self.devices[i]
            item.title = device.name
            item.image = device.icon
            i += 1
        }
    }
    
    @objc(ImportViewControllerDeviceInfo) private class DeviceInfo: NSObject {
        /// Name of the device
        @objc dynamic var name: String = "<no name>"
        /// Device icon
        @objc dynamic var icon: NSImage?
        
        /// Ref to the device
        var device: ICDevice!
    }
    
    // MARK: - Helpers
    static func localized(_ key: String) -> String {
        return Bundle.main.localizedString(forKey: key, value: nil, table: "Importing")
    }
}
