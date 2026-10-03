#!/bin/sh
# Renders the Light Glass hourglass (idle day, mid-block, until sunset, past sunset, break ready, night) to PNGs with SwiftUI's
# ImageRenderer, without launching the app. Usage: scripts/render-lightglass.sh [output-dir]
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-build/renders}"
mkdir -p build
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  Paragonday/LightGlass.swift Paragonday/LightGlassView.swift Paragonday/SolarMath.swift \
  Tools/LightGlassRender/main.swift \
  -o build/lightglass-render
./build/lightglass-render "$OUT"
