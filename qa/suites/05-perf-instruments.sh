#!/usr/bin/env bash
# qa/05-perf-instruments.sh — performance probes (no Xcode required).
#
# Measures:
#   1. Idle RSS + CPU% (5 min sample via ps)
#   2. Idle wake-ups/sec (via top)
#   3. Active-CPU tap overhead p50 (via os_log instrumentation)
#
# Runtime: ~5.5 min. Not CI-safe (needs Accessibility).
#
# Usage: ./qa/suites/05-perf-instruments.sh [--output FILE] [--idle-seconds N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OUTPUT=""
IDLE_SECONDS=300
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --idle-seconds) IDLE_SECONDS="$2"; shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

qa::require_cliclick
qa::build_release

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
    LINE="$(ps -o rss=,pcpu= -p "$PID" 2>/dev/null | awk '{$1=$1;print}')"
    if [[ -z "$LINE" ]]; then break; fi
    RSS="${LINE%% *}"
    CPU="${LINE##* }"
    printf "%s\n" "$RSS" >> "$RSS_FILE"
    printf "%s\n" "$CPU" >> "$CPU_FILE"
    sleep 1
done
MEAN_KB="$(awk 'BEGIN{s=0;n=0} {s+=$1;n++} END{if(n>0)printf "%d", s/n; else print "0"}' "$RSS_FILE")"
PEAK_KB="$(awk 'BEGIN{m=0} {if($1+0>m)m=$1+0} END{printf "%d", m}' "$RSS_FILE")"
MEAN_MB="$(awk -v k="$MEAN_KB" 'BEGIN{printf "%.1f", k/1024}')"
PEAK_MB="$(awk -v k="$PEAK_KB" 'BEGIN{printf "%.1f", k/1024}')"
CPU_MEAN="$(awk 'BEGIN{s=0;n=0} {s+=$1;n++} END{if(n>0)printf "%.2f", s/n; else print "0.00"}' "$CPU_FILE")"
CPU_PEAK="$(awk 'BEGIN{m=0} {if($1+0>m)m=$1+0} END{printf "%.2f", m}' "$CPU_FILE")"
rm -f "$RSS_FILE" "$CPU_FILE"
qa::info "05: idle RSS mean=${MEAN_MB}MB peak=${PEAK_MB}MB"
qa::info "05: idle CPU mean=${CPU_MEAN}% peak=${CPU_PEAK}%"

# --- 2. Idle wake-ups/sec ----------------------------------------------------
qa::info "05: idle wake-ups (idle-cpu) over 10s"
WAKE_BEFORE="$(top -l 1 -stats pid,idlew -pid "$PID" 2>/dev/null | awk -v p="$PID" '$1==p {print $2}')"
sleep 10
WAKE_AFTER="$(top -l 1 -stats pid,idlew -pid "$PID" 2>/dev/null | awk -v p="$PID" '$1==p {print $2}')"
WAKE_BEFORE="${WAKE_BEFORE:-0}"
WAKE_AFTER="${WAKE_AFTER:-0}"
IDLE_WAKEUPS_PER_SEC="$(awk -v a="$WAKE_AFTER" -v b="$WAKE_BEFORE" 'BEGIN{d=a-b; if(d<0)d=0; printf "%.2f", d/10.0}')"
qa::info "05: idle wake-ups/sec = ${IDLE_WAKEUPS_PER_SEC}"

# --- 3. Active-CPU tap overhead (p50 µs) --------------------------------------
qa::info "05: active-cpu tap overhead (50 synthetic clicks)"
for _ in $(seq 1 50); do
    cliclick "c:10,10" >/dev/null 2>&1 || true
    sleep 0.05
done
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

# --- Output -------------------------------------------------------------------
if [[ -n "$OUTPUT" ]]; then
    {
        printf "PASS\n"
        printf "idle_rss_mean_mb=%s\n" "$MEAN_MB"
        printf "idle_rss_peak_mb=%s\n" "$PEAK_MB"
        printf "idle_cpu_mean_pct=%s\n" "$CPU_MEAN"
        printf "idle_cpu_peak_pct=%s\n" "$CPU_PEAK"
        printf "memory_mb=%s\n" "$MEAN_MB"
        printf "idle_cpu_wakeups_per_sec=%s\n" "$IDLE_WAKEUPS_PER_SEC"
        printf "active_cpu_tap_overhead_us_p50=%s\n" "$TAP_P50_US"
    } > "$OUTPUT"
fi

qa::pass "05-perf-instruments"
