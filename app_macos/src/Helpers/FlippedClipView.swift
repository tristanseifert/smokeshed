//
//  FlippedClipView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

/**
 * A clip view subclass with a flipped coordinate system
 */
class FlippedClipView: NSClipView {
    override var isFlipped: Bool {
        return true
    }
}
