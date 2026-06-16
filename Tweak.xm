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

static NSString *FLEXingSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSSet<NSString *> *FLEXingSelectedPatchIdentifiers(void) {
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    for (NSDictionary *patch in FLEXingPatchesForBundle(FLEXingCurrentBundleIdentifier())) {
        NSString *identifier = FLEXingSafeString(patch[@"Identifier"]);
        if (identifier.length > 0) {
            [identifiers addObject:identifier];
        }
    }
    return identifiers;
}

@interface FLEXingBrowserItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSDictionary *metadata;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle section:(NSString *)section kind:(NSString *)kind identifier:(NSString *)identifier metadata:(NSDictionary *)metadata;
@end

@implementation FLEXingBrowserItem
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle section:(NSString *)section kind:(NSString *)kind identifier:(NSString *)identifier metadata:(NSDictionary *)metadata {
    FLEXingBrowserItem *item = [FLEXingBrowserItem new];
    item.title = title ?: @"";
    item.subtitle = subtitle ?: @"";
    item.section = section ?: @"";
    item.kind = kind ?: @"";
    item.identifier = identifier ?: @"";
    item.metadata = [metadata isKindOfClass:NSDictionary.class] ? metadata : @{};
    return item;
}
@end

static NSDictionary *FLEXingPatchFromBrowserItem(FLEXingBrowserItem *item) {
    NSMutableDictionary *patch = [NSMutableDictionary dictionary];
    NSString *now = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    NSString *kind = item.kind ?: @"";
    NSDictionary *metadata = item.metadata ?: @{};

    patch[@"Identifier"] = item.identifier ?: @"";
    patch[@"Kind"] = kind;
    patch[@"UnitName"] = item.title ?: @"";
    patch[@"Title"] = item.title ?: @"";
    patch[@"Subtitle"] = item.subtitle ?: @"";
    patch[@"Enabled"] = @YES;
    patch[@"ReturnMode"] = @"pass-through";
    patch[@"ReturnType"] = FLEXingSafeString(metadata[@"ReturnType"]).length ? FLEXingSafeString(metadata[@"ReturnType"]) : @"id";
    patch[@"Created"] = now;
    patch[@"Updated"] = now;

    if ([kind isEqualToString:@"method"] || [kind isEqualToString:@"classMethod"]) {
        patch[@"TargetClass"] = FLEXingSafeString(metadata[@"Class"]);
        patch[@"TargetMethod"] = FLEXingSafeString(metadata[@"Selector"]);
        patch[@"MethodScope"] = [kind isEqualToString:@"classMethod"] ? @"class" : @"instance";
        patch[@"TypeEncoding"] = FLEXingSafeString(metadata[@"TypeEncoding"]);
    } else if ([kind isEqualToString:@"class"]) {
        patch[@"TargetClass"] = item.title ?: @"";
        patch[@"TargetMethod"] = @"";
        patch[@"MethodScope"] = @"class";
    } else if ([kind isEqualToString:@"library"]) {
        patch[@"Library"] = item.title ?: @"";
        patch[@"Path"] = FLEXingSafeString(metadata[@"Path"]);
    }

    return patch;
}

static NSString *FLEXingPatchDisplayTitle(NSDictionary *patch) {
    NSString *name = FLEXingSafeString(patch[@"UnitName"]);
    if (name.length > 0) {
        return name;
    }
    name = FLEXingSafeString(patch[@"TargetMethod"]);
    if (name.length > 0) {
        return name;
    }
    name = FLEXingSafeString(patch[@"TargetClass"]);
    if (name.length > 0) {
        return name;
    }
    name = FLEXingSafeString(patch[@"Library"]);
    return name.length ? name : @"Patch Unit";
}

static NSString *FLEXingPatchDisplaySubtitle(NSDictionary *patch) {
    NSString *kind = FLEXingSafeString(patch[@"Kind"]);
    if ([kind isEqualToString:@"method"] || [kind isEqualToString:@"classMethod"]) {
        NSString *scope = [kind isEqualToString:@"classMethod"] ? @"+" : @"-";
        return [NSString stringWithFormat:@"%@ %@\n%@ %@", FLEXingSafeString(patch[@"TargetClass"]), FLEXingSafeString(patch[@"TargetMethod"]), scope, FLEXingSafeString(patch[@"TypeEncoding"] )];
    }
    if ([kind isEqualToString:@"class"]) {
        return @"Obj-C class selection";
    }
    if ([kind isEqualToString:@"library"]) {
        return FLEXingSafeString(patch[@"Path"]);
    }
    return FLEXingSafeString(patch[@"Subtitle"]);
}

@interface FLEXingPatchEditorViewController : UITableViewController
@property (nonatomic, strong) NSMutableDictionary *patch;
@end

@implementation FLEXingPatchEditorViewController

- (instancetype)initWithPatch:(NSDictionary *)patch {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _patch = [patch mutableCopy] ?: [NSMutableDictionary dictionary];
        self.title = @"Edit Unit";
    }
    return self;
}

- (void)savePatch {
    self.patch[@"Updated"] = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    FLEXingUpsertPatchForBundle(FLEXingCurrentBundleIdentifier(), self.patch);
}

- (NSString *)titleForRow:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return @"Unit Name";
    }
    if (indexPath.section == 1) {
        return indexPath.row == 0 ? @"Target Class" : @"Target Method";
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) return @"Enabled";
        if (indexPath.row == 1) return @"Return Mode";
        return @"Return Type";
    }
    return indexPath.row == 0 ? @"Remove From Saved Patches" : @"";
}

- (NSString *)valueForRow:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return FLEXingPatchDisplayTitle(self.patch);
    }
    if (indexPath.section == 1) {
        return indexPath.row == 0 ? FLEXingSafeString(self.patch[@"TargetClass"]) : FLEXingSafeString(self.patch[@"TargetMethod"]);
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) return [self.patch[@"Enabled"] boolValue] ? @"On" : @"Off";
        if (indexPath.row == 1) return FLEXingSafeString(self.patch[@"ReturnMode"]).length ? FLEXingSafeString(self.patch[@"ReturnMode"]) : @"pass-through";
        return FLEXingSafeString(self.patch[@"ReturnType"]).length ? FLEXingSafeString(self.patch[@"ReturnType"]) : @"id";
    }
    return @"";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    if (section == 2) return 3;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Unit Name";
    if (section == 1) return @"Target";
    if (section == 2) return @"Patch Settings";
    return @"Actions";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FLEXingPatchEditorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }

    cell.textLabel.text = [self titleForRow:indexPath];
    cell.detailTextLabel.text = [self valueForRow:indexPath];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (indexPath.section == 3) {
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)presentTextEditorWithTitle:(NSString *)title key:(NSString *)key placeholder:(NSString *)placeholder {
    UIAlertController *editor = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [editor addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.text = FLEXingSafeString(self.patch[key]);
    }];
    [editor addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [editor addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.patch[key] = editor.textFields.firstObject.text ?: @"";
        [self savePatch];
        [self.tableView reloadData];
    }]];
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)presentReturnModePicker {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Return Mode" message:@"Saved only. Automatic execution will be wired separately." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *modes = @[@"pass-through", @"true", @"false", @"nil", @"custom"];
    for (NSString *mode in modes) {
        [picker addAction:[UIAlertAction actionWithTitle:mode style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.patch[@"ReturnMode"] = mode;
            [self savePatch];
            [self.tableView reloadData];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self presentTextEditorWithTitle:@"Unit Name" key:@"UnitName" placeholder:@"Patch name"];
        return;
    }

    if (indexPath.section == 1) {
        [self presentTextEditorWithTitle:(indexPath.row == 0 ? @"Target Class" : @"Target Method") key:(indexPath.row == 0 ? @"TargetClass" : @"TargetMethod") placeholder:@"Value"];
        return;
    }

    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            self.patch[@"Enabled"] = @(![self.patch[@"Enabled"] boolValue]);
            [self savePatch];
            [self.tableView reloadData];
        } else if (indexPath.row == 1) {
            [self presentReturnModePicker];
        } else {
            [self presentTextEditorWithTitle:@"Return Type" key:@"ReturnType" placeholder:@"id / BOOL / void"];
        }
        return;
    }

    if (indexPath.section == 3) {
        NSString *identifier = FLEXingSafeString(self.patch[@"Identifier"]);
        FLEXingRemovePatchForBundle(FLEXingCurrentBundleIdentifier(), identifier);
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end

@interface FLEXingPatchListViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *patches;
@end

@implementation FLEXingPatchListViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Saved Patches";
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.patches = FLEXingPatchesForBundle(FLEXingCurrentBundleIdentifier());
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.patches.count == 0 ? 1 : self.patches.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%@ Patches", FLEXingDisplayNameForCurrentProcess()];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FLEXingPatchListCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (self.patches.count == 0) {
        cell.textLabel.text = @"No Saved Patches";
        cell.detailTextLabel.text = @"Search classes or methods, then tap a result to add it here.";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    NSDictionary *patch = self.patches[(NSUInteger)indexPath.row];
    cell.textLabel.text = FLEXingPatchDisplayTitle(patch);
    cell.detailTextLabel.text = FLEXingPatchDisplaySubtitle(patch);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.patches.count == 0) {
        return;
    }

    NSDictionary *patch = self.patches[(NSUInteger)indexPath.row];
    FLEXingPatchEditorViewController *editor = [[FLEXingPatchEditorViewController alloc] initWithPatch:patch];
    [self.navigationController pushViewController:editor animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.patches.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.row < (NSInteger)self.patches.count) {
        NSDictionary *patch = self.patches[(NSUInteger)indexPath.row];
        FLEXingRemovePatchForBundle(FLEXingCurrentBundleIdentifier(), FLEXingSafeString(patch[@"Identifier"]));
        self.patches = FLEXingPatchesForBundle(FLEXingCurrentBundleIdentifier());
        [self.tableView reloadData];
    }
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
    self.searchBar.placeholder = @"Search class or method...";
    self.tableView.tableHeaderView = self.searchBar;

    [self reloadItems];
}

- (NSString *)identifierForKind:(NSString *)kind parts:(NSArray<NSString *> *)parts {
    NSMutableArray<NSString *> *clean = [NSMutableArray arrayWithObject:kind ?: @""];
    for (NSString *part in parts) {
        [clean addObject:part ?: @""];
    }
    return [clean componentsJoinedByString:@"|"];
}

- (void)addMethodItemsForClass:(Class)classObject className:(NSString *)className toArray:(NSMutableArray<FLEXingBrowserItem *> *)items {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(classObject, &methodCount);
    for (unsigned int index = 0; index < methodCount; index++) {
        SEL selector = method_getName(methods[index]);
        const char *typeEncoding = method_getTypeEncoding(methods[index]);
        NSString *selectorName = selector ? NSStringFromSelector(selector) : @"";
        NSString *encoding = typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"";
        if (selectorName.length == 0) {
            continue;
        }

        NSString *kind = class_isMetaClass(classObject) ? @"classMethod" : @"method";
        NSString *scope = class_isMetaClass(classObject) ? @"+" : @"-";
        NSString *identifier = [self identifierForKind:kind parts:@[className ?: @"", selectorName]];
        NSDictionary *metadata = @{
            @"Class": className ?: @"",
            @"Selector": selectorName,
            @"TypeEncoding": encoding,
            @"ReturnType": @"id"
        };
        NSString *subtitle = [NSString stringWithFormat:@"%@ %@\n%@", scope, className ?: @"", encoding];
        [items addObject:[FLEXingBrowserItem itemWithTitle:selectorName subtitle:subtitle section:@"Obj-C Methods" kind:kind identifier:identifier metadata:metadata]];
    }
    if (methods) {
        free(methods);
    }
}

- (void)reloadItems {
    NSMutableArray<FLEXingBrowserItem *> *items = [NSMutableArray array];
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);
    NSUInteger patchCount = FLEXingPatchesForBundle(bundleIdentifier).count;

    [items addObject:[FLEXingBrowserItem itemWithTitle:FLEXingDisplayNameForCurrentProcess() subtitle:bundleIdentifier.length ? bundleIdentifier : @"No bundle identifier" section:@"Current App" kind:@"info" identifier:@"currentApp" metadata:@{}]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:[NSString stringWithFormat:@"Saved Patches (%lu)", (unsigned long)patchCount] subtitle:@"Selected classes and methods appear here for this app" section:@"Patches" kind:@"savedPatches" identifier:@"savedPatches" metadata:@{}]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:(enabled ? @"Enabled: On" : @"Enabled: Off") subtitle:@"Tap to toggle FLEX for this app on next launch" section:@"Settings" kind:@"toggleEnabled" identifier:@"toggleEnabled" metadata:@{}]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:(autoShow ? @"Auto Show: On" : @"Auto Show: Off") subtitle:@"Tap to toggle automatic opening on next launch" section:@"Settings" kind:@"toggleAutoShow" identifier:@"toggleAutoShow" metadata:@{}]];
    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments" identifier:@"editAdjustments" metadata:@{}]];

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
        NSString *identifier = [self identifierForKind:@"library" parts:@[name ?: @"", path ?: @""]];
        [items addObject:[FLEXingBrowserItem itemWithTitle:name subtitle:path section:@"Libraries" kind:@"library" identifier:identifier metadata:@{@"Path": path ?: @""}]];
    }

    int classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        Class *classes = (Class *)calloc((NSUInteger)classCount, sizeof(Class));
        int actualCount = objc_getClassList(classes, classCount);
        NSMutableArray<NSString *> *classNames = [NSMutableArray arrayWithCapacity:(NSUInteger)actualCount];
        NSMutableDictionary<NSString *, id> *classLookup = [NSMutableDictionary dictionary];

        for (int index = 0; index < actualCount; index++) {
            const char *name = class_getName(classes[index]);
            if (name) {
                NSString *className = [NSString stringWithUTF8String:name];
                [classNames addObject:className];
                classLookup[className] = classes[index];
            }
        }

        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *className in classNames) {
            NSString *identifier = [self identifierForKind:@"class" parts:@[className]];
            [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class" identifier:identifier metadata:@{@"Class": className}]];

            Class cls = (__bridge Class)classLookup[className];
            [self addMethodItemsForClass:cls className:className toArray:items];
            [self addMethodItemsForClass:object_getClass(cls) className:className toArray:items];
        }

        free(classes);
    }

    self.allItems = items;
    [self applyFilter];
}

- (NSArray<FLEXingBrowserItem *> *)visibleItemsForQuery:(NSString *)trimmed {
    NSSet<NSString *> *selectedIdentifiers = FLEXingSelectedPatchIdentifiers();

    if (trimmed.length == 0) {
        NSMutableArray<FLEXingBrowserItem *> *defaultItems = [NSMutableArray array];
        for (FLEXingBrowserItem *item in self.allItems) {
            if ([item.kind isEqualToString:@"method"] || [item.kind isEqualToString:@"classMethod"]) {
                continue;
            }
            [defaultItems addObject:item];
        }
        return defaultItems;
    }

    NSString *lower = trimmed.lowercaseString;
    NSMutableArray<FLEXingBrowserItem *> *matches = [NSMutableArray array];
    for (FLEXingBrowserItem *item in self.allItems) {
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @"", item.identifier ?: @""];
        if ([haystack.lowercaseString containsString:lower] || [selectedIdentifiers containsObject:item.identifier]) {
            [matches addObject:item];
        }
    }
    return matches;
}

- (void)applyFilter {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.filteredItems = [self visibleItemsForQuery:trimmed];
    [self.tableView reloadData];
}

- (NSMutableOrderedSet<NSString *> *)visibleSections {
    NSMutableOrderedSet<NSString *> *sections = [NSMutableOrderedSet orderedSet];
    for (FLEXingBrowserItem *item in self.filteredItems) {
        [sections addObject:item.section ?: @""];
    }
    return sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self visibleSections].count;
}

- (NSString *)sectionTitleAtIndex:(NSInteger)sectionIndex {
    NSMutableOrderedSet<NSString *> *sections = [self visibleSections];
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
    static NSString *cellIdentifier = @"FLEXingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];
    NSSet<NSString *> *selectedIdentifiers = FLEXingSelectedPatchIdentifiers();
    BOOL selectablePatchItem = [@[@"class", @"method", @"classMethod", @"library"] containsObject:item.kind];

    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = item.subtitle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (selectablePatchItem) {
        cell.accessoryType = [selectedIdentifiers containsObject:item.identifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if ([item.kind isEqualToString:@"savedPatches"] || [item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"editAdjustments"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)showPatchSavedToastForItem:(FLEXingBrowserItem *)item added:(BOOL)added {
    NSString *message = added ? @"Added to Saved Patches" : @"Removed from Saved Patches";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title message:message preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);

    if ([item.kind isEqualToString:@"savedPatches"]) {
        FLEXingPatchListViewController *patches = [[FLEXingPatchListViewController alloc] init];
        [self.navigationController pushViewController:patches animated:YES];
        return;
    }

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

    if ([@[@"class", @"method", @"classMethod", @"library"] containsObject:item.kind]) {
        NSSet<NSString *> *selectedIdentifiers = FLEXingSelectedPatchIdentifiers();
        BOOL wasSelected = [selectedIdentifiers containsObject:item.identifier];
        if (wasSelected) {
            FLEXingRemovePatchForBundle(bundleIdentifier, item.identifier);
        } else {
            FLEXingUpsertPatchForBundle(bundleIdentifier, FLEXingPatchFromBrowserItem(item));
        }
        [self reloadItems];
        [self showPatchSavedToastForItem:item added:!wasSelected];
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
