#!/usr/bin/env bash
# scripts/ci-integration-test.sh — CI integration test using --test-click.
#
# Tests the full ClickToMin pipeline by injecting a click at the Dock tile
# coordinates for a target app. Verifies the window actually minimizes.
#
# Requires: ClickToMin.app built, AXProbe built, TCC grants applied.
#
# Usage: scripts/ci-integration-test.sh [--app BUNDLE_ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_BID="${1:-com.apple.TextEdit}"
AXPROBE="$(swift build -c release --package-path "$PROJECT_ROOT/qa/harness/AXProbe" --show-bin-path)/axprobe"
APP_BUNDLE="$PROJECT_ROOT/ClickToMin.app"
RESULT_FILE="/tmp/clicktomin-test-result.txt"

echo "=== CI Integration Test ==="
echo "Target: $APP_BID"
echo "AXProbe: $AXPROBE"
echo ""

pkill -x ClickToMin 2>/dev/null || true
sleep 1

open -a "$(echo "$APP_BID" | sed 's/com.apple.//')" 2>/dev/null || open -b "$APP_BID" 2>/dev/null || true
sleep 2

FRAME=$("$AXPROBE" dock-item-frame "$APP_BID" 2>&1) || { echo "FAIL: dock-item-frame failed: $FRAME"; exit 1; }
echo "Dock frame: $FRAME"
eval "$FRAME"
CX=$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')
CY=$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')
echo "Click target: ($CX, $CY)"

osascript -e "tell application id \"$APP_BID\" to activate" 2>/dev/null || true
sleep 1
FM=$("$AXPROBE" frontmost-bundle-id 2>/dev/null || echo "unknown")
echo "Frontmost: $FM"

rm -f "$RESULT_FILE"
"$APP_BUNDLE/Contents/MacOS/ClickToMin" --test-click "$CX,$CY" &
CTMPID=$!
echo "Launched ClickToMin (PID $CTMPID) with --test-click $CX,$CY"

sleep 2
RESULT=$(cat "$RESULT_FILE" 2>/dev/null || echo "no-result-file")
echo "Result: $RESULT"

if [[ "$RESULT" == error:* ]]; then
    echo "FAIL: $RESULT"
    kill "$CTMPID" 2>/dev/null || true
    exit 1
fi

if "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 5; then
    echo "PASS: Window minimized via --test-click"
    kill "$CTMPID" 2>/dev/null || true
    exit 0
else
    echo "FAIL: Window did not minimize within 5s"
    echo "  window-count: $("$AXPROBE" window-count "$APP_BID" 2>&1 || true)"
    echo "  is-minimized: $("$AXPROBE" is-minimized "$APP_BID" 2>&1 || true)"
    kill "$CTMPID" 2>/dev/null || true
    exit 1
fi
