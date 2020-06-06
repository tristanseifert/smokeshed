//
//  AppDelegate.swift
//  SmokeShed
//
//  Created by Tristan Seifert on 20200605.
//

import Cocoa
import Bowl

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
        self.openDataStore()
        
        // TODO: do stuff
    }

    /**
     * Begins tearing down the app logic and UI, and notifies the external components to finish up whatever
     * they're busy with.
     */
    func applicationWillTerminate(_ aNotification: Notification) {
        // TODO: do stuff
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
    /**
     * Implements the data store loading and info window logic.
     */
    func openDataStore() {
    }
    
    /**
     * Presents the data store picker. A tuple of attempted URL and error can be passed to display an error
     * why a store failed to open.
     */
    func presentStorePicker(_ failureInfo: (URL, Error)?) {
    }
}

