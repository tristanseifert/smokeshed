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
    /// The contents directory is missing.
    case missingContents
    /// An IO error took place reading data.
    case ioError(message: String)
    /// The library version is incompatible with this binary.
    case invalidVersion(_ version: Int)

    /// Provides a localized description of the error cause.
    var errorDescription: String? {
        let b = Bundle(for: LibraryBundle.self)

        switch self {
            case let .invalidFormat(message):
                let fmt = NSLocalizedString("The library is corrupted (%@)",
                            tableName: nil, bundle: b, value: "",
                            comment: "LibraryBundle error invalid format description")
                return String(format: fmt, message)

            case .missingContents:
                return NSLocalizedString("The contents directory is missing.",
                            tableName: nil, bundle: b, value: "",
                            comment: "LibraryBundle error missing contents file wrapper")

            case let .ioError(message):
                let fmt = NSLocalizedString("An error occurred reading library data (%@)",
                            tableName: nil, bundle: b, value: "",
                            comment: "LibraryBundle error io error description")
                return String(format: fmt, message)

            case let .invalidVersion(version):
                let fmt = NSLocalizedString("The library version (%d) is incompatible with this version of the app.",
                            tableName: nil, bundle: b, value: "",
                            comment: "LibraryBundle error invalid version description")
                return String(format: fmt, version)
        }
    }
}
