#!/usr/bin/env python3
from pathlib import Path

changed = False

# This script can be run by both GitHub Actions and the Makefile in the same checkout.
# If the global auto show patch is already present, exit early so later patches that
# insert code between our helper block and FLEXingNetworkMonitoringEnabled do not make
# the old insertion needle look unpatched and duplicate the helper functions.
config_path = Path('Shared/FLEXingConfig.m')
header_path = Path('Shared/FLEXingConfig.h')
tweak_path = Path('Tweak.xm')
if config_path.exists() and header_path.exists() and tweak_path.exists():
    config_text = config_path.read_text()
    header_text = header_path.read_text()
    tweak_text = tweak_path.read_text()
    if (
        'BOOL FLEX4BetaGlobalAutoShowEnabled(void)' in config_text
        and 'BOOL FLEX4BetaSaveGlobalAutoShowEnabled(BOOL enabled)' in header_text
        and 'toggleGlobalAutoShow' in tweak_text
    ):
        print('FLEX 4 Beta global Auto Show patch already present')
        raise SystemExit(0)

def patch_file(path_name, patches):
    global changed
    path = Path(path_name)
    text = path.read_text()
    original = text

    for old, new, label, required in patches:
        if new in text:
            print(f'Skipped already patched: {path_name} {label}')
            continue
        if old in text:
            text = text.replace(old, new, 1)
            print(f'Patched: {path_name} {label}')
        elif required:
            raise SystemExit(f'Could not find block to patch: {path_name} {label}')
        else:
            print(f'Skipped missing block: {path_name} {label}')

    if text != original:
        path.write_text(text)
        changed = True

header_patches = [
    (
        'BOOL FLEXingNetworkMonitoringEnabled(void);\n',
        'BOOL FLEX4BetaGlobalAutoShowEnabled(void);\nBOOL FLEX4BetaSaveGlobalAutoShowEnabled(BOOL enabled);\nBOOL FLEXingNetworkMonitoringEnabled(void);\n',
        'global auto show declarations',
        True,
    ),
]

config_patches = [
    (
        'static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n',
        'static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\nstatic NSString * const FLEX4BetaGlobalAutoShowKey = @"GlobalAutoShow";\n',
        'global auto show key',
        True,
    ),
    (
        '    if (!mutablePreferences[FLEXingNetworkMonitoringKey]) {\n        mutablePreferences[FLEXingNetworkMonitoringKey] = @YES;\n    }\n',
        '    if (!mutablePreferences[FLEXingNetworkMonitoringKey]) {\n        mutablePreferences[FLEXingNetworkMonitoringKey] = @YES;\n    }\n\n    if (!mutablePreferences[FLEX4BetaGlobalAutoShowKey]) {\n        mutablePreferences[FLEX4BetaGlobalAutoShowKey] = @YES;\n    }\n',
        'global auto show default',
        True,
    ),
    (
        '''BOOL FLEXingShouldAutoShowBundle(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSNumber *autoShow = settings[FLEXingAutoShowKey];
    return [autoShow respondsToSelector:@selector(boolValue)] ? autoShow.boolValue : YES;
}
''',
        '''BOOL FLEXingShouldAutoShowBundle(NSString *bundleIdentifier) {
    NSDictionary *settings = FLEXingSettingsForBundle(bundleIdentifier);
    NSNumber *autoShow = settings[FLEXingAutoShowKey];
    if ([autoShow respondsToSelector:@selector(boolValue)]) {
        return autoShow.boolValue;
    }
    return FLEX4BetaGlobalAutoShowEnabled();
}
''',
        'global auto show fallback',
        True,
    ),
    (
        'BOOL FLEXingNetworkMonitoringEnabled(void) {\n',
        '''BOOL FLEX4BetaGlobalAutoShowEnabled(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSNumber *enabled = preferences[FLEX4BetaGlobalAutoShowKey];
    return [enabled respondsToSelector:@selector(boolValue)] ? enabled.boolValue : YES;
}

BOOL FLEX4BetaSaveGlobalAutoShowEnabled(BOOL enabled) {
    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    preferences[FLEX4BetaGlobalAutoShowKey] = @(enabled);

    NSString *directory = [FLEXingPreferencesPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL saved = [preferences writeToFile:FLEXingPreferencesPath() atomically:YES];
    if (saved) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)FLEXingPreferencesChangedNotification, NULL, NULL, true);
    }
    return saved;
}

BOOL FLEXingNetworkMonitoringEnabled(void) {
''',
        'global auto show helpers',
        True,
    ),
]

tweak_patches = [
    (
        '    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);\n    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);\n',
        '    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);\n    BOOL globalAutoShow = FLEX4BetaGlobalAutoShowEnabled();\n    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);\n',
        'load global auto show state',
        True,
    ),
    (
        '    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments"]];\n',
        '    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments"]];\n\n    [items addObject:[FLEXingBrowserItem itemWithTitle:(globalAutoShow ? @"Default Auto Show: On" : @"Default Auto Show: Off") subtitle:@"Controls automatic opening for apps without a saved per-app Auto Show setting" section:@"FLEX 4 Beta" kind:@"toggleGlobalAutoShow"]];\n',
        'global auto show row',
        True,
    ),
    (
        '    cell.accessoryType = ([item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"editAdjustments"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;\n',
        '    cell.accessoryType = ([item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"toggleGlobalAutoShow"] || [item.kind isEqualToString:@"editAdjustments"] || [item.kind isEqualToString:@"overridesBucket"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;\n',
        'global auto show accessory',
        True,
    ),
    (
        '    if ([item.kind isEqualToString:@"toggleEnabled"]) {\n',
        '    if ([item.kind isEqualToString:@"toggleGlobalAutoShow"]) {\n        BOOL nextGlobalAutoShow = !FLEX4BetaGlobalAutoShowEnabled();\n        FLEX4BetaSaveGlobalAutoShowEnabled(nextGlobalAutoShow);\n        [self reloadItems];\n        return;\n    }\n\n    if ([item.kind isEqualToString:@"toggleEnabled"]) {\n',
        'global auto show action',
        True,
    ),
]

patch_file('Shared/FLEXingConfig.h', header_patches)
patch_file('Shared/FLEXingConfig.m', config_patches)
patch_file('Tweak.xm', tweak_patches)

print('Added FLEX 4 Beta global Auto Show default toggle' if changed else 'No changes needed')