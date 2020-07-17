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
    
    /// Currently selected offline rendering GPU index
    @objc dynamic private var offlineRenderDeviceIdx: NSNumber? = nil {
        didSet {
            // ensure there is an index
            guard let index = self.offlineRenderDeviceIdx?.intValue else {
                return
            }
            
            DDLogVerbose("Index: \(index)")
            guard index < self.gpuDevices.count else {
                return
            }
            
            let device = self.gpuDevices[index]
            self.offlineRenderDeviceId = device.registryID
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
    
        // process each installed device
        self.updateGpuDisplayList(devices)
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
        var names: [String] = []
        
        for device in devices {
            names.append(self.displayStringForGpu(device))
        }
        
        DDLogVerbose("Device names: \(names)")
        
        DispatchQueue.main.async {
            self.gpuDeviceNames = names
            self.gpuDevices = devices
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
    
    // MARK: - Preferences
    /// Are thumbnail preferences accessible? If not, assume we're loading them
    @objc dynamic private var xpcPrefsAvailable: Bool = false
    
    /// Automatic gpu device selection for offline renders
    @objc dynamic private var autoselectOfflineRenderDevice = true
    /// Is the gpu used to render user-interactive data the same as is backing the view?
    @objc dynamic private var matchDisplayDevice = true
    
    /// Registry id of the offline render device. Ignored if autoselection is enabled
    @objc dynamic private var offlineRenderDeviceId: UInt64 = 0
    
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
                self.autoselectOfflineRenderDevice = config[RendererXPCConfigKey.autoselectOfflineRenderDevice.rawValue] as! Bool
                self.matchDisplayDevice = config[RendererXPCConfigKey.matchDisplayDevice.rawValue] as! Bool
                
                if let id = config[RendererXPCConfigKey.offlineRenderDeviceId.rawValue] as? UInt64,
                   let index = self.gpuDevices.firstIndex(where: { $0.registryID == id }) {
                    self.offlineRenderDeviceIdx = NSNumber(value: index)
                }
                
                self.xpcPrefsAvailable = true
            }
        }
    }
    
    /**
     * Saves the preferences back to the xpc service.
     */
    @IBAction private func saveServicePrefs(_ sender: Any?) {
        // create a settings dict
        let dict: [String: Any] = [
            RendererXPCConfigKey.autoselectOfflineRenderDevice.rawValue: self.autoselectOfflineRenderDevice,
            RendererXPCConfigKey.offlineRenderDeviceId.rawValue: self.offlineRenderDeviceId,
            RendererXPCConfigKey.matchDisplayDevice.rawValue: self.matchDisplayDevice,
        ]
        
        self.maintenance?.setConfig(dict)
    }
}
