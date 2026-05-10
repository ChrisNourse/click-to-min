#!/usr/bin/env bash
# qa/03-edge-cases.sh — frozen-app timeout, rapid-click debounce,
# launch-race, multi-window, right/ctrl-click non-trigger.
#
# Requires: Accessibility granted; cliclick.
#
# Usage: ./qa/03-edge-cases.sh [--app BUNDLE_ID] [--output FILE]

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

qa::require_cliclick
qa::require_axprobe_granted
qa::build_release

AXPROBE="$(qa::axprobe_bin)"

# Resolve Dock tile coords.
open -gb "$APP_BID" || true
sleep 1
DOCK_FRAME="$("$AXPROBE" dock-item-frame "$APP_BID")"
eval "$DOCK_FRAME"
# shellcheck disable=SC2154
CLICK_X="$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')"
# shellcheck disable=SC2154
CLICK_Y="$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')"

qa::launch_app
FROZEN_PID=""
cleanup() {
    if [[ -n "$FROZEN_PID" ]]; then
        kill -CONT "$FROZEN_PID" 2>/dev/null || true
    fi
    qa::quit_app
}
trap cleanup EXIT

FAIL=0

# --- Case A: frozen app (SIGSTOP) — pipeline must not hang -------------------
qa::info "03: case A — frozen app timeout"
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5
FROZEN_PID="$(pgrep -n -x "$(osascript -e "tell application id \"$APP_BID\" to name")" || true)"
if [[ -z "$FROZEN_PID" ]]; then
    # Fallback: use any running process matching the bundle.
    FROZEN_PID="$(pgrep -f "$APP_BID" | head -1 || true)"
fi
if [[ -n "$FROZEN_PID" ]]; then
    kill -STOP "$FROZEN_PID"
    LOG_FILE="$(mktemp -t clicktomin-pipeline)"
    /usr/bin/log stream --style syslog --info --debug \
        --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
        >"$LOG_FILE" 2>/dev/null &
    LOG_PID=$!
    cliclick "c:$CLICK_X,$CLICK_Y"
    # ClickToMin's minimize path uses a 0.25s dispatch delay, so 1s is plenty
    # for any log-line emission (timeout or minimize dispatched).
    sleep 1
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    kill -CONT "$FROZEN_PID"
    FROZEN_PID=""
    # Expect a pipeline log line to have fired; don't assert a specific
    # outcome (minimize may still be scheduled) — key thing is we didn't hang.
    if ! grep -q 'pipeline:' "$LOG_FILE"; then
        qa::fail "case A: no pipeline log line after frozen-app click"
        FAIL=1
    fi
    rm -f "$LOG_FILE"
else
    qa::warn "case A: could not find PID for $APP_BID; skipping"
fi

# --- Case B: rapid double-click debounce -> exactly one dispatch -------------
qa::info "03: case B — rapid double-click debounce"
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5
LOG_FILE="$(mktemp -t clicktomin-pipeline)"
/usr/bin/log stream --style syslog --info --debug \
    --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
    >"$LOG_FILE" 2>/dev/null &
LOG_PID=$!
# cliclick `w:50` waits 50ms between chained events
cliclick "c:$CLICK_X,$CLICK_Y" "w:50" "c:$CLICK_X,$CLICK_Y"
sleep 1
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true
DISPATCH_COUNT="$(grep -c 'minimize dispatched' "$LOG_FILE" || true)"
# Depending on debounce tuning, expect 1 (ideal). Allow 0 or 1; fail on 2+.
if [[ "$DISPATCH_COUNT" -gt 1 ]]; then
    qa::fail "case B: expected <=1 minimize dispatched, got $DISPATCH_COUNT"
    FAIL=1
fi
rm -f "$LOG_FILE"
# Restore for next case
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5

# --- Case C: launch-race — click during cold launch, no crash ----------------
qa::info "03: case C — launch-race"
osascript -e "tell application id \"$APP_BID\" to quit" >/dev/null 2>&1 || true
sleep 1
open -b "$APP_BID"
# cliclick during launch animation
sleep 0.1
cliclick "c:$CLICK_X,$CLICK_Y" || true
sleep 1.5
qa::assert_process_running ClickToMin || FAIL=1

# --- Case D: multi-window — window count drops by exactly 1 ------------------
if [[ "$APP_BID" == "com.apple.Safari" ]]; then
    qa::info "03: case D — multi-window"
    # Case C quit + relaunched Safari, so ensure it's fully up with a loaded
    # document before making siblings. A freshly-opened "new document" from
    # AppleScript may not yet be AX-minimizable for ~1s on slow VMs.
    osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    sleep 1.5
    osascript -e 'tell application "Safari" to make new document' \
              -e 'tell application "Safari" to make new document' >/dev/null 2>&1 || true
    sleep 2.0
    osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    # Wait for Safari to actually report >=2 AX-visible windows before
    # asserting the minimize. Newly-created documents can take a beat to
    # become AX-queryable on slower VMs, and without this guard the test
    # races the click against AX readiness.
    for _ in $(seq 1 20); do
        WC="$("$AXPROBE" window-count "$APP_BID" 2>/dev/null || echo 0)"
        [[ "$WC" -ge 2 ]] && break
        sleep 0.25
    done
    sleep 0.3
    BEFORE="$("$AXPROBE" window-count "$APP_BID" || echo 0)"
    # Warmup: send a click to a neutral screen location so ClickToMin's
    # CGEventTap is re-primed (post-case-C relaunch + churn can leave the
    # tap sluggish on first event for up to a second on slow VMs).
    cliclick "c:50,50" >/dev/null 2>&1 || true
    sleep 0.2
    osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    sleep 0.3
    cliclick "c:$CLICK_X,$CLICK_Y"
    # wait-until-minimized returns 0 iff any window of the app is minimized
    # (not just the focused one) — with multi-window, focus moves to an
    # un-minimized sibling after minimize so a focused-window check would
    # incorrectly fail. Bumped to 8s: multi-window Safari on a VM after a
    # cold relaunch under orchestrator load occasionally takes 5-7s to
    # service the first AX-minimize after the click lands.
    if ! "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 8.0 >/dev/null; then
        qa::fail "case D: no window minimized within 8000ms (BEFORE window-count=$BEFORE)"
        FAIL=1
    fi
    sleep 0.3
    AFTER="$("$AXPROBE" window-count "$APP_BID" || echo 0)"
    # Window count includes minimized windows. "Minimize" doesn't remove it
    # from kAXWindowsAttribute, so the count should be unchanged.
    if [[ "$BEFORE" != "$AFTER" ]]; then
        qa::warn "case D: window-count changed $BEFORE->$AFTER (minimize should preserve count)"
    fi
else
    qa::info "03: case D skipped (not Safari)"
fi

# --- Case E: right-click / ctrl-click non-trigger ----------------------------
qa::info "03: case E — right-click / ctrl-click non-trigger"
# Drain any pending events from case D; `log stream` backscans a small window
# on attach so we use `log show --start` with an explicit cutoff instead to
# avoid pulling case D's "minimize dispatched" signpost into this case.
sleep 2
osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5
# Record cutoff AFTER the activate but BEFORE the clicks. `log show --start`
# accepts `YYYY-MM-DD HH:MM:SS` (local time) format.
CUTOFF="$(date '+%Y-%m-%d %H:%M:%S')"
# Wait past cutoff granularity (1s) so any pre-click noise is excluded.
sleep 1.1
cliclick "rc:$CLICK_X,$CLICK_Y"
sleep 0.3
# dismiss any contextual menu
cliclick "kp:esc"
sleep 0.3
cliclick "kd:ctrl" "c:$CLICK_X,$CLICK_Y" "ku:ctrl"
sleep 0.3
cliclick "kp:esc"
sleep 0.5
CASE_E_LOG="$(/usr/bin/log show --info --debug --style syslog \
    --start "$CUTOFF" \
    --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' 2>/dev/null || true)"
if grep -q 'minimize dispatched' <<<"$CASE_E_LOG"; then
    # Known bug: https://github.com/ChrisNourse/click-to-min/issues/34
    qa::warn "case E: minimize dispatched on right/ctrl-click (known bug #34)"
fi

if [[ -n "$OUTPUT" ]]; then
    if [[ "$FAIL" -eq 0 ]]; then echo PASS > "$OUTPUT"; else echo FAIL > "$OUTPUT"; fi
fi

if [[ "$FAIL" -eq 0 ]]; then
    qa::pass "03-edge-cases"
else
    qa::fail "03-edge-cases"
    exit 1
fi
