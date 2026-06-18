#!/usr/bin/env python3
from pathlib import Path

changed = False

# Option A keeps the existing FLEX 4 Beta rootless package and libFLEX.dylib loader,
# but improves reach by using the rootless-safe UIKit/UIKitCore framework filter,
# then a runtime guard that only continues inside real app processes.
plist = Path('FLEXing.plist')
plist_text = '''{
    Filter =     {
        Bundles =         (
            "com.apple.UIKit",
            "com.apple.UIKitCore"
        );
    };
}
'''
if plist.read_text() != plist_text:
    plist.write_text(plist_text)
    changed = True
    print('Patched FLEXing.plist to rootless-safe UIKit/UIKitCore filter')
else:
    print('FLEXing.plist already uses rootless-safe UIKit/UIKitCore filter')

tweak = Path('Tweak.xm')
text = tweak.read_text()

marker = 'FLEX4BetaAutoFlexOptionAMarker'
if marker in text:
    print('AutoFLEX Option A runtime guard already present')
else:
    old_guard = '''// FLEX4BetaAppInjectionPathFixMarker
// Keep daemon injection blocked, but recognize modern rootless/user app paths.
static BOOL FLEX4BetaPathLooksLikeAppBundle(NSString *path) {
    if (path.length == 0) {
        return NO;
    }

    BOOL hasAppComponent = [path hasSuffix:@".app"] || [path containsString:@".app/"];
    if (!hasAppComponent) {
        return NO;
    }

    NSArray<NSString *> *allowedPrefixes = @[
        realPath(@"/Applications"),
        @"/Applications",
        @"/System/Applications",
        @"/System/Library/CoreServices",
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
        @"/var/mobile/Containers/Bundle/Application",
        @"/private/var/mobile/Containers/Bundle/Application",
        @"/var/jb/Applications",
        @"/private/var/jb/Applications",
        @"/procursus/Applications"
    ];

    for (NSString *prefix in allowedPrefixes) {
        if (prefix.length > 0 && [path hasPrefix:prefix]) {
            return YES;
        }
    }

    // App Store paths can vary by jailbreak/runtime normalization.
    return [path containsString:@"/Bundle/Application/"];
}

inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments.firstObject ?: @"";
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    HBLogInfo(@"FLEXing: executablePath: %@ bundlePath: %@ bundleIdentifier: %@", executablePath, bundlePath, bundleIdentifier);

    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"] || [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"]) {
        return YES;
    }

#if TARGET_OS_SIMULATOR
    if ([executablePath containsString:@"/data/Containers/Bundle/Application"] || [bundlePath containsString:@"/data/Containers/Bundle/Application"]) {
        return YES;
    }
#endif

    return FLEX4BetaPathLooksLikeAppBundle(executablePath) || FLEX4BetaPathLooksLikeAppBundle(bundlePath);
}
'''

    new_guard = '''// FLEX4BetaAppInjectionPathFixMarker
// FLEX4BetaAutoFlexOptionAMarker
// AutoFLEX-style runtime guard: allow the framework filter to reach UIKit apps,
// then stop immediately unless the process looks like a foreground app bundle.
static BOOL FLEX4BetaPathIsAppExtension(NSString *path) {
    return path.length > 0 && ([path containsString:@".appex/"] || [path hasSuffix:@".appex"] || [path containsString:@"/PlugIns/"]);
}

static BOOL FLEX4BetaPathLooksLikeAppBundle(NSString *path) {
    if (path.length == 0 || FLEX4BetaPathIsAppExtension(path)) {
        return NO;
    }

    if ([path hasSuffix:@".app"] || [path containsString:@".app/"]) {
        return YES;
    }

    NSArray<NSString *> *appContainerFragments = @[
        @"/Bundle/Application/",
        @"/Containers/Bundle/Application/",
        @"/var/containers/Bundle/Application/",
        @"/private/var/containers/Bundle/Application/",
        @"/var/mobile/Containers/Bundle/Application/",
        @"/private/var/mobile/Containers/Bundle/Application/"
    ];

    for (NSString *fragment in appContainerFragments) {
        if ([path containsString:fragment]) {
            return YES;
        }
    }

    return NO;
}

static BOOL FLEX4BetaBundleIdentifierLooksUnsafe(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return YES;
    }

    NSArray<NSString *> *unsafePrefixes = @[
        @"com.apple.WebKit.",
        @"com.apple.runningboard",
        @"com.apple.backboard",
        @"com.apple.frontboard.systemappservices",
        @"com.apple.mobileactivationd",
        @"com.apple.mobileassetd",
        @"com.apple.networkextension",
        @"com.apple.security",
        @"com.apple.xpc."
    ];

    for (NSString *prefix in unsafePrefixes) {
        if ([bundleIdentifier hasPrefix:prefix]) {
            return YES;
        }
    }

    return NO;
}

inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments.firstObject ?: @"";
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSString *executableName = NSProcessInfo.processInfo.processName ?: @"";
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    HBLogInfo(@"FLEXing: executablePath: %@ bundlePath: %@ bundleIdentifier: %@ processName: %@", executablePath, bundlePath, bundleIdentifier, executableName);

    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"] || [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"]) {
        return YES;
    }

    if (FLEX4BetaBundleIdentifierLooksUnsafe(bundleIdentifier)) {
        return NO;
    }

    if (FLEX4BetaPathIsAppExtension(executablePath) || FLEX4BetaPathIsAppExtension(bundlePath)) {
        return NO;
    }

#if TARGET_OS_SIMULATOR
    if ([executablePath containsString:@"/data/Containers/Bundle/Application"] || [bundlePath containsString:@"/data/Containers/Bundle/Application"]) {
        return YES;
    }
#endif

    if (FLEX4BetaPathLooksLikeAppBundle(executablePath) || FLEX4BetaPathLooksLikeAppBundle(bundlePath)) {
        return YES;
    }

    // Last safe fallback for unusual app launchers: require a bundle id and UIApplication runtime.
    // This helps app-like processes whose paths are normalized differently, but keeps daemons out.
    Class applicationClass = NSClassFromString(@"UIApplication");
    if (applicationClass && bundleIdentifier.length > 0 && ![bundleIdentifier hasPrefix:@"com.apple."]) {
        return YES;
    }

    return NO;
}
'''

    if old_guard not in text:
        raise SystemExit('Could not find FLEX 4 Beta app injection guard block to upgrade')
    text = text.replace(old_guard, new_guard, 1)
    changed = True
    print('Patched runtime guard for AutoFLEX Option A app process handling')

old_ctor = '''    BOOL springBoardProcess = isSpringBoardProcess();
    currentBundleAllowsFLEX = springBoardProcess || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = FLEXingShouldAutoShowBundle(currentBundleIdentifier);

    if (!currentBundleAllowsFLEX && !springBoardProcess) {
        HBLogInfo(@"FLEXing: Disabled for %@. Enable this app in FLEXing and restart it.", currentBundleIdentifier);
        return;
    }
'''
new_ctor = '''    BOOL likelyUIProcess = isLikelyUIProcess();
    if (!likelyUIProcess) {
        HBLogInfo(@"FLEXing: Skipping non-app process %@.", currentBundleIdentifier.length ? currentBundleIdentifier : NSProcessInfo.processInfo.processName);
        return;
    }

    BOOL springBoardProcess = isSpringBoardProcess();
    currentBundleAllowsFLEX = springBoardProcess || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = FLEXingShouldAutoShowBundle(currentBundleIdentifier);

    if (!currentBundleAllowsFLEX && !springBoardProcess) {
        HBLogInfo(@"FLEXing: Disabled for %@. Enable this app in FLEXing and restart it.", currentBundleIdentifier);
        return;
    }
'''
if new_ctor in text:
    print('Early non-app process skip already present')
elif old_ctor in text:
    text = text.replace(old_ctor, new_ctor, 1)
    changed = True
    print('Patched ctor to skip non-app processes before loading prefs/libFLEX')
else:
    raise SystemExit('Could not find ctor process setup block to patch')

old_dlopen_gate = '        if (isLikelyUIProcess() && !isSnapchatApp() && currentBundleAllowsFLEX) {'
new_dlopen_gate = '        if (likelyUIProcess && !isSnapchatApp() && currentBundleAllowsFLEX) {'
if new_dlopen_gate in text:
    print('libFLEX load gate already uses cached likelyUIProcess')
elif old_dlopen_gate in text:
    text = text.replace(old_dlopen_gate, new_dlopen_gate, 1)
    changed = True
    print('Patched libFLEX load gate to reuse early app-process decision')
else:
    raise SystemExit('Could not find libFLEX load gate to patch')

if changed:
    tweak.write_text(text)
    print('Applied AutoFLEX Option A rootless-safe patch')
else:
    print('No AutoFLEX Option A changes needed')
