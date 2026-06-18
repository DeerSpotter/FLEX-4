#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()
original = text

if 'FLEX4BetaForceOpenAppsPatchMarker' not in text:
    print('Force Open Apps patch not present yet; skipping Force Open Logs runtime fix')
    raise SystemExit(0)

if 'FLEX4BetaForceOpenLogsPatchMarker' not in text:
    print('Force Open Logs patch not present yet; skipping Force Open Logs runtime fix')
    raise SystemExit(0)

# Guarantee the third custom row even if the main logs script skipped its exact block match.
if '@"Force Open Apps", forceOpenAction' in text and '@"Force Open Logs"' not in text:
    force_open_registration = '    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Apps", forceOpenAction);\n'
    force_open_logs_registration = force_open_registration + '''
    FLEXingGlobalsRowAction forceOpenLogsAction = ^(__kindof UITableViewController *host) {
        FLEX4BetaOpenForceOpenLogsMenu(host);
    };
    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Logs", forceOpenLogsAction);
'''
    text = text.replace(force_open_registration, force_open_logs_registration, 1)
    print('Patched missing Force Open Logs custom row registration')

# When AutoFLEX Option A inserted an early runtime guard, Force Open still needs to continue
# for selected apps so we can either open FLEX or record exactly why it failed.
early_guard_with_late_force = '''    BOOL likelyUIProcess = isLikelyUIProcess();
    if (!likelyUIProcess) {
        HBLogInfo(@"FLEXing: Skipping non-app process %@.", currentBundleIdentifier.length ? currentBundleIdentifier : NSProcessInfo.processInfo.processName);
        return;
    }

    BOOL springBoardProcess = isSpringBoardProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
'''
force_aware_early_guard = '''    BOOL likelyUIProcess = isLikelyUIProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    if (!likelyUIProcess && !currentBundleForceOpen) {
        HBLogInfo(@"FLEXing: Skipping non-app process %@.", currentBundleIdentifier.length ? currentBundleIdentifier : NSProcessInfo.processInfo.processName);
        return;
    }
    if (!likelyUIProcess && currentBundleForceOpen) {
        FLEX4BetaLogForceOpenLaunch(@"Runtime Guard Override", @"Force Open is enabled, so FLEX 4 Beta will continue past the normal app-process guard.");
    }

    BOOL springBoardProcess = isSpringBoardProcess();
'''
if force_aware_early_guard not in text and early_guard_with_late_force in text:
    text = text.replace(early_guard_with_late_force, force_aware_early_guard, 1)
    print('Patched Force Open to continue past the AutoFLEX Option A runtime guard')

# Add high-value launch state logs for both possible generated variants.
launch_state_no_decl = '''    BOOL springBoardProcess = isSpringBoardProcess();
    currentBundleAllowsFLEX = springBoardProcess || currentBundleForceOpen || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = currentBundleForceOpen || FLEXingShouldAutoShowBundle(currentBundleIdentifier);
'''
launch_state_no_decl_logged = '''    BOOL springBoardProcess = isSpringBoardProcess();
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
if 'FLEX4BetaLogForceOpenLaunch(@"Process Reached"' not in text and launch_state_no_decl in text:
    text = text.replace(launch_state_no_decl, launch_state_no_decl_logged, 1)
    print('Patched Force Open launch state diagnostics')

launch_state_with_decl = '''    BOOL springBoardProcess = isSpringBoardProcess();
    BOOL currentBundleForceOpen = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    currentBundleAllowsFLEX = springBoardProcess || currentBundleForceOpen || FLEXingIsBundleEnabled(currentBundleIdentifier);
    currentBundleShouldAutoShow = currentBundleForceOpen || FLEXingShouldAutoShowBundle(currentBundleIdentifier);
'''
launch_state_with_decl_logged = '''    BOOL springBoardProcess = isSpringBoardProcess();
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
if 'FLEX4BetaLogForceOpenLaunch(@"Process Reached"' not in text and launch_state_with_decl in text:
    text = text.replace(launch_state_with_decl, launch_state_with_decl_logged, 1)
    print('Patched Force Open launch state diagnostics with declaration')

if text != original:
    path.write_text(text)
    print('Applied Force Open Logs runtime fix')
else:
    print('No Force Open Logs runtime fix needed')
