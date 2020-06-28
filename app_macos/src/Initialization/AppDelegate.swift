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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowRestoration {
    /// Main window
    var mainWindow: MainWindowController! = nil

    // MARK: - App startup
    /**
     * Performs some initialization for the external components (such as logging, some XPC stuff) before
     * the actual app logic (and UI) is created.
     */
    func applicationWillFinishLaunching(_ notification: Notification) {
        // load the bowl
        Bowl.Logger.setup()
        
        // register user defaults
        InitialDefaults.register()
    }

    /**
     * Initializes all of the app logic and user interface. Additionally, the library is loaded from the last path,
     * or the "open library" dialog is shown. This message is also shown if option is held down during
     * startup.
     */
    func applicationDidFinishLaunching(_ n: Notification) {
        let isDefault = n.userInfo![NSApplication.launchIsDefaultUserInfoKey]! as! Bool

        // if no state is being restored, run through normal library opening
        if isDefault || self.mainWindow == nil {
            self.openLastLibrary()
            
            // instantiate main window controller from storyboard
            let sb = NSStoryboard(name: "Main", bundle: nil)
            guard let wc = sb.instantiateInitialController() as? MainWindowController else {
                fatalError("Failed to create initial window controller")
            }
            
            self.mainWindow = wc
            self.mainWindow.library = self.library
        }

        // open the main window controller (it should be allocated by now)
        self.mainWindow.showWindow(self)
    }

    // MARK: App file handling
    /**
     * Open file request; this will be called when any files are dragged onto the dock icon, or a library is
     * clicked in the Finder
     */
    func application(_ application: NSApplication, open urls: [URL]) {
        DDLogInfo("Open urls: \(urls)")

        // TODO: implement
    }

    // MARK: App teardown
    /**
     * Begins tearing down the app logic and UI, and notifies the external components to finish up whatever
     * they're busy with.
     */
    func applicationWillTerminate(_ aNotification: Notification) {
        // save library bundle if one is open
        if let library = self.library {
            do {
                try library.store!.save()
                try library.write()
            } catch {
                DDLogError("Failed to save library '\(String(describing: self.library))' during shutdown: \(error)")

                NSApp.presentError(error)
            }
        }
    }

    /**
     * If the last window (the main window) is closed, the app should exit.
     */
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /**
     * Allows us to intercept application termination if there are operations ongoing.
     */
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    // MARK: Misc notifications
    /**
     * Receive information when the screen's parameters change. This could indicate displays being
     * connected, resolution changes, or color space changes.
     */
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        // TODO: do stuff
    }

    // MARK: State restoration
    /**
     * Restores the state of the main window controller. This will attempt to re-open the same library as was
     * last opened.
     */
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                              state: NSCoder,
                              completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        // get a handle to the app delegate class
        guard let delegate = NSApp.delegate as? AppDelegate else {
            DDLogError("Failed to convert delegate: \(String(describing: NSApp.delegate))")
            return completionHandler(nil, RestorationError.invalidAppDelegate)
        }

        // is it the main window?
        if identifier == .mainWindow {
            // if option is being held, skip state restoration
            if NSEvent.modifierFlags.contains(.option) {
                return completionHandler(nil, RestorationError.userRequestsPicking)
            }

            // get the url bookmark
            guard let bookmark = state.decodeObject(forKey: MainWindowController.StateKeys.libraryBookmark) as? Data else {
                DDLogError("Failed to get library url bookmark")
                return completionHandler(nil, RestorationError.invalidLibraryUrl)
            }

            // try to resolve it
            var libraryUrl: URL

            do {
                var isStale = false
                libraryUrl = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            } catch {
                DDLogError("Failed to resolve library url bookmark: \(error)")
                return completionHandler(nil, error)
            }

            // open the library
            do {
                try delegate.openLibrary(libraryUrl)
            } catch {
                DDLogError("Failed to open library from \(libraryUrl): \(error)")
                return completionHandler(nil, RestorationError.libraryLoadErr(error))
            }
            
            // create main window controller
            let sb = NSStoryboard(name: "Main", bundle: nil)
            guard let wc = sb.instantiateInitialController() as? MainWindowController else {
                return completionHandler(nil, RestorationError.failedToMakeMainController)
            }

            // done!
            delegate.mainWindow = wc
            delegate.mainWindow.library = delegate.library
            return completionHandler(wc.window, nil)
        }

        // unknown window type. should not happen
        DDLogError("Request to restore window with unknown identifier \(identifier)")
        completionHandler(nil, RestorationError.unknown)
    }

    /**
     * Errors that may take place during state restoration.
     */
    enum RestorationError: Error {
        /// Failed to get a reference to the app delegate.
        case invalidAppDelegate
        /// Unable to retrieve the URL of the library that was opened.
        case invalidLibraryUrl
        /// The user requested to pick a library on startup by holding option.
        case userRequestsPicking
        /// Failed to load the library
        case libraryLoadErr(_ underlying: Error)
        /// The main window controller couldn't be created.
        case failedToMakeMainController
        /// Unknown error; should never get this
        case unknown
    }
    
    // MARK: - App preferences
    /// Preferences window controller
    private var preferences: PreferencesWindowController? = nil
    
    /**
     * Opens the preferences window.
     */
    @IBAction func openPreferences(_ sender: Any?) {
        // allocate preferences controller if required
        if self.preferences == nil {
            let sb = NSStoryboard(name: "Preferences", bundle: nil)
            let initial = sb.instantiateInitialController()
            
            self.preferences = initial as? PreferencesWindowController
        }
        
        // show it
        self.preferences?.showWindow(sender)
    }
    
    
    // MARK: - Data store handling
    /// Currently loaded library
    private(set) internal var library: LibraryBundle! = nil

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

                self.library = nil
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

                self.library = nil
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
        self.library = try LibraryBundle(url, shouldOpenStore: true)

        // migrate store if required
        if self.library.store!.migrationRequired {
            DDLogVerbose("Migration required for library '\(url)'")
            abort() // XXX: remove this when implemented :)
        }

        // once everything loaded, add it to the history
        LibraryHistoryManager.openLibrary(url)

        // last minute setup of some internal components
        ThumbHandler.shared.pushLibraryId(self.library.identifier)
    }
    
    // MARK: Library UI
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
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to instantiate the main window controller
        case failedToMakeMainWindow
    }
}

