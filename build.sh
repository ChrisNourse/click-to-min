#!/usr/bin/env bash
# ClickToMin build script (Phase 4 T-4.2).
#
# Assembles a .app bundle from the SwiftPM executable with ad-hoc codesign
# for stable TCC identity.
#
# Post-build manual smoke (T-4.3, required gate into Phase 6):
#   - open ClickToMin.app
#   - Verify menu bar icon appears
#   - Verify Accessibility prompt fires on first launch
#   - Quit via the menu item; confirm `ps -A | grep ClickToMin` is empty
#   - Run: log stream --predicate 'subsystem == "com.chrisno.click-to-min"'
#     and confirm lifecycle signposts appear
set -euo pipefail

APP_NAME="ClickToMin"
BUNDLE="${APP_NAME}.app"

rm -rf "$BUNDLE"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

plutil -lint "$BUNDLE/Contents/Info.plist"

# Ad-hoc codesign. --deep is deprecated on macOS 14+; we have a single-binary
# bundle with no nested frameworks so it's unnecessary. If the single-pass
# sign emits a warning, fall back to signing the inner binary first.
if ! codesign --sign - --force --timestamp=none "$BUNDLE" 2>/tmp/clicktomin-codesign.err; then
    echo "Single-pass codesign warned; falling back to two-step sign..." >&2
    cat /tmp/clicktomin-codesign.err >&2 || true
    codesign --sign - --force "$BUNDLE/Contents/MacOS/$APP_NAME"
    codesign --sign - --force "$BUNDLE"
fi

codesign --verify --verbose "$BUNDLE"

echo "Built $BUNDLE"
