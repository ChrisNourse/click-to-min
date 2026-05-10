#!/usr/bin/env bash
# qa/verify-tap.sh — Local-only proof that the CGEventTap receives real events.
#
# Performs one real cliclick at a Dock tile, asserts minimize, writes a
# tap-proof.json attestation that CI can check for freshness.
#
# Requires: Accessibility granted to ClickToMin.app and axprobe; cliclick.
#
# Usage: ./qa/verify-tap.sh [--app BUNDLE_ID]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

APP_BID="${1:-com.apple.Safari}"
PROOF_FILE="$PROJECT_ROOT/qa/tap-proof.json"

qa::require_cliclick
qa::require_axprobe_granted
qa::build_release

AXPROBE="$(qa::axprobe_bin)"

open -gb "$APP_BID" || true
sleep 1

DOCK_FRAME="$("$AXPROBE" dock-item-frame "$APP_BID")"
eval "$DOCK_FRAME"
CLICK_X="$(awk -v x="$x" -v w="$w" 'BEGIN{printf "%d", x + w/2}')"
CLICK_Y="$(awk -v y="$y" -v h="$h" 'BEGIN{printf "%d", y + h/2}')"

qa::launch_app
trap 'qa::quit_app' EXIT

osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null
sleep 0.5

cliclick "c:$CLICK_X,$CLICK_Y"

if ! "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 3.0 >/dev/null; then
    qa::fail "verify-tap: real click did not minimize within 3s"
    exit 1
fi

SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")"
HOST="$(hostname -s 2>/dev/null || echo "unknown")"
TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

printf '{"verified":"%s","sha":"%s","host":"%s"}\n' "$TS" "$SHA" "$HOST" > "$PROOF_FILE"

qa::pass "verify-tap: real event tap works — proof written to qa/tap-proof.json"
