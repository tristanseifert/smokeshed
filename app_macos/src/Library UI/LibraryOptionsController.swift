//
//  LibraryOptionsController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200608.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

class LibraryOptionsController: NSWindowController, NSWindowDelegate {
    /// Library whose options we're adjusting
    private var library: LibraryBundle! = nil

    // MARK: - Initialization
    /**
     * Provide the nib name.
     */
    override var windowNibName: NSNib.Name? {
        return "LibraryOptionsController"
    }

    /**
     * Initializes the library controller with the given library.
     */
    init(_ library: LibraryBundle) {
        super.init(window: nil)

        // load library metadata
        self.library = library
        self.loadMetadata()
    }
    /// Decoding the controller is not supported.
    required init?(coder: NSCoder) {
        return nil
    }

    /**
     * Reset any constraints that were set to make design easier.
     */
    override func windowDidLoad() {
        super.windowDidLoad()
    }

    /**
     * Presents the controller as a modal sheet on the given parent window. Using this method ensures that
     * metadata is up-to-date when the window is displayed.
     */
    public func present(_ parent: NSWindow) {
        self.loadMetadata()

        parent.beginSheet(self.window!, completionHandler: nil)
    }

    // MARK: - Metadata handling
    /// Library name string
    @objc dynamic var libraryName: String! = nil
    /// Library detailed description string
    @objc dynamic var libraryDesc: String! = nil
    /// Library creator name
    @objc dynamic var libraryCreator: String! = nil

    /**
     * Loads metadata from the library file and populates our copies of it.
     */
    private func loadMetadata() {
        let meta = self.library.getMetadata()

        self.libraryName = meta.displayName
        self.libraryDesc = meta.userDescription

        self.libraryCreator = meta.creatorName
    }

    /**
     * Copies our changes to the library metadata.
     */
    private func saveMetadata() {
        var meta = self.library.getMetadata()

        meta.displayName = self.libraryName
        meta.userDescription = self.libraryDesc
        meta.creatorName = self.libraryCreator

        self.library.setMetadata(meta)
    }

    // MARK: - Window lifecycle
    /**
     * Action for the help button.
     */
    @IBAction func helpAction(_ sender: Any) {

    }

    /**
     * Action for the dismiss button.
     */
    @IBAction func dismissAction(_ sender: Any) {
        // restore changes to library metadata
        self.saveMetadata()

        // save library
        do {
            try self.library.write()
            self.window!.sheetParent?.endSheet(self.window!, returnCode: .OK)
        } catch {
            DDLogError("Failed to save library changes: \(error)")

            let wrapper = OptionsError.failedToSave(error)

            let alert = NSAlert(error: wrapper)
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "library options save changes error button"))

            alert.beginSheetModal(for: self.window!, completionHandler: nil)
        }
    }

    // MARK: - Errors
    /**
     * Error type for handling errors during editing of library options. This mostly has to do with failures in
     * saving the changes, or manipulating the media directories.
     */
    enum OptionsError: Error {
        /// Failed to save the library
        case failedToSave(_ underlyingError: Error)
    }
}
