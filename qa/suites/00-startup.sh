#!/usr/bin/env bash
# qa/00-startup.sh — cold-launch startup-time metric.
#
# Measures elapsed time from `open ClickToMin.app` (t0) to the first
# lifecycle signpost emitted by the app (t1). Repeats N times cold and
# reports the median in milliseconds.
#
# A "cold" launch = no ClickToMin process running. We force-quit before
# each trial and sleep a beat so macOS evicts any warm file-backed mmap
# pages.
#
# Timing strategy: start `log stream` in background BEFORE `open` so the
# first signpost ends up in the stream with its native wall-clock
# timestamp. Parse that timestamp and compute (signpost_ts - open_ts) *
# 1000. Using `log show` after-the-fact is unreliable because its
# --last/--start windows can pull in signposts from earlier suite runs.
#
# Thresholds (moderate policy, qa/metrics/thresholds.json):
#   green  < 1000 ms
#   orange 1000..2000 ms
#   red    > 2000 ms
#
# Usage: ./qa/00-startup.sh [--trials N] [--emit FILE | --output FILE]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TRIALS=5
EMIT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --trials) TRIALS="$2"; shift 2 ;;
        --emit)   EMIT="$2";   shift 2 ;;
        --output) EMIT="$2";   shift 2 ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"

if [[ ! -d "$PROJECT_ROOT/ClickToMin.app" ]]; then
    qa::fail "00-startup: ClickToMin.app missing — run build first"
    exit 1
fi

qa::info "00-startup: $TRIALS cold launches"

# Kill any lingering instance so trial 1 is actually cold.
if pgrep -x ClickToMin >/dev/null 2>&1; then
    osascript -e 'tell application "ClickToMin" to quit' >/dev/null 2>&1 || true
    sleep 0.5
    pkill -x ClickToMin 2>/dev/null || true
    sleep 0.5
fi

SAMPLES=()
for trial in $(seq 1 "$TRIALS"); do
    # Confirm cold state.
    pkill -x ClickToMin 2>/dev/null || true
    sleep 0.5

    # Start log stream BEFORE open so the signpost is captured with its
    # authoritative wall-clock timestamp. `--info --debug` is required
    # because our lifecycle signposts are os_log .info level.
    STREAM_FILE="$(mktemp -t clicktomin-startup)"
    /usr/bin/log stream --style syslog --info --debug \
        --predicate 'subsystem == "com.click-to-min" && category == "lifecycle"' \
        >"$STREAM_FILE" 2>/dev/null &
    STREAM_PID=$!
    # Give log stream a moment to attach (otherwise it can miss the very
    # first signpost that fires in the first ~100ms after open).
    sleep 0.3

    # t0: wall-clock epoch float seconds, matched against the log line's
    # own `%Y-%m-%d %H:%M:%S.%f%z` stamp below.
    T0="$(/usr/bin/python3 -c 'import time; print(time.time())')"
    open "$PROJECT_ROOT/ClickToMin.app"

    # Poll the stream file for up to 5s looking for a lifecycle signpost
    # timestamped >= t0.
    t1_ms=""
    for _ in $(seq 1 50); do
        sleep 0.1
        if grep -Eq 'permission (granted|missing, polling started)' "$STREAM_FILE"; then
            # Parse the first matching line's timestamp.
            LINE="$(grep -E 'permission (granted|missing, polling started)' "$STREAM_FILE" | head -1)"
            t1_ms="$(/usr/bin/python3 - "$T0" "$LINE" <<'PY'
import sys, re, datetime
t0 = float(sys.argv[1])
line = sys.argv[2]
# Match the leading syslog-style timestamp: "2026-04-25 22:34:57.123456-0700"
m = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+[+-]\d{4})', line)
if not m:
    print("PARSE_FAIL")
    sys.exit(0)
ts = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f%z").timestamp()
delta_ms = int((ts - t0) * 1000)
print(delta_ms)
PY
)"
            break
        fi
    done

    kill "$STREAM_PID" 2>/dev/null || true
    wait "$STREAM_PID" 2>/dev/null || true
    rm -f "$STREAM_FILE"

    if [[ -z "$t1_ms" || "$t1_ms" == "PARSE_FAIL" ]]; then
        qa::fail "00-startup: trial $trial — no valid lifecycle signpost within 5s"
        exit 1
    fi
    if [[ "$t1_ms" -lt 0 ]]; then
        qa::warn "00-startup: trial $trial — negative delta ($t1_ms ms), clamping to 0"
        t1_ms=0
    fi

    qa::info "00-startup: trial $trial — ${t1_ms} ms"
    SAMPLES+=("$t1_ms")

    # Tear down for next cold trial.
    osascript -e 'tell application "ClickToMin" to quit' >/dev/null 2>&1 || true
    sleep 0.4
    pkill -x ClickToMin 2>/dev/null || true
    sleep 0.4
done

# Median.
MEDIAN_MS="$(printf "%s\n" "${SAMPLES[@]}" | sort -n | awk -v n="${#SAMPLES[@]}" '
    { a[NR]=$1 }
    END {
        if (n % 2) { print a[(n+1)/2] }
        else       { printf "%d\n", (a[n/2] + a[n/2+1]) / 2 }
    }
')"

qa::pass "00-startup: median ${MEDIAN_MS} ms over $TRIALS cold launches"

if [[ -n "$EMIT" ]]; then
    printf "startup_ms=%s\n" "$MEDIAN_MS" >> "$EMIT"
fi

exit 0
