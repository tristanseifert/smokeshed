//
//  XPCCSHelpers.swift
//  Bowl
//
//  Created by Tristan Seifert on 20200627.
//

import Foundation
import Security

/**
 * Provides helpers to check a remote XPC connection's code signature.
 */
public class XPCCSHelpers {
    // MARK: - Signature retrieval
    /**
     * Gets a reference to the Security code signature guest that's attempting to connect.
     */
    public static func getXpcGuest(_ connection: NSXPCConnection) throws -> SecCode {
        // extract the audit token
        var token = connection.auditToken
        let tokenData = NSData(bytes: &token, length: MemoryLayout.size(ofValue: token))

        // try to query the guest
        let props = [
            kSecGuestAttributeAudit: tokenData
        ] as CFDictionary

        var codeRef: SecCode? = nil
        let err = SecCodeCopyGuestWithAttributes(nil, props, [], &codeRef)

        guard err == errSecSuccess, let code = codeRef else {
            throw ConnectionError.failedToCopyGuest(err)
        }

        return code
    }

    /**
     * Retrieves signing information for the specified guest.
     */
    public static func getSigningInfo(_ inCode: SecCode) throws -> [String: Any] {
        /*
         * We need to do a pretty disgusting hack to get a SecStaticCodeRef,
         * since that's what the SecCodeCopySigningInformation() call expects;
         * on ObjC, we don't even have to cast it, but… yeah.
         */
        let staticCodeRef = withUnsafePointer(to: inCode) {
            $0.withMemoryRebound(to: SecStaticCode.self, capacity: 1) {
                $0.pointee
            }
        }

        // extract info
        var infoRef: CFDictionary? = nil
        let err = SecCodeCopySigningInformation(staticCodeRef,
                    SecCSFlags(rawValue: kSecCSDynamicInformation), &infoRef)

        guard err == errSecSuccess, let info = infoRef as? [String: Any] else {
            throw ConnectionError.failedToCopySigningInfo(err)
        }

        return info
    }

    // MARK: - Policy
    /**
     * Verifies the code's signature state.
     *
     * This checks the code's signature flags; for all situations, this will ensure that the system enforces that
     * the process only ever has validly signed pages mapped, and it will be killed if it ever changes.
     * Additionally, hardened runtime and library verification are required. The task also may not be
     * debuggable.
     *
     * Note that for debug builds of the XPC service, these requirements are relaxed to require that the
     * client only implements the hardened runtime.
     */
    public static func validateSignatureState(_ info: [String: Any]) throws {
        #if DEBUG
        let required: SecCodeStatus = [.hardenedRuntime]
        #else
        let required: SecCodeStatus = [.hard, .kill, .hardenedRuntime, .libraryValidation, .noDebugging]
        #endif

        // the actual flags must contain at least all of the required flags
        let rawFlags = info[kSecCodeInfoStatus as String]
        let flags = SecCodeStatus(rawValue: rawFlags as! UInt32)

        guard flags.isSuperset(of: required) else {
            throw ConnectionError.invalidSignatureStatus(flags)
        }
    }

    /**
     * Validates the signing identity used to sign the code. It must have been signed with an Apple-issued
     * certificate, matching the expected developer ID.
     */
    public static func validateSignature(_ code: SecCode) throws {
        // build the requirements
        let reqStr = "anchor apple generic and certificate leaf[subject.OU] = \"8QDQ246B94\""

        var reqRef: SecRequirement? = nil
        var err = SecRequirementCreateWithString(reqStr as CFString, [], &reqRef)

        guard err == errSecSuccess, let requirement = reqRef else {
            throw ConnectionError.requirementInvalid(err)
        }

        // validate the code with those requirements
        var verifyErrors: Unmanaged<CFError>? = nil

        err = SecCodeCheckValidityWithErrors(code, [], requirement, &verifyErrors)

        guard err == errSecSuccess else {
            let errorDetail = verifyErrors?.takeRetainedValue()
            throw ConnectionError.signatureInvalid(err, errorDetail)
        }

        // if we get here, the signature was valid :)
    }
    
    // MARK: Errors
    /**
     * Indicates potential errors that may take place during the connection process.
     */
    public enum ConnectionError: Error {
        /// We could not get a reference to the caller's code signature.
        case failedToCopyGuest(_ secErr: OSStatus)
        /// Something went wrong getting a reference to the static on-disk code object.
        case failedToCopyStaticCode(_ secErr: OSStatus)
        /// Signature information couldn't be retrieved.
        case failedToCopySigningInfo(_ secErr: OSStatus)
        /// Code signature flags are not secure enough.
        case invalidSignatureStatus(_ status: SecCodeStatus)
        /// A requirement object could not be created.
        case requirementInvalid(_ secErr: OSStatus)
        /// The signature of the code is invalid.
        case signatureInvalid(_ secErr: OSStatus, _ detail: Error!)
    }
}

/**
 * Provide some private flags that aren't otherwise accessible.
 */
extension SecCodeStatus {
    /// Library validation is required for the process.
    fileprivate static var libraryValidation = SecCodeStatus(rawValue: 0x2000)
    /// The code is using the hardened runtime.
    fileprivate static var hardenedRuntime = SecCodeStatus(rawValue: 0x10000)
    /// Debugging of the process is prohibited.
    fileprivate static var noDebugging = SecCodeStatus(rawValue: 0x800)
}
