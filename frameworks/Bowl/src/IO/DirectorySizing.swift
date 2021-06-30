//
//  DirectorySizing.swift
//  Bowl (macOS)
//
//  Adds a category to `FileManager` to allow recursive directory sizing.
//
//  Created by Tristan Seifert on 20200627.
//

import Foundation
import OSLog

fileprivate var logger = Logger(subsystem: Bundle(for: ContainerHelper.self).bundleIdentifier!,
                                     category: "DirectorySizing")

extension URL {
    fileprivate var fileSize: Int? {
        do {
            let val = try self.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return val.totalFileAllocatedSize ?? val.fileAllocatedSize
        } catch {
            logger.warning("Failed to get properties for '\(self.absoluteString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension FileManager {
    /**
     * Recursively sizes the given directory.
     */
    public func directorySize(_ dir: URL) throws -> UInt {
        var result: Result<UInt, Error>! = nil
        
        // make an enumerator
        if let enumerator = self.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: { (_, error) -> Bool in
            result = .failure(error)
            return false
        }) {
            // sum up each of the bytes
            var bytes: UInt = 0
            for case let url as URL in enumerator {
                bytes += UInt(url.fileSize ?? 0)
            }
            
            // save result if not already filled (perhaps by error)
            if result == nil {
                result = .success(bytes)
            }
        }
        
        // get the byte count or propagate error
        return try result.get()
    }
}
