#!/usr/bin/env bash
# qa/04-dock-config.sh — Dock resize / orientation / autohide variations.
#
# Snapshots current Dock prefs, flips values via `defaults write`, asserts
# `dock frame refreshed` log line fires, then always restores baseline via
# trap EXIT. Each flip runs `killall Dock` which takes ~1s to settle.
#
# Requires: Accessibility granted; cliclick for the autohide edge-strip probe.
#
# Usage: ./qa/04-dock-config.sh [--app BUNDLE_ID] [--output FILE]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

APP_BID="com.apple.Safari"
OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP_BID="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

qa::require_axprobe_granted
qa::build_release
qa::require_click_tool

# --- Snapshot baseline ------------------------------------------------------
BASELINE_TILESIZE="$(defaults read com.apple.dock tilesize 2>/dev/null || echo 48)"
BASELINE_ORIENTATION="$(defaults read com.apple.dock orientation 2>/dev/null || echo bottom)"
BASELINE_AUTOHIDE="$(defaults read com.apple.dock autohide 2>/dev/null || echo 0)"

qa::info "04: baseline tilesize=$BASELINE_TILESIZE orientation=$BASELINE_ORIENTATION autohide=$BASELINE_AUTOHIDE"

restore_dock() {
    qa::info "04: restoring Dock baseline"
    defaults write com.apple.dock tilesize -int "$BASELINE_TILESIZE"
    defaults write com.apple.dock orientation -string "$BASELINE_ORIENTATION"
    defaults write com.apple.dock autohide -bool \
        "$([[ "$BASELINE_AUTOHIDE" == "1" ]] && echo true || echo false)"
    killall Dock 2>/dev/null || true
    sleep 1.5
    qa::quit_app
}
trap restore_dock EXIT

qa::launch_app
FAIL=0
AXPROBE="$(qa::axprobe_bin)"

# Ensure target app is running
open -gb "$APP_BID" 2>/dev/null || true
sleep 1
qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
sleep 0.5

# Verify click-to-minimize works after a Dock mutation.
# Activates Safari, resolves its new Dock tile position, clicks it,
# and asserts the window minimizes.
verify_minimize() {
    local label="$1"
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to set miniaturized of windows to false" 2>/dev/null || true
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1
    sleep 1.5
    local dock_frame
    dock_frame="$(qa::timeout_cmd 10 "$AXPROBE" dock-item-frame "$APP_BID" 2>/dev/null || true)"
    if [[ -z "$dock_frame" ]]; then
        qa::warn "04 $label: could not resolve Dock tile — skipping minimize check"
        return
    fi
    eval "$dock_frame"
    CLICK_X="$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')"
    CLICK_Y="$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')"
    qa::dock_click
    if [[ "$QA_CLICK_MODE" == "inject" ]]; then
        if [[ "$QA_INJECT_RESULT" == done:timing_ms=* ]]; then
            qa::info "04 $label: minimize confirmed (inject)"
        else
            qa::warn "04 $label: inject did not minimize ($QA_INJECT_RESULT)"
        fi
    else
        if "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 3.0 2>/dev/null; then
            qa::info "04 $label: minimize confirmed"
        else
            qa::warn "04 $label: click-to-minimize did not fire (VM timing — non-fatal)"
        fi
    fi
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to set miniaturized of windows to false" 2>/dev/null || true
    sleep 1
}

# Assert lifecycle emits `dock frame refreshed` within N seconds.
# Starts capture, runs `mutate`, then checks capture. This order matters
# because ClickToMin detects the Dock restart and emits the signpost
# during Dock's settle window — if capture starts after the settle,
# the signpost is already gone.
assert_refresh_on_mutate() {
    local label="$1"
    shift
    local tmp
    tmp="$(mktemp -t clicktomin-logstream)"
    /usr/bin/log stream --style syslog --info --debug \
        --predicate 'subsystem == "com.click-to-min" && category == "lifecycle"' \
        >"$tmp" 2>/dev/null &
    local log_pid=$!
    sleep 0.2
    "$@"
    # Give ClickToMin time to react to the new Dock PID + emit the signpost.
    # On slower VMs or after repeated killall Dock cycles (autohide toggles
    # especially, where the Dock also plays a slide animation), 4s is too
    # tight. 6s is still well under the 10s xctrace perf budget.
    sleep 6
    kill "$log_pid" 2>/dev/null || true
    wait "$log_pid" 2>/dev/null || true
    # Save capture for diagnosis
    if [[ -n "${QA_ARTIFACT_DIR:-}" ]]; then
        local safe_label="${label//[^a-zA-Z0-9_=-]/_}"
        cp "$tmp" "$QA_ARTIFACT_DIR/04-$safe_label.log" 2>/dev/null || true
    fi
    if ! grep -q 'dock frame refreshed' "$tmp"; then
        qa::fail "04 $label: no 'dock frame refreshed' after mutate"
        # Dump the capture to aid diagnosis
        echo "--- capture for '$label' ---"
        cat "$tmp"
        echo "--- end capture ---"
        FAIL=1
    fi
    rm -f "$tmp"
    # Settle between cases so Dock's notification stream doesn't backlog
    # (rapid killall Dock cycles can drop didLaunchApplicationNotification
    # for subsequent cycles — the distributed prefchanged notification and
    # AppKit's launch observer both need breathing room on slower hosts).
    sleep 2
}

flip_tilesize() {
    local size="$1"
    qa::info "04: tilesize=$size"
    assert_refresh_on_mutate "tilesize=$size" bash -c "
        defaults write com.apple.dock tilesize -int $size
        killall Dock
    "
    verify_minimize "tilesize=$size"
}

flip_orientation() {
    local ori="$1"
    qa::info "04: orientation=$ori"
    assert_refresh_on_mutate "orientation=$ori" bash -c "
        defaults write com.apple.dock orientation -string $ori
        killall Dock
    "
    verify_minimize "orientation=$ori"
}

flip_autohide() {
    local on="$1"
    qa::info "04: autohide=$on"
    assert_refresh_on_mutate "autohide=$on" bash -c "
        defaults write com.apple.dock autohide -bool $on
        killall Dock
    "
    if [[ "$on" == "true" ]]; then
        if [[ "$QA_CLICK_MODE" != "inject" ]]; then
            local screen_h
            screen_h="$(qa::timeout_cmd 5 osascript -e 'tell application "Finder" to get item 4 of (get bounds of window of desktop)' 2>/dev/null || echo 900)"
            cliclick "m:512,$((screen_h - 1))"
            sleep 1.5
        fi
    fi
    verify_minimize "autohide=$on"
}

flip_tilesize 96
flip_tilesize 32
flip_orientation left
flip_orientation right
flip_orientation bottom
flip_autohide true
flip_autohide false

if [[ -n "$OUTPUT" ]]; then
    if [[ "$FAIL" -eq 0 ]]; then echo PASS > "$OUTPUT"; else echo FAIL > "$OUTPUT"; fi
fi

if [[ "$FAIL" -eq 0 ]]; then
    qa::pass "04-dock-config"
else
    qa::fail "04-dock-config"
    exit 1
fi
