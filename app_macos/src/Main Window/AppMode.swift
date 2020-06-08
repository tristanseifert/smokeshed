//
//  AppMode.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Foundation

/**
 * Different view modes supported by the main window.
 */
enum AppMode: Int {
    /// Shows all images in the library in a grid-style interface.
    case Library = 1
    /// Displays images on a map instead of a grid.
    case Map = 2
    /// Allows editing of a single image at a time.
    case Edit = 3
}
