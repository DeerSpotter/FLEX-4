#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

old = 'NSString *message = [NSString stringWithFormat:@"Original: %@\nOverride: %@",'
new = 'NSString *message = [NSString stringWithFormat:@"Original: %@\\nOverride: %@",'

if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text)
    print('Fixed override message Objective-C newline escape')
else:
    print('Override message newline fix not needed')
