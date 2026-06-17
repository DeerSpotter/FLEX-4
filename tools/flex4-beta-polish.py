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

# Add a lightweight overrides bucket near the top of the FLEX 4 Beta panel.
patch_once(
'''    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments"]];
''',
'''    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Saved Adjustments" subtitle:(adjustments.length ? adjustments : @"None. Tap to edit saved text for this app.") section:@"Settings" kind:@"editAdjustments"]];

    NSArray *flex4OverriddenKeys = [NSUserDefaults.standardUserDefaults arrayForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"] ?: @[];
    NSString *overrideSubtitle = flex4OverriddenKeys.count == 0
        ? @"No overridden values"
        : [NSString stringWithFormat:@"%lu overridden value%@. Tap to reset.", (unsigned long)flex4OverriddenKeys.count, flex4OverriddenKeys.count == 1 ? @"" : @"s"];
    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Overrides" subtitle:overrideSubtitle section:@"FLEX 4 Beta" kind:@"overridesBucket"]];
''',
'overrides bucket row',
required=True)

# Add reset actions for the overrides bucket.
patch_once(
'''    if ([item.kind isEqualToString:@"toggleEnabled"]) {
''',
'''    if ([item.kind isEqualToString:@"overridesBucket"]) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSMutableArray *overriddenKeys = [[defaults arrayForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"] mutableCopy] ?: [NSMutableArray array];
        NSMutableDictionary *originalValues = [[defaults dictionaryForKey:@"FLEX4BetaOriginalUserDefaultsValues"] mutableCopy] ?: [NSMutableDictionary dictionary];

        if (overriddenKeys.count == 0) {
            UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"Overrides" message:@"No overridden values yet." preferredStyle:UIAlertControllerStyleAlert];
            [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:empty animated:YES completion:nil];
            return;
        }

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Overrides" message:@"Reset one value or reset all overrides." preferredStyle:UIAlertControllerStyleActionSheet];

        void (^resetKey)(NSString *) = ^(NSString *keyToReset) {
            if (keyToReset.length == 0) { return; }
            id originalValue = originalValues[keyToReset];
            if (originalValue) {
                [defaults setObject:originalValue forKey:keyToReset];
            } else {
                [defaults removeObjectForKey:keyToReset];
            }
            [overriddenKeys removeObject:keyToReset];
            [originalValues removeObjectForKey:keyToReset];
            [defaults setObject:overriddenKeys forKey:@"FLEX4BetaOverriddenUserDefaultsKeys"];
            [defaults setObject:originalValues forKey:@"FLEX4BetaOriginalUserDefaultsValues"];
            [defaults synchronize];
            [self reloadItems];
        };

        [sheet addAction:[UIAlertAction actionWithTitle:@"Reset All Overrides" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            for (NSString *keyToReset in [overriddenKeys copy]) {
                id originalValue = originalValues[keyToReset];
                if (originalValue) {
                    [defaults setObject:originalValue forKey:keyToReset];
                } else {
                    [defaults removeObjectForKey:keyToReset];
                }
            }
            [defaults removeObjectForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"];
            [defaults removeObjectForKey:@"FLEX4BetaOriginalUserDefaultsValues"];
            [defaults synchronize];
            [self reloadItems];
        }]];

        NSUInteger visibleLimit = MIN((NSUInteger)overriddenKeys.count, (NSUInteger)12);
        for (NSUInteger index = 0; index < visibleLimit; index++) {
            NSString *keyToReset = overriddenKeys[index];
            [sheet addAction:[UIAlertAction actionWithTitle:keyToReset style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                resetKey(keyToReset);
            }]];
        }

        if (overriddenKeys.count > visibleLimit) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%lu more hidden. Use Reset All or search the key.", (unsigned long)(overriddenKeys.count - visibleLimit)] style:UIAlertActionStyleDefault handler:nil]];
        }

        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = self.view.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    if ([item.kind isEqualToString:@"toggleEnabled"]) {
''',
'overrides bucket reset actions',
required=True)

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
# This intentionally reloads only the tapped row so the table does not jump to the bottom.
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
            NSMutableArray *overriddenKeys = [[defaults arrayForKey:@"FLEX4BetaOverriddenUserDefaultsKeys"] mutableCopy] ?: [NSMutableArray array];
            NSMutableDictionary *originalValues = [[defaults dictionaryForKey:@"FLEX4BetaOriginalUserDefaultsValues"] mutableCopy] ?: [NSMutableDictionary dictionary];

            if (![overriddenKeys containsObject:key]) {
                id originalValue = [defaults objectForKey:key];
                if (originalValue) {
                    originalValues[key] = originalValue;
                }
                [overriddenKeys addObject:key];
            }

            BOOL nextValue = ![defaults boolForKey:key];
            [defaults setBool:nextValue forKey:key];
            [defaults setObject:overriddenKeys forKey:@"FLEX4BetaOverriddenUserDefaultsKeys"];
            [defaults setObject:originalValues forKey:@"FLEX4BetaOriginalUserDefaultsValues"];
            [defaults synchronize];

            item.subtitle = nextValue ? @"1" : @"0";
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
        return;
    }
}
''',
'immediate bool value toggle without scroll jump',
required=True)

path.write_text(text)
print('Added FLEX 4 Beta visible branding, overrides bucket, stable immediate BOOL values, and overridden-row highlighting' if changed else 'No changes needed')
