#!/bin/sh
set -eu

if [ ! -n "${THEOS:-}" ]; then
  echo "THEOS is not set. Install Theos and export THEOS before building." >&2
  exit 1
fi

: "${ARCHS:=arm64}"
export ARCHS

echo "Building FLEXing with ARCHS=$ARCHS"
make clean package ARCHS="$ARCHS"

echo "Built packages:"
ls -1 packages/*.deb
