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
static BOOL flexOverlayHooksInitialized = NO;

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();

static void FLEXingInitializeFLEXOverlayHooks(void);

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

static void FLEXingSaveCurrentAppSettings(BOOL enabled, BOOL autoShow, NSString *note) {
    NSString *bundleIdentifier = currentBundleIdentifier.length ? currentBundleIdentifier : (NSBundle.mainBundle.bundleIdentifier ?: @"");
    FLEXingSaveSettingsForBundle(bundleIdentifier, enabled, autoShow, note ?: FLEXingAdjustmentsForBundle(bundleIdentifier));
    currentBundleAllowsFLEX = enabled;
    currentBundleShouldAutoShow = autoShow;
}

static void FLEXingShowResult(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void FLEXingInstallInlineSettingsButton(UIViewController *controller) {
    if (!controller || isFLEXingManagerProcess()) {
        return;
    }

    UIBarButtonItem *existing = controller.navigationItem.leftBarButtonItem;
    if ([existing.title isEqualToString:@"FLEXing"]) {
        return;
    }

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"FLEXing" style:UIBarButtonItemStylePlain target:(id)controller action:@selector(flexing_openInlineSettings:)];
    controller.navigationItem.leftBarButtonItem = item;
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

%group FLEXOverlayHooks

%hook FLEXExplorerViewController
- (void)viewDidLoad {
    %orig;
    FLEXingInstallInlineSettingsButton((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    FLEXingInstallInlineSettingsButton((UIViewController *)self);
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

%new(v@:@)
- (void)flexing_openInlineSettings:(id)sender {
    UIViewController *presenter = (UIViewController *)self;
    NSString *bundleIdentifier = currentBundleIdentifier.length ? currentBundleIdentifier : (NSBundle.mainBundle.bundleIdentifier ?: @"");
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);

    NSString *message = [NSString stringWithFormat:@"%@\n%@\n\nEnabled: %@\nAuto Show: %@\n\nSaved Adjustments:\n%@", FLEXingDisplayNameForCurrentProcess(), bundleIdentifier.length ? bundleIdentifier : @"No bundle identifier", enabled ? @"On" : @"Off", autoShow ? @"On" : @"Off", adjustments.length ? adjustments : @"None"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"FLEXing" message:message preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:(enabled ? @"Disable FLEX For This App" : @"Enable FLEX For This App") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL nextEnabled = !enabled;
        FLEXingSaveCurrentAppSettings(nextEnabled, autoShow, adjustments);
        FLEXingShowResult(presenter, @"Saved", nextEnabled ? @"FLEX will stay enabled for this app." : @"FLEX will be disabled for this app after restart.");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(autoShow ? @"Turn Auto Show Off" : @"Turn Auto Show On") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL nextAutoShow = !autoShow;
        FLEXingSaveCurrentAppSettings(enabled, nextAutoShow, adjustments);
        FLEXingShowResult(presenter, @"Saved", nextAutoShow ? @"FLEX will auto show next launch." : @"FLEX will not auto show next launch.");
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save Note / Adjustment Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *editor = [UIAlertController alertControllerWithTitle:@"Saved Adjustments" message:@"Stored for this app. Execution support can use this field later." preferredStyle:UIAlertControllerStyleAlert];
        [editor addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Adjustment text";
            textField.text = adjustments ?: @"";
        }];
        [editor addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [editor addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *saveAction) {
            NSString *text = editor.textFields.firstObject.text ?: @"";
            FLEXingSaveCurrentAppSettings(enabled, autoShow, text);
            FLEXingShowResult(presenter, @"Saved", @"Adjustment text saved for this app.");
        }]];
        [presenter presentViewController:editor animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = presenter.navigationItem.leftBarButtonItem;
    }

    [presenter presentViewController:alert animated:YES completion:nil];
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

%end

static void FLEXingInitializeFLEXOverlayHooks(void) {
    if (flexOverlayHooksInitialized) {
        return;
    }

    if (!NSClassFromString(@"FLEXExplorerViewController")) {
        HBLogInfo(@"FLEXing: FLEXExplorerViewController not available yet; overlay menu hook not installed.");
        return;
    }

    %init(FLEXOverlayHooks);
    flexOverlayHooksInitialized = YES;
    HBLogInfo(@"FLEXing: Installed FLEX overlay menu hooks.");
}

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
        FLEXingInitializeFLEXOverlayHooks();

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
