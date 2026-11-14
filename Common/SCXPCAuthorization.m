//
//  SCXPCAuthorization.m
//  SelfControl
//
//  Created by Charlie Stigler on 1/4/21.
//

#import "SCXPCAuthorization.h"

@implementation SCXPCAuthorization

// all of these methods (basically this whole file) copied from Apple's Even Better Authorization Sample code

static NSString * kCommandKeyAuthRightName    = @"authRightName";
static NSString * kCommandKeyAuthRightDefault = @"authRightDefault";
static NSString * kCommandKeyAuthRightDesc    = @"authRightDescription";

static NSDictionary* kAuthorizationRuleAuthenticateAsAdmin2MinTimeout;

// copied from Apple's Even Better Authorization Sample code
+ (NSError *)checkAuthorization:(NSData *)authData command:(SEL)command
    // Check that the client denoted by authData is allowed to run the specified command.
    // authData is expected to be an NSData with an AuthorizationExternalForm embedded inside.
{
    #pragma unused(authData)
    AuthorizationRef            authRef;

    assert(command != nil);
    
    authRef = NULL;

    // First check that authData looks reasonable.
    if ( (authData == nil) || ([authData length] != sizeof(AuthorizationExternalForm)) ) {
        return [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
    }
    
    // Create an authorization ref from that the external form data contained within.
    OSStatus extFormStatus = AuthorizationCreateFromExternalForm([authData bytes], &authRef);
    if (extFormStatus != errAuthorizationSuccess) {
        return [NSError errorWithDomain: NSOSStatusErrorDomain code: extFormStatus userInfo: nil];
    }

    // Authorize the right associated with the command.

    AuthorizationItem   oneRight = { NULL, 0, NULL, 0 };
    AuthorizationRights rights   = { 1, &oneRight };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;

    oneRight.name = [[SCXPCAuthorization authorizationRightForCommand:command] UTF8String];
    assert(oneRight.name != NULL);
    
    OSStatus authStatus = AuthorizationCopyRights(
        authRef,
        &rights,
        kAuthorizationEmptyEnvironment,
        flags,
        NULL
    );
    if (authRef != NULL) {
        AuthorizationFree(authRef, 0);
    }

    if (authStatus != errAuthorizationSuccess) {
        return [NSError errorWithDomain: NSOSStatusErrorDomain code: authStatus userInfo: nil];
    }

    return nil;
}


+ (NSDictionary *)commandInfo
{
    static dispatch_once_t sOnceToken;
    static NSDictionary *  sCommandInfo;
    
    // static var needs to bre defined before first use
    if (kAuthorizationRuleAuthenticateAsAdmin2MinTimeout == nil) {
        kAuthorizationRuleAuthenticateAsAdmin2MinTimeout = @{
            @"class": @"user",
            @"group": @"admin",
            @"timeout": @(120), // 2 minutes
            @"shared": @(YES),
            @"version": @1 // not entirely sure what this does TBH
            // NOTE: don't set "mechanisms" here. Without it, macOS uses its standard admin
            // prompt (which already supports Touch ID). Upstream once set it to just
            // "builtin:authenticate", which shows the password dialog but never verifies the
            // password - so every prompt failed. See +rightDefinitionIsBroken: below.
        };
    }
    
    dispatch_once(&sOnceToken, ^{
        #pragma clang diagnostic ignored "-Wundeclared-selector"
        
        
        NSDictionary* startBlockCommandInfo = @{
            kCommandKeyAuthRightName    : @"org.eyebeam.SelfControl.startBlock",
            kCommandKeyAuthRightDefault : kAuthorizationRuleAuthenticateAsAdmin2MinTimeout,
            kCommandKeyAuthRightDesc    : NSLocalizedString(
                @"SelfControl needs your username and password to start the block.",
                @"prompt shown when user is required to authorize to start block"
            )
        };
        NSDictionary* modifyBlockCommandInfo = @{
            kCommandKeyAuthRightName    : @"org.eyebeam.SelfControl.modifyBlock",
            kCommandKeyAuthRightDefault : kAuthorizationRuleAuthenticateAsAdmin2MinTimeout,
            kCommandKeyAuthRightDesc    : NSLocalizedString(
                @"SelfControl needs your username and password to modify the block",
                @"prompt shown when user is required to authorize to modify their block"
            )
        };
        
        sCommandInfo = @{
            NSStringFromSelector(@selector(startBlockWithControllingUID:blocklist:isAllowlist:endDate:blockSettings:authorization:reply:)) : startBlockCommandInfo,
            NSStringFromSelector(@selector(updateBlocklist:authorization:reply:)) : modifyBlockCommandInfo,
            NSStringFromSelector(@selector(updateBlockEndDate:authorization:reply:)) : modifyBlockCommandInfo
            #pragma clang diagnostic pop
        };
    });
    return sCommandInfo;
}

+ (void)enumerateRightsUsingBlock:(void (^)(NSString * authRightName, id authRightDefault, NSString * authRightDesc))block
    // Calls the supplied block with information about each known authorization right..
{
    [self.commandInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        #pragma unused(key)
        #pragma unused(stop)
        NSDictionary *  commandDict;
        NSString *      authRightName;
        id              authRightDefault;
        NSString *      authRightDesc;
        
        // If any of the following asserts fire it's likely that you've got a bug
        // in sCommandInfo.
        
        commandDict = (NSDictionary *) obj;
        assert([commandDict isKindOfClass:[NSDictionary class]]);

        authRightName = [commandDict objectForKey:kCommandKeyAuthRightName];
        assert([authRightName isKindOfClass:[NSString class]]);

        authRightDefault = [commandDict objectForKey:kCommandKeyAuthRightDefault];
        assert(authRightDefault != nil);

        authRightDesc = [commandDict objectForKey:kCommandKeyAuthRightDesc];
        assert([authRightDesc isKindOfClass:[NSString class]]);

        block(authRightName, authRightDefault, authRightDesc);
    }];
}

// Rights created by builds containing upstream commit 34774c4 ("Add Touch ID support") list only
// the non-privileged "builtin:authenticate" mechanism. That mechanism just shows the dialog; the
// password is normally checked by a second, privileged "builtin:authenticate,privileged" step, which
// was missing - so authentication always failed, no matter what password was entered.
+ (BOOL)rightDefinitionIsBroken:(NSDictionary*)definition {
    return [definition[@"mechanisms"] isEqual: @[@"builtin:authenticate"]];
}

+ (void)setupAuthorizationRights:(AuthorizationRef)authRef
    // See comment in header.
{
    assert(authRef != NULL);
    NSMutableDictionary<NSString*, NSArray*>* brokenRights = [NSMutableDictionary dictionary];

    [SCXPCAuthorization enumerateRightsUsingBlock:^(NSString * authRightName, id authRightDefault, NSString * authRightDesc) {
        OSStatus    blockErr;
        CFDictionaryRef existingDefinition = NULL;
        
        // First get the right.  If we get back errAuthorizationDenied that means there's
        // no current definition, so we add our default one.
        
        blockErr = AuthorizationRightGet([authRightName UTF8String], &existingDefinition);
        if (blockErr == errAuthorizationDenied) {
            NSLog(@"setting auth right default for %@: %@", authRightName, authRightDefault);
            blockErr = AuthorizationRightSet(
                authRef,                                    // authRef
                [authRightName UTF8String],                 // rightName
                (__bridge CFTypeRef) authRightDefault,      // rightDefinition
                (__bridge CFStringRef) authRightDesc,       // descriptionKey
                NULL,                                       // bundle (NULL implies main bundle)
                CFSTR("SCXPCAuthorization")                             // localeTableName
            );
            assert(blockErr == errAuthorizationSuccess);
        } else if (blockErr == errAuthorizationSuccess && [SCXPCAuthorization rightDefinitionIsBroken: (__bridge NSDictionary*)existingDefinition]) {
            brokenRights[authRightName] = @[authRightDefault, authRightDesc];
        } else {
            // A right already exists (err == noErr) or any other error occurs, we
            // assume that it has been set up in advance by the system administrator or
            // this is the second time we've run.  Either way, there's nothing more for
            // us to do.
        }

        if (existingDefinition != NULL) CFRelease(existingDefinition);
    }];

    if (brokenRights.count > 0) {
        [SCXPCAuthorization repairBrokenRights: brokenRights authorization: authRef];
    }
}

+ (void)repairBrokenRights:(NSDictionary<NSString*, NSArray*>*)brokenRights authorization:(AuthorizationRef)authRef {
    // Changing an existing right requires config.modify.<right name>, which uses the
    // system's (working) admin prompt. Ask for all of them at once so the user sees one prompt.
    NSArray<NSString*>* rightNames = brokenRights.allKeys;
    NSMutableArray<NSString*>* configRightNames = [NSMutableArray arrayWithCapacity: rightNames.count];
    AuthorizationItem* items = calloc(rightNames.count, sizeof(AuthorizationItem));
    for (NSUInteger i = 0; i < rightNames.count; i++) {
        [configRightNames addObject: [@"config.modify." stringByAppendingString: rightNames[i]]];
        items[i].name = configRightNames[i].UTF8String;
    }
    AuthorizationRights configRights = { (UInt32)rightNames.count, items };
    OSStatus err = AuthorizationCopyRights(authRef,
                                           &configRights,
                                           kAuthorizationEmptyEnvironment,
                                           kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights,
                                           NULL);
    free(items);
    if (err != errAuthorizationSuccess) {
        NSLog(@"WARNING: couldn't get permission to repair authorization rights %@ (error %d); block changes will keep failing to authenticate", rightNames, (int)err);
        return;
    }

    for (NSString* rightName in rightNames) {
        err = AuthorizationRightSet(authRef,
                                    rightName.UTF8String,
                                    (__bridge CFTypeRef) brokenRights[rightName][0],
                                    (__bridge CFStringRef) brokenRights[rightName][1],
                                    NULL,
                                    CFSTR("SCXPCAuthorization"));
        NSLog(@"%@ broken auth right %@ (status %d)", (err == errAuthorizationSuccess) ? @"Repaired" : @"ERROR: failed to repair", rightName, (int)err);
    }
}

+ (NSString *)authorizationRightForCommand:(SEL)command
    // See comment in header.
{
    return [self commandInfo][NSStringFromSelector(command)][kCommandKeyAuthRightName];
}


@end
