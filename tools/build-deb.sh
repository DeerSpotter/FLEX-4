#!/bin/sh
set -eu

if [ ! -n "${THEOS:-}" ]; then
  echo "THEOS is not set. Install Theos and export THEOS before building." >&2
  exit 1
fi

make clean package

echo "Built packages:"
ls -1 packages/*.deb
