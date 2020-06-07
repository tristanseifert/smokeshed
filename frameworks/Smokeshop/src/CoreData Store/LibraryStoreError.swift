//
//  LibraryStoreError.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation
import CoreData


/**
 * An error class representing errors raised by the LibraryStore class.
 */
enum LibraryStoreError: LocalizedError {
    /// The model file could not be loaded.
    case modelFailedToLoad
    /// Path to the store inside the library is invalid
    case invalidStoreUrl

    /// Provides a localized description of the error cause.
    var errorDescription: String? {
        let b = Bundle(for: LibraryStore.self)

        switch self {
            case .modelFailedToLoad:
                return NSLocalizedString("The data model could not be loaded.",
                        tableName: nil, bundle: b, value: "",
                        comment: "LibraryStore error model failed to load description")

            case .invalidStoreUrl:
                return NSLocalizedString("Failed to get the store URL from the library bundle",
                         tableName: nil, bundle: b, value: "",
                         comment: "LibraryStore error model failed to get store url")
        }
    }
}
