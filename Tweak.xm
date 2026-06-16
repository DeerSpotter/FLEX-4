//
//  Tweak.m
//  FLEXing
//
//  Created by Tanner Bennett on 2016-07-11
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import "Interfaces.h"
#import "Shared/FLEXingConfig.h"
#import <rootless.h>
#import <HBLog.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

#if TARGET_OS_SIMULATOR
#import <UIKit/UIFunctions.h>
#define realPath(path) [UISystemRootDirectory() stringByAppendingPathComponent:path]
#else
#define realPath(path) path
#endif

BOOL initialized = NO;
id manager = nil;
SEL show = nil;
BOOL didAutoShowExplorer = NO;
NSString *currentBundleIdentifier = nil;
BOOL currentBundleAllowsFLEX = NO;
BOOL currentBundleShouldAutoShow = NO;

static NSHashTable *windowsWithGestures = nil;
static BOOL flexingPanelEntryRegistered = NO;

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();

typedef void (^FLEXingGlobalsRowAction)(__kindof UITableViewController *host);

inline BOOL isFLEXingManagerProcess() {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.github.devnoname120.flexing.manager"];
}

/// This isn't perfect, but works for most cases as intended
inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
    HBLogInfo(@"FLEXing: executablePath: %@", executablePath);

    return [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"] ||
        [executablePath hasPrefix:realPath(@"/Applications")] ||
#if TARGET_OS_SIMULATOR
        [executablePath containsString:@"/data/Containers/Bundle/Application"];
#else
        [executablePath hasPrefix:@"/var/containers/Bundle/Application"] ||
        [executablePath hasPrefix:@"/var/jb/Applications"] ||
        [executablePath containsString:@"/procursus/Applications"];
#endif
}

inline bool isSnapchatApp() {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.toyopagroup.picaboo"];
}

inline BOOL flexAlreadyLoaded() {
    return NSClassFromString(@"FLEXExplorerToolbar") != nil || NSClassFromString(@"FLEXExplorerViewController") != nil;
}

inline BOOL isSpringBoardProcess() {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

inline void enableNetworkMonitoringIfPossible() {
    if (!manager || !FLEXingNetworkMonitoringEnabled()) {
        return;
    }

    // FLEX exposes this as the setter for the `networkDebuggingEnabled` property
    // (from FLEXManager+Networking), but keep a fallback for older/variant builds.
    SEL selectors[] = {
        @selector(setNetworkDebuggingEnabled:),
        NSSelectorFromString(@"enableNetworkDebugging")
    };

    for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(SEL); i++) {
        SEL selector = selectors[i];
        if ([manager respondsToSelector:selector]) {
            if (selector == @selector(setNetworkDebuggingEnabled:)) {
                ((void (*)(id, SEL, BOOL))[manager methodForSelector:selector])(manager, selector, YES);
            } else {
                ((void (*)(id, SEL))[manager methodForSelector:selector])(manager, selector);
            }
            HBLogInfo(@"FLEXing: Enabled network monitoring via %@", NSStringFromSelector(selector));
            break;
        }
    }
}

static NSString *FLEXingDisplayNameForCurrentProcess(void) {
    NSString *displayName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (displayName.length == 0) {
        displayName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    }
    if (displayName.length == 0) {
        displayName = currentBundleIdentifier ?: @"Current App";
    }
    return displayName;
}

static NSString *FLEXingCurrentBundleIdentifier(void) {
    return currentBundleIdentifier.length ? currentBundleIdentifier : (NSBundle.mainBundle.bundleIdentifier ?: @"");
}

static BOOL FLEXingSaveCurrentAppSettings(BOOL enabled, BOOL autoShow, NSString *note) {
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL saved = FLEXingSaveSettingsForBundle(bundleIdentifier, enabled, autoShow, note ?: FLEXingAdjustmentsForBundle(bundleIdentifier));
    currentBundleAllowsFLEX = enabled;
    currentBundleShouldAutoShow = autoShow;
    return saved;
}

@interface FLEXingBrowserItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, copy) NSString *kind;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle section:(NSString *)section kind:(NSString *)kind;
@end

@implementation FLEXingBrowserItem
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle section:(NSString *)section kind:(NSString *)kind {
    FLEXingBrowserItem *item = [FLEXingBrowserItem new];
    item.title = title ?: @"";
    item.subtitle = subtitle ?: @"";
    item.section = section ?: @"";
    item.kind = kind ?: @"";
    return item;
}
@end

@interface FLEXingBrowserViewController : UITableViewController <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *allItems;
@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *filteredItems;
@property (nonatomic, copy) NSString *query;
@end

@implementation FLEXingBrowserViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"FLEXing";
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
    self.searchBar.placeholder = @"Search class, library, setting...";
    self.tableView.tableHeaderView = self.searchBar;

    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"FLEXingCell"];
    [self reloadItems];
}

- (void)reloadItems {
    NSMutableArray<FLEXingBrowserItem *> *items = [NSMutableArray array];
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);

    [items addObject:[FLEXingBrowserItem itemWithTitle:FLEXingDisplayNameForCurrentProcess() subtitle:bundleIdentifier.length ? bundleIdentifier : @"No bundle identifier" section:@"Current App" kind:@"info"]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:(enabled ? @"Enabled: On" : @"Enabled: Off") subtitle:@"Tap to toggle FLEX for this app on next launch" section:@"Settings" kind:@"toggleEnabled"]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:(autoShow ? @"Auto Show: On" : @"Auto Show: Off") subtitle:@"Tap to toggle automatic opening on next launch" section:@"Settings" kind:@"toggleAutoShow"]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments"]];

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String:imageName];
        NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
        if (name.length == 0) {
            name = path.lastPathComponent;
        }
        [items addObject:[FLEXingBrowserItem itemWithTitle:name subtitle:path section:@"Libraries" kind:@"library"]];
    }

    int classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        Class *classes = (Class *)calloc((NSUInteger)classCount, sizeof(Class));
        int actualCount = objc_getClassList(classes, classCount);
        NSMutableArray<NSString *> *classNames = [NSMutableArray arrayWithCapacity:(NSUInteger)actualCount];
        for (int index = 0; index < actualCount; index++) {
            const char *name = class_getName(classes[index]);
            if (name) {
                [classNames addObject:[NSString stringWithUTF8String:name]];
            }
        }
        free(classes);

        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *className in classNames) {
            [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class"]];
        }
    }

    self.allItems = items;
    [self applyFilter];
}

- (void)applyFilter {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.filteredItems = self.allItems;
    } else {
        NSString *lower = trimmed.lowercaseString;
        NSMutableArray<FLEXingBrowserItem *> *matches = [NSMutableArray array];
        for (FLEXingBrowserItem *item in self.allItems) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @""];
            if ([haystack.lowercaseString containsString:lower]) {
                [matches addObject:item];
            }
        }
        self.filteredItems = matches;
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSMutableOrderedSet<NSString *> *sections = [NSMutableOrderedSet orderedSet];
    for (FLEXingBrowserItem *item in self.filteredItems) {
        [sections addObject:item.section ?: @""];
    }
    return sections.count;
}

- (NSString *)sectionTitleAtIndex:(NSInteger)sectionIndex {
    NSMutableOrderedSet<NSString *> *sections = [NSMutableOrderedSet orderedSet];
    for (FLEXingBrowserItem *item in self.filteredItems) {
        [sections addObject:item.section ?: @""];
    }
    if (sectionIndex < 0 || sectionIndex >= (NSInteger)sections.count) {
        return @"";
    }
    return sections[(NSUInteger)sectionIndex];
}

- (NSArray<FLEXingBrowserItem *> *)itemsForSection:(NSInteger)sectionIndex {
    NSString *section = [self sectionTitleAtIndex:sectionIndex];
    NSMutableArray<FLEXingBrowserItem *> *items = [NSMutableArray array];
    for (FLEXingBrowserItem *item in self.filteredItems) {
        if ([item.section isEqualToString:section]) {
            [items addObject:item];
        }
    }
    return items;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self itemsForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self sectionTitleAtIndex:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FLEXingCell" forIndexPath:indexPath];
    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];

    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = ([item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"editAdjustments"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    if (item.subtitle.length > 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@\n%@", item.title, item.subtitle];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);

    if ([item.kind isEqualToString:@"toggleEnabled"]) {
        BOOL nextEnabled = !enabled;
        FLEXingSaveCurrentAppSettings(nextEnabled, autoShow, adjustments);
        [self reloadItems];
        return;
    }

    if ([item.kind isEqualToString:@"toggleAutoShow"]) {
        BOOL nextAutoShow = !autoShow;
        FLEXingSaveCurrentAppSettings(enabled, nextAutoShow, adjustments);
        [self reloadItems];
        return;
    }

    if ([item.kind isEqualToString:@"editAdjustments"]) {
        UIAlertController *editor = [UIAlertController alertControllerWithTitle:@"Saved Adjustments" message:@"Stored for this app. Execution support can use this field later." preferredStyle:UIAlertControllerStyleAlert];
        [editor addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Adjustment text";
            textField.text = adjustments ?: @"";
        }];
        [editor addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [editor addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *saveAction) {
            NSString *text = editor.textFields.firstObject.text ?: @"";
            FLEXingSaveCurrentAppSettings(enabled, autoShow, text);
            [self reloadItems];
        }]];
        [self presentViewController:editor animated:YES completion:nil];
        return;
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end

static void FLEXingOpenPanelMenu(__kindof UITableViewController *host) {
    FLEXingBrowserViewController *browser = [[FLEXingBrowserViewController alloc] init];
    if (host.navigationController) {
        [host.navigationController pushViewController:browser animated:YES];
    } else {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:browser];
        [(UIViewController *)host presentViewController:navigationController animated:YES completion:nil];
    }
}

static void FLEXingRegisterPanelEntryIfPossible(void) {
    if (flexingPanelEntryRegistered || !manager) {
        return;
    }

    SEL registerSelector = NSSelectorFromString(@"registerGlobalEntryWithName:action:");
    if (![manager respondsToSelector:registerSelector]) {
        HBLogInfo(@"FLEXing: FLEX manager does not support panel entry registration.");
        return;
    }

    FLEXingGlobalsRowAction action = ^(__kindof UITableViewController *host) {
        FLEXingOpenPanelMenu(host);
    };

    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"FLEXing", action);
    flexingPanelEntryRegistered = YES;
    HBLogInfo(@"FLEXing: Registered FLEXing panel row.");
}

%hook UIWindow
- (BOOL)_shouldCreateContextAsSecure {
    if (isFLEXingManagerProcess()) {
        return %orig;
    }
    return (initialized && FLXWindowClass && [self isKindOfClass:FLXWindowClass()]) ? YES : %orig;
}

- (void)becomeKeyWindow {
    %orig;

    if (isFLEXingManagerProcess() || !initialized) {
        return;
    }

    BOOL needsGesture = ![windowsWithGestures containsObject:self];
    BOOL isFLEXWindow = FLXWindowClass && [self isKindOfClass:FLXWindowClass()];
    BOOL isStatusBar  = [self isKindOfClass:[UIStatusBarWindow class]];
    BOOL shouldAutoShow = !didAutoShowExplorer && !isSpringBoardProcess() && currentBundleAllowsFLEX && currentBundleShouldAutoShow;

    if (shouldAutoShow && !isFLEXWindow && manager && show) {
        didAutoShowExplorer = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [manager performSelector:show];
        });
    }

    if (needsGesture && !isFLEXWindow && !isStatusBar && manager && show) {
        [windowsWithGestures addObject:self];

        // Add 3-finger long-press gesture for apps without a status bar
        UILongPressGestureRecognizer *tap = [[UILongPressGestureRecognizer alloc] initWithTarget:manager action:show];
        tap.minimumPressDuration = .5;
        tap.numberOfTouchesRequired = 3;

        [self addGestureRecognizer:tap];
    }
}
%end

%hook UIStatusBarWindow
- (id)initWithFrame:(CGRect)frame {
    self = %orig;
    
    if (!isFLEXingManagerProcess() && initialized && manager && show) {
        // Add long-press gesture to status bar
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:manager action:show]];
    }
    
    return self;
}
%end

%hook _UISheetPresentationController
- (id)initWithPresentedViewController:(id)present presentingViewController:(id)presenter {
    self = %orig;
    if (!isFLEXingManagerProcess() && [present isKindOfClass:%c(FLEXNavigationController)]) {
        // Enable half height sheet
        if ([self respondsToSelector:@selector(_presentsAtStandardHalfHeight)]) {
            self._presentsAtStandardHalfHeight = YES;
        } else {
            self._detents = @[[%c(_UISheetDetent) _mediumDetent], [%c(_UISheetDetent) _largeDetent]];
        }
        // Start fullscreen, 0 for half height
        self._indexOfCurrentDetent = 1;
        // Don't expand unless dragged up
        self._prefersScrollingExpandsToLargerDetentWhenScrolledToEdge = NO;
        // Don't dim first detent
        self._indexOfLastUndimmedDetent = 1;
    }
    
    return self;
}
%end

%hook FLEXManager
%new(@@:@)
+ (NSString *)dlopen:(NSString *)path {
    if (!dlopen(path.UTF8String, RTLD_NOW)) {
        return @(dlerror());
    }
    
    return @"OK";
}
%end

%ctor {
    currentBundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";

    if (isFLEXingManagerProcess()) {
        HBLogInfo(@"FLEXing: Skipping manager app process.");
        return;
    }

    BOOL springBoardProcess = isSpringBoardProcess();
    currentBundleAllowsFLEX = springBoardProcess || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = FLEXingShouldAutoShowBundle(currentBundleIdentifier);

    if (!currentBundleAllowsFLEX && !springBoardProcess) {
        HBLogInfo(@"FLEXing: Disabled for %@. Enable this app in FLEXing and restart it.", currentBundleIdentifier);
        return;
    }

#if TARGET_OS_SIMULATOR
    NSString *standardPath = realPath(@"/Library/MobileSubstrate/DynamicLibraries/libFLEX.dylib");
    NSString *reflexPath =   realPath(@"/Library/MobileSubstrate/DynamicLibraries/libreflex.dylib");
#else
    NSString *standardPath = ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries/libFLEX.dylib");
    NSString *reflexPath =   ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries/libreflex.dylib");
#endif
    NSFileManager *disk = NSFileManager.defaultManager;
    NSString *libflex = nil;
    NSString *libreflex = nil;
    void *handle = nil;

    if ([disk fileExistsAtPath:standardPath]) {
        libflex = standardPath;
        if ([disk fileExistsAtPath:reflexPath]) {
            libreflex = reflexPath;
        }
    } else {
        // Check if libFLEX resides in the same folder as me
        NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
        NSString *whereIam = executablePath.stringByDeletingLastPathComponent;
        NSString *possibleFlexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libFLEX.dylib"];
        NSString *possibleReflexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libreflex.dylib"];
        if ([disk fileExistsAtPath:possibleFlexPath]) {
            libflex = possibleFlexPath;
            if ([disk fileExistsAtPath:possibleReflexPath]) {
                libreflex = possibleReflexPath;
            }
        } else {
            // libFLEX not found
            // ...
        }
    }

    if (libflex) {
        // Hey Snapchat / Snap Inc devs,
        // This is so users don't get their accounts locked.
        if (isLikelyUIProcess() && !isSnapchatApp() && currentBundleAllowsFLEX) {
            handle = dlopen(libflex.UTF8String, RTLD_LAZY);
            
            if (libreflex) {
                dlopen(libreflex.UTF8String, RTLD_NOW);
            }

            HBLogInfo(@"FLEXing: Initialized for %@", currentBundleIdentifier);

            NSString *savedAdjustments = FLEXingAdjustmentsForBundle(currentBundleIdentifier);
            if (savedAdjustments.length > 0) {
                HBLogInfo(@"FLEXing: Saved adjustments for %@: %@", currentBundleIdentifier, savedAdjustments);
            }
        }
    }

    if (handle || flexAlreadyLoaded()) {
        // FLEXing.dylib itself does not hard-link against libFLEX.dylib,
        // instead libFLEX.dylib provides getters for the relevant class
        // objects so that it can be updated independently of THIS tweak.
        FLXGetManager = (id(*)())dlsym(handle, "FLXGetManager");
        FLXRevealSEL = (SEL(*)())dlsym(handle, "FLXRevealSEL");
        FLXWindowClass = (Class(*)())dlsym(handle, "FLXWindowClass");

        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
            enableNetworkMonitoringIfPossible();
            FLEXingRegisterPanelEntryIfPossible();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
        }
    }
}

%ctor {
#if TARGET_OS_SIMULATOR
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isFLEXingManagerProcess() && initialized && manager && show) {
            [manager performSelector:show];
        }
    });
#endif
}
