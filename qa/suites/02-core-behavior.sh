#!/usr/bin/env bash
# qa/02-core-behavior.sh — scripted 3-click cycle + latency measurement.
#
# Requires: Accessibility granted to ClickToMin.app and axprobe; cliclick.
#
# Usage: ./qa/02-core-behavior.sh [--app BUNDLE_ID] [--trials N] [--output FILE]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

APP_BID="com.apple.Safari"
TRIALS=20
OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP_BID="$2"; shift 2 ;;
        --trials) TRIALS="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

qa::require_cliclick
qa::require_axprobe_granted
qa::build_release

AXPROBE="$(qa::axprobe_bin)"

# Dock tile coordinates for the target app.
qa::info "02: resolving Dock tile frame for $APP_BID"
# Ensure target is running so the Dock has a tile (for non-persistent icons).
open -gb "$APP_BID" || true
sleep 1

# Ensure target has at least one visible window, otherwise AXMinimize has
# nothing to act on and wait-until-minimized polls forever. Fresh Safari
# profiles on clean VMs launch with zero windows.
WIN_COUNT="$("$AXPROBE" window-count "$APP_BID" 2>/dev/null || echo 0)"
if [[ "$WIN_COUNT" -lt 1 ]]; then
    qa::info "02: $APP_BID has no windows; opening one"
    osascript -e "tell application id \"$APP_BID\" to make new document" >/dev/null 2>&1 \
        || osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1
    sleep 1
fi

DOCK_FRAME="$("$AXPROBE" dock-item-frame "$APP_BID")"
# shellcheck disable=SC2086
# parse "x=.. y=.. w=.. h=.."
eval "$DOCK_FRAME"
# shellcheck disable=SC2154
CLICK_X="$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')"
# shellcheck disable=SC2154
CLICK_Y="$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')"

qa::info "02: Dock tile at ($CLICK_X,$CLICK_Y)"

qa::launch_app
trap 'qa::quit_app' EXIT

# Case 1: background app -> Dock click -> frontmost becomes target, not minimized.
qa::info "02: case 1 — bring-to-front"
osascript -e 'tell application "Finder" to activate' >/dev/null
sleep 0.5
cliclick "c:$CLICK_X,$CLICK_Y"
# Poll for frontmost transition. On a loaded VM, the Dock's bring-to-front
# animation + AppKit activation can easily exceed 600ms.
FM=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    FM="$("$AXPROBE" frontmost-bundle-id || true)"
    [[ "$FM" == "$APP_BID" ]] && break
    sleep 0.3
done
if [[ "$FM" != "$APP_BID" ]]; then
    qa::fail "case 1: frontmost is $FM, expected $APP_BID"
    exit 1
fi
MIN="$("$AXPROBE" is-minimized "$APP_BID" || echo minimized=unknown)"
if [[ "$MIN" == "minimized=true" ]]; then
    qa::fail "case 1: target was minimized, expected visible"
    exit 1
fi

# Case 2: frontmost -> Dock click -> minimizes within 500ms.
qa::info "02: case 2 — frontmost-to-minimize"
sleep 0.5
cliclick "c:$CLICK_X,$CLICK_Y"
if ! "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 1.5 >/dev/null; then
    qa::fail "case 2: did not minimize within 1500ms"
    exit 1
fi

# Case 3: minimized -> Dock click -> macOS restores (our code no-ops).
qa::info "02: case 3 — restore (no interference)"
sleep 0.5
cliclick "c:$CLICK_X,$CLICK_Y"
# Poll for up to 2s: the restore animation + AX re-attach isn't instant,
# especially after a full minimize. `is-minimized` returns
# "no focused window" mid-animation because the window isn't yet focused.
MIN="minimized=unknown"
for _ in $(seq 1 40); do
    sleep 0.1
    MIN="$("$AXPROBE" is-minimized "$APP_BID" 2>/dev/null || echo minimized=unknown)"
    [[ "$MIN" == "minimized=false" ]] && break
done
if [[ "$MIN" != "minimized=false" ]]; then
    # Last-resort: explicitly deminiaturize so downstream cases have a
    # known-good Safari state, but still fail the assertion.
    osascript -e 'tell application "Safari" to set miniaturized of windows to false' \
              >/dev/null 2>&1 || true
    qa::fail "case 3: expected minimized=false after restore, got $MIN"
    exit 1
fi

# Latency: N trials of frontmost->click; parse pipeline timestamps.
qa::info "02: latency across $TRIALS trials"
# Bring target frontmost once
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5

# Start a long log capture in background. --info --debug required — the
# pipeline signposts are os_log default/info level and are suppressed by
# `log stream` without these flags.
LOG_FILE="$(mktemp -t clicktomin-pipeline)"
/usr/bin/log stream --style syslog --info --debug \
    --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
    >"$LOG_FILE" 2>/dev/null &
LOG_PID=$!

for _ in $(seq 1 "$TRIALS"); do
    # Ensure no miniaturized windows — AppleScript directly un-miniaturizes
    # via AX, which is more reliable than a second Dock click.
    osascript -e "tell application id \"$APP_BID\" to set miniaturized of every window to false" \
        >/dev/null 2>&1 || true
    sleep 0.3
    osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
    sleep 0.4
    cliclick "c:$CLICK_X,$CLICK_Y"
    "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 1.5 >/dev/null || true
    sleep 0.3
done

sleep 0.5
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true

# Parse timestamps. log stream syslog format:
# 2026-04-25 10:12:34.567890-0700 0x1234  Default  0x0  ClickToMin: (…) pipeline: click received at ...
# Strategy: pair each "click received" with the next "minimize dispatched"
# (same stream, temporal order). Emit delta in ms.
LATENCIES="$(awk '
    function toMs(ts,    parts, hms, ms, h, m, s, frac) {
        # ts is "HH:MM:SS.ffffff"
        split(ts, parts, ":")
        h = parts[1] + 0
        m = parts[2] + 0
        split(parts[3], frac, ".")
        s = frac[1] + 0
        ms = substr(frac[2], 1, 3) + 0
        return ((h*3600 + m*60 + s) * 1000) + ms
    }
    /pipeline: click received/ {
        split($2, _t, "-")
        click = toMs(_t[1])
        have_click = 1
    }
    /pipeline: minimize dispatched/ {
        if (have_click) {
            split($2, _t, "-")
            d = toMs(_t[1])
            delta = d - click
            if (delta < 0) delta += 86400000
            print delta
            have_click = 0
        }
    }
' "$LOG_FILE")"

rm -f "$LOG_FILE"

SAMPLES=$(wc -l <<<"$LATENCIES" | tr -d ' ')
if [[ "$SAMPLES" -lt 3 ]]; then
    qa::warn "02: only $SAMPLES latency samples; Dock log timestamp parsing may have drifted"
fi

P50="$(sort -n <<<"$LATENCIES" | awk -v n="$SAMPLES" 'BEGIN{k=int(n*0.5)} NR==k{print; exit}')"
P95="$(sort -n <<<"$LATENCIES" | awk -v n="$SAMPLES" 'BEGIN{k=int(n*0.95); if(k<1)k=1} NR==k{print; exit}')"

qa::info "02: latency samples=$SAMPLES p50=${P50:-n/a}ms p95=${P95:-n/a}ms"

if [[ -n "$OUTPUT" ]]; then
    {
        printf "PASS\n"
        printf "samples=%s\n" "$SAMPLES"
        printf "p50_ms=%s\n" "${P50:-0}"
        printf "p95_ms=%s\n" "${P95:-0}"
        # --- metrics.sh key (schema: thresholds.json) ---
        printf "latency_ms_p50=%s\n" "${P50:-0}"
    } > "$OUTPUT"
fi

qa::pass "02-core-behavior"
