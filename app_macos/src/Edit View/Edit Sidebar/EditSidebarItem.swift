//
//  EditSidebarItem.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200820.
//

import Foundation

import Smokeshop

/**
 * A common protocol implemented by  all sidebar items in the edit view.
 */
internal protocol EditSidebarItem {
    /**
     * The active image has changed.
     */
    func imageChanged(_ to: Image?)
    
    /**
     * The edit view that this item belongs to has rendered a new image.
     */
    func imageRendered(_ note: Notification?)
}
