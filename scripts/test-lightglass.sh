#!/bin/sh
# Light Glass tests, with only the Command Line Tools:
#   1. the timer logic (state machine, light share, tally, persistence, bell) on its own, and checked
#      against the app's own SolarMath and menu-bar Horizon Time;
#   2. an offscreen click-through of the menu section (no app launched, nothing in the menu bar).
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
FLAGS="-swift-version 5 -target arm64-apple-macos14.0"

# shellcheck disable=SC2086
xcrun swiftc $FLAGS \
  Paragonday/LightGlass.swift Paragonday/LightGlassBell.swift Paragonday/SolarMath.swift \
  Tests/LightGlassTests/main.swift \
  -o build/lightglass-tests
./build/lightglass-tests

echo
# shellcheck disable=SC2086
xcrun swiftc $FLAGS \
  Paragonday/LightGlass.swift Paragonday/LightGlassBell.swift Paragonday/LightGlassView.swift \
  Paragonday/LightGlassController.swift Tools/LightGlassMenuSmoke/main.swift \
  -o build/lightglass-menu-smoke
./build/lightglass-menu-smoke
