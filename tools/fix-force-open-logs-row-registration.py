#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

registration_call = 'registerSelector, @"Force Open Logs", forceOpenLogsAction'
if registration_call in text:
    print('Skipped already patched: Force Open Logs row registration')
    raise SystemExit(0)

if 'static void FLEX4BetaOpenForceOpenLogsMenu(__kindof UITableViewController *host)' not in text:
    print('Skipped Force Open Logs row registration because logs controller is not present yet')
    raise SystemExit(0)

marker = '    flexingPanelEntryRegistered = YES;\n'
if marker not in text:
    raise SystemExit('Could not find flexingPanelEntryRegistered marker for Force Open Logs row registration')

insertion = '''    FLEXingGlobalsRowAction forceOpenLogsAction = ^(__kindof UITableViewController *host) {
        FLEX4BetaOpenForceOpenLogsMenu(host);
    };
    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"Force Open Logs", forceOpenLogsAction);

'''

text = text.replace(marker, insertion + marker, 1)
text = text.replace(
    'HBLogInfo(@"FLEXing: Registered FLEX 4 Beta and Force Open Apps panel rows.");',
    'HBLogInfo(@"FLEXing: Registered FLEX 4 Beta, Force Open Apps, and Force Open Logs panel rows.");'
)
text = text.replace(
    'HBLogInfo(@"FLEXing: Registered FLEXing panel row.");',
    'HBLogInfo(@"FLEXing: Registered FLEX 4 Beta and Force Open Logs panel rows.");'
)

path.write_text(text)
print('Patched Force Open Logs row registration')
