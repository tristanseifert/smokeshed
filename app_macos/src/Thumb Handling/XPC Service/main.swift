//
//  main.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

import Bowl

// set up some of our environment
Bowl.Logger.setup()

// allocate XPC delegate and create a listener with it
let delegate = XPCDelegate()

let listener = NSXPCListener.service()
listener.delegate = delegate

// once it's resumed, we gucci
listener.resume()
