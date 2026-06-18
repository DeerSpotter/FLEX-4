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


def insert_before(text, needle, insertion, label):
    if insertion.strip() in text:
        print(f'Skipped already patched: {label}')
        return text
    if needle not in text:
        raise SystemExit(f'Could not find block to patch: {label}')
    print(f'Patched: {label}')
    return text.replace(needle, insertion + needle, 1)


def replace_once(text, old, new, label):
    if new in text:
        print(f'Skipped already patched: {label}')
        return text
    if old not in text:
        raise SystemExit(f'Could not find block to patch: {label}')
    print(f'Patched: {label}')
    return text.replace(old, new, 1)


HEADER_DECLS = '''NSArray<NSString *> *FLEX4BetaForceOpenBundleIdentifiers(void);
BOOL FLEX4BetaIsForceOpenBundle(NSString *bundleIdentifier);
BOOL FLEX4BetaSetForceOpenBundle(NSString *bundleIdentifier, BOOL enabled);
'''


def patch_header(text):
    return insert_before(text, 'BOOL FLEXingNetworkMonitoringEnabled(void);\n', HEADER_DECLS, 'force open declarations')


CONFIG_KEY = 'static NSString * const FLEX4BetaForceOpenApplicationsKey = @"ForceOpenApplications";\n'
CONFIG_HELPERS = '''NSArray<NSString *> *FLEX4BetaForceOpenBundleIdentifiers(void) {
    NSDictionary *preferences = FLEXingLoadPreferences();
    NSArray *bundleIdentifiers = preferences[FLEX4BetaForceOpenApplicationsKey];
    if (![bundleIdentifiers isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSString *> *validBundleIdentifiers = [NSMutableArray array];
    for (id value in bundleIdentifiers) {
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
            [validBundleIdentifiers addObject:value];
        }
    }
    return validBundleIdentifiers;
}

BOOL FLEX4BetaIsForceOpenBundle(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }
    return [FLEX4BetaForceOpenBundleIdentifiers() containsObject:bundleIdentifier];
}

BOOL FLEX4BetaSetForceOpenBundle(NSString *bundleIdentifier, BOOL enabled) {
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *preferences = FLEXingLoadMutablePreferences();
    NSMutableArray<NSString *> *forceOpenApplications = [preferences[FLEX4BetaForceOpenApplicationsKey] mutableCopy];
    if (!forceOpenApplications) {
        forceOpenApplications = [NSMutableArray array];
    }

    if (enabled) {
        if (![forceOpenApplications containsObject:bundleIdentifier]) {
            [forceOpenApplications addObject:bundleIdentifier];
        }

        NSMutableDictionary *applications = [preferences[FLEXingApplicationsKey] mutableCopy];
        if (!applications) {
            applications = [NSMutableDictionary dictionary];
        }

        NSDictionary *existingSettings = [applications[bundleIdentifier] isKindOfClass:NSDictionary.class] ? applications[bundleIdentifier] : @{};
        NSString *adjustments = [existingSettings[FLEXingAdjustmentsKey] isKindOfClass:NSString.class] ? existingSettings[FLEXingAdjustmentsKey] : @"Force Open";
        applications[bundleIdentifier] = @{
            FLEXingEnabledKey: @YES,
            FLEXingAutoShowKey: @YES,
            FLEXingAdjustmentsKey: adjustments.length ? adjustments : @"Force Open",
            FLEXingUpdatedKey: @([[NSDate date] timeIntervalSince1970])
        };
        preferences[FLEXingApplicationsKey] = applications;
    } else {
        [forceOpenApplications removeObject:bundleIdentifier];
    }

    preferences[FLEX4BetaForceOpenApplicationsKey] = forceOpenApplications;

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
        if 'static NSString * const FLEX4BetaGlobalAutoShowKey = @"GlobalAutoShow";\n' in text:
            text = text.replace('static NSString * const FLEX4BetaGlobalAutoShowKey = @"GlobalAutoShow";\n', 'static NSString * const FLEX4BetaGlobalAutoShowKey = @"GlobalAutoShow";\n' + CONFIG_KEY, 1)
            print('Patched: force open key after global auto show key')
        else:
            text = text.replace('static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n', 'static NSString * const FLEXingNetworkMonitoringKey = @"NetworkMonitoring";\n' + CONFIG_KEY, 1)
            print('Patched: force open key after network monitoring key')
    else:
        print('Skipped already patched: force open key')

    text = insert_before(text, 'BOOL FLEXingNetworkMonitoringEnabled(void) {\n', CONFIG_HELPERS, 'force open helpers')
    return text


FORCE_OPEN_VIEW_CONTROLLER = '''// FLEX4BetaForceOpenAppsPatchMarker
static id FLEX4BetaPerformNoArg(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:selector];
#pragma clang diagnostic pop
}

@interface FLEX4BetaForceOpenAppsViewController : UITableViewController <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<NSDictionary *> *allApps;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredApps;
@property (nonatomic, copy) NSString *query;
@end

@implementation FLEX4BetaForceOpenAppsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Force Open Apps";
        self.query = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56.0)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search apps or bundle IDs";
    self.tableView.tableHeaderView = self.searchBar;

    self.allApps = [self loadInstalledApps];
    [self applyFilter];
}

- (NSArray<NSDictionary *> *)loadInstalledApps {
    NSMutableArray<NSDictionary *> *apps = [NSMutableArray array];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = FLEX4BetaPerformNoArg(workspaceClass, @"defaultWorkspace");
    NSArray *applications = FLEX4BetaPerformNoArg(workspace, @"allApplications");

    for (id application in applications) {
        NSString *bundleIdentifier = FLEX4BetaPerformNoArg(application, @"applicationIdentifier");
        if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0) {
            bundleIdentifier = FLEX4BetaPerformNoArg(application, @"bundleIdentifier");
        }
        if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0) {
            continue;
        }

        NSString *name = FLEX4BetaPerformNoArg(application, @"localizedName");
        if (![name isKindOfClass:NSString.class] || name.length == 0) {
            name = FLEX4BetaPerformNoArg(application, @"itemName");
        }
        if (![name isKindOfClass:NSString.class] || name.length == 0) {
            name = bundleIdentifier;
        }

        NSURL *bundleURL = FLEX4BetaPerformNoArg(application, @"bundleURL");
        NSString *bundlePath = [bundleURL respondsToSelector:@selector(path)] ? bundleURL.path : @"";
        if ([bundlePath containsString:@".appex"] || [bundlePath containsString:@"/PlugIns/"]) {
            continue;
        }

        [apps addObject:@{
            @"name": name,
            @"bundle": bundleIdentifier,
            @"path": bundlePath ?: @""
        }];
    }

    if (apps.count == 0 && FLEXingCurrentBundleIdentifier().length > 0) {
        [apps addObject:@{
            @"name": FLEXingDisplayNameForCurrentProcess(),
            @"bundle": FLEXingCurrentBundleIdentifier(),
            @"path": NSBundle.mainBundle.bundlePath ?: @""
        }];
    }

    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    return [apps sortedArrayUsingDescriptors:@[sort]];
}

- (void)applyFilter {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.filteredApps = self.allApps;
    } else {
        NSString *lower = trimmed.lowercaseString;
        NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
        for (NSDictionary *app in self.allApps) {
            NSString *name = [app[@"name"] isKindOfClass:NSString.class] ? app[@"name"] : @"";
            NSString *bundle = [app[@"bundle"] isKindOfClass:NSString.class] ? app[@"bundle"] : @"";
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", name, bundle].lowercaseString;
            if ([haystack containsString:lower]) {
                [matches addObject:app];
            }
        }
        self.filteredApps = matches;
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *forceOpen = FLEX4BetaForceOpenBundleIdentifiers();
    return [NSString stringWithFormat:@"Apps - %lu force open", (unsigned long)forceOpen.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Checked apps will open FLEX automatically when that app launches. This is for apps where gestures are blocked or unreliable.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FLEX4BetaForceOpenAppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FLEX4BetaForceOpenAppCell"];
    }

    NSDictionary *app = self.filteredApps[(NSUInteger)indexPath.row];
    NSString *name = [app[@"name"] isKindOfClass:NSString.class] ? app[@"name"] : @"";
    NSString *bundle = [app[@"bundle"] isKindOfClass:NSString.class] ? app[@"bundle"] : @"";
    BOOL forceOpen = FLEX4BetaIsForceOpenBundle(bundle);

    cell.textLabel.text = name.length ? name : bundle;
    cell.detailTextLabel.text = forceOpen ? [NSString stringWithFormat:@"%@ • Force Open On", bundle] : bundle;
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = forceOpen ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.textLabel.textColor = forceOpen ? UIColor.systemOrangeColor : UIColor.labelColor;
    cell.detailTextLabel.textColor = forceOpen ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = self.filteredApps[(NSUInteger)indexPath.row];
    NSString *bundle = [app[@"bundle"] isKindOfClass:NSString.class] ? app[@"bundle"] : @"";
    if (bundle.length == 0) {
        return;
    }

    BOOL next = !FLEX4BetaIsForceOpenBundle(bundle);
    FLEX4BetaSetForceOpenBundle(bundle, next);
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end

static void FLEX4BetaOpenForceOpenAppsMenu(__kindof UITableViewController *host) {
    FLEX4BetaForceOpenAppsViewController *forceOpenApps = [[FLEX4BetaForceOpenAppsViewController alloc] init];
    if (host.navigationController) {
        [host.navigationController pushViewController:forceOpenApps animated:YES];
    } else {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:forceOpenApps];
        [(UIViewController *)host presentViewController:navigationController animated:YES completion:nil];
    }
}

'''


def patch_tweak(text):
    text = insert_before(text, 'static void FLEXingOpenPanelMenu(__kindof UITableViewController *host) {\n', FORCE_OPEN_VIEW_CONTROLLER, 'force open apps view controller')

    old_register = '''    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"FLEX 4 Beta", action);
    flexingPanelEntryRegistered = YES;
    HBLogInfo(@"FLEXing: Registered FLEX 4 Beta panel row.");
'''
    new_register = '''    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"FLEX 4 Beta", action);

    FLEXingGlobalsRowAction forceOpenAction = ^(__kindof UITableViewController *host) {
        FLEX4BetaOpenForceOpenAppsMenu(host);
    };
    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Apps", forceOpenAction);

    flexingPanelEntryRegistered = YES;
    HBLogInfo(@"FLEXing: Registered FLEX 4 Beta and Force Open Apps panel rows.");
'''
    text = replace_once(text, old_register, new_register, 'force open custom row registration')

    old_ctor = '''    BOOL springBoardProcess = isSpringBoardProcess();
    currentBundleAllowsFLEX = springBoardProcess || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = FLEXingShouldAutoShowBundle(currentBundleIdentifier);
'''
    new_ctor = '''    BOOL springBoardProcess = isSpringBoardProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    currentBundleAllowsFLEX = springBoardProcess || currentBundleForceOpen || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = currentBundleForceOpen || FLEXingShouldAutoShowBundle(currentBundleIdentifier);
'''
    text = replace_once(text, old_ctor, new_ctor, 'force open launch state')

    old_initialized = '''            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
'''
    new_initialized = '''            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;

            if (currentBundleForceOpen && !didAutoShowExplorer && !isSpringBoardProcess()) {
                didAutoShowExplorer = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (manager && show) {
                        [manager performSelector:show];
                    }
                });
            }
'''
    text = replace_once(text, old_initialized, new_initialized, 'force open delayed app launch')
    return text


patch_text('Shared/FLEXingConfig.h', patch_header)
patch_text('Shared/FLEXingConfig.m', patch_config)
patch_text('Tweak.xm', patch_tweak)

print('Added FLEX 4 Beta Force Open Apps row and launch list' if changed else 'No changes needed')
