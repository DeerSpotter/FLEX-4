//
//  FLEXingRootViewController.m
//  FLEXingManager
//

#import "FLEXingRootViewController.h"
#import "FLEXingAppSettingsViewController.h"
#import "../Shared/FLEXingConfig.h"
#import <sys/sysctl.h>

static NSString * const FLEXingAppNameKey = @"name";
static NSString * const FLEXingAppBundleIDKey = @"bundleIdentifier";
static NSString * const FLEXingAppPathKey = @"path";
static NSString * const FLEXingAppExecutableKey = @"executable";

@interface FLEXingRootViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *allApplications;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleApplications;
@property (nonatomic, strong) NSSet<NSString *> *runningBundleIdentifiers;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@end

@implementation FLEXingRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"FLEXing";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshApplications)];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Running", @"All"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;

    [self refreshApplications];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyCurrentFilter];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self applyCurrentFilter];
}

- (void)refreshApplications {
    NSArray<NSDictionary *> *applications = [self scanApplications];
    self.runningBundleIdentifiers = [self detectRunningBundleIdentifiersFromApplications:applications];
    self.allApplications = applications;
    [self applyCurrentFilter];
}

- (void)applyCurrentFilter {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        NSMutableArray *running = [NSMutableArray array];
        for (NSDictionary *application in self.allApplications) {
            NSString *bundleIdentifier = application[FLEXingAppBundleIDKey];
            if ([self.runningBundleIdentifiers containsObject:bundleIdentifier]) {
                [running addObject:application];
            }
        }
        self.visibleApplications = running;
    } else {
        self.visibleApplications = self.allApplications;
    }

    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)scanApplications {
    NSMutableArray<NSDictionary *> *applications = [NSMutableArray array];
    NSMutableSet<NSString *> *seenBundleIdentifiers = [NSMutableSet set];

    NSArray<NSDictionary *> *roots = @[
        @{@"path": @"/Applications", @"depth": @0},
        @{@"path": @"/var/jb/Applications", @"depth": @0},
        @{@"path": @"/var/containers/Bundle/Application", @"depth": @2},
        @{@"path": @"/private/var/containers/Bundle/Application", @"depth": @2},
        @{@"path": @"/var/jb/var/containers/Bundle/Application", @"depth": @2}
    ];

    for (NSDictionary *root in roots) {
        [self scanDirectory:root[@"path"] remainingDepth:[root[@"depth"] integerValue] applications:applications seenBundleIdentifiers:seenBundleIdentifiers];
    }

    [applications sortUsingComparator:^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
        NSString *firstName = first[FLEXingAppNameKey] ?: @"";
        NSString *secondName = second[FLEXingAppNameKey] ?: @"";
        return [firstName localizedCaseInsensitiveCompare:secondName];
    }];

    return applications;
}

- (void)scanDirectory:(NSString *)directory remainingDepth:(NSInteger)remainingDepth applications:(NSMutableArray<NSDictionary *> *)applications seenBundleIdentifiers:(NSMutableSet<NSString *> *)seenBundleIdentifiers {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:directory error:nil];
    if (children.count == 0) {
        return;
    }

    for (NSString *child in children) {
        NSString *path = [directory stringByAppendingPathComponent:child];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }

        if ([path.pathExtension.lowercaseString isEqualToString:@"app"]) {
            NSDictionary *application = [self applicationInfoAtPath:path];
            NSString *bundleIdentifier = application[FLEXingAppBundleIDKey];
            if (bundleIdentifier.length > 0 && ![seenBundleIdentifiers containsObject:bundleIdentifier]) {
                [seenBundleIdentifiers addObject:bundleIdentifier];
                [applications addObject:application];
            }
            continue;
        }

        if (remainingDepth > 0) {
            [self scanDirectory:path remainingDepth:remainingDepth - 1 applications:applications seenBundleIdentifiers:seenBundleIdentifiers];
        }
    }
}

- (NSDictionary *)applicationInfoAtPath:(NSString *)path {
    NSString *infoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];

    NSString *bundleIdentifier = info[@"CFBundleIdentifier"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    NSString *displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    NSString *executable = info[@"CFBundleExecutable"] ?: displayName;

    return @{
        FLEXingAppNameKey: displayName ?: @"Unknown",
        FLEXingAppBundleIDKey: bundleIdentifier ?: @"",
        FLEXingAppPathKey: path ?: @"",
        FLEXingAppExecutableKey: executable ?: @""
    };
}

- (NSSet<NSString *> *)detectRunningBundleIdentifiersFromApplications:(NSArray<NSDictionary *> *)applications {
    NSMutableSet<NSString *> *runningExecutables = [NSMutableSet set];

    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) {
        return [NSSet set];
    }

    struct kinfo_proc *processes = malloc(size);
    if (!processes) {
        return [NSSet set];
    }

    if (sysctl(mib, 4, processes, &size, NULL, 0) == 0) {
        NSUInteger processCount = size / sizeof(struct kinfo_proc);
        for (NSUInteger index = 0; index < processCount; index++) {
            NSString *processName = [NSString stringWithUTF8String:processes[index].kp_proc.p_comm];
            if (processName.length > 0) {
                [runningExecutables addObject:processName];
            }
        }
    }

    free(processes);

    NSMutableSet<NSString *> *runningBundleIdentifiers = [NSMutableSet set];
    for (NSDictionary *application in applications) {
        NSString *bundleIdentifier = application[FLEXingAppBundleIDKey];
        NSString *executable = application[FLEXingAppExecutableKey];
        if (bundleIdentifier.length == 0 || executable.length == 0) {
            continue;
        }

        for (NSString *runningExecutable in runningExecutables) {
            BOOL exactMatch = [runningExecutable isEqualToString:executable];
            BOOL truncatedProcessMatch = runningExecutable.length >= 15 && [executable hasPrefix:runningExecutable];
            BOOL truncatedExecutableMatch = executable.length >= 15 && [runningExecutable hasPrefix:executable];
            if (exactMatch || truncatedProcessMatch || truncatedExecutableMatch) {
                [runningBundleIdentifiers addObject:bundleIdentifier];
                break;
            }
        }
    }

    return runningBundleIdentifiers;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleApplications.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        return @"Running apps";
    }

    return @"All detected apps";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.segmentedControl.selectedSegmentIndex == 0 && self.visibleApplications.count == 0) {
        return @"No running apps were detected. Tap All to configure an app, then restart that app after enabling FLEX.";
    }

    return @"Tap an app to enable FLEX, choose whether FLEX opens automatically, and save notes or adjustment details for next launch.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
    }

    NSDictionary *application = self.visibleApplications[indexPath.row];

    NSString *bundleIdentifier = application[FLEXingAppBundleIDKey];
    BOOL running = [self.runningBundleIdentifiers containsObject:bundleIdentifier];
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);

    cell.textLabel.text = application[FLEXingAppNameKey];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@%@", bundleIdentifier, running ? @" • Running" : @"", enabled ? (autoShow ? @" • Auto Show" : @" • Enabled") : @""];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = enabled ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 62.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *application = self.visibleApplications[indexPath.row];
    NSString *bundleIdentifier = application[FLEXingAppBundleIDKey];
    BOOL running = [self.runningBundleIdentifiers containsObject:bundleIdentifier];
    FLEXingAppSettingsViewController *settings = [[FLEXingAppSettingsViewController alloc] initWithApplicationInfo:application running:running];
    [self.navigationController pushViewController:settings animated:YES];
}

@end
