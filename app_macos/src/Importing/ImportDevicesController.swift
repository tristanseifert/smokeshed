//
//  ImportDevicesController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Foundation
import ImageCaptureCore

import CocoaLumberjackSwift

/**
 * Provides the glue between the image capture framework and the sidebar UI to allow display and import from devices that are
 * connected to the machine.
 */
internal class ImportDevicesController: NSObject, ICDeviceBrowserDelegate {
    typealias SidebarItem = ImportSidebarController.SidebarItem
    
    /// Sidebar in which the devices are appeared
    private weak var owner: ImportSidebarController!
    
    /// Device browser
    private var browser: ICDeviceBrowser!
    /// Sidebar item for the devices
    private(set) internal var sidebarItem: SidebarItem!
    
    // MARK: - Initialization
    /**
     * Initializes a new device import controller
     */
    init(_ owner: ImportSidebarController) {
        self.owner = owner
        
        super.init()
        
        // create the device browser
        self.browser = ICDeviceBrowser()
        self.browser.delegate = self
        self.browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue:
                                                                ICDeviceLocationTypeMask.local.rawValue |
                                                                    ICDeviceLocationTypeMask.shared.rawValue |
                                                                    ICDeviceLocationTypeMask.bonjour.rawValue |
                                                                    ICDeviceLocationTypeMask.remote.rawValue |
                                                                    ICDeviceLocationTypeMask.bluetooth.rawValue |
                                                                ICDeviceTypeMask.camera.rawValue)!
        
        // then, create the sidebar item
        let item = SidebarItem()
        item.isGroupItem = true
        item.title = Self.localized("sidebar.devices.title")
        
        self.sidebarItem = item
    }
    
    /**
     * Starts browsing for devices.
     */
    internal func startBrowsing() {
        self.browser.start()
    }
    
    /**
     * Stops looking for new devices.
     */
    internal func stopBrowsing() {
        self.browser.stop()
    }
    
    // MARK: - Device browser delegate
    /// Whether we're currently enumerating devices (used to drive UI)
    @objc dynamic internal var enumeratingDevices: Bool = false
    
    /**
     * A new device was located
     */
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        self.addDevice(device)
        self.updateSidebarChildren()
        
        // update sidebar
        if !moreComing {
            self.owner.updateItem(self.sidebarItem)
        }
    }
    
    /**
     * Device was disappeared
     */
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        self.devices.removeAll { $0.device == device }
        self.updateSidebarChildren()
        
        // update sidebar
        if !moreGoing {
            self.owner.updateItem(self.sidebarItem)
        }
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
    
    // MARK: - Device list UI
    /// Device info structs
    private var devices: [DeviceInfo] = []
    
    private struct DeviceInfo {
        /// Name of the device
        var name: String = "<no name>"
        /// Device icon
        var icon: NSImage?
        
        /// Ref to the device
        var device: ICDevice!
    }

    /**
     * Adds/updates the device info entry for this device
     */
    private func addDevice(_ device: ICDevice) {
        var info = DeviceInfo()
        info.device = device
        info.name = device.name ?? Self.localized("device.name.unknown")
        
        if let icon = device.icon {
            info.icon = NSImage(cgImage: icon, size: .zero)
        }
        
        self.devices.append(info)
    }
    
    /**
     * Updates the list of children item for the sidebar
     */
    private func updateSidebarChildren() {
        // remove all items that don't exist anymore
        self.sidebarItem.children.removeAll {
            let device = $0.representedObject as! ICDevice
            return !self.devices.contains {
                $0.device == device
            }
        }
        
        // update existing items or create new ones
        for device in self.devices {
            let existing = self.sidebarItem.children.first {
                let representedDevice = $0.representedObject as! ICDevice
                return representedDevice == device.device
            }
            
            // have we got an item to update?
            if let existing = existing {
                existing.title = device.name
                existing.icon = device.icon
            }
            // otherwise, create a new item
            else {
                let item = SidebarItem()
                item.title = device.name
                item.icon = device.icon
                item.representedObject = device.device
                item.viewIdentifier = SidebarItem.deviceItemType
                item.menuProvider = self.menuProvider(_:_:)
                
                self.sidebarItem.children.append(item)
            }
        }
    }
    
    // MARK: Context menus
    /// Context menu template for items
    internal var menuTemplate: NSMenu!
    
    /**
     * Returns a context menu for  the given device entry in the sidebar.
     */
    private func menuProvider(_ item: SidebarItem, _ inMenu: NSMenu?) -> NSMenu? {
        // get the device
        guard let device = item.representedObject as? ICDevice else {
            return inMenu
        }
        
        // prepare the menu template
        for item in self.menuTemplate.items {
            item.representedObject = device
        }
        
        if let item = self.menuTemplate.item(withTag: 1),
           let camera = device as? ICCameraDevice {
            item.isEnabled = camera.isEjectable
            item.target = self
        }

        return self.menuTemplate
    }
    
    /**
     * Menu action to eject the selected device
     */
    @IBAction private func ejectDevice(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let device = menuItem.representedObject as? ICDevice else {
            return
        }
        
        device.requestEject {
            if let err = $0 {
                NSApp.presentError(err)
            }
        }
    }
    
    // MARK: - Helpers
    static func localized(_ key: String) -> String {
        return Bundle.main.localizedString(forKey: key, value: nil, table: "Importing")
    }
}
