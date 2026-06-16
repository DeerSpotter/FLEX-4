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

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();

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
    return NSClassFromString(@"FLEXExplorerToolbar") != nil;
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

@interface FLEXingInlineSettingsViewController : UIViewController
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *autoShowSwitch;
@property (nonatomic, strong) UITextView *adjustmentsView;
@end

@implementation FLEXingInlineSettingsViewController

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _bundleIdentifier = bundleIdentifier.length > 0 ? [bundleIdentifier copy] : @"";
    }
    return self;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle switchControl:(UISwitch *)switchControl {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.secondarySystemBackgroundColor;
    row.layer.cornerRadius = 12.0;

    UILabel *titleLabel = [self labelWithText:title font:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] color:UIColor.labelColor];
    UILabel *subtitleLabel = [self labelWithText:subtitle font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] color:UIColor.secondaryLabelColor];

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 3.0;

    switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:textStack];
    [row addSubview:switchControl];

    [NSLayoutConstraint activateConstraints:@[
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-12.0],
        [switchControl.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:12.0],
        [switchControl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [switchControl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];

    return row;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"FLEXing";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeSettings)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(saveSettings)];

    BOOL enabled = FLEXingIsBundleEnabled(self.bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(self.bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(self.bundleIdentifier);

    self.enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enabledSwitch.on = enabled;
    self.autoShowSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.autoShowSwitch.on = autoShow;

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.layoutMargins = UIEdgeInsetsMake(18.0, 18.0, 18.0, 18.0);
    stack.layoutMarginsRelativeArrangement = YES;
    [scrollView addSubview:stack];

    UILabel *header = [self labelWithText:[NSString stringWithFormat:@"%@\n%@", FLEXingDisplayNameForCurrentProcess(), self.bundleIdentifier.length ? self.bundleIdentifier : @"No bundle identifier"] font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:UIColor.labelColor];
    [stack addArrangedSubview:header];

    UILabel *note = [self labelWithText:@"These settings are saved for this app and load the next time this app starts. FLEX stays available right here; the separate Home Screen manager is no longer required." font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] color:UIColor.secondaryLabelColor];
    [stack addArrangedSubview:note];

    [stack addArrangedSubview:[self rowWithTitle:@"Enable FLEX" subtitle:@"Turn FLEXing on or off for this app on next launch." switchControl:self.enabledSwitch]];
    [stack addArrangedSubview:[self rowWithTitle:@"Auto Show FLEX" subtitle:@"Open FLEX automatically when this app starts." switchControl:self.autoShowSwitch]];

    UILabel *adjustmentsLabel = [self labelWithText:@"Saved Adjustments" font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:UIColor.labelColor];
    [stack addArrangedSubview:adjustmentsLabel];

    self.adjustmentsView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.adjustmentsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.adjustmentsView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.adjustmentsView.textColor = UIColor.labelColor;
    self.adjustmentsView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.adjustmentsView.layer.cornerRadius = 12.0;
    self.adjustmentsView.textContainerInset = UIEdgeInsetsMake(12.0, 10.0, 12.0, 10.0);
    self.adjustmentsView.text = adjustments.length ? adjustments : @"";
    [self.adjustmentsView.heightAnchor constraintEqualToConstant:150.0].active = YES;
    [stack addArrangedSubview:self.adjustmentsView];

    UILabel *footer = [self labelWithText:@"For now this stores notes or future adjustment commands in the same plist FLEXing already reads. It does not need the crashing Home Screen app." font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] color:UIColor.secondaryLabelColor];
    [stack addArrangedSubview:footer];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor]
    ]];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveSettings {
    BOOL saved = FLEXingSaveSettingsForBundle(self.bundleIdentifier, self.enabledSwitch.on, self.autoShowSwitch.on, self.adjustmentsView.text ?: @"");
    currentBundleAllowsFLEX = self.enabledSwitch.on;
    currentBundleShouldAutoShow = self.autoShowSwitch.on;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:saved ? @"Saved" : @"Save Failed" message:saved ? @"FLEXing settings were saved for this app. Some changes apply next launch." : @"FLEXing could not write the preferences plist." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (saved) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

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
        HBLogInfo(@"FLEXing: Disabled for %@. Enable this app in FLEXing Manager and restart it.", currentBundleIdentifier);
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

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
        }
    }
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

%hook FLEXExplorerViewController
- (void)viewDidLoad {
    %orig;
    [(id)self flexing_installInlineSettingsButton];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    [(id)self flexing_installInlineSettingsButton];
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

%new(v@:@)
- (void)flexing_openInlineSettings:(id)sender {
    NSString *bundleIdentifier = currentBundleIdentifier.length ? currentBundleIdentifier : (NSBundle.mainBundle.bundleIdentifier ?: @"");
    FLEXingInlineSettingsViewController *settings = [[FLEXingInlineSettingsViewController alloc] initWithBundleIdentifier:bundleIdentifier];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settings];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    [(UIViewController *)self presentViewController:navigationController animated:YES completion:nil];
}

%new(v@:)
- (void)flexing_installInlineSettingsButton {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"FLEXing" style:UIBarButtonItemStylePlain target:self action:@selector(flexing_openInlineSettings:)];
    ((UIViewController *)self).navigationItem.leftBarButtonItem = item;
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
#if TARGET_OS_SIMULATOR
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isFLEXingManagerProcess() && initialized && manager && show) {
            [manager performSelector:show];
        }
    });
#endif
}
