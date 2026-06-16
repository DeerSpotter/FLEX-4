#!/usr/bin/env python3
"""Small CI-only compatibility fixes before the Theos build.

This keeps the GitHub Actions workflow YAML simple and avoids large embedded
source patches inside build-rootless-deb.yml.
"""
from pathlib import Path
import re

path = Path("Tweak.xm")
text = path.read_text()

# Objective-C object values from NSDictionary need a normal Obj-C cast, not a bridge cast.
text = text.replace(
    "Class cls = (__bridge Class)classLookup[className];",
    "Class cls = (Class)classLookup[className];",
)

# Keep the FLEXing row on the stable lightweight menu. The searchable browser is
# too heavy to open directly from the FLEX row and can crash apps on tap.
stable_open = r'''static void FLEXingOpenPanelMenu(__kindof UITableViewController *host) {
    NSString *bundleIdentifier = FLEXingCurrentBundleIdentifier();
    BOOL enabled = FLEXingIsBundleEnabled(bundleIdentifier);
    BOOL autoShow = FLEXingShouldAutoShowBundle(bundleIdentifier);
    NSString *adjustments = FLEXingAdjustmentsForBundle(bundleIdentifier);
    NSUInteger patchCount = FLEXingPatchesForBundle(bundleIdentifier).count;

    NSString *message = [NSString stringWithFormat:@"%@\n%@\n\nEnabled: %@\nAuto Show: %@\nSaved Patches: %lu\n\nSaved Adjustments:\n%@",
                         @"Settings",
                         bundleIdentifier.length ? bundleIdentifier : @"No bundle identifier",
                         enabled ? @"On" : @"Off",
                         autoShow ? @"On" : @"Off",
                         (unsigned long)patchCount,
                         adjustments.length ? adjustments : @"None"];

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"FLEXing" message:message preferredStyle:UIAlertControllerStyleActionSheet];

    [menu addAction:[UIAlertAction actionWithTitle:(enabled ? @"Disable FLEX For This App" : @"Enable FLEX For This App") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        FLEXingSaveCurrentAppSettings(!enabled, autoShow, adjustments);
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:(autoShow ? @"Turn Auto Show Off" : @"Turn Auto Show On") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        FLEXingSaveCurrentAppSettings(enabled, !autoShow, adjustments);
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Saved Patches" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        FLEXingPatchListViewController *patches = [[FLEXingPatchListViewController alloc] init];
        if (host.navigationController) {
            [host.navigationController pushViewController:patches animated:YES];
        } else {
            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:patches];
            [(UIViewController *)host presentViewController:navigationController animated:YES completion:nil];
        }
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Save Note / Adjustment Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *editor = [UIAlertController alertControllerWithTitle:@"Saved Adjustments" message:@"Stored for this app. Execution support can use this field later." preferredStyle:UIAlertControllerStyleAlert];
        [editor addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Adjustment text";
            textField.text = adjustments ?: @"";
        }];
        [editor addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [editor addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *saveAction) {
            NSString *note = editor.textFields.firstObject.text ?: @"";
            FLEXingSaveCurrentAppSettings(enabled, autoShow, note);
        }]];
        [(UIViewController *)host presentViewController:editor animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [(UIViewController *)host presentViewController:menu animated:YES completion:nil];
}
'''

text = re.sub(
    r"static void FLEXingOpenPanelMenu\(__kindof UITableViewController \*host\) \{.*?\n\}\n\nstatic void FLEXingRegisterPanelEntryIfPossible",
    stable_open + "\nstatic void FLEXingRegisterPanelEntryIfPossible",
    text,
    count=1,
    flags=re.S,
)

# Retain the custom row block. If FLEX does not copy the block internally, a
# temporary stack block can be invalid by the time the row is tapped.
if "static FLEXingGlobalsRowAction flexingPanelEntryAction = nil;" not in text:
    text = text.replace(
        "typedef void (^FLEXingGlobalsRowAction)(__kindof UITableViewController *host);\n",
        "typedef void (^FLEXingGlobalsRowAction)(__kindof UITableViewController *host);\nstatic FLEXingGlobalsRowAction flexingPanelEntryAction = nil;\n",
    )

text = text.replace(
    "    FLEXingGlobalsRowAction action = ^(__kindof UITableViewController *host) {\n        FLEXingOpenPanelMenu(host);\n    };\n\n    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @\"FLEXing\", action);",
    "    if (!flexingPanelEntryAction) {\n        flexingPanelEntryAction = [^(__kindof UITableViewController *host) {\n            FLEXingOpenPanelMenu(host);\n        } copy];\n    }\n\n    ((void (*)(id, SEL, NSString *, FLEXingGlobalsRowAction))[manager methodForSelector:registerSelector])(manager, registerSelector, @\"FLEXing\", flexingPanelEntryAction);",
)

path.write_text(text)
