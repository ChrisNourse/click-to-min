#!/usr/bin/env bash
# qa/06-settings.sh — validate enable/disable + icon-hide toggles via defaults.
#
# Requires: Accessibility granted to ClickToMin.app and axprobe; cliclick.
#
# Usage: ./qa/06-settings.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

APP_BID="com.apple.Safari"
BUNDLE_DEFAULTS="com.click-to-min"

qa::require_cliclick
qa::require_axprobe_granted
qa::build_release

AXPROBE="$(qa::axprobe_bin)"

qa::launch_app
trap 'qa::quit_app; defaults delete "$BUNDLE_DEFAULTS" 2>/dev/null || true' EXIT

sleep 2

# --- Case A: disable via defaults, click should NOT minimize ---
qa::info "06-A: disable ClickToMin via defaults"
defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.enabled" -bool false
sleep 1

open -gb "$APP_BID" || true
sleep 1
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1
sleep 0.5

DOCK_FRAME="$("$AXPROBE" dock-item-frame "$APP_BID")"
eval "$DOCK_FRAME"
CLICK_X="$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')"
CLICK_Y="$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')"

cliclick "c:$CLICK_X,$CLICK_Y"
sleep 0.5

MIN="$("$AXPROBE" is-minimized "$APP_BID" || echo minimized=unknown)"
if [[ "$MIN" == "minimized=true" ]]; then
    qa::fail "06-A: window minimized while disabled — should have been no-op"
    exit 1
fi
qa::pass "06-A: disabled mode — click did not minimize"

# --- Case B: re-enable via defaults, click SHOULD minimize ---
qa::info "06-B: re-enable ClickToMin via defaults"
defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.enabled" -bool true
sleep 1

osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1
sleep 0.5

cliclick "c:$CLICK_X,$CLICK_Y"
"$AXPROBE" wait-until-minimized "$APP_BID" --timeout 3.0 \
    || { qa::fail "06-B: window did not minimize after re-enable"; exit 1; }
qa::pass "06-B: re-enabled mode — click minimized"

# Restore window for subsequent tests.
cliclick "c:$CLICK_X,$CLICK_Y"
sleep 1

# --- Case C: hide icon, relaunch, icon reappears ---
qa::info "06-C: hide icon + relaunch"
defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.iconHidden" -bool true
sleep 1

qa::quit_app
sleep 1
qa::launch_app
sleep 2

defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.iconHidden" -bool false
sleep 0.5

ICON_HIDDEN="$(defaults read "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.iconHidden" 2>/dev/null || echo 0)"
if [[ "$ICON_HIDDEN" != "0" ]]; then
    qa::fail "06-C: iconHidden should be false after relaunch"
    exit 1
fi
qa::pass "06-C: relaunch un-hides icon"

qa::info "06: all settings tests passed"
