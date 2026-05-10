#!/usr/bin/env bash
# qa/01-smoke.sh — CI-safe build / bundle / signature / plist + runtime signposts.
#
# Safe to run on a machine without Accessibility granted: the runtime-launch
# portion only asserts the lifecycle signposts that fire regardless of grant
# state (permission granted | awaiting permission).
#
# Usage: ./qa/01-smoke.sh [--output FILE]

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

cd "$PROJECT_ROOT"

qa::info "01-smoke: swift build -c release"
swift build -c release >/dev/null

qa::info "01-smoke: build.sh -> ClickToMin.app"
qa::build_release

qa::info "01-smoke: codesign verify"
codesign --verify --verbose "$PROJECT_ROOT/ClickToMin.app"

qa::info "01-smoke: plutil lint"
plutil -lint "$PROJECT_ROOT/Resources/Info.plist" >/dev/null

qa::info "01-smoke: launching + capturing 10s of signposts"
qa::launch_app
# Wait out the launch window, then read the *past* 15s of log events.
# `log stream` would miss the lifecycle signposts that fire during launch;
# `log show --last` catches them retroactively.
sleep 10
LOG_CAPTURE="$(qa::log_show_last "" 15)"
qa::quit_app
qa::assert_process_not_running ClickToMin

# Signpost assertions. "permission granted" fires when access is pre-granted;
# "permission missing, polling started" fires otherwise. Either is acceptable.
FAIL=0
if ! grep -Eq 'permission granted|permission missing, polling started' <<<"$LOG_CAPTURE"; then
    qa::fail "missing lifecycle signpost: permission granted / awaiting"
    FAIL=1
fi
# "monitor installed" signpost only fires when permission is granted;
# in ungranted-and-polling mode it's expected absent. Only assert if we
# saw permission granted.
if grep -q 'permission granted' <<<"$LOG_CAPTURE"; then
    if ! grep -q 'global click monitor installed' <<<"$LOG_CAPTURE"; then
        qa::fail "missing lifecycle signpost: global click monitor installed"
        FAIL=1
    fi
    if ! grep -q 'dock PID refreshed' <<<"$LOG_CAPTURE"; then
        qa::fail "missing lifecycle signpost: dock PID refreshed"
        FAIL=1
    fi
fi

if [[ -n "$OUTPUT" ]]; then
    if [[ "$FAIL" -eq 0 ]]; then
        printf "PASS\n" > "$OUTPUT"
    else
        printf "FAIL\n" > "$OUTPUT"
    fi
    printf "%s\n" "$LOG_CAPTURE" >> "$OUTPUT"
fi

if [[ "$FAIL" -eq 0 ]]; then
    qa::pass "01-smoke"
    exit 0
else
    qa::fail "01-smoke"
    exit 1
fi
