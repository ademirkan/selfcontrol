//
//  PacketFilter.h
//  SelfControl
//
//  Created by Charles Stigler on 6/29/14.
//
//

#import <Foundation/Foundation.h>

@class SCBlockEntry;

@interface PacketFilter : NSObject {
	NSMutableString* rules;
	BOOL isAllowlist;
}

+ (BOOL)blockFoundInPF;

// If set, the block also drops all DNS traffic (port 53, and DNS-over-TLS on 853) that isn't
// going to one of these servers. Entries must be valid IP addresses (see SCDNSEnforcer).
@property (nonatomic, copy) NSArray<NSString*>* allowedDNSServers;

- (PacketFilter*)initAsAllowlist: (BOOL)allowlist;
- (void)addBlockHeader:(NSMutableString*)configText;
- (void)addAllowlistFooter:(NSMutableString*)configText;
- (void)addRuleWithIP:(NSString*)ip port:(NSInteger)port maskLen:(NSInteger)maskLen;
- (void)writeConfiguration;
- (int)startBlock;
- (int)stopBlock:(BOOL)force;
- (void)addSelfControlConfig;
- (BOOL)containsSelfControlBlock;
- (void)enterAppendMode;
- (void)finishAppending;
- (int)refreshPFRules;
// Adds the allowedDNSServers rules to the block that's already running, and reloads pf.
- (void)appendDNSRulesToCurrentBlock;

@end
