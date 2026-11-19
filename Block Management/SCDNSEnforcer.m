//
//  SCDNSEnforcer.m
//  SelfControl
//

#import "SCDNSEnforcer.h"
#include <arpa/inet.h>

static NSString* const kNetworksetupPath = @"/usr/sbin/networksetup";
// service name -> array of the DNS servers it had before the block (empty array = "use DHCP's")
static NSString* const kDNSBackupPath = @"/etc/SelfControlDNSBackup.plist";

@implementation SCDNSEnforcer

+ (NSString*)runNetworksetup:(NSArray<NSString*>*)args status:(int*)status {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath: kNetworksetupPath];
    task.arguments = args;
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError* err = nil;
    if (![task launchAndReturnError: &err]) {
        NSLog(@"ERROR: couldn't run networksetup %@: %@", args, err);
        if (status) *status = -1;
        return @"";
    }
    NSData* output = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (status) *status = task.terminationStatus;
    return [[NSString alloc] initWithData: output encoding: NSUTF8StringEncoding] ?: @"";
}

+ (NSArray<NSString*>*)nonEmptyLines:(NSString*)output {
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* line in [output componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]]) {
        NSString* trimmed = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) [lines addObject: trimmed];
    }
    return lines;
}

+ (BOOL)isIPAddress:(NSString*)str {
    struct in_addr v4;
    struct in6_addr v6;
    const char* cStr = str.UTF8String;
    return cStr != NULL && (inet_pton(AF_INET, cStr, &v4) == 1 || inet_pton(AF_INET6, cStr, &v6) == 1);
}

+ (NSArray<NSString*>*)validDNSServersFromArray:(NSArray*)servers {
    NSMutableArray<NSString*>* valid = [NSMutableArray array];
    for (id server in servers) {
        if ([server isKindOfClass: [NSString class]] && [self isIPAddress: server]) {
            [valid addObject: server];
        } else {
            NSLog(@"WARNING: ignoring invalid DNS server %@", server);
        }
    }
    return valid;
}

// All network services, including disabled ones (so enabling a disabled service can't dodge the DNS block)
+ (NSArray<NSString*>*)allNetworkServices {
    int status = 0;
    NSString* output = [self runNetworksetup: @[@"-listallnetworkservices"] status: &status];
    if (status != 0) return @[];

    NSMutableArray<NSString*>* services = [NSMutableArray array];
    for (NSString* line in [self nonEmptyLines: output]) {
        // first line is "An asterisk (*) denotes that a network service is disabled."
        if ([line hasPrefix: @"An asterisk"]) continue;
        [services addObject: [line hasPrefix: @"*"] ? [line substringFromIndex: 1] : line];
    }
    return services;
}

+ (NSArray<NSString*>*)dnsServersForService:(NSString*)service {
    int status = 0;
    NSString* output = [self runNetworksetup: @[@"-getdnsservers", service] status: &status];
    if (status != 0) return nil;
    // when none are set manually, it prints "There aren't any DNS Servers set on <service>."
    NSMutableArray<NSString*>* servers = [NSMutableArray array];
    for (NSString* line in [self nonEmptyLines: output]) {
        if ([self isIPAddress: line]) [servers addObject: line];
    }
    return servers;
}

+ (BOOL)setDNSServers:(NSArray<NSString*>*)servers forService:(NSString*)service {
    NSArray* args = [@[@"-setdnsservers", service] arrayByAddingObjectsFromArray: (servers.count > 0) ? servers : @[@"Empty"]];
    int status = 0;
    NSString* output = [self runNetworksetup: args status: &status];
    // networksetup exits 0 even for some failures, but prints an error
    if (status != 0 || [output rangeOfString: @"Error"].location != NSNotFound) {
        NSLog(@"WARNING: failed to set DNS servers for %@ to %@: %@", service, servers, output);
        return NO;
    }
    return YES;
}

+ (void)flushDNSCache {
    NSTask* flush = [NSTask launchedTaskWithLaunchPath: @"/usr/bin/dscacheutil" arguments: @[@"-flushcache"]];
    [flush waitUntilExit];
    NSTask* hup = [NSTask launchedTaskWithLaunchPath: @"/usr/bin/killall" arguments: @[@"-HUP", @"mDNSResponder"]];
    [hup waitUntilExit];
}

+ (BOOL)enforceDNSServers:(NSArray<NSString*>*)servers {
    servers = [self validDNSServersFromArray: servers];
    if (servers.count == 0) {
        NSLog(@"WARNING: no valid DNS servers to enforce");
        return NO;
    }

    NSMutableDictionary* backup = [NSMutableDictionary dictionaryWithContentsOfFile: kDNSBackupPath] ?: [NSMutableDictionary dictionary];
    NSMutableArray<NSString*>* servicesToChange = [NSMutableArray array];
    for (NSString* service in [self allNetworkServices]) {
        NSArray<NSString*>* current = [self dnsServersForService: service];
        if (current == nil) continue;
        // remember the original servers the first time we see a service (including services
        // that show up mid-block, like a newly plugged-in adapter)
        if (backup[service] == nil) backup[service] = current;
        if (![current isEqualToArray: servers]) [servicesToChange addObject: service];
    }

    if (servicesToChange.count == 0) return NO;

    // save the originals *before* changing anything, so a crash can't lose them
    if (![backup writeToFile: kDNSBackupPath atomically: YES]) {
        NSLog(@"WARNING: couldn't save original DNS servers to %@; they'll have to be restored manually", kDNSBackupPath);
    }
    for (NSString* service in servicesToChange) {
        if ([self setDNSServers: servers forService: service]) {
            NSLog(@"INFO: set DNS servers for %@ to %@", service, servers);
        }
    }
    [self flushDNSCache];
    return YES;
}

+ (void)restoreOriginalDNSServers {
    NSDictionary* backup = [NSDictionary dictionaryWithContentsOfFile: kDNSBackupPath];
    if (backup == nil) return;

    NSSet<NSString*>* existingServices = [NSSet setWithArray: [self allNetworkServices]];
    NSMutableDictionary* failed = [NSMutableDictionary dictionary];
    for (NSString* service in backup) {
        if (![existingServices containsObject: service]) continue; // adapter was removed since
        NSArray* original = [self validDNSServersFromArray: backup[service]];
        if ([self setDNSServers: original forService: service]) {
            NSLog(@"INFO: restored DNS servers for %@ to %@", service, (original.count > 0) ? original : @"automatic (DHCP)");
        } else {
            failed[service] = backup[service];
        }
    }
    if (failed.count > 0) {
        // keep what we couldn't restore, so the next attempt can try again
        [failed writeToFile: kDNSBackupPath atomically: YES];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath: kDNSBackupPath error: nil];
    }
    [self flushDNSCache];
}

@end
