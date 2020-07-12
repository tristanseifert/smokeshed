//
//  LibraryMetaKeys.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation

/**
 * Metadata structure
 */
public struct LibraryMeta: Codable {
    /// Library format version
    var version: Int = -1

    /// Library identifier
    var uuid: UUID! = nil

    /// Relative path to the data store file
    var storePath: String! = nil

    /// Date on which this store was created
    public var createdOn: Date! = nil

    /// App identifier that created this library
    var creatorAppId: String! = nil
    /// App version that created this library
    var creatorAppVers: String! = nil
    /// User that created this library
    public var creatorName: String! = nil

    /// System build on which this library was created
    var creatorOSVers: String! = nil

    /// Cached info containing the number of items in the library
    public var numItems: UInt! = nil

    /// Library name
    public var displayName: String! = nil
    /// User provided description for library
    public var userDescription: String! = nil

    /// User metadata
    public var userInfo: [String: String]! = nil
}
