#!/bin/sh
set -eu

if [ ! -n "${THEOS:-}" ]; then
  echo "THEOS is not set. Install Theos and export THEOS before building." >&2
  exit 1
fi

: "${ARCHS:=arm64}"
export ARCHS

# Keep CI builds compatible with Objective-C++ ARC. The dictionary stores Class
# objects directly, so this needs a normal Objective-C cast, not a bridge cast.
if grep -q 'Class cls = (__bridge Class)classLookup\[className\];' Tweak.xm; then
  python3 - <<'PY'
from pathlib import Path
path = Path('Tweak.xm')
text = path.read_text()
text = text.replace('Class cls = (__bridge Class)classLookup[className];', 'Class cls = (Class)classLookup[className];')
path.write_text(text)
PY
fi

echo "Building FLEXing with ARCHS=$ARCHS"
make clean package ARCHS="$ARCHS"

echo "Built packages:"
ls -1 packages/*.deb
