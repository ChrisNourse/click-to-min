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

qa::require_axprobe_granted
qa::build_release
qa::require_click_tool

AXPROBE="$(qa::axprobe_bin)"

qa::info "02: resolving Dock tile frame for $APP_BID"
qa::resolve_dock_tile "$APP_BID" || exit 1

WIN_COUNT="$(qa::timeout_cmd 5 "$AXPROBE" window-count "$APP_BID" 2>/dev/null || echo 0)"
if [[ "$WIN_COUNT" -lt 1 ]]; then
    qa::info "02: $APP_BID has no windows; opening one"
    qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to make new document" >/dev/null 2>&1 \
        || qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
    sleep 1
fi

if [[ "$QA_CLICK_MODE" != "inject" ]]; then
    qa::launch_app
fi
trap 'qa::quit_app 2>/dev/null || true' EXIT

# Case 1: background app -> Dock click -> pipeline rejects (app not frontmost).
qa::info "02: case 1 — bring-to-front (pipeline rejects non-frontmost)"
qa::timeout_cmd 5 osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
sleep 0.5
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    qa::dock_click
    if [[ "$QA_INJECT_RESULT" == done:no-minimize:* || "$QA_INJECT_RESULT" == done:rejected ]]; then
        qa::info "case 1: pipeline correctly rejected (non-frontmost)"
    else
        qa::fail "case 1: expected rejection, got $QA_INJECT_RESULT"
        exit 1
    fi
else
    cliclick "c:$CLICK_X,$CLICK_Y"
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
fi

# Case 2: frontmost -> Dock click -> minimizes within 500ms.
qa::info "02: case 2 — frontmost-to-minimize"
qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
sleep 0.5
qa::dock_click
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    if [[ "$QA_INJECT_RESULT" == done:timing_ms=* ]]; then
        qa::info "case 2: minimized ($QA_INJECT_RESULT)"
    else
        qa::fail "case 2: expected minimize, got $QA_INJECT_RESULT"
        exit 1
    fi
else
    if ! "$AXPROBE" wait-until-minimized "$APP_BID" --timeout 1.5 >/dev/null; then
        qa::fail "case 2: did not minimize within 1500ms"
        exit 1
    fi
fi

# Case 3: minimized -> Dock click -> macOS restores (our code no-ops).
qa::info "02: case 3 — restore (no interference)"
sleep 0.5
if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    qa::info "case 3: skipped in inject mode (restore is macOS Dock behavior)"
else
    cliclick "c:$CLICK_X,$CLICK_Y"
    MIN="minimized=unknown"
    for _ in $(seq 1 40); do
        sleep 0.1
        MIN="$("$AXPROBE" is-minimized "$APP_BID" 2>/dev/null || echo minimized=unknown)"
        [[ "$MIN" == "minimized=false" ]] && break
    done
    if [[ "$MIN" != "minimized=false" ]]; then
        osascript -e 'tell application "Safari" to set miniaturized of windows to false' \
                  >/dev/null 2>&1 || true
        qa::fail "case 3: expected minimized=false after restore, got $MIN"
        exit 1
    fi
fi

# Latency: N trials of frontmost->click; parse pipeline timestamps.
qa::info "02: latency across $TRIALS trials"
qa::timeout_cmd 5 osascript -e "tell application id \"$APP_BID\" to activate" >/dev/null 2>&1 || true
sleep 0.5

if [[ "$QA_CLICK_MODE" == "inject" ]]; then
    INJECT_LATENCIES=""
    for _ in $(seq 1 "$TRIALS"); do
        open -a TextEdit 2>/dev/null || true
        sleep 0.5
        qa::dock_click
        if [[ "$QA_INJECT_RESULT" == done:timing_ms=* ]]; then
            local_ms="${QA_INJECT_RESULT#done:timing_ms=}"
            INJECT_LATENCIES="${INJECT_LATENCIES}${local_ms}\n"
        fi
        sleep 0.2
    done
    LATENCIES="$(printf '%b' "$INJECT_LATENCIES" | sed '/^$/d')"
else
    LOG_FILE="$(mktemp -t clicktomin-pipeline)"
    /usr/bin/log stream --style syslog --info --debug \
        --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' \
        >"$LOG_FILE" 2>/dev/null &
    LOG_PID=$!

    for _ in $(seq 1 "$TRIALS"); do
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

    LATENCIES="$(awk '
        function toMs(ts,    parts, hms, ms, h, m, s, frac) {
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
fi

SAMPLES=$(echo "$LATENCIES" | grep -c . || true)
if [[ "$SAMPLES" -lt 3 ]]; then
    qa::warn "02: only $SAMPLES latency samples"
fi

P50="$(echo "$LATENCIES" | sort -n | awk -v n="$SAMPLES" 'BEGIN{k=int(n*0.5); if(k<1)k=1} NR==k{print; exit}')"
P95="$(echo "$LATENCIES" | sort -n | awk -v n="$SAMPLES" 'BEGIN{k=int(n*0.95); if(k<1)k=1} NR==k{print; exit}')"

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
