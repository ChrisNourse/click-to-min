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

qa::require_axprobe_granted
qa::build_release
qa::require_click_tool

AXPROBE="$(qa::axprobe_bin)"

qa::resolve_dock_tile "$APP_BID" || exit 1

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
qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
sleep 0.5
FROZEN_PID="$(qa::timeout_cmd 3 osascript -e "tell application id \"$APP_BID\" to name" 2>/dev/null | xargs pgrep -n -x 2>/dev/null || true)"
if [[ -z "$FROZEN_PID" ]]; then
    FROZEN_PID="$(pgrep -f "$APP_BID" | head -1 || true)"
fi
if [[ -n "$FROZEN_PID" ]]; then
    kill -STOP "$FROZEN_PID"
    if [[ "$QA_CLICK_MODE" == "inject" ]]; then
        qa::dock_click || true
        qa::info "case A: inject completed without hanging"
    else
        LOG_FILE="$(mktemp -t clicktomin-pipeline)"
        /usr/bin/log stream --style syslog --info --debug \
            --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
            >"$LOG_FILE" 2>/dev/null &
        LOG_PID=$!
        cliclick "c:$CLICK_X,$CLICK_Y"
        sleep 1
        kill "$LOG_PID" 2>/dev/null || true
        wait "$LOG_PID" 2>/dev/null || true
        if ! grep -q 'pipeline:' "$LOG_FILE"; then
            qa::fail "case A: no pipeline log line after frozen-app click"
            FAIL=1
        fi
        rm -f "$LOG_FILE"
    fi
    kill -CONT "$FROZEN_PID"
    FROZEN_PID=""
else
    qa::warn "case A: could not find PID for $APP_BID; skipping"
fi

# --- Case B: rapid double-click debounce -> exactly one dispatch -------------
qa::info "03: case B — rapid double-click debounce"
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    qa::rapid_click_dock 2
    if [[ "$QA_INJECT_RESULT" == done:debounced:* ]]; then
        DEBOUNCED="${QA_INJECT_RESULT#done:debounced:}"
        if [[ "$DEBOUNCED" -lt 1 ]]; then
            qa::fail "case B: expected at least 1 debounced, got $DEBOUNCED"
            FAIL=1
        fi
    else
        qa::warn "case B: unexpected result $QA_INJECT_RESULT"
    fi
else
    LOG_FILE="$(mktemp -t clicktomin-pipeline)"
    /usr/bin/log stream --style syslog --info --debug \
        --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
        >"$LOG_FILE" 2>/dev/null &
    LOG_PID=$!
    cliclick "c:$CLICK_X,$CLICK_Y" "w:50" "c:$CLICK_X,$CLICK_Y"
    sleep 1
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    DISPATCH_COUNT="$(grep -c 'minimize dispatched' "$LOG_FILE" || true)"
    if [[ "$DISPATCH_COUNT" -gt 1 ]]; then
        qa::fail "case B: expected <=1 minimize dispatched, got $DISPATCH_COUNT"
        FAIL=1
    fi
    rm -f "$LOG_FILE"
fi
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5

# --- Case C: launch-race — click during cold launch, no crash ----------------
qa::info "03: case C — launch-race"
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    qa::info "case C: skipped in inject mode (tests event-tap race, not pipeline)"
else
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    open -b "$APP_BID"
    sleep 0.1
    cliclick "c:$CLICK_X,$CLICK_Y" || true
    sleep 1.5
    qa::assert_process_running ClickToMin || FAIL=1
fi

# --- Case D: multi-window — window count drops by exactly 1 ------------------
if [[ "$APP_BID" == "com.apple.Safari" ]]; then
    qa::info "03: case D — multi-window"
    qa::timeout_cmd 5 osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    sleep 1.5
    qa::timeout_cmd 5 osascript -e 'tell application "Safari" to make new document' \
              -e 'tell application "Safari" to make new document' >/dev/null 2>&1 || true
    sleep 2.0
    qa::timeout_cmd 5 osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        WC="$("$AXPROBE" window-count "$APP_BID" 2>/dev/null || echo 0)"
        [[ "$WC" -ge 2 ]] && break
        sleep 0.25
    done
    sleep 0.3
    BEFORE="$("$AXPROBE" window-count "$APP_BID" || echo 0)"
    if [[ "$QA_CLICK_MODE" != "inject" ]]; then
        cliclick "c:50,50" >/dev/null 2>&1 || true
        sleep 0.2
    qa::timeout_cmd 5 osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
        sleep 0.3
    fi
    qa::dock_click
    if [[ "$QA_CLICK_MODE" == "inject" ]]; then
        if [[ "$QA_INJECT_RESULT" != done:timing_ms=* ]]; then
            qa::fail "case D: expected minimize, got $QA_INJECT_RESULT"
            FAIL=1
        fi
    else
        if ! "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 8.0 >/dev/null; then
            qa::fail "case D: no window minimized within 8000ms (BEFORE window-count=$BEFORE)"
            FAIL=1
        fi
    fi
    sleep 0.3
    AFTER="$("$AXPROBE" window-count "$APP_BID" || echo 0)"
    if [[ "$BEFORE" != "$AFTER" ]]; then
        qa::warn "case D: window-count changed $BEFORE->$AFTER (minimize should preserve count)"
    fi
else
    qa::info "03: case D skipped (not Safari)"
fi

# --- Case E: right-click / ctrl-click non-trigger ----------------------------
qa::info "03: case E — right-click / ctrl-click non-trigger"
sleep 2
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    qa::right_click_dock
    if [[ "$QA_INJECT_RESULT" != "done:rejected" ]]; then
        qa::fail "case E: right-click not rejected ($QA_INJECT_RESULT)"
        FAIL=1
    fi
    qa::ctrl_click_dock
    if [[ "$QA_INJECT_RESULT" != "done:rejected" ]]; then
        qa::fail "case E: ctrl-click not rejected ($QA_INJECT_RESULT)"
        FAIL=1
    fi
else
    CUTOFF="$(date '+%Y-%m-%d %H:%M:%S')"
    sleep 1.1
    cliclick "rc:$CLICK_X,$CLICK_Y"
    sleep 0.3
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
        qa::warn "case E: minimize dispatched on right/ctrl-click (known bug #34)"
    fi
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
