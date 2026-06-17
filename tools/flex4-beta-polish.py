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
        : [NSString stringWithFormat:@"%lu overridden value%@. Tap to inspect/edit.", (unsigned long)flex4OverriddenKeys.count, flex4OverriddenKeys.count == 1 ? @"" : @"s"];
    [items addObject:[FLEXingBrowserItem itemWithTitle:@"Overrides" subtitle:overrideSubtitle section:@"FLEX 4 Beta" kind:@"overridesBucket"]];
''',
'overrides bucket row',
required=True)

# Add inspect/edit actions for the overrides bucket.
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

        NSString *(^displayValue)(id) = ^NSString *(id value) {
            if (!value || value == (id)kCFNull) { return @"<not set>"; }
            if ([value isKindOfClass:NSNumber.class]) { return [value boolValue] ? @"1" : @"0"; }
            if ([value isKindOfClass:NSString.class]) { return (NSString *)value; }
            return [NSString stringWithFormat:@"%@", value];
        };

        void (^persistOverrideState)(void) = ^{
            [defaults setObject:overriddenKeys forKey:@"FLEX4BetaOverriddenUserDefaultsKeys"];
            [defaults setObject:originalValues forKey:@"FLEX4BetaOriginalUserDefaultsValues"];
            [defaults synchronize];
            [self reloadItems];
        };

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
            persistOverrideState();
        };

        void (^setBoolOverride)(NSString *, BOOL) = ^(NSString *keyToSet, BOOL boolValue) {
            if (keyToSet.length == 0) { return; }
            if (![overriddenKeys containsObject:keyToSet]) {
                id originalValue = [defaults objectForKey:keyToSet];
                if (originalValue) { originalValues[keyToSet] = originalValue; }
                [overriddenKeys addObject:keyToSet];
            }
            [defaults setBool:boolValue forKey:keyToSet];
            persistOverrideState();
        };

        void (^showDetailForKey)(NSString *) = ^(NSString *keyToInspect) {
            id originalValue = originalValues[keyToInspect];
            id overrideValue = [defaults objectForKey:keyToInspect];
            NSString *message = [NSString stringWithFormat:@"Original: %@\nOverride: %@", displayValue(originalValue), displayValue(overrideValue)];
            UIAlertController *detail = [UIAlertController alertControllerWithTitle:keyToInspect message:message preferredStyle:UIAlertControllerStyleActionSheet];

            [detail addAction:[UIAlertAction actionWithTitle:@"Set True" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                setBoolOverride(keyToInspect, YES);
            }]];
            [detail addAction:[UIAlertAction actionWithTitle:@"Set False" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                setBoolOverride(keyToInspect, NO);
            }]];
            [detail addAction:[UIAlertAction actionWithTitle:@"Reset to Original" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                resetKey(keyToInspect);
            }]];
            [detail addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            detail.popoverPresentationController.sourceView = self.view;
            detail.popoverPresentationController.sourceRect = self.view.bounds;
            [self presentViewController:detail animated:YES completion:nil];
        };

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Overrides" message:@"Select an override to inspect, change, or reset." preferredStyle:UIAlertControllerStyleActionSheet];

        NSUInteger visibleLimit = MIN((NSUInteger)overriddenKeys.count, (NSUInteger)24);
        for (NSUInteger index = 0; index < visibleLimit; index++) {
            NSString *keyToInspect = overriddenKeys[index];
            id originalValue = originalValues[keyToInspect];
            id overrideValue = [defaults objectForKey:keyToInspect];
            NSString *summary = [NSString stringWithFormat:@"%@  %@ → %@", keyToInspect, displayValue(originalValue), displayValue(overrideValue)];
            [sheet addAction:[UIAlertAction actionWithTitle:summary style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                showDetailForKey(keyToInspect);
            }]];
        }

        if (overriddenKeys.count > visibleLimit) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%lu more hidden. Use search to find the key.", (unsigned long)(overriddenKeys.count - visibleLimit)] style:UIAlertActionStyleDefault handler:nil]];
        }

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

        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = self.view.bounds;
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    if ([item.kind isEqualToString:@"toggleEnabled"]) {
''',
'overrides bucket inspect/edit actions',
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
print('Added FLEX 4 Beta visible branding, editable overrides bucket, stable immediate BOOL values, and overridden-row highlighting' if changed else 'No changes needed')
