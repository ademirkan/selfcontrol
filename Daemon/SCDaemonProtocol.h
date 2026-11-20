//
//  SCDaemonProtocol.h
//  selfcontrold
//
//  Created by Charlie Stigler on 5/30/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SCDaemonProtocol <NSObject>

// XPC method to start block
- (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

// XPC method to add to blocklist
- (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

// XPC method to extend block
- (void)updateBlockEndDate:(NSDate*)newEndDate authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

// XPC method to force DNS servers for the block that's already running. Only makes the block
// stricter (it can't be turned back off until the block ends), so it doesn't need authorization.
- (void)enforceDNSServersForRunningBlock:(NSArray<NSString*>*)servers reply:(void(^)(NSError* error))reply;

// XPC method to get version of the installed daemon
- (void)getVersionWithReply:(void(^)(NSString * version))reply;

@end

NS_ASSUME_NONNULL_END
