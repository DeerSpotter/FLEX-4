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

BOOL FLEXingSaveSettingsForBundle(NSString *bundleIdentifier, BOOL enabled, BOOL autoShow, NSString *adjustments) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    NSMutableDictionary *applications = [preferences[FLEXingApplicationsKey] mutableCopy];
    if (!applications) {
        applications = [NSMutableDictionary dictionary];
    }

    applications[bundleIdentifier] = @{
        FLEXingEnabledKey: @(enabled),
        FLEXingAutoShowKey: @(autoShow),
        FLEXingAdjustmentsKey: adjustments ?: @"",
        FLEXingUpdatedKey: @([[NSDate date] timeIntervalSince1970])
    };

    preferences[FLEXingApplicationsKey] = applications;

    NSString *directory = [FLEXingPreferencesPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL saved = [preferences writeToFile:FLEXingPreferencesPath() atomically:YES];
    if (saved) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)FLEXingPreferencesChangedNotification, NULL, NULL, true);
    }

    return saved;
}
