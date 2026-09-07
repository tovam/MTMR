//
//  LaunchAtLoginController.m
//
//  Copyright 2011 Tomáš Znamenáček
//  Copyright 2010 Ben Clark-Robinson
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the ‘Software’),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "LaunchAtLoginController.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const StartAtLoginKey = @"launchAtLogin";

@interface LaunchAtLoginController ()
@property(assign) LSSharedFileListRef loginItems;
@end

@implementation LaunchAtLoginController
@synthesize loginItems;

#pragma mark Change Observing

void sharedFileListDidChange(LSSharedFileListRef inList, void *context)
{
    LaunchAtLoginController *self = (__bridge id) context;
    [self willChangeValueForKey:StartAtLoginKey];
    [self didChangeValueForKey:StartAtLoginKey];
}

#pragma mark Initialization

- (id) init
{
    self = [super init];
    loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    LSSharedFileListAddObserver(loginItems, CFRunLoopGetMain(),
                                (CFStringRef)NSDefaultRunLoopMode, sharedFileListDidChange, (__bridge void *)(self));
    return self;
}

- (void) dealloc
{
    LSSharedFileListRemoveObserver(loginItems, CFRunLoopGetMain(),
                                   (CFStringRef)NSDefaultRunLoopMode, sharedFileListDidChange, (__bridge void *)(self));
    CFRelease(loginItems);
}

#pragma mark Launch List Control
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
LSSharedFileListItemRef copyItemWithURLinFileList(NSURL* wantedURL, LSSharedFileListRef fileList) {
    if (wantedURL == NULL || fileList == NULL)
        return NULL;
    
    NSArray *listSnapshot = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(fileList, NULL);
    for(NSUInteger i = 0; i< [listSnapshot count]; i++) {
        LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)[listSnapshot objectAtIndex:i];
        UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
        CFURLRef currentItemURL = NULL;
        LSSharedFileListItemResolve(item, resolutionFlags, &currentItemURL, NULL);
        if (currentItemURL && [(__bridge_transfer NSURL*)currentItemURL isEqual:wantedURL]) {
            CFRetain(item);
            return item;
        }
    }
    
    return NULL;
}

static BOOL MMTMRLoginItemURLMatchesApplication(NSURL *itemURL)
{
    if (itemURL == nil)
        return NO;

    static NSSet<NSString *> *bundleIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleIdentifiers = [NSSet setWithArray:@[
            @"Toxblh.MTMR",
            @"com.toxblh.MTMR",
            @"com.tovam.MTMR",
            @"com.tovam.MMTMR"
        ]];
    });

    NSString *bundleIdentifier = [NSBundle bundleWithURL:itemURL].bundleIdentifier;
    if (bundleIdentifier != nil && [bundleIdentifiers containsObject:bundleIdentifier])
        return YES;

    // A moved or partially replaced bundle may no longer have readable metadata.
    NSString *name = itemURL.lastPathComponent.lowercaseString;
    return [name isEqualToString:@"mmtmr.app"] || [name isEqualToString:@"mtmr.app"];
}

static NSURL *MMTMRStandardizedFileURL(NSURL *URL)
{
    return URL.filePathURL.URLByStandardizingPath;
}
#pragma clang diagnostic pop

- (BOOL) willLaunchAtLogin: (NSURL*) itemURL
{
    return !!copyItemWithURLinFileList(itemURL, loginItems);
}

- (void) setLaunchAtLogin: (BOOL) enabled forURL: (NSURL*) itemURL
{
    LSSharedFileListItemRef appItem = copyItemWithURLinFileList(itemURL, loginItems);
    if (enabled && !appItem) {
        LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst,
                                      NULL, NULL, (__bridge CFURLRef)itemURL, NULL, NULL);
    } else if (!enabled && appItem) {
        LSSharedFileListItemRemove(loginItems, appItem);
    }
    if (appItem) {
        CFRelease(appItem);
    }
}

- (BOOL) repairLaunchAtLoginForURL: (NSURL*) itemURL
{
    if (itemURL == nil || loginItems == NULL)
        return NO;

    NSURL *wantedURL = MMTMRStandardizedFileURL(itemURL);
    NSArray *snapshot = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, NULL);
    NSMutableArray *matchingItems = [NSMutableArray array];
    NSUInteger currentURLCount = 0;

    for (id value in snapshot) {
        LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)value;
        UInt32 flags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
        CFURLRef resolvedURL = NULL;
        if (LSSharedFileListItemResolve(item, flags, &resolvedURL, NULL) != noErr || resolvedURL == NULL)
            continue;

        NSURL *URL = CFBridgingRelease(resolvedURL);
        if (!MMTMRLoginItemURLMatchesApplication(URL))
            continue;

        [matchingItems addObject:value];
        if ([MMTMRStandardizedFileURL(URL) isEqual:wantedURL])
            currentURLCount += 1;
    }

    if (matchingItems.count == 0 || (matchingItems.count == 1 && currentURLCount == 1))
        return NO;

    // Preserve the user's enabled choice, but collapse duplicates and stale
    // aliases onto the currently executing application bundle.
    for (id value in matchingItems) {
        LSSharedFileListItemRemove(loginItems, (__bridge LSSharedFileListItemRef)value);
    }
    LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst,
                                  NULL, NULL, (__bridge CFURLRef)wantedURL, NULL, NULL);
    return YES;
}

#pragma mark Basic Interface

- (NSURL*) appURL
{
    return [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
}

- (void) setLaunchAtLogin: (BOOL) enabled
{
    [self willChangeValueForKey:StartAtLoginKey];
    [self setLaunchAtLogin:enabled forURL:[self appURL]];
    [self didChangeValueForKey:StartAtLoginKey];
}

- (BOOL) launchAtLogin
{
    return [self willLaunchAtLogin:[self appURL]];
}

@end
#pragma clang diagnostic pop
