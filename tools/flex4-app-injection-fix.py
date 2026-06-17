#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'FLEX4BetaAppInjectionPathFixMarker'
if marker in text:
    print('FLEX 4 Beta app injection path fix already present')
    raise SystemExit(0)

old = '''/// This isn't perfect, but works for most cases as intended
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
'''

new = '''// FLEX4BetaAppInjectionPathFixMarker
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

if old not in text:
    raise SystemExit('Could not find isLikelyUIProcess block to patch')

path.write_text(text.replace(old, new, 1))
print('Patched FLEX 4 Beta app injection path allowlist for modern/private var app bundles')
