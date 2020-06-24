//
//  SidebarController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200623.
//

import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Implements the main window's sidebar: an outline view allowing the user to select from shortcuts, their
 * images sorted by days, and their albums.
 */
class SidebarController: NSViewController, MainWindowLibraryPropagating {
    /// Currently opened library
    internal var library: LibraryBundle!
}
