//
//  ThumbXPCService.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

/**
 * Defines the interface implemented by the thumbnail XPC service.
 */
@objc public protocol ThumbXPCProtocol {
    /**
     * Initializes the XPC service and load the thumbnail directory.
     */
    func wakeUp(withReply reply: @escaping (Error?) -> Void)
}

/**
 * Some helper functions for working with the XPC protocol
 */
class ThumbXPCProtocolHelpers {
    /**
     * Creates a reference to the thumb XPC protocol, with all functions configured as needed.
     */
    public class func make() -> NSXPCInterface {
        let int = NSXPCInterface(with: ThumbXPCProtocol.self)

        return int
    }

    /// Don't allow initialization of the class, it's just a bunch of static methods
    private init() {}
}
