#!/bin/sh
# Builds Paragonday.app with only the Command Line Tools (no Xcode): compiles every Swift source in
# Paragonday/ with swiftc for Apple Silicon, macOS 14, and assembles the bundle (Info.plist, icon,
# ad-hoc signature) in build/cli/. Usage: scripts/build-cli.sh [--debug]
#
# It takes the released app's bundle ID, so it shares that app's settings and notification permission.
# BUNDLE_ID=com.tealprocess.paragonday.dev scripts/build-cli.sh gives it settings of its own instead.
set -eu
cd "$(dirname "$0")/.."

OPT="-O"
if [ "${1:-}" = "--debug" ]; then OPT="-Onone -g"; fi

BUNDLE_ID="${BUNDLE_ID:-com.tealprocess.paragonday}"
OUT=build/cli
APP="$OUT/Paragonday.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# shellcheck disable=SC2086
xcrun swiftc $OPT -swift-version 5 -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Paragonday/*.swift \
  -o "$APP/Contents/MacOS/Paragonday"

# Info.plist carries Xcode build-setting placeholders; fill them the way the Xcode target does.
sed -e 's/\$(EXECUTABLE_NAME)/Paragonday/' \
    -e "s/\\\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e 's/\$(PRODUCT_NAME)/Paragonday/' \
    Paragonday/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null
cp Paragonday/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: enough to run locally and for macOS to allow notifications.
codesign --force --sign - "$APP"

echo "Built $APP"
