//
//  FLEXingConfig.m
//  Shared rootless configuration helpers for FLEXing.
//

#import "FLEXingConfig.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const FLEXingPreferencesChangedNotification = @"com.github.devnoname120.flexing.preferenceschanged";

static NSString * const FLEXingApplicationsKey = @"Applications";
static NSString * const FLEXingEnabledKey = @"Enabled";
static NSString * const FLEXingAutoShowKey = @"AutoShow";
static NSString * const FLEXingAdjustmentsKey = @"Adjustments";
static NSString * const FLEXingPatchesKey = @"Patches";
static NSString * const FLEXingPatchIdentifierKey = @"Identifier";
static NSString * const FLEXingUpdatedKey = @"Updated";
static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";

NSString *FLEXingPreferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.github.devnoname120.flexing.plist";
}

NSDictionary *FLEXingLoadPreferences(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:FLEXingPreferencesPath()];
    return [preferences isKindOfClass:NSDictionary.class] ? preferences : @{};
}

NSMutableDictionary *FLEXingLoadMutablePreferences(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSMutableDictionary *mutablePreferences = [preferences mutableCopy];
    if (!mutablePreferences) {
        mutablePreferences = [NSMutableDictionary dictionary];
    }

    NSDictionary *applications = mutablePreferences[FLEXingApplicationsKey];
    if (![applications isKindOfClass:NSDictionary.class]) {
        mutablePreferences[FLEXingApplicationsKey] = [NSMutableDictionary dictionary];
    } else if (![applications isKindOfClass:NSMutableDictionary.class]) {
        mutablePreferences[FLEXingApplicationsKey] = [applications mutableCopy];
    }

    if (!mutablePreferences[FLEXingNetworkMonitoringKey]) {
        mutablePreferences[FLEXingNetworkMonitoringKey] = @YES;
    }

    return mutablePreferences;
}

static NSDictionary *FLEXingApplicationsDictionary(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSDictionary *applications = preferences[FLEXingApplicationsKey];
    return [applications isKindOfClass:NSDictionary.class] ? applications : @{};
}

static BOOL FLEXingWritePreferences(NSDictionary *preferences) {
    NSString *directory = [FLEXingPreferencesPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL saved = [preferences writeToFile:FLEXingPreferencesPath() atomically:YES];
    if (saved) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)FLEXingPreferencesChangedNotification, NULL, NULL, true);
    }

    return saved;
}

BOOL FLEXingHasSettingsForBundle(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSDictionary *settings = FLEXingApplicationsDictionary()[bundleIdentifier];
    return [settings isKindOfClass:NSDictionary.class];
}

NSDictionary *FLEXingSettingsForBundle(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return @{};
    }

    NSDictionary *settings = FLEXingApplicationsDictionary()[bundleIdentifier];
    return [settings isKindOfClass:NSDictionary.class] ? settings : @{};
}

BOOL FLEXingIsBundleEnabled(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSNumber *enabled = settings[FLEXingEnabledKey];
    return [enabled respondsToSelector:@selector(boolValue)] ? enabled.boolValue : YES;
}

BOOL FLEXingShouldAutoShowBundle(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSNumber *autoShow = settings[FLEXingAutoShowKey];
    return [autoShow respondsToSelector:@selector(boolValue)] ? autoShow.boolValue : YES;
}

BOOL FLEXingNetworkMonitoringEnabled(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSNumber *enabled = preferences[FLEXingNetworkMonitoringKey];
    return [enabled respondsToSelector:@selector(boolValue)] ? enabled.boolValue : YES;
}

NSString *FLEXingAdjustmentsForBundle(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSString *adjustments = settings[FLEXingAdjustmentsKey];
    return [adjustments isKindOfClass:NSString.class] ? adjustments : @"";
}

NSArray<NSDictionary *> *FLEXingPatchesForBundle(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSArray *patches = settings[FLEXingPatchesKey];
    if (![patches isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *clean = [NSMutableArray array];
    for (id patch in patches) {
        if ([patch isKindOfClass:NSDictionary.class]) {
            [clean addObject:patch];
        }
    }
    return clean;
}

BOOL FLEXingSaveSettingsForBundle(NSString *bundleIdentifier, BOOL enabled, BOOL autoShow, NSString *adjustments) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    NSMutableDictionary *applications = [preferences[FLEXingApplicationsKey] mutableCopy];
    if (!applications) {
        applications = [NSMutableDictionary dictionary];
    }

    NSMutableDictionary *settings = [applications[bundleIdentifier] mutableCopy];
    if (!settings) {
        settings = [NSMutableDictionary dictionary];
    }

    settings[FLEXingEnabledKey] = @(enabled);
    settings[FLEXingAutoShowKey] = @(autoShow);
    settings[FLEXingAdjustmentsKey] = adjustments ?: @"";
    settings[FLEXingUpdatedKey] = @([[NSDate date] timeIntervalSince1970]);

    applications[bundleIdentifier] = settings;
    preferences[FLEXingApplicationsKey] = applications;

    return FLEXingWritePreferences(preferences);
}

BOOL FLEXingSavePatchesForBundle(NSString *bundleIdentifier, NSArray<NSDictionary *> *patches) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    NSMutableDictionary *applications = [preferences[FLEXingApplicationsKey] mutableCopy];
    if (!applications) {
        applications = [NSMutableDictionary dictionary];
    }

    NSMutableDictionary *settings = [applications[bundleIdentifier] mutableCopy];
    if (!settings) {
        settings = [NSMutableDictionary dictionary];
    }

    NSMutableArray<NSDictionary *> *clean = [NSMutableArray array];
    for (id patch in patches ?: @[]) {
        if ([patch isKindOfClass:NSDictionary.class]) {
            [clean addObject:patch];
        }
    }

    settings[FLEXingPatchesKey] = clean;
    settings[FLEXingUpdatedKey] = @([[NSDate date] timeIntervalSince1970]);
    applications[bundleIdentifier] = settings;
    preferences[FLEXingApplicationsKey] = applications;

    return FLEXingWritePreferences(preferences);
}

BOOL FLEXingUpsertPatchForBundle(NSString *bundleIdentifier, NSDictionary *patch) {
    if (bundleIdentifier.length == 0 || ![patch isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSString *identifier = patch[FLEXingPatchIdentifierKey];
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) {
        return NO;
    }

    NSMutableArray<NSDictionary *> *patches = [FLEXingPatchesForBundle(bundleIdentifier) mutableCopy];
    NSUInteger existingIndex = NSNotFound;
    for (NSUInteger index = 0; index < patches.count; index++) {
        NSString *existingIdentifier = patches[index][FLEXingPatchIdentifierKey];
        if ([existingIdentifier isEqualToString:identifier]) {
            existingIndex = index;
            break;
        }
    }

    if (existingIndex == NSNotFound) {
        [patches addObject:patch];
    } else {
        patches[existingIndex] = patch;
    }

    return FLEXingSavePatchesForBundle(bundleIdentifier, patches);
}

BOOL FLEXingRemovePatchForBundle(NSString *bundleIdentifier, NSString *patchIdentifier) {
    if (bundleIdentifier.length == 0 || patchIdentifier.length == 0) {
        return NO;
    }

    NSMutableArray<NSDictionary *> *patches = [NSMutableArray array];
    for (NSDictionary *patch in FLEXingPatchesForBundle(bundleIdentifier)) {
        NSString *identifier = patch[FLEXingPatchIdentifierKey];
        if (![identifier isEqualToString:patchIdentifier]) {
            [patches addObject:patch];
        }
    }

    return FLEXingSavePatchesForBundle(bundleIdentifier, patches);
}
