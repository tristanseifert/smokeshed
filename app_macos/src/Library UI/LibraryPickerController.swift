//
//  LibraryPickerController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200605.
//

import Cocoa

/**
 * Provides an UI to allow picking a library.
 */
class LibraryPickerController: NSWindowController, NSWindowDelegate {
    /// URL of the library to open
    private var pickedUrl: URL! = nil
    
    /**
     * Provide the nib name.
     */
    override var windowNibName: NSNib.Name? {
        return "LibraryPickerController"
    }
    
    /**
     * Once UI has loaded, populate the recent libraries list.
     */
    override func windowDidLoad() {
        super.windowDidLoad()
        
        self.loadHistory()
    }
    
    // MARK: - Modal handling
    /**
     * Modally presents the window. The URL of a new library to open, or nil if the process was aborted, is
     * returned.
     */
    func presentModal() -> URL! {
        let resp = NSApp.runModal(for: self.window!)
        
        // dismiss the window when we return
        self.window?.close()
    
        // was the "open selected" option chosen?
        if resp == .OK {
            return self.pickedUrl
        }
        // no URL was decided on
        else {
            return nil
        }
    }
    
    /**
     * If the window was closed, abort the modal session.
     */
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }
    
    // MARK: - General UI
    /// Box containing detail info
    @IBOutlet var detailsBox: NSBox! = nil
    /// Layout constraint for box height
    @IBOutlet var detailsHeightConstraint: NSLayoutConstraint! = nil
    
    /**
     * Handles the disclosure triangle button for the library details box.
     */
    @IBAction func detailsDisclosure(_ sender: NSButton) {
        // show details view
        if sender.state == .on {
            detailsBox.isHidden = false
            
            NSAnimationContext.runAnimationGroup({ (ctx) in
                ctx.duration = 0.125
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                detailsBox.animator().alphaValue = 1.0
                detailsHeightConstraint.animator().constant = 100
            }, completionHandler: {
                // nothing
            })
        }
        // hide the details view
        else {
            NSAnimationContext.runAnimationGroup({ (ctx) in
                ctx.duration = 0.125
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                detailsBox.animator().alphaValue = 0.0
                detailsHeightConstraint.animator().constant = 0
            }, completionHandler: {
                self.detailsBox.isHidden = true
            })
        }
    }
    
    /**
     * Opens help for the window.
     */
    @IBAction func openHelp(_ sender: Any) {
        // TODO: implement
    }
    
    // MARK: - History
    /**
     * Wrapper structure to represent a history entry.
     */
    class HistoryEntry: NSObject {
        /**
         * Initializes a history entry with the given file path. The timestamps and sizes will be loaded
         * automatically.
         */
        init(_ url: URL) {
            self.fullUrl = url
            
            // get timestamps and size
            do {
                let attribs = try FileManager.default.attributesOfItem(atPath: url.path)
                
                self.filesize = attribs[.size] as! UInt
                self.lastOpened = attribs[.modificationDate] as? Date
                self.created = attribs[.creationDate] as? Date
                
                // library is accessible if we got its attributes
                self.accessible = true
            } catch {
                // ignore errors
            }
        }
        
        /// An icon for the file; this will probably just be the file type icon
        @objc dynamic var icon: NSImage! {
            return NSWorkspace.shared.icon(forFile: self.fullUrl.path)
        }
        /// Full URL of the library file
        @objc dynamic var fullUrl: URL! = nil
        /// Date last opened
        @objc dynamic var lastOpened: Date! = nil
        /// Date created
        @objc dynamic var created: Date! = nil
        /// Filesize (of library by itself)
        @objc dynamic var filesize: UInt = 0
        /// Number of photos in library
        @objc dynamic var numPhotos: UInt = 0
        /// Whether this library is accessible
        @objc dynamic var accessible: Bool = false
        
        /// Filename component of the URL
        @objc dynamic var filename: String! {
            guard let url = self.fullUrl else {
                return NSLocalizedString("<Unknown filename>",
                                         comment: "LibraryPickerController nil url filename")
            }
            
            return url.lastPathComponent
        }
    }
    
    /**
     * Array displayed in the history list. This must be objc accessible, and KVO observable, as the UI binds
     * an array controller to it.
     */
    @objc dynamic var historyArray = [HistoryEntry]()
    
    /// Array controller for history
    @IBOutlet var historyController: NSArrayController!
    
    /**
     * Loads recently opened libraries from the history file. This file may not exist, which is not a fatal error.
     */
    private func loadHistory() {
        let libraries = LibraryHistoryManager.getLibraries()
        var entries = [HistoryEntry]()
        
        for url in libraries {
            entries.append(HistoryEntry(url))
        }
        
        self.historyArray = entries
    }
    
    /**
     * Opens the library that is currently selected.
     */
    @IBAction func openSelected(_ sender: Any) {
        // make sure we got a selection
        guard let objs = self.historyController.selectedObjects,
            let selected = objs.first as? HistoryEntry else {
            // no selection :(
            return
        }
        
        // use it
        self.pickedUrl = selected.fullUrl
        NSApp.stopModal(withCode: .OK)
    }
    
    // MARK: - Browsing
    /**
     * Creates a new library, showing a save file picker.
     */
    @IBAction func newLibrary(_ sender: Any) {
        self.pickedUrl = nil
        
        let panel = NSSavePanel()
        
        panel.canCreateDirectories = true
        panel.allowedFileTypes = ["me.tseifert.smokeshed.library"]
        panel.nameFieldStringValue = "Library.smokelib"
        
        do {
            try panel.directoryURL = FileManager.default.url(for: .picturesDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: false)
        } catch {
            // ignore error
        }
        
        panel.prompt = NSLocalizedString("Create Library", comment: "LibraryPickerController library create sheet prompt")
        
        panel.beginSheetModal(for: self.window!, completionHandler: { (resp) in
            if resp == .OK {
                self.pickedUrl = panel.url
                NSApp.stopModal(withCode: .OK)
            } else {
                // no file was selected
            }
        })
    }
    
    /**
     * Open the file picker to open a library.
     */
    @IBAction func openLibrary(_ sender: Any) {
        self.pickedUrl = nil
        
        let panel = NSOpenPanel()
        
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["me.tseifert.smokeshed.library"]
        
        panel.prompt = NSLocalizedString("Open Library", comment: "LibraryPickerController library open sheet prompt")
        
        panel.beginSheetModal(for: self.window!, completionHandler: { (resp) in
            if resp == .OK {
                self.pickedUrl = panel.url
                NSApp.stopModal(withCode: .OK)
            } else {
                // no file was selected
            }
        })
    }
    
    // MARK: - Errors
    /**
     * If the reason this controller is to be presented was because of an error loading a library, provide the
     * relevant faulting URL and error information.
     */
    func setErrorInfo(url: URL!, error: Error!) {
        
    }
}
