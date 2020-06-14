//
//  LibraryViewMenuProvider.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200613.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Provides the appropriate menu for the main collection view in the library view.
 */
class LibraryViewMenuProvider: NSObject, LibraryCollectionViewDelegate,
                               NSMenuItemValidation, NSMenuDelegate {
    /// Containing library controller
    private var parent: LibraryViewController

    /// Nib file containing the menu template
    private var templateNib: NSNib!
    /// Menu template
    @IBOutlet private var template: NSMenu!

    /// Collection view item that's currently selected
    private weak var currentItem: NSCollectionViewItem? = nil
    /// Image for which the current menu is displayed
    private var currentImage: Image? = nil

    // MARK: - Initialization
    /**
     * Creates a new menu provider with the given library controller as a parent.
     */
    init(_ parent: LibraryViewController) {
        // set the parent and initialize superclass
        self.parent = parent
        super.init()

        // load the menu template
        guard let nib = NSNib(nibNamed: "LibraryViewMenu", bundle: nil) else {
            fatalError("Failed to load library view menu")
        }
        self.templateNib = nib
        self.templateNib.instantiate(withOwner: self, topLevelObjects: nil)
    }

    // MARK: - Collection delegate
    /**
     * Returns the appropriate menu.
     */
    func collectionView(_ collectionView: NSCollectionView, menu: NSMenu?, at indexPath: IndexPath?) -> NSMenu? {
        // cancel previous clearing action
        NSObject.cancelPreviousPerformRequests(withTarget: self)

        // try to get the object that was clicked
        if let path = indexPath {
            self.currentImage = self.parent.fetchReqCtrl.object(at: path)
            self.currentItem = collectionView.item(at: path)

            // use the default menu template
            return self.template
        }

        // return the deafult menu, probably nothing
        return menu
    }

    // MARK: - Actions
    /**
     * Switches to the edit mode with the given image.
     */
    @IBAction private func editImage(_ sender: Any?) {
        if let image = self.currentImage {
            self.parent.openEditorForImages([image])
        } else {
            DDLogError("editImage(_:) called without an image set!")
            NSSound.beep()
        }
    }
    /**
     * Removes the image from the library.
     */
    @IBAction private func removeImage(_ sender: Any?) {
        if let image = self.currentImage {
            self.parent.removeImagesWithConfirmation([image])
        } else {
            DDLogError("removeImage(_:) called without an image set!")
            NSSound.beep()
        }
    }

    /**
     * Sets the rating of the selected image.
     */
    @IBAction private func setRating(_ sender: Any?) {
        // get the rating value to set
        guard let item = sender as? NSMenuItem else {
            fatalError("setRating(_:) may only be called from menu items")
        }

        self.currentImage!.rating = Int16(item.tag)
    }

    // MARK: - Menu delegate
    /**
     * Once the menu appears, try to draw the outline on the affected item.
     */
    func menuWillOpen(_ menu: NSMenu) {
        // try to draw the outline
        if let view = self.currentItem as? LibraryCollectionItem {
            view.drawContextOutline = true
        }
    }

    /**
     * When the menu is closed, clear state and stop drawing the outline on the item.
     */
    func menuDidClose(_ menu: NSMenu) {
        // try to hide the outline
        if let view = self.currentItem as? LibraryCollectionItem {
            view.drawContextOutline = false
        }

        // clear the state soon
        self.perform(#selector(clearState), with: nil, afterDelay: 0.05)
    }

    /**
     * Clears the internal state after a small time after the menu closed.
     */
    @objc private func clearState() {
        self.currentImage = nil
        self.currentItem = nil
    }

    // MARK: - Menu validation
    /**
     * Updates the state of the given menu item prior to display, and ensures that items are enabled.
     */
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // can't do anything without an image :)
        guard let image = self.currentImage else {
            return false
        }

        // update the rating item with the image's rating
        if menuItem.action == #selector(setRating(_:)) {
            menuItem.state = (menuItem.tag == image.rating) ? .on : .off
            return true
        }

        // allow all other actions that don't require updating
        if menuItem.action == #selector(removeImage(_:)) ||
           menuItem.action == #selector(editImage(_:)) {
            return true
        }

        return false
    }
}
