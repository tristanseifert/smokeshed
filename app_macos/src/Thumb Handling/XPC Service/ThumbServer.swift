//
//  ThumbServer.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200611.
//

import Foundation

import Bowl
import CocoaLumberjackSwift

/**
 * Provides the interface used by XPC clients to generate and request thumbnail images.
 */
class ThumbServer: ThumbXPCProtocol {
    // MARK: - XPC Calls
    /**
     * Loads the thumbnail directory, if not done already.
     */
    func wakeUp(withReply reply: @escaping (Error?) -> Void) {
        // fuck u
        reply(nil)
    }
}
