//
//  FLEXingConfig.h
//  Shared rootless configuration helpers for FLEXing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const FLEXingPreferencesChangedNotification;

NSString *FLEXingPreferencesPath(void);
NSDictionary *FLEXingLoadPreferences(void);
NSMutableDictionary *FLEXingLoadMutablePreferences(void);
NSDictionary *FLEXingSettingsForBundle(NSString *bundleIdentifier);
BOOL FLEXingIsBundleEnabled(NSString *bundleIdentifier);
BOOL FLEXingShouldAutoShowBundle(NSString *bundleIdentifier);
BOOL FLEXingNetworkMonitoringEnabled(void);
NSString *FLEXingAdjustmentsForBundle(NSString *bundleIdentifier);
BOOL FLEXingSaveSettingsForBundle(NSString *bundleIdentifier, BOOL enabled, BOOL autoShow, NSString *adjustments);

NS_ASSUME_NONNULL_END
