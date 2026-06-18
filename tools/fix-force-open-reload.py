#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()
old = '''    FLEX4BetaSetForceOpenBundle(bundle, next);
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
'''
new = '''    FLEX4BetaSetForceOpenBundle(bundle, next);
    [self.tableView reloadData];
'''
if new in text:
    print('Force Open Apps reload already patched')
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print('Patched Force Open Apps reload')
else:
    print('Force Open Apps reload block not found')
