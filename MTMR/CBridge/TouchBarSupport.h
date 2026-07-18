//
//  TouchBarSupport.h
//  MTMR
//
//  Created by Anton Palgunov on 08/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdint.h>

typedef NS_ENUM(NSInteger, MMTMRHIDPostEventAccess) {
    MMTMRHIDPostEventAccessGranted = 0,
    MMTMRHIDPostEventAccessDenied = 1,
    MMTMRHIDPostEventAccessUnknown = 2,
};

typedef struct {
    BOOL succeeded;
    BOOL usedCachedConnection;
    BOOL mainPortAttempted;
    BOOL matchingServicesAttempted;
    BOOL serviceOpenAttempted;
    BOOL serviceReleaseAttempted;
    BOOL iteratorReleaseAttempted;
    BOOL connectionCloseAttempted;
    BOOL keyDownAttempted;
    BOOL keyDownPosted;
    BOOL keyUpAttempted;
    BOOL keyUpPosted;
    int32_t mainPortResult;
    int32_t matchingServicesResult;
    int32_t serviceOpenResult;
    int32_t serviceReleaseResult;
    int32_t iteratorReleaseResult;
    int32_t connectionCloseResult;
    int32_t keyDownResult;
    int32_t keyUpResult;
} MMTMRIOHIDPostResult;

typedef struct {
    BOOL succeeded;
    BOOL keyDownCreated;
    BOOL keyUpCreated;
} MMTMRCoreGraphicsAuxPostResult;

@interface MediaKeys : NSObject

/// Legacy entry point retained for source compatibility. New Swift code uses
/// the granular APIs below so it can publish structured diagnostics.
+ (void)HIDPostAuxKey:(UInt8)keyCode;

+ (MMTMRHIDPostEventAccess)checkHIDPostEventAccess NS_SWIFT_NAME(checkHIDPostEventAccess());
+ (BOOL)requestHIDPostEventAccess NS_SWIFT_NAME(requestHIDPostEventAccess());
+ (MMTMRIOHIDPostResult)postAuxKeyUsingIOHID:(UInt8)keyCode NS_SWIFT_NAME(postAuxKeyUsingIOHID(_:));

+ (BOOL)checkCoreGraphicsPostEventAccess NS_SWIFT_NAME(checkCoreGraphicsPostEventAccess());
+ (BOOL)requestCoreGraphicsPostEventAccess NS_SWIFT_NAME(requestCoreGraphicsPostEventAccess());
+ (MMTMRCoreGraphicsAuxPostResult)postAuxKeyUsingCoreGraphics:(UInt8)keyCode NS_SWIFT_NAME(postAuxKeyUsingCoreGraphics(_:));

@end
