//
//  NSXPCConnection+Hacks.h
//  Bowl (macOS)
//
//  Created by Tristan Seifert on 20200611.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Expose some private interfaces on the NSXPCConnection class.
 *
 * Particularly, we're after the `auditToken` property. This is the only non-racy way to validate the identity
 * of a connecting client.
 */
@interface NSXPCConnection (Hacks)

/**
 * Audit token of the connecting client. Can be used with `SecCodeCopyGuestWithAttributes()` to get a
 * reference to the client's code signature.
 */
@property (nonatomic, readonly) audit_token_t auditToken;

@end

NS_ASSUME_NONNULL_END
