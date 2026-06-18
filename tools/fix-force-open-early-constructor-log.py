#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'FLEX4BetaEarlyConstructorLogPatchMarker'
if marker in text:
    print('Skipped already patched: early force open constructor log')
else:
    needle = '    currentBundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";\n'
    if needle not in text:
        raise SystemExit('Could not find block to patch: current bundle identifier assignment for early constructor log')

    insertion = needle + f'''
    // {marker}
    BOOL FLEX4BetaEarlyForceOpenSelected = FLEX4BetaIsForceOpenBundle(currentBundleIdentifier);
    if (FLEX4BetaEarlyForceOpenSelected) {{
        NSString *earlyExecutable = NSProcessInfo.processInfo.arguments.firstObject ?: @"";
        NSString *earlyProcessName = NSProcessInfo.processInfo.processName ?: @"";
        NSString *earlyBundlePath = NSBundle.mainBundle.bundlePath ?: @"";
        NSString *earlyMainBundlePath = NSBundle.mainBundle.executablePath ?: @"";
        NSString *earlyDetail = [NSString stringWithFormat:@"constructor reached before guards. process=%@ executable=%@ bundlePath=%@ mainExecutable=%@", earlyProcessName, earlyExecutable, earlyBundlePath, earlyMainBundlePath];
        FLEX4BetaAppendForceOpenLaunchLog(currentBundleIdentifier, FLEXingDisplayNameForCurrentProcess(), @"Constructor Reached", earlyDetail);
    }}
'''

    text = text.replace(needle, insertion, 1)
    path.write_text(text)
    print('Patched: early force open constructor log')

fallback = Path('tools/flex4-flextest-inprocess-fallback.py')
if fallback.exists():
    exec(fallback.read_text(), {'__name__': '__main__'})
