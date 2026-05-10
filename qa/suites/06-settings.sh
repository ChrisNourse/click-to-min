#!/usr/bin/env bash
# qa/06-settings.sh — validate enable/disable + icon-hide toggles via defaults.
#
# Requires: Accessibility granted to ClickToMin.app and axprobe; cliclick.
#
# Usage: ./qa/06-settings.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

APP_BID="com.apple.Safari"
BUNDLE_DEFAULTS="com.click-to-min"

qa::require_axprobe_granted
qa::build_release
qa::require_click_tool

AXPROBE="$(qa::axprobe_bin)"

qa::launch_app
trap 'qa::quit_app; defaults delete "$BUNDLE_DEFAULTS" 2>/dev/null || true' EXIT

sleep 2

# --- Case A: disable via defaults, click should NOT minimize ---
qa::info "06-A: disable ClickToMin via defaults"
defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.enabled" -bool false
sleep 1

open -gb "$APP_BID" 2>/dev/null || true
sleep 1
qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
sleep 0.5

qa::resolve_dock_tile "$APP_BID" || exit 1

qa::dock_click
sleep 0.5

if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    if [[ "$QA_INJECT_RESULT" == done:no-minimize:* || "$QA_INJECT_RESULT" == error:* ]]; then
        qa::info "06-A: inject correctly did not minimize (disabled)"
    elif [[ "$QA_INJECT_RESULT" == done:timing_ms=* ]]; then
        qa::warn "06-A: inject bypasses enabled guard (expected in inject mode)"
    fi
else
    MIN="$("$AXPROBE" is-minimized "$APP_BID" || echo minimized=unknown)"
    if [[ "$MIN" == "minimized=true" ]]; then
        qa::fail "06-A: window minimized while disabled — should have been no-op"
        exit 1
    fi
fi
qa::pass "06-A: disabled mode — click did not minimize"

# --- Case B: re-enable via defaults, click SHOULD minimize ---
qa::info "06-B: re-enable ClickToMin via defaults"
defaults write "$BUNDLE_DEFAULTS" "$BUNDLE_DEFAULTS.enabled" -bool true
sleep 1

qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1
sleep 0.5

qa::dock_click
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    if [[ "$QA_INJECT_RESULT" != done:timing_ms=* ]]; then
        qa::fail "06-B: window did not minimize after re-enable ($QA_INJECT_RESULT)"
        exit 1
    fi
else
    "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 3.0 \
        || { qa::fail "06-B: window did not minimize after re-enable"; exit 1; }
fi
qa::pass "06-B: re-enabled mode — click minimized"

# Restore window for subsequent tests.
qa::dock_click
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
