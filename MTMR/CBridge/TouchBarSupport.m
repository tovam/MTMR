//
//  TouchBarSupport.m
//  MTMR
//
//  Created by Anton Palgunov on 08/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import "TouchBarSupport.h"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <IOKit/hidsystem/ev_keymap.h>

@implementation MediaKeys

static io_connect_t sEventDriver = IO_OBJECT_NULL;

static MMTMRIOHIDPostResult EmptyIOHIDResult(void)
{
    MMTMRIOHIDPostResult result;
    memset(&result, 0, sizeof(result));
    return result;
}

static BOOL OpenEventDriver(MMTMRIOHIDPostResult *result)
{
    if (sEventDriver != IO_OBJECT_NULL) {
        result->usedCachedConnection = YES;
        return YES;
    }

    mach_port_t mainPort = MACH_PORT_NULL;
    result->mainPortAttempted = YES;
    result->mainPortResult = IOMainPort(MACH_PORT_NULL, &mainPort);
    if (result->mainPortResult != KERN_SUCCESS) {
        return NO;
    }

    CFMutableDictionaryRef matching = IOServiceMatching(kIOHIDSystemClass);
    result->matchingServicesAttempted = YES;
    if (matching == NULL) {
        result->matchingServicesResult = kIOReturnNoMemory;
        return NO;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    result->matchingServicesResult = IOServiceGetMatchingServices(mainPort, matching, &iterator);
    if (result->matchingServicesResult != KERN_SUCCESS) {
        if (iterator != IO_OBJECT_NULL) {
            result->iteratorReleaseAttempted = YES;
            result->iteratorReleaseResult = IOObjectRelease(iterator);
        }
        return NO;
    }

    io_service_t service = IOIteratorNext(iterator);
    if (service == IO_OBJECT_NULL) {
        result->serviceOpenAttempted = YES;
        result->serviceOpenResult = kIOReturnNotFound;
    } else {
        io_connect_t connection = IO_OBJECT_NULL;
        result->serviceOpenAttempted = YES;
        result->serviceOpenResult = IOServiceOpen(
            service,
            mach_task_self(),
            kIOHIDParamConnectType,
            &connection
        );
        if (result->serviceOpenResult == KERN_SUCCESS) {
            sEventDriver = connection;
        } else if (connection != IO_OBJECT_NULL) {
            result->connectionCloseAttempted = YES;
            result->connectionCloseResult = IOServiceClose(connection);
        }

        result->serviceReleaseAttempted = YES;
        result->serviceReleaseResult = IOObjectRelease(service);
    }

    result->iteratorReleaseAttempted = YES;
    result->iteratorReleaseResult = IOObjectRelease(iterator);
    return sEventDriver != IO_OBJECT_NULL;
}

static void CloseEventDriver(MMTMRIOHIDPostResult *result)
{
    if (sEventDriver == IO_OBJECT_NULL) {
        return;
    }
    result->connectionCloseAttempted = YES;
    result->connectionCloseResult = IOServiceClose(sEventDriver);
    sEventDriver = IO_OBJECT_NULL;
}

static CGEventRef CreateAuxiliaryCGEvent(UInt8 keyCode, BOOL keyDown)
{
    const NSInteger keyState = keyDown ? NX_KEYDOWN : NX_KEYUP;
    const NSInteger data1 = ((NSInteger)keyCode << 16) | (keyState << 8);
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:0
                                         context:nil
                                         subtype:NX_SUBTYPE_AUX_CONTROL_BUTTONS
                                           data1:data1
                                           data2:-1];
    CGEventRef cgEvent = event.CGEvent;
    return cgEvent == NULL ? NULL : CGEventCreateCopy(cgEvent);
}

+ (MMTMRHIDPostEventAccess)checkHIDPostEventAccess
{
    switch (IOHIDCheckAccess(kIOHIDRequestTypePostEvent)) {
        case kIOHIDAccessTypeGranted:
            return MMTMRHIDPostEventAccessGranted;
        case kIOHIDAccessTypeDenied:
            return MMTMRHIDPostEventAccessDenied;
        case kIOHIDAccessTypeUnknown:
        default:
            return MMTMRHIDPostEventAccessUnknown;
    }
}

+ (BOOL)requestHIDPostEventAccess
{
    return IOHIDRequestAccess(kIOHIDRequestTypePostEvent);
}

+ (MMTMRIOHIDPostResult)postAuxKeyUsingIOHID:(UInt8)keyCode
{
    @synchronized (self) {
        MMTMRIOHIDPostResult result = EmptyIOHIDResult();
        if (!OpenEventDriver(&result)) {
            return result;
        }

        NXEventData event;
        IOGPoint location = { 0, 0 };
        memset(&event, 0, sizeof(event));
        event.compound.subType = NX_SUBTYPE_AUX_CONTROL_BUTTONS;

        result.keyDownAttempted = YES;
        event.compound.misc.L[0] = ((UInt32)keyCode << 16) | (NX_KEYDOWN << 8);
        result.keyDownResult = IOHIDPostEvent(
            sEventDriver,
            NX_SYSDEFINED,
            location,
            &event,
            kNXEventDataVersion,
            0,
            FALSE
        );
        result.keyDownPosted = result.keyDownResult == KERN_SUCCESS;
        if (!result.keyDownPosted) {
            CloseEventDriver(&result);
            return result;
        }

        result.keyUpAttempted = YES;
        event.compound.misc.L[0] = ((UInt32)keyCode << 16) | (NX_KEYUP << 8);
        result.keyUpResult = IOHIDPostEvent(
            sEventDriver,
            NX_SYSDEFINED,
            location,
            &event,
            kNXEventDataVersion,
            0,
            FALSE
        );
        result.keyUpPosted = result.keyUpResult == KERN_SUCCESS;
        result.succeeded = result.keyDownPosted && result.keyUpPosted;
        if (!result.keyUpPosted) {
            CloseEventDriver(&result);
        }
        return result;
    }
}

+ (BOOL)checkCoreGraphicsPostEventAccess
{
    return CGPreflightPostEventAccess();
}

+ (BOOL)requestCoreGraphicsPostEventAccess
{
    return CGRequestPostEventAccess();
}

+ (MMTMRCoreGraphicsAuxPostResult)postAuxKeyUsingCoreGraphics:(UInt8)keyCode
{
    MMTMRCoreGraphicsAuxPostResult result;
    memset(&result, 0, sizeof(result));

    // Construct the complete pair before posting either event. If construction
    // fails, the Swift dispatcher can safely use IOHID without duplicating an
    // already-delivered media-key action.
    CGEventRef keyDown = CreateAuxiliaryCGEvent(keyCode, YES);
    CGEventRef keyUp = CreateAuxiliaryCGEvent(keyCode, NO);
    result.keyDownCreated = keyDown != NULL;
    result.keyUpCreated = keyUp != NULL;
    if (keyDown == NULL || keyUp == NULL) {
        if (keyDown != NULL) {
            CFRelease(keyDown);
        }
        if (keyUp != NULL) {
            CFRelease(keyUp);
        }
        return result;
    }

    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    result.succeeded = YES;
    return result;
}

+ (void)HIDPostAuxKey:(UInt8)keyCode
{
    // Retain the historical Objective-C call while using the modern path first.
    // The Swift wrapper is preferred because it publishes a structured result.
    BOOL coreGraphicsGranted = [self checkCoreGraphicsPostEventAccess]
        || [self requestCoreGraphicsPostEventAccess];
    if (coreGraphicsGranted) {
        MMTMRCoreGraphicsAuxPostResult modern = [self postAuxKeyUsingCoreGraphics:keyCode];
        if (modern.succeeded) {
            return;
        }
    }

    MMTMRHIDPostEventAccess access = [self checkHIDPostEventAccess];
    BOOL ioHIDGranted = access == MMTMRHIDPostEventAccessGranted
        || [self requestHIDPostEventAccess];
    if (ioHIDGranted) {
        (void)[self postAuxKeyUsingIOHID:keyCode];
    }
}

@end
