//
//  AppDelegate.swift
//  SmokeShed
//
//  Created by Tristan Seifert on 20200605.
//

import Cocoa

import Bowl
import Smokeshop
import CocoaLumberjackSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    /**
     * Performs some initialization for the external components (such as logging, some XPC stuff) before
     * the actual app logic (and UI) is created.
     */
    func applicationWillFinishLaunching(_ notification: Notification) {
        // register user defaults
        if let url = Bundle.main.url(forResource: "Defaults",
                                     withExtension: "plist"),
            let defaults = NSDictionary(contentsOf: url) {
            UserDefaults.standard.register(defaults: defaults as! [String : Any])
        }
        
        // load the bowl
        Bowl.Logger.setup()
    }

    /**
     * Initializes all of the app logic and user interface. Additionally, the library is loaded from the last path,
     * or the "open library" dialog is shown. This message is also shown if option is held down during
     * startup.
     */
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.openLastLibrary()
        
        // TODO: do stuff
    }

    /**
     * Begins tearing down the app logic and UI, and notifies the external components to finish up whatever
     * they're busy with.
     */
    func applicationWillTerminate(_ aNotification: Notification) {
        // save library bundle if one is open
        if let library = self.library, let store = self.store {
            do {
                try store.save()
                try library.write()
            } catch {
                DDLogError("Failed to save library '\(String(describing: self.library))' during shutdown: \(error)")

                NSApp.presentError(error)
            }
        }
    }

    /**
     * Allows us to intercept application termination if there are operations ongoing.
     */
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    /**
     * Receive information when the screen's parameters change. This could indicate displays being
     * connected, resolution changes, or color space changes.
     */
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        // TODO: do stuff
    }
    
    
    // MARK: - Data store handling
    /// Currently loaded library
    private var library: LibraryBundle! = nil
    /// Data store for the loaded library
    private var store: LibraryStore! = nil

    /**
     * Implements the data store loading and info window logic.
     */
    func openLastLibrary() {
        // present the picker if option is held during startup
        if NSEvent.modifierFlags.contains(.option) {
            if self.pickLibraryAndOpen(true) {
                return
            }
        }
        
        // try the last opened library path
        var failureInfo: (URL, Error)? = nil

        if let url = LibraryHistoryManager.getMostRecentlyOpened() {
            do {
                // this will raise if library doesn't exist
                try FileManager.default.attributesOfItem(atPath: url.path)

                // if it exists, try to open the library
                return try self.openLibrary(url)
            } catch {
                // the error info will be displayed next
                failureInfo = (url, error)
            }
        }
        
        // open a picker; quit if closed but loop on error
        self.pickLibraryAndOpen(true, withErrorInfo: failureInfo)
    }

    /**
     * Repeatedly presents a picker until a library is successfully opened. The function can either return or
     * terminate the app if the picker is canceled.
     *
     * @return Whether a library was opened
     */
    @discardableResult func pickLibraryAndOpen(_ terminateOnClose: Bool = false, withErrorInfo errorInfo: (URL, Error)? = nil) -> Bool {
        var failureInfo: (URL, Error)? = errorInfo
        
        while true {
            // ask user to pick a library
            guard let url = self.presentLibraryPicker(failureInfo) else {
                // terminate or just return when done
                if terminateOnClose {
                    NSApp.terminate(self)
                    return false
                } else {
                    return false
                }
            }

            // attempt to actually open the library
            do {
                // if opening succeeds, return
                try self.openLibrary(url)
                return true
            } catch {
                // present the proper error next time
                failureInfo = (url, error)
            }
        }
    }
    
    /**
     * Attempt to open a data store at the given URL. If opening fails, the library picker is opened again but
     * with an error message.
     */
    func openLibrary(_ url: URL) throws {
        DDLogVerbose("Opening library from: \(url)")

        // load the library and its data store
        self.library = try LibraryBundle(url)
        self.store = try LibraryStore(self.library)

        // once everything loaded, add it to the history
        LibraryHistoryManager.openLibrary(url)
    }
    
    /**
     * Presents the data store picker. A tuple of attempted URL and error can be passed to display an error
     * why a store failed to open.
     */
    func presentLibraryPicker(_ failureInfo: (URL, Error)? = nil) -> URL! {
        let picker = LibraryPickerController()
        
        if let info = failureInfo {
            picker.setErrorInfo(url: info.0, error: info.1)
        }
        
        return picker.presentModal()
    }
}

