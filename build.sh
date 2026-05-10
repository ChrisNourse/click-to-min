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
#   - Run: log stream --predicate 'subsystem == "com.click-to-min"'
#     and confirm lifecycle signposts appear
set -euo pipefail

# Prefer swift.org toolchain when present (workaround for broken CLT 16.2
# PackageDescription dylib that ships out-of-sync with its swiftmodule).
TOOLCHAIN_BIN="/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin"
if [[ -x "$TOOLCHAIN_BIN/swift" ]]; then
    PATH="$TOOLCHAIN_BIN:$PATH"
fi

APP_NAME="ClickToMin"
BUNDLE="${APP_NAME}.app"

rm -rf "$BUNDLE"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/menubar-icon.png "$BUNDLE/Contents/Resources/menubar-icon.png"
cp "Resources/menubar-icon@2x.png" "$BUNDLE/Contents/Resources/menubar-icon@2x.png"

plutil -lint "$BUNDLE/Contents/Info.plist"

# Codesign. Prefer a stable self-signed identity so TCC grants (Accessibility)
# survive rebuilds — every byte change of the Mach-O rotates the cdhash, and
# an ad-hoc signature binds TCC to that cdhash, forcing a re-grant after every
# `swift build`. A proper signing identity binds TCC to the certificate +
# bundle identifier instead, so recompiles no longer invalidate the grant.
#
# Usage:
#   1. Create a local self-signed cert once (Keychain Access -> Certificate
#      Assistant -> Create a Certificate, name "ClickToMin Local Dev",
#      Identity Type "Self Signed Root", Certificate Type "Code Signing").
#   2. `export CLICKTOMIN_SIGN_ID="ClickToMin Local Dev"` (or set in your shell
#      rc). Absent the env var, build.sh auto-detects that exact common name
#      in the login keychain.
#   3. If no identity is available, fall back to ad-hoc (`-`). That still
#      produces a runnable bundle — only TCC persistence is lost.
SIGN_ID="${CLICKTOMIN_SIGN_ID:-ClickToMin Local Dev}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    echo "No '$SIGN_ID' codesigning identity in keychain — falling back to ad-hoc." >&2
    echo "  TCC grants will be lost on every rebuild. See build.sh comments." >&2
    SIGN_ID="-"
fi

# `--identifier` pins the TCC identity independent of the Mach-O path, so the
# Accessibility grant survives bundle relocations too.
if ! codesign --sign "$SIGN_ID" --identifier com.click-to-min \
        --force --timestamp=none "$BUNDLE" 2>/tmp/clicktomin-codesign.err; then
    echo "Single-pass codesign warned; falling back to two-step sign..." >&2
    cat /tmp/clicktomin-codesign.err >&2 || true
    codesign --sign "$SIGN_ID" --identifier com.click-to-min --force \
        "$BUNDLE/Contents/MacOS/$APP_NAME"
    codesign --sign "$SIGN_ID" --identifier com.click-to-min --force "$BUNDLE"
fi

codesign --verify --verbose "$BUNDLE"

echo "Built $BUNDLE (signed: $SIGN_ID)"
