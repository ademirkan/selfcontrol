//
//  SCDNSEnforcer.h
//  SelfControl
//
//  Forces every network service to use a fixed set of DNS servers while a block is running
//  (e.g. Cloudflare for Families, 1.1.1.3), and restores the user's original DNS settings
//  when the block ends. Must run as root.
//
//  The DNS settings alone are easy to change back in System Settings, so the block also adds
//  pf rules (see PacketFilter) that drop DNS traffic to any other server, and the daemon's
//  integrity check re-applies the settings if they drift.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCDNSEnforcer : NSObject

// Only the entries that are valid IPv4/IPv6 addresses (anything else is dropped).
+ (NSArray<NSString*>*)validDNSServersFromArray:(nullable NSArray*)servers;

// Sets every network service's DNS servers to `servers`, saving each service's original
// servers first so they can be restored. Safe to call repeatedly (e.g. from integrity checks):
// only services that don't already match are changed. Returns YES if anything was changed.
+ (BOOL)enforceDNSServers:(NSArray<NSString*>*)servers;

// Puts back the DNS servers saved by enforceDNSServers:, if any. No-op if DNS isn't enforced.
+ (void)restoreOriginalDNSServers;

@end

NS_ASSUME_NONNULL_END
