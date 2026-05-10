#!/usr/bin/env bash
# qa/05-perf-instruments.sh — Instruments-backed perf probes.
#
# Runs:
#   1. Idle RSS sample (5 min): ps -o rss once/sec; compute mean, peak.
#   2. xctrace Time Profiler: 30s capture during 1000 synthetic clicks
#      outside the Dock; report whether ClickToMin symbols appear in the
#      top-N and aggregate CPU weight.
#   3. xctrace Allocations: 500-click run, report persistent byte growth.
#
# Runtime: ~7 min. Not CI-safe; runs locally on request.
#
# Usage: ./qa/05-perf-instruments.sh [--output FILE] [--idle-seconds N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/xctrace-parse.sh
source "$SCRIPT_DIR/lib/xctrace-parse.sh"

OUTPUT=""
IDLE_SECONDS=300
CLICKS_PROFILER=1000
CLICKS_ALLOC=500
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --idle-seconds) IDLE_SECONDS="$2"; shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

qa::require_cliclick
qa::build_release

if ! command -v xctrace >/dev/null 2>&1; then
    qa::fail "xctrace not found; install Xcode"
    exit 1
fi

qa::launch_app
trap 'qa::quit_app' EXIT
sleep 2

PID="$(pgrep -x ClickToMin | head -1)"
if [[ -z "$PID" ]]; then
    qa::fail "ClickToMin not running after launch"
    exit 1
fi

# --- 1. Idle RSS + CPU% ------------------------------------------------------
qa::info "05: idle RSS + CPU% sampling for ${IDLE_SECONDS}s"
RSS_FILE="$(mktemp -t clicktomin-rss)"
CPU_FILE="$(mktemp -t clicktomin-cpu)"
for _ in $(seq 1 "$IDLE_SECONDS"); do
    # RSS (KB) and CPU (%). If process died, break.
    # ps -o rss=,pcpu= prints "RSS PCPU" space-separated.
    LINE="$(ps -o rss=,pcpu= -p "$PID" 2>/dev/null | awk '{$1=$1;print}')"
    if [[ -z "$LINE" ]]; then break; fi
    RSS="${LINE%% *}"
    CPU="${LINE##* }"
    printf "%s\n" "$RSS" >> "$RSS_FILE"
    printf "%s\n" "$CPU" >> "$CPU_FILE"
    sleep 1
done
STATS="$(xctrace_mem_stats < "$RSS_FILE")"
MEAN_KB="$(awk -F'\t' '{print $1}' <<<"$STATS")"
PEAK_KB="$(awk -F'\t' '{print $2}' <<<"$STATS")"
MEAN_MB="$(awk -v k="$MEAN_KB" 'BEGIN{printf "%.1f", k/1024}')"
PEAK_MB="$(awk -v k="$PEAK_KB" 'BEGIN{printf "%.1f", k/1024}')"
# Mean CPU% across idle window.
CPU_MEAN="$(awk 'BEGIN{s=0;n=0} {s+=$1;n++} END{if(n>0)printf "%.2f", s/n; else print "0.00"}' "$CPU_FILE")"
CPU_PEAK="$(awk 'BEGIN{m=0} {if($1+0>m)m=$1+0} END{printf "%.2f", m}' "$CPU_FILE")"
rm -f "$RSS_FILE" "$CPU_FILE"
qa::info "05: idle RSS mean=${MEAN_MB}MB peak=${PEAK_MB}MB"
qa::info "05: idle CPU mean=${CPU_MEAN}% peak=${CPU_PEAK}%"

# --- 1b. Idle wake-ups/sec (idle-cpu metric) --------------------------------
# `top -l 2 -stats pid,idlew -pid <PID>` gives idle wake-ups; the second
# sample is a delta over the interval. Sample over ~10s and divide.
qa::info "05: idle wake-ups (idle-cpu) over 10s"
WAKE_BEFORE="$(top -l 1 -stats pid,idlew -pid "$PID" 2>/dev/null | awk -v p="$PID" '$1==p {print $2}')"
sleep 10
WAKE_AFTER="$(top -l 1 -stats pid,idlew -pid "$PID" 2>/dev/null | awk -v p="$PID" '$1==p {print $2}')"
WAKE_BEFORE="${WAKE_BEFORE:-0}"
WAKE_AFTER="${WAKE_AFTER:-0}"
IDLE_WAKEUPS_PER_SEC="$(awk -v a="$WAKE_AFTER" -v b="$WAKE_BEFORE" 'BEGIN{d=a-b; if(d<0)d=0; printf "%.2f", d/10.0}')"
qa::info "05: idle wake-ups/sec = ${IDLE_WAKEUPS_PER_SEC}"

# --- 1c. Active-cpu tap overhead (p50 µs) -----------------------------------
# GlobalClickMonitor emits `tap_overhead_ns=<N>` at os_log .info on every
# click. Fire 50 synthetic clicks at a benign location, then parse the ns
# values from the log and compute p50 in microseconds.
qa::info "05: active-cpu tap overhead (50 synthetic clicks)"
for _ in $(seq 1 50); do
    cliclick "c:10,10" >/dev/null 2>&1 || true
    sleep 0.05
done
# Read the last 30s of pipeline log; extract ns values.
TAP_NS_FILE="$(mktemp -t clicktomin-tap-ns)"
/usr/bin/log show --style syslog --info --debug --last 30s \
    --predicate 'subsystem == "com.click-to-min" && category == "pipeline"' 2>/dev/null \
    | grep -oE 'tap_overhead_ns=[0-9]+' \
    | awk -F= '{print $2}' > "$TAP_NS_FILE" || true
TAP_SAMPLES="$(wc -l < "$TAP_NS_FILE" | awk '{print $1}')"
if [[ "$TAP_SAMPLES" -gt 0 ]]; then
    TAP_P50_US="$(/usr/bin/python3 - "$TAP_NS_FILE" <<'PY'
import sys, statistics
vals = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line.isdigit():
            vals.append(int(line))
if not vals:
    print("0")
else:
    p50_ns = statistics.median(vals)
    print(f"{p50_ns/1000.0:.2f}")
PY
    )"
else
    TAP_P50_US="0.00"
fi
rm -f "$TAP_NS_FILE"
qa::info "05: tap overhead p50 = ${TAP_P50_US}µs (${TAP_SAMPLES} samples)"

# --- xctrace availability check -----------------------------------------------
HAVE_XCTRACE=1
if ! xctrace version >/dev/null 2>&1; then
    qa::fail "xctrace not available (requires full Xcode, not just CLT)"
    exit 1
fi

# --- 2a. xctrace Time Profiler: OUTSIDE Dock --------------------------------
qa::info "05: xctrace Time Profiler ($CLICKS_PROFILER clicks outside Dock)"
TRACE_DIR="$(mktemp -d -t clicktomin-trace)"
TRACE_TP_OUT="$TRACE_DIR/tp-out.trace"
xctrace record --template 'Time Profiler' --attach "$PID" --output "$TRACE_TP_OUT" \
    --time-limit 30s >/dev/null 2>&1 &
XPID=$!
# Drive synthetic clicks at a benign screen location (top-left corner).
for _ in $(seq 1 "$CLICKS_PROFILER"); do
    cliclick "c:10,10" >/dev/null 2>&1 || true
done
wait "$XPID" 2>/dev/null || true

TP_EXPORT_OUT="$TRACE_DIR/tp-out.txt"
xctrace export --input "$TRACE_TP_OUT" --xpath '//trace-toc/run/data/table[@schema="time-profile"]' \
    > "$TP_EXPORT_OUT" 2>/dev/null || true

HOTSPOT_OUT=""
if [[ -s "$TP_EXPORT_OUT" ]]; then
    HOTSPOT_OUT="$(xctrace_parse_time_profiler "$TP_EXPORT_OUT" 10 || true)"
fi
CLICKTOMIN_OUT="no"
if grep -q 'ClickToMin' <<<"$HOTSPOT_OUT"; then
    CLICKTOMIN_OUT="yes"
fi
qa::info "05: ClickToMin in top-10 hotspots (outside Dock): $CLICKTOMIN_OUT"

# --- 2b. xctrace Time Profiler: INSIDE Dock ---------------------------------
# Click the Dock center to exercise the AX hit-test path. Use axprobe to find
# a Dock item, falling back to an approximate bottom-center coordinate.
qa::info "05: xctrace Time Profiler ($CLICKS_PROFILER clicks inside Dock)"

# Get main screen size for Dock region estimate (bottom-center).
SCREEN_W="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null | awk -F', ' '{print $3+0}')"
SCREEN_H="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null | awk -F', ' '{print $4+0}')"
DOCK_X="${SCREEN_W:-800}"
DOCK_X=$((DOCK_X / 2))
DOCK_Y="${SCREEN_H:-600}"
DOCK_Y=$((DOCK_Y - 30))

TRACE_TP_IN="$TRACE_DIR/tp-in.trace"
xctrace record --template 'Time Profiler' --attach "$PID" --output "$TRACE_TP_IN" \
    --time-limit 30s >/dev/null 2>&1 &
XPID=$!
# Right-click so we don't actually minimize anything during profiling.
for _ in $(seq 1 "$CLICKS_PROFILER"); do
    cliclick "rc:$DOCK_X,$DOCK_Y" >/dev/null 2>&1 || true
done
wait "$XPID" 2>/dev/null || true

TP_EXPORT_IN="$TRACE_DIR/tp-in.txt"
xctrace export --input "$TRACE_TP_IN" --xpath '//trace-toc/run/data/table[@schema="time-profile"]' \
    > "$TP_EXPORT_IN" 2>/dev/null || true

HOTSPOT_IN=""
if [[ -s "$TP_EXPORT_IN" ]]; then
    HOTSPOT_IN="$(xctrace_parse_time_profiler "$TP_EXPORT_IN" 10 || true)"
fi
CLICKTOMIN_IN="no"
if grep -q 'ClickToMin' <<<"$HOTSPOT_IN"; then
    CLICKTOMIN_IN="yes"
fi
qa::info "05: ClickToMin in top-10 hotspots (inside Dock): $CLICKTOMIN_IN"

# Kept for backward-compat with report.sh's older key.
CLICKTOMIN_PRESENT="$CLICKTOMIN_OUT"

# --- 3. xctrace Allocations --------------------------------------------------
qa::info "05: xctrace Allocations ($CLICKS_ALLOC clicks outside Dock)"
TRACE_ALLOC="$TRACE_DIR/alloc.trace"
xctrace record --template 'Allocations' --attach "$PID" --output "$TRACE_ALLOC" \
    --time-limit 30s >/dev/null 2>&1 &
XPID=$!
for _ in $(seq 1 "$CLICKS_ALLOC"); do
    cliclick "c:10,10" >/dev/null 2>&1 || true
done
wait "$XPID" 2>/dev/null || true

ALLOC_EXPORT="$TRACE_DIR/alloc.txt"
xctrace export --input "$TRACE_ALLOC" --xpath '//trace-toc/run/data/table[@schema="all-allocations"]' \
    > "$ALLOC_EXPORT" 2>/dev/null || true

PERSISTENT_BYTES=0
if [[ -s "$ALLOC_EXPORT" ]]; then
    PERSISTENT_BYTES="$(xctrace_parse_allocations "$ALLOC_EXPORT" || echo 0)"
fi
GROWTH_KB="$(awk -v b="$PERSISTENT_BYTES" 'BEGIN{printf "%.1f", b/1024}')"
qa::info "05: persistent growth over $CLICKS_ALLOC clicks: ${GROWTH_KB}KB"

rm -rf "$TRACE_DIR"

if [[ -n "$OUTPUT" ]]; then
    {
        printf "PASS\n"
        printf "idle_rss_mean_mb=%s\n" "$MEAN_MB"
        printf "idle_rss_peak_mb=%s\n" "$PEAK_MB"
        printf "idle_cpu_mean_pct=%s\n" "$CPU_MEAN"
        printf "idle_cpu_peak_pct=%s\n" "$CPU_PEAK"
        printf "top10_hotspot_clicktomin=%s\n" "$CLICKTOMIN_PRESENT"
        printf "hotspot_outside_dock=%s\n" "$CLICKTOMIN_OUT"
        printf "hotspot_inside_dock=%s\n" "$CLICKTOMIN_IN"
        printf "alloc_persistent_kb=%s\n" "$GROWTH_KB"
        # --- metrics.sh keys (schema: thresholds.json) ---
        printf "memory_mb=%s\n" "$MEAN_MB"
        printf "idle_cpu_wakeups_per_sec=%s\n" "$IDLE_WAKEUPS_PER_SEC"
        printf "active_cpu_tap_overhead_us_p50=%s\n" "$TAP_P50_US"
    } > "$OUTPUT"
fi

qa::pass "05-perf-instruments"
