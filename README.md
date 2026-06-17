# FLEX 4 Beta

FLEX 4 Beta is a rootless iOS tweak package that loads the FLEX runtime explorer into apps and adds a FLEX-native patch helper under **CUSTOM ADDITIONS**.

The package is based on FLEX/FLEXing, but this branch is focused on an in-FLEX workflow. There is no separate Home Screen manager app. Open FLEX inside a target app, go to **CUSTOM ADDITIONS**, then tap **FLEX 4 Beta**.

## Current package metadata

```text
Package: com.github.devnoname120.flexing
Name: FLEX 4 Beta
Version: 1.0.0
Architecture: iphoneos-arm64
Maintainer: DeerSpotter
Author: DeerSpotter
```

## What this build adds

- Rootless package build for iOS 15+.
- FLEX entry renamed to **FLEX 4 Beta**.
- FLEX-native UI style that follows the existing FLEX panels.
- Searchable runtime browser inside FLEX.
- Global search across runtime items while keeping the visible table format close to FLEX.
- Search results for libraries, Objective-C classes, methods, properties, ivars, setters, and values.
- NSUserDefaults value search.
- One-tap Boolean override support for NSUserDefaults values.
- Orange-highlighted rows for overridden values.
- **Overrides** bucket under FLEX 4 Beta for reviewing and managing changed values.

## FLEX 4 Beta panel flow

Inside a supported app:

```text
Open FLEX
CUSTOM ADDITIONS
FLEX 4 Beta
```

The FLEX 4 Beta row opens the searchable runtime panel. Boolean NSUserDefaults rows can be toggled directly from the search results.

Override rows are tracked separately so they can be reviewed later:

```text
FLEX 4 Beta
Overrides
  keyName  originalValue -> overrideValue
```

Inside the override editor you can:

```text
Set True
Set False
Reset to Original
Reset All Overrides
```

## Stored preferences

Per-app settings and overrides are stored in:

```text
/var/mobile/Library/Preferences/com.github.devnoname120.flexing.plist
```

Current override tracking keys include:

```text
FLEX4BetaOverriddenUserDefaultsKeys
FLEX4BetaOriginalUserDefaultsValues
```

Saved settings are keyed by bundle identifier where applicable.

## App injection notes

The tweak is intended to load in normal UIKit apps. The rootless build expands the injection target to cover UIKit and UIKitCore based apps and accepts common app bundle paths including:

```text
/Applications
/System/Applications
/System/Library/CoreServices
/var/containers/Bundle/Application
/private/var/containers/Bundle/Application
/var/mobile/Containers/Bundle/Application
/private/var/mobile/Containers/Bundle/Application
/var/jb/Applications
/procursus/Applications
```

After installing or updating, fully close and relaunch the target app. If FLEX 4 Beta does not appear in a specific app, respring and try launching that app again.

## GitHub Actions build

Use the **Build rootless DEB** workflow from the Actions tab.

The generated `.deb` is uploaded as an artifact named:

```text
flexing-rootless-deb
```

The workflow applies build-time compatibility patches before compiling, including the FLEX 4 Beta polish and runtime search behavior.

## Local build

```bash
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless ARCHS=arm64
```

The package is rootless by default for device builds:

```make
export THEOS_PACKAGE_SCHEME = rootless
```

## Install

```bash
dpkg -i packages/*.deb
sbreload
uicache -a
```

Then fully restart the target app. If the app was already running, force close it before testing.

## Known beta behavior

- Boolean NSUserDefaults values can be toggled immediately.
- String and number override editing still need a dedicated inline editor.
- Some apps may block tweak injection or use unusual process/app bundle layouts.
- Runtime search is intentionally kept close to FLEX's native table style instead of using a separate custom app UI.

## License

BSD for this code and for FLEX itself.
