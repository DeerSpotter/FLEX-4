#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
if not path.exists():
    print('Tweak.xm not found')
    raise SystemExit(0)

text = path.read_text()
original = text

replacements = [
    (
        'cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", bundle, time, detail];',
        'cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\\n%@\\n%@", bundle, time, detail];'
    ),
    (
        'NSString *message = [NSString stringWithFormat:@"App: %@\nBundle: %@\nTime: %@\n\n%@", app, bundle, time, detail];',
        'NSString *message = [NSString stringWithFormat:@"App: %@\\nBundle: %@\\nTime: %@\\n\\n%@", app, bundle, time, detail];'
    ),
]

for old, new in replacements:
    text = text.replace(old, new)

if text != original:
    path.write_text(text)
    print('Fixed Force Open Logs generated string newlines')
else:
    print('No Force Open Logs newline fixes needed')
