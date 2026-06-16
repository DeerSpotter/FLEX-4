# FLEXing

FLEXing is a rootless iOS tweak package that loads the FLEX explorer into applications.

This fork adds a homescreen manager app named **FLEXing**. Open the manager, choose a running app or any detected installed app, set an override for that bundle id, choose whether FLEX should open automatically, and save notes or adjustment details for the next launch.

## What changed

- FLEX keeps the original FLEXing behavior by default.
- FLEX is enabled unless you explicitly turn a bundle id off in the manager.
- Auto Show is enabled unless you explicitly turn it off for that bundle id.
- Per-app settings are stored at:

```text
/var/mobile/Library/Preferences/com.github.devnoname120.flexing.plist
```

- Saved settings are keyed by bundle id.
- The tweak reads the saved profile when the target app starts.
- The manager app can list running apps and all detected installed apps.

## GitHub Actions build

Use the **Build rootless DEB** workflow from the Actions tab to build the package from GitHub. The generated `.deb` is uploaded as an artifact named `flexing-rootless-deb`.

## Local build

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

After installing, open **FLEXing** from the homescreen if you want to override a specific app, then fully restart that target app.

## Notes

The saved adjustments field is stored in the shared plist for the target bundle id. Use it for selectors, class names, offsets, notes, or manual adjustment details you want available next launch.

# License

BSD for this code and for FLEX itself.
