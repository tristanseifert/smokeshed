//
//  main.swift
//  Renderer
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation

// allocate XPC delegate and create a listener with it
let delegate = XPCDelegate()

let listener = NSXPCListener.service()
listener.delegate = delegate

// once it's resumed, we gucci
listener.resume()

