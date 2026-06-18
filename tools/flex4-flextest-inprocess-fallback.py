#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

helper_marker = 'FLEX4Beta in-process FLEX manager fallback'
if helper_marker not in text:
    anchor = '%hook UIWindow\n'
    helper = '''
// FLEX4Beta in-process FLEX manager fallback
static BOOL FLEX4BetaResolveInProcessFLEXManagerIfPossible(void) {
    if (manager && show) {
        return YES;
    }

    Class flexManagerClass = NSClassFromString(@"FLEXManager");
    if (!flexManagerClass || ![flexManagerClass respondsToSelector:@selector(sharedManager)]) {
        HBLogInfo(@"FLEX4Beta: In-process FLEXManager class not available.");
        return NO;
    }

    id candidate = [flexManagerClass performSelector:@selector(sharedManager)];
    if (!candidate) {
        HBLogInfo(@"FLEX4Beta: In-process FLEXManager sharedManager returned nil.");
        return NO;
    }

    SEL candidateShow = @selector(showExplorer);
    if (![candidate respondsToSelector:candidateShow]) {
        HBLogInfo(@"FLEX4Beta: In-process FLEXManager does not respond to showExplorer.");
        return NO;
    }

    manager = candidate;
    show = candidateShow;
    HBLogInfo(@"FLEX4Beta: Resolved in-process FLEXManager fallback using FLEXtest-style linked FLEX.");
    return YES;
}

static void FLEX4BetaShowExplorerFromAppActiveIfNeeded(void) {
    if (didAutoShowExplorer || isSpringBoardProcess() || !currentBundleAllowsFLEX || !currentBundleShouldAutoShow || !manager || !show) {
        return;
    }

    didAutoShowExplorer = YES;
    HBLogInfo(@"FLEX4Beta: UIApplicationDidBecomeActive auto show for %@", currentBundleIdentifier ?: @"");
    [manager performSelector:show];
}

'''
    if anchor not in text:
        raise SystemExit('Could not find UIWindow hook anchor')
    text = text.replace(anchor, helper + anchor, 1)

old = '''        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
            enableNetworkMonitoringIfPossible();
            FLEXingRegisterPanelEntryIfPossible();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
        }
'''
new = '''        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
        } else {
            FLEX4BetaResolveInProcessFLEXManagerIfPossible();
        }

        if (manager && show) {
            enableNetworkMonitoringIfPossible();
            FLEXingRegisterPanelEntryIfPossible();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *note) {
                FLEX4BetaShowExplorerFromAppActiveIfNeeded();
            }];

            FLEX4BetaShowExplorerFromAppActiveIfNeeded();
        }
'''
if old in text:
    text = text.replace(old, new, 1)
elif 'FLEX4BetaShowExplorerFromAppActiveIfNeeded' not in text:
    raise SystemExit('Could not find manager initialization block')

path.write_text(text)
