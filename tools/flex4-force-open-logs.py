#!/usr/bin/env python3
from pathlib import Path

changed = False


def patch_text(path_name, transform):
    global changed
    path = Path(path_name)
    text = path.read_text()
    new_text = transform(text)
    if new_text != text:
        path.write_text(new_text)
        changed = True
        print(f'Patched {path_name}')
    else:
        print(f'No changes needed for {path_name}')


def insert_before(text, needle, insertion, label, required=True):
    if insertion.strip() in text:
        print(f'Skipped already patched: {label}')
        return text
    if needle not in text:
        message = f'Could not find block to patch: {label}'
        if required:
            raise SystemExit(message)
        print(message)
        return text
    print(f'Patched: {label}')
    return text.replace(needle, insertion + needle, 1)


def replace_optional(text, old, new, label):
    if new in text:
        print(f'Skipped already patched: {label}')
        return text
    if old not in text:
        print(f'Skipped missing block: {label}')
        return text
    print(f'Patched: {label}')
    return text.replace(old, new, 1)


HEADER_DECLS = '''NSArray<NSDictionary *> *FLEX4BetaForceOpenLaunchLogs(void);
BOOL FLEX4BetaAppendForceOpenLaunchLog(NSString *bundleIdentifier, NSString *appName, NSString *event, NSString *detail);
BOOL FLEX4BetaClearForceOpenLaunchLogs(void);
'''


def patch_header(text):
    return insert_before(text, 'BOOL FLEXingNetworkMonitoringEnabled(void);\n', HEADER_DECLS, 'force open logs declarations')


CONFIG_KEY = 'static NSString * const FLEX4BetaForceOpenLaunchLogsKey = @"ForceOpenLaunchLogs";\n'
CONFIG_HELPERS = '''static NSString *FLEX4BetaLogSafeString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return (NSString *)value;
    }
    if ([value respondsToSelector:@selector(description)]) {
        return [value description] ?: @"";
    }
    return @"";
}

NSArray<NSDictionary *> *FLEX4BetaForceOpenLaunchLogs(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSArray *logs = preferences[FLEX4BetaForceOpenLaunchLogsKey];
    if (![logs isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *validLogs = [NSMutableArray array];
    for (id entry in logs) {
        if ([entry isKindOfClass:NSDictionary.class]) {
            [validLogs addObject:entry];
        }
    }
    return validLogs;
}

BOOL FLEX4BetaAppendForceOpenLaunchLog(NSString *bundleIdentifier, NSString *appName, NSString *event, NSString *detail) {
    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    NSMutableArray<NSDictionary *> *logs = [preferences[FLEX4BetaForceOpenLaunchLogsKey] mutableCopy];
    if (!logs) {
        logs = [NSMutableArray array];
    }

    NSDictionary *entry = @{
        @"Time": @([[NSDate date] timeIntervalSince1970]),
        @"Bundle": FLEX4BetaLogSafeString(bundleIdentifier),
        @"App": FLEX4BetaLogSafeString(appName),
        @"Event": FLEX4BetaLogSafeString(event),
        @"Detail": FLEX4BetaLogSafeString(detail)
    };

    [logs insertObject:entry atIndex:0];
    while (logs.count > 120) {
        [logs removeLastObject];
    }
    preferences[FLEX4BetaForceOpenLaunchLogsKey] = logs;

    NSString *directory = [FLEXingPreferencesPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL saved = [preferences writeToFile:FLEXingPreferencesPath() atomically:YES];
    if (saved) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)FLEXingPreferencesChangedNotification, NULL, NULL, true);
    }
    return saved;
}

BOOL FLEX4BetaClearForceOpenLaunchLogs(void) {
    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    [preferences removeObjectForKey:FLEX4BetaForceOpenLaunchLogsKey];

    NSString *directory = [FLEXingPreferencesPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL saved = [preferences writeToFile:FLEXingPreferencesPath() atomically:YES];
    if (saved) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)FLEXingPreferencesChangedNotification, NULL, NULL, true);
    }
    return saved;
}

'''


def patch_config(text):
    if CONFIG_KEY not in text:
        if 'static NSString * const FLEX4BetaForceOpenApplicationsKey = @"ForceOpenApplications";\n' in text:
            text = text.replace('static NSString * const FLEX4BetaForceOpenApplicationsKey = @"ForceOpenApplications";\n', 'static NSString * const FLEX4BetaForceOpenApplicationsKey = @"ForceOpenApplications";\n' + CONFIG_KEY, 1)
            print('Patched: force open launch logs key after force open key')
        elif 'static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n' in text:
            text = text.replace('static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n', 'static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n' + CONFIG_KEY, 1)
            print('Patched: force open launch logs key after network monitoring key')
        else:
            raise SystemExit('Could not find block to patch: force open launch logs key')
    else:
        print('Skipped already patched: force open launch logs key')

    text = insert_before(text, 'BOOL FLEXingNetworkMonitoringEnabled(void) {\n', CONFIG_HELPERS, 'force open launch logs helpers')
    return text


LOG_HELPER_AND_VIEW = '''// FLEX4BetaForceOpenLogsPatchMarker
static void FLEX4BetaLogForceOpenLaunch(NSString *event, NSString *detail) {
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    if (!FLEX4BetaIsForceOpenBundle(bundleIdentifier)) {
        return;
    }

    NSString *appName = FLEXingDisplayNameForCurrentProcess();
    NSString *message = [NSString stringWithFormat:@"%@: %@", event ?: @"Log", detail ?: @""];
    HBLogInfo(@"FLEX 4 Beta Force Open: %@ %@", bundleIdentifier, message);
    FLEX4BetaAppendForceOpenLaunchLog(bundleIdentifier, appName, event ?: @"Log", detail ?: @"");
}

@interface FLEX4BetaForceOpenLogsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *logs;
@end

@implementation FLEX4BetaForceOpenLogsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Force Open Logs";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLogs)];
    [self reloadLogs];
}

- (void)reloadLogs {
    self.logs = FLEX4BetaForceOpenLaunchLogs();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.logs.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Launch Diagnostics - %lu", (unsigned long)self.logs.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Logs are written only when a selected Force Open app is actually reached by the tweak. If a selected app never appears here, injection did not reach that app or the process never loaded the tweak.";
}

- (NSString *)stringForLog:(NSDictionary *)entry key:(NSString *)key fallback:(NSString *)fallback {
    id value = entry[key];
    return [value isKindOfClass:NSString.class] && [(NSString *)value length] ? value : fallback;
}

- (NSString *)timeStringForLog:(NSDictionary *)entry {
    NSNumber *time = entry[@"Time"];
    if (![time respondsToSelector:@selector(doubleValue)]) {
        return @"No timestamp";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:time.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:date];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FLEX4BetaForceOpenLogCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FLEX4BetaForceOpenLogCell"];
    }

    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 4;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (self.logs.count == 0) {
        cell.textLabel.text = @"No Force Open logs yet";
        cell.detailTextLabel.text = @"Launch one of the apps selected in Force Open Apps. If it still never logs here, the tweak is not being injected into that app.";
        return cell;
    }

    NSDictionary *entry = self.logs[(NSUInteger)indexPath.row];
    NSString *event = [self stringForLog:entry key:@"Event" fallback:@"Log"];
    NSString *app = [self stringForLog:entry key:@"App" fallback:@"Unknown App"];
    NSString *bundle = [self stringForLog:entry key:@"Bundle" fallback:@"No bundle"];
    NSString *detail = [self stringForLog:entry key:@"Detail" fallback:@""];
    NSString *time = [self timeStringForLog:entry];

    cell.textLabel.text = [NSString stringWithFormat:@"%@ - %@", event, app];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", bundle, time, detail];
    if ([event.lowercaseString containsString:@"blocked"] || [event.lowercaseString containsString:@"failed"]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.detailTextLabel.textColor = UIColor.systemOrangeColor;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.logs.count == 0 || indexPath.row >= (NSInteger)self.logs.count) {
        return;
    }

    NSDictionary *entry = self.logs[(NSUInteger)indexPath.row];
    NSString *event = [self stringForLog:entry key:@"Event" fallback:@"Log"];
    NSString *app = [self stringForLog:entry key:@"App" fallback:@"Unknown App"];
    NSString *bundle = [self stringForLog:entry key:@"Bundle" fallback:@"No bundle"];
    NSString *detail = [self stringForLog:entry key:@"Detail" fallback:@""];
    NSString *time = [self timeStringForLog:entry];
    NSString *message = [NSString stringWithFormat:@"App: %@\nBundle: %@\nTime: %@\n\n%@", app, bundle, time, detail];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:event message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearLogs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Force Open Logs" message:@"Remove all recorded launch diagnostics?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        FLEX4BetaClearForceOpenLaunchLogs();
        [self reloadLogs];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

static void FLEX4BetaOpenForceOpenLogsMenu(__kindof UITableViewController *host) {
    FLEX4BetaForceOpenLogsViewController *logs = [[FLEX4BetaForceOpenLogsViewController alloc] init];
    if (host.navigationController) {
        [host.navigationController pushViewController:logs animated:YES];
    } else {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:logs];
        [(UIViewController *)host presentViewController:navigationController animated:YES completion:nil];
    }
}

'''


def patch_tweak(text):
    if 'FLEX4BetaForceOpenAppsPatchMarker' not in text:
        print('Skipped Force Open Logs row because Force Open Apps patch is not present yet')
        return text

    text = insert_before(text, 'static void FLEX4BetaOpenForceOpenAppsMenu(__kindof UITableViewController *host) {\n', LOG_HELPER_AND_VIEW, 'force open logs view controller', required=False)

    if '@"Force Open Logs"' not in text:
        force_open_registration = '    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Apps", forceOpenAction);\n'
        force_open_logs_registration = force_open_registration + '''
    FLEXingGlobalsRowAction forceOpenLogsAction = ^(__kindof UITableViewController *host) {
        FLEX4BetaOpenForceOpenLogsMenu(host);
    };
    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Logs", forceOpenLogsAction);
'''
        text = replace_optional(text, force_open_registration, force_open_logs_registration, 'force open logs custom row registration')
    else:
        print('Skipped already patched: force open logs custom row registration')

    text = text.replace('HBLogInfo(@"FLEXing: Registered FLEX 4 Beta and Force Open Apps panel rows.");', 'HBLogInfo(@"FLEXing: Registered FLEX 4 Beta, Force Open Apps, and Force Open Logs panel rows.");')

    old_launch_state = '''    BOOL springBoardProcess = isSpringBoardProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    currentBundleAllowsFLEX = springBoardProcess || currentBundleForceOpen || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = currentBundleForceOpen || FLEXingShouldAutoShowBundle(currentBundleIdentifier);
'''
    new_launch_state = '''    BOOL springBoardProcess = isSpringBoardProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    if (currentBundleForceOpen) {
        NSString *detail = [NSString stringWithFormat:@"Process reached. executable=%@ bundlePath=%@", NSProcessInfo.processInfo.arguments.firstObject ?: @"", NSBundle.mainBundle.bundlePath ?: @""];
        FLEX4BetaLogForceOpenLaunch(@"Process Reached", detail);
    }
    currentBundleAllowsFLEX = springBoardProcess || currentBundleForceOpen || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = currentBundleForceOpen || FLEXingShouldAutoShowBundle(currentBundleIdentifier);
    if (currentBundleForceOpen) {
        FLEX4BetaLogForceOpenLaunch(@"Settings Loaded", [NSString stringWithFormat:@"allows=%@ autoShow=%@", currentBundleAllowsFLEX ? @"YES" : @"NO", currentBundleShouldAutoShow ? @"YES" : @"NO"]);
    }
'''
    text = replace_optional(text, old_launch_state, new_launch_state, 'force open launch state logging')

    old_no_lib = '''        } else {
            // libFLEX not found
            // ...
        }
'''
    new_no_lib = '''        } else {
            if (currentBundleForceOpen) {
                NSString *detail = [NSString stringWithFormat:@"libFLEX.dylib was not found. checked=%@ appFrameworks=%@", standardPath ?: @"", possibleFlexPath ?: @""];
                FLEX4BetaLogForceOpenLaunch(@"Blocked - Missing libFLEX", detail);
            }
        }
'''
    text = replace_optional(text, old_no_lib, new_no_lib, 'force open missing libFLEX logging')

    old_guard = '''        if (isLikelyUIProcess() && !isSnapchatApp() && currentBundleAllowsFLEX) {
            handle = dlopen(libflex.UTF8String, RTLD_LAZY);
            
            if (libreflex) {
                dlopen(libreflex.UTF8String, RTLD_NOW);
            }

            HBLogInfo(@"FLEXing: Initialized for %@", currentBundleIdentifier);
'''
    new_guard = '''        BOOL likelyUIProcess = isLikelyUIProcess();
        BOOL snapchatApp = isSnapchatApp();
        if (currentBundleForceOpen && !likelyUIProcess) {
            NSString *detail = [NSString stringWithFormat:@"Runtime guard rejected this process. executable=%@ bundlePath=%@", NSProcessInfo.processInfo.arguments.firstObject ?: @"", NSBundle.mainBundle.bundlePath ?: @""];
            FLEX4BetaLogForceOpenLaunch(@"Blocked - Runtime Guard", detail);
        }
        if (currentBundleForceOpen && snapchatApp) {
            FLEX4BetaLogForceOpenLaunch(@"Blocked - Protected App", @"Snapchat protection prevented FLEX from loading.");
        }

        if (likelyUIProcess && !snapchatApp && currentBundleAllowsFLEX) {
            handle = dlopen(libflex.UTF8String, RTLD_LAZY);
            if (!handle && currentBundleForceOpen) {
                const char *loadError = dlerror();
                NSString *detail = [NSString stringWithFormat:@"dlopen failed for %@: %s", libflex ?: @"", loadError ?: "unknown"];
                FLEX4BetaLogForceOpenLaunch(@"Blocked - dlopen Failed", detail);
            }
            
            if (libreflex) {
                dlopen(libreflex.UTF8String, RTLD_NOW);
            }

            HBLogInfo(@"FLEXing: Initialized for %@", currentBundleIdentifier);
            if (currentBundleForceOpen && handle) {
                FLEX4BetaLogForceOpenLaunch(@"Loaded libFLEX", [NSString stringWithFormat:@"Loaded %@", libflex ?: @""]);
            }
'''
    text = replace_optional(text, old_guard, new_guard, 'force open guard and dlopen logging')

    old_symbols = '''        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
            enableNetworkMonitoringIfPossible();
            FLEXingRegisterPanelEntryIfPossible();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
'''
    new_symbols = '''        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
            enableNetworkMonitoringIfPossible();
            FLEXingRegisterPanelEntryIfPossible();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
            if (currentBundleForceOpen) {
                FLEX4BetaLogForceOpenLaunch(@"Initialized", @"FLEX manager and reveal selector resolved.");
            }
'''
    text = replace_optional(text, old_symbols, new_symbols, 'force open initialized logging')

    old_delayed = '''            if (currentBundleForceOpen && !didAutoShowExplorer && !isSpringBoardProcess()) {
                didAutoShowExplorer = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (manager && show) {
                        [manager performSelector:show];
                    }
                });
            }
'''
    new_delayed = '''            if (currentBundleForceOpen && !didAutoShowExplorer && !isSpringBoardProcess()) {
                didAutoShowExplorer = YES;
                FLEX4BetaLogForceOpenLaunch(@"Scheduled Open", @"Will call FLEX show selector after app launch delay.");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (manager && show) {
                        FLEX4BetaLogForceOpenLaunch(@"Show Attempt", @"Calling FLEX show selector now.");
                        [manager performSelector:show];
                    } else {
                        FLEX4BetaLogForceOpenLaunch(@"Blocked - Missing Manager", @"FLEX manager or show selector was nil at delayed open time.");
                    }
                });
            }
'''
    text = replace_optional(text, old_delayed, new_delayed, 'force open delayed show logging')

    return text


patch_text('Shared/FLEXingConfig.h', patch_header)
patch_text('Shared/FLEXingConfig.m', patch_config)
patch_text('Tweak.xm', patch_tweak)

print('Added FLEX 4 Beta Force Open Logs row and diagnostics' if changed else 'No changes needed')
