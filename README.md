# FLEXing

FLEXing is a rootless iOS tweak package that loads the FLEX explorer into selected applications.

This fork adds a homescreen manager app named **FLEXing**. Open the manager, choose a running app or any detected installed app, enable FLEX for that bundle id, choose whether FLEX should open automatically, and save notes or adjustment details for the next launch.

## What changed

- FLEX no longer auto loads into every app by default.
- Apps are disabled until selected in the FLEXing manager app.
- Per-app settings are stored at:

```text
/var/mobile/Library/Preferences/com.github.devnoname120.flexing.plist
```

- Saved settings are keyed by bundle id.
- The tweak reads the saved profile when the target app starts.
- The manager app can list running apps and all detected installed apps.

## Build

```bash
make clean package
```

The package is rootless by default on device builds:

```make
export THEOS_PACKAGE_SCHEME = rootless
```

## Install

```bash
dpkg -i packages/*.deb
sbreload
uicache -a
```

After installing, open **FLEXing** from the homescreen, enable the target app, then fully restart that target app.

## Notes

The saved adjustments field is intentionally stored as text in the shared plist. Use it for selectors, class names, offsets, notes, or manual adjustment details you want available next launch. The tweak logs saved adjustment text when it initializes for that bundle id.

# License

BSD for this code and for FLEX itself.
