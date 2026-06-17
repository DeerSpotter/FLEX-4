#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'FLEX4BetaImmediateDefaultsPatchMarker'
if marker in text:
    print('FLEX 4 Beta polish patch already present')
    raise SystemExit(0)

changed = False

def patch_once(old, new, label, required=False):
    global text, changed
    if old in text:
        text = text.replace(old, new, 1)
        changed = True
        print(f'Patched: {label}')
        return True
    if required:
        raise SystemExit(f'Could not find block to patch: {label}')
    print(f'Skipped missing block: {label}')
    return False

# Branding inside the FLEX panel. Keep package internals stable, only change visible labels.
patch_once('        self.title = @"FLEXing";\n', '        self.title = @"FLEX 4 Beta";\n', 'browser title')
patch_once('    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"FLEXing", action);\n',
           '    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @"FLEX 4 Beta", action);\n',
           'FLEX global row title')
patch_once('    HBLogInfo(@"FLEXing: Registered FLEXing panel row.");\n',
           '    HBLogInfo(@"FLEXing: Registered FLEX 4 Beta panel row.");\n',
           'registration log')

# Color rows that were changed directly from FLEX 4 Beta.
patch_once(
'''    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
''',
'''    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    // FLEX4BetaImmediateDefaultsPatchMarker: highlight values changed directly from FLEX 4 Beta.
    if ([item.kind isEqualToString:@"userDefault"]) {
        NSString *key = nil;
        NSRange firstSpace = [item.title rangeOfString:@" "];
        if (firstSpace.location != NSNotFound && firstSpace.location + 1 < item.title.length) {
            key = [item.title substringFromIndex:firstSpace.location + 1];
        }

        NSArray *overriddenKeys = [NSUserDefaults.standardUserDefaults arrayForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"] ?: @[];
        if (key.length > 0 && [overriddenKeys containsObject:key]) {
            cell.textLabel.textColor = UIColor.systemOrangeColor;
            cell.detailTextLabel.textColor = UIColor.systemOrangeColor;
        }
    }
''',
'overridden value row color',
required=True)

# Allow immediate no-menu Bool changes from the global NSUserDefaults value rows.
patch_once(
'''        [self presentViewController:editor animated:YES completion:nil];
        return;
    }
}
''',
'''        [self presentViewController:editor animated:YES completion:nil];
        return;
    }

    // Tap BOOL NSUserDefaults rows to toggle immediately, persist, and mark as overridden.
    if ([item.kind isEqualToString:@"userDefault"] && [item.title hasPrefix:@"BOOL "]) {
        NSString *key = [item.title substringFromIndex:5];
        if (key.length > 0) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            BOOL nextValue = ![defaults boolForKey:key];
            [defaults setBool:nextValue forKey:key];

            NSMutableArray *overriddenKeys = [[defaults arrayForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"] mutableCopy] ?: [NSMutableArray array];
            if (![overriddenKeys containsObject:key]) {
                [overriddenKeys addObject:key];
            }
            [defaults setObject:overriddenKeys forKey:@"FLEX4BetaOverriddenUserDefaultsKeys"];
            [defaults synchronize];

            self.asyncGlobalItems = @[];
            if ([[self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] >= 2) {
                [self flexingRunDeferredGlobalSearch];
            }
            [self applyFilter];
        }
        return;
    }
}
''',
'immediate bool value toggle',
required=True)

path.write_text(text)
print('Added FLEX 4 Beta visible branding, immediate BOOL values, and overridden-row highlighting' if changed else 'No changes needed')
