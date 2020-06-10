//
//  LibraryCollectionItem.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Cocoa

/**
 * Each image in the library is rendered by one of these bad boys.
 */
class LibraryCollectionItem: NSCollectionViewItem {
    // MARK: - Initialization
    /**
     * Creates the content view.
     */
    override func loadView() {
        self.view = LibraryCollectionItemView()
    }

    // MARK: - View lifecycle
    /**
     * Prepare for the view being shown by refetching all visible objects.
     */
    override func viewWillAppear() {
        if let view = self.view as? LibraryCollectionItemView {
            view.prepareForDisplay()
        }
    }

    /**
     * Quiesces data store access when the view has disappeared.
     */
    override func viewDidDisappear() {

    }
}
