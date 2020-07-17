//
//  RenderPreferencesViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200716.
//

import Cocoa
import Metal

import Bowl
import CocoaLumberjackSwift

class RenderPreferencesViewController: NSViewController {
    /// Maintenance endpoint of the renderer service
    @objc dynamic weak private var maintenance: RendererMaintenanceXPCProtocol!
    
    /**
     * When the view is about to appear, install the GPU device observer. This is used to populate dropdowns in the UI that let the user
     * select a specific GPU (or combinations of GPUs) to render with.
     */
    override func viewWillAppear() {
        super.viewWillAppear()
        self.setUpGpuObserver()
    }
    
    /**
     * When the view has appeared, establish a connection to the maintenance endpoint in the renderer
     */
    override func viewDidAppear() {
        super.viewDidAppear()
        
        RenderManager.shared.getMaintenanceEndpoint() { res in
            switch res {
            // couldn't get the maintenance endpoint
            case .failure(let err):
                DDLogError("Failed to get renderer maintenance endpoint: \(err)")
                
                if let window = self.view.window {
                    NSApp.presentError(err, modalFor: window, delegate: nil, didPresent: nil,
                                       contextInfo: nil)
                } else {
                    NSApp.presentError(err)
                }
            
            // we got the endpoint
            case .success(let ep):
                self.maintenance = ep
                self.getServicePrefs(self)
            }
        }
        self.xpcPrefsAvailable = true
    }
    
    /**
     * When the view is disappearing, make sure we close the maintenance endpoint connection.
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // save preferences
        self.saveServicePrefs(nil)
    
        // invalidate management connection and any cached values
        RenderManager.shared.closeMaintenanceEndpoint()
        self.maintenance = nil
        
        // remove the GPU observer
        self.removeGpuObserver()
    }
    
    // MARK: - GPU Selections
    /// Previously installed Metal device observer
    private var gpuObserver: NSObjectProtocol? = nil
    /// Metal devices currently installed in the system
    private var gpuDevices: [MTLDevice] = []
    /// Display names for each GPU device.
    @objc dynamic private var gpuDeviceNames: [String] = []
    
    /// Display name for the system default GPU
    @objc dynamic private var defaultGpuName: String? = nil
    
    /// Currently selected offline rendering GPU index
    @objc dynamic private var offlineRenderDeviceIdx: NSNumber? = nil {
        didSet {
            // ensure there is a valid index
            guard let index = self.offlineRenderDeviceIdx?.intValue,
                  index < self.gpuDevices.count else {
                return
            }
            self.offlineRenderDeviceId = self.gpuDevices[index].registryID
        }
    }
    
    /// Currently selected display rendering GPU index
    @objc dynamic private var displayRenderDeviceIdx: NSNumber? = nil {
        didSet {
            // ensure there is a valid index
            guard let index = self.displayRenderDeviceIdx?.intValue,
                  index < self.gpuDevices.count else {
                return
            }
            self.displayRenderDeviceId = self.gpuDevices[index].registryID
        }
    }
    
    /**
     * Installs an observer to catch any device insertions/removals.
     */
    private func setUpGpuObserver() {
        // install the observer
        let (devices, obs) = MTLCopyAllDevicesWithObserver() { device, type in
            DDLogInfo("Device notification (type \(type)) with device \(device) received")
            
            DispatchQueue.main.async {
                var devices = self.gpuDevices
                
                if type == .wasAdded {
                    devices.append(device)
                } else if type == .wasRemoved {
                    devices.removeAll(where: { $0.registryID == device.registryID })
                }
                
                if type != .removalRequested {
                    self.updateGpuDisplayList(devices)
                }
            }
        }
        
        self.gpuObserver = obs
    
        // process each installed device and select the system default device by default
        self.updateGpuDisplayList(devices)

        DispatchQueue.main.async {
            if let id = MTLCreateSystemDefaultDevice()?.registryID,
               let index = self.gpuDevices.firstIndex(where: { $0.registryID == id}) {
                if self.offlineRenderDeviceIdx == nil {
                    self.offlineRenderDeviceIdx = NSNumber(value: index)
                }
                if self.displayRenderDeviceIdx == nil {
                    self.displayRenderDeviceIdx = NSNumber(value: index)
                }
            }
        }
    }
    
    /**
     * Removes the GPU observer.
     */
    private func removeGpuObserver() {
        if let obs = self.gpuObserver {
            MTLRemoveDeviceObserver(obs)
        }
    }
    
    /**
     * Updates the display list of GPUs.
     */
    private func updateGpuDisplayList(_ devices: [MTLDevice]) {
        // get display names for all GPUs
        var names: [String] = []
        
        for device in devices {
            names.append(self.displayStringForGpu(device))
        }
        
        DDLogVerbose("Device names: \(names)")
        
        DispatchQueue.main.async {
            self.gpuDeviceNames = names
            self.gpuDevices = devices
        }
        
        // then for the system main device
        if let device = MTLCreateSystemDefaultDevice() {
            let name = self.displayStringForGpu(device)
            DispatchQueue.main.async {
                self.defaultGpuName = name
            }
        }
    }
    
    /**
     * Returns a display string for the given device.
     */
    private func displayStringForGpu(_ device: MTLDevice) -> String {
        // get the appropriate format string depending on the GPU location
        var formatKey = ""
        
        switch device.location {
        case .builtIn:
            formatKey = "gpu.name.builtin"
        case .external:
            formatKey = "gpu.name.external"
        case .slot:
            formatKey = "gpu.name.slot"
        case .unspecified:
            formatKey = "gpu.name.unspecified"
        @unknown default:
            formatKey = "gpu.name.default"
        }
        
        let format = Bundle.main.localizedString(forKey: formatKey, value: nil,
                                                 table: "RenderPreferencesViewController")
        
        // produce formatted string
        return String(format: format, device.name, device.locationNumber,
                      device.isRemovable ? "✅" : "❌", device.isLowPower ? "✅" : "❌",
                      device.isHeadless ? "✅" : "❌")
    }
    
    /**
     * Selects the default gpu for the offline device.
     */
    @IBAction private func selectDefaultForOfflineGpu(_ sender: Any?) {
        if let id = MTLCreateSystemDefaultDevice()?.registryID,
            let index = self.gpuDevices.firstIndex(where: { $0.registryID == id}) {
             self.offlineRenderDeviceIdx = NSNumber(value: index)
         }
    }
    
    /**
     * Selects the default gpu for the display device.
     */
    @IBAction private func selectDefaultForDisplayGpu(_ sender: Any?) {
        if let id = MTLCreateSystemDefaultDevice()?.registryID,
            let index = self.gpuDevices.firstIndex(where: { $0.registryID == id}) {
             self.displayRenderDeviceIdx = NSNumber(value: index)
         }
    }
    
    // MARK: - Preferences
    /// Are thumbnail preferences accessible? If not, assume we're loading them
    @objc dynamic private var xpcPrefsAvailable: Bool = false
    
    /// Automatic gpu device selection for offline renders
    @objc dynamic private var autoselectOfflineRenderDevice = true
    /// Is the gpu used to render user-interactive data the same as is backing the view?
    @objc dynamic private var matchDisplayDevice = true
    
    /// Registry id of the offline render device. Ignored if autoselection is enabled
    @objc dynamic private var offlineRenderDeviceId: UInt64 = 0
    /// Registry id of the display render device. Ignored if matching the display GPU
    @objc dynamic private var displayRenderDeviceId: UInt64 = 0
    
    /**
     * Gets the preferences dictionary from the thumbs endpoint.
     */
    private func getServicePrefs(_ sender: Any?) {
        // mark prefs as unavailable
        DispatchQueue.main.async {
            self.xpcPrefsAvailable = false
        }
        
        // request the new config
        self.maintenance!.getConfig()
        { config in
            // update the ui
            DispatchQueue.main.async {
                // offline renderer options
                self.autoselectOfflineRenderDevice = config[RendererXPCConfigKey.autoselectOfflineRenderDevice.rawValue] as! Bool
                if let id = config[RendererXPCConfigKey.offlineRenderDeviceId.rawValue] as? UInt64 {
                    // if that GPU already exists, select it
                    if let index = self.gpuDevices.firstIndex(where: { $0.registryID == id }) {
                        self.offlineRenderDeviceIdx = NSNumber(value: index)
                    }
                    // TODO: handle the case where it no longer exists
                    // for now, we fall back to the default item being selected
                    DDLogError("offline rendering GPU with registry ID \(id) no longer exists! (devices: \(self.gpuDevices)")
                }
                
                // user interactive (display) renderer options
                self.matchDisplayDevice = config[RendererXPCConfigKey.matchDisplayDevice.rawValue] as! Bool
                if let id = config[RendererXPCConfigKey.displayRenderDeviceId.rawValue] as? UInt64 {
                    // if that GPU already exists, select it
                    if let index = self.gpuDevices.firstIndex(where: { $0.registryID == id }) {
                        self.displayRenderDeviceIdx = NSNumber(value: index)
                    }
                    // TODO: handle the case where it no longer exists
                    DDLogError("display GPU with registry ID \(id) no longer exists! (devices: \(self.gpuDevices)")
                }
                
                // mark properties as available
                self.xpcPrefsAvailable = true
            }
        }
    }
    
    /**
     * Saves the preferences back to the xpc service.
     */
    @IBAction private func saveServicePrefs(_ sender: Any?) {
        // basic settings that don't change based on state
        var dict: [String: Any] = [
            RendererXPCConfigKey.autoselectOfflineRenderDevice.rawValue: self.autoselectOfflineRenderDevice,
            RendererXPCConfigKey.matchDisplayDevice.rawValue: self.matchDisplayDevice,
        ]
        
        // offline and display render device id's
        if !self.autoselectOfflineRenderDevice {
            dict[RendererXPCConfigKey.offlineRenderDeviceId.rawValue] = self.offlineRenderDeviceId
        }
        if !self.matchDisplayDevice {
            dict[RendererXPCConfigKey.displayRenderDeviceId.rawValue] = self.displayRenderDeviceId
        }
        
        self.maintenance?.setConfig(dict)
    }
}
