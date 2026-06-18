#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()
marker = '// FLEX4BetaForceOpenLogsPatchMarker'
force_open_anchor = 'static void FLEX4BetaOpenForceOpenAppsMenu(__kindof UITableViewController *host) {\n'

removed = 0
while text.count(marker) > 1:
    first = text.find(marker)
    second = text.find(marker, first + len(marker))
    if second < 0:
        break

    next_marker = text.find(marker, second + len(marker))
    end = next_marker if next_marker >= 0 else text.find(force_open_anchor, second)
    if end < 0:
        # If the normal anchor cannot be found, do not guess and risk deleting source.
        print('Force Open Logs duplicate marker found, but no safe end anchor was found')
        break

    text = text[:second] + text[end:]
    removed += 1

if removed:
    path.write_text(text)
    print(f'Removed {removed} duplicate Force Open Logs generated block(s)')
else:
    print('No duplicate Force Open Logs generated block found')
