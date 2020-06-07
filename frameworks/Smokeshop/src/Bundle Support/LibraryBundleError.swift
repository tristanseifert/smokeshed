//
//  LibraryBundleError.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation


/**
 * Errors that may be raised during library interfacing.
 */
enum LibraryBundleError: LocalizedError {
    /// The format of the bundle on disk was incorrect.
    case invalidFormat(message: String)
    /// An IO error took place reading data.
    case ioError(message: String)

    /// Provides a localized description of the error cause.
    var errorDescription: String? {
        let b = Bundle(for: LibraryBundle.self)

        switch self {
            case let .invalidFormat(message):
                let fmt = NSLocalizedString("The library is corrupted (%@)",
                                            tableName: nil, bundle: b, value: "",
                                            comment: "LibraryBundle error invalid format description")
                return String(format: fmt, message)

            case let .ioError(message):
                let fmt = NSLocalizedString("An error occurred reading library data (%@)",
                                            tableName: nil, bundle: b, value: "",
                                            comment: "LibraryBundle error io error description")
                return String(format: fmt, message)
        }
    }
}
