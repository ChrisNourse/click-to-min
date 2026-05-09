#!/usr/bin/env bash
# qa/run-all.sh — orchestrator for ClickToMin QA suites.
#
# Runs the selected suites sequentially, captures per-suite logs, writes a
# timestamped markdown summary to qa/reports/<ts>.md, and emits performance
# metrics to qa/metrics/history.jsonl + renders shields.io badge JSON. When
# CLICKTOMIN_BADGE_GIST_ID/TOKEN are set, also pushes the badges to a Gist
# so the README badges go live.
#
# Usage:
#   ./qa/run-all.sh              full local run (00..05)
#   ./qa/run-all.sh --ci         CI-safe subset (01 only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/report.sh
source "$SCRIPT_DIR/lib/report.sh"
# shellcheck source=lib/metrics.sh
source "$SCRIPT_DIR/lib/metrics.sh"

MODE="FULL"
LOG_FILE=""
REPAIR_TOOLCHAIN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci) MODE="CI-SUBSET"; shift ;;
        --log-file) LOG_FILE="$2"; shift 2 ;;
        --repair-toolchain) REPAIR_TOOLCHAIN=1; shift ;;
        -h|--help)
            printf "Usage: %s [--ci] [--log-file PATH] [--repair-toolchain]\n" "$0"
            exit 0
            ;;
        *) qa::fail "unknown flag: $1"; exit 1 ;;
    esac
done

STAMP="$(date +%Y-%m-%d-%H%M%S)"
REPORT_DIR="$QA_REPORTS_DIR/$STAMP"
REPORT_MD="$QA_REPORTS_DIR/$STAMP.md"
mkdir -p "$REPORT_DIR"

# Default log path colocated with per-suite logs. Tee stdout+stderr so the
# user still sees live progress while the full transcript is captured.
if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$REPORT_DIR/run-all.log"
fi
exec > >(tee -a "$LOG_FILE") 2>&1
qa::info "logging to $LOG_FILE"
qa::info "mode=$MODE report=$REPORT_MD"

# Total step count depends on mode.
#   CI-SUBSET: toolchain + build axprobe + ax gate + suite 01               = 4
#   FULL:      toolchain + build axprobe + ax gate + 6 suites (00..05)
#              + metrics record + regression guard + badge publish          = 12
if [[ "$MODE" == "FULL" ]]; then
    TOTAL_STEPS=13
else
    TOTAL_STEPS=4
fi
STEP=0

qa::step $((++STEP)) "$TOTAL_STEPS" "Swift toolchain preflight"
if [[ "$REPAIR_TOOLCHAIN" -eq 1 ]]; then
    qa::require_swift_toolchain --auto-repair || exit 1
else
    qa::require_swift_toolchain || exit 1
fi
qa::info "toolchain OK ($(xcode-select -p 2>/dev/null || echo unknown))"

qa::step $((++STEP)) "$TOTAL_STEPS" "Build AXProbe harness"
qa::build_axprobe

qa::step $((++STEP)) "$TOTAL_STEPS" "Accessibility permission gate"
# CI-subset mode only runs 01-smoke, which is designed to pass without AX
# grant (the "permission missing, polling started" signpost is an accepted
# outcome). Skip the interactive gate so CI doesn't hang 10min on an
# ungrantable hosted runner.
if [[ "$MODE" == "CI-SUBSET" ]]; then
    qa::info "CI-SUBSET mode: skipping interactive AX gate"
else
    qa::require_accessibility
fi

qa::report_begin "$REPORT_MD" "$MODE"

run_suite() {
    local name="$1"
    local label="$2"
    shift 2
    local script="$SCRIPT_DIR/$name"
    local log="$REPORT_DIR/$name.log"
    local kv="$REPORT_DIR/${name%.sh}.kv"
    local start status dur
    qa::step $((++STEP)) "$TOTAL_STEPS" "$label ($name)"
    qa::info "live output tailing to $log"
    start="$(date +%s)"
    local rc=0
    if bash "$script" --output "$kv" "$@" > "$log" 2>&1; then
        status="PASS"
    else
        rc=$?
        status="FAIL"
    fi
    dur=$(( $(date +%s) - start ))
    qa::report_row "$REPORT_MD" "$name" "$status" "$dur" "$STAMP/$name.log"
    if [[ "$status" == "PASS" ]]; then
        qa::pass "$name in ${dur}s"
    else
        qa::fail "$name in ${dur}s (rc=$rc) — see $log"
    fi
    return "$rc"
}

OVERALL="PASS"

# Suite 01 — always.
if ! run_suite 01-smoke.sh "Smoke: build / bundle / signposts"; then OVERALL="FAIL"; fi

if [[ "$MODE" == "FULL" ]]; then
    # AX-dependent + perf suites only in full mode.
    if ! run_suite 00-startup.sh       "Startup: cold launch -> first lifecycle log"; then OVERALL="FAIL"; fi
    if ! run_suite 02-core-behavior.sh "Core behavior: 3-click cycle + latency"; then OVERALL="FAIL"; fi
    if ! run_suite 03-edge-cases.sh    "Edge cases: frozen/debounce/multi-window"; then OVERALL="FAIL"; fi
    if ! run_suite 04-dock-config.sh   "Dock config: tilesize/orientation/autohide"; then OVERALL="FAIL"; fi
    if ! run_suite 05-perf-instruments.sh "Perf: xctrace + idle-cpu + active-cpu"; then OVERALL="FAIL"; fi
    if ! run_suite 06-settings.sh "Settings: enable/disable + icon-hide toggles"; then OVERALL="FAIL"; fi

    # --- Metrics pipeline: aggregate, record, classify, publish ------------
    qa::step $((++STEP)) "$TOTAL_STEPS" "Recording perf metrics"
    EMIT_FILE="$REPORT_DIR/metrics.emit"
    : > "$EMIT_FILE"
    for kv in "$REPORT_DIR/00-startup.kv" \
              "$REPORT_DIR/02-core-behavior.kv" \
              "$REPORT_DIR/05-perf-instruments.kv"; do
        if [[ -f "$kv" ]]; then
            # Whitelist only metrics-schema keys so emit stays clean.
            grep -E '^(startup_ms|memory_mb|idle_cpu_wakeups_per_sec|active_cpu_tap_overhead_us_p50|latency_ms_p50)=' \
                "$kv" >> "$EMIT_FILE" || true
        fi
    done
    if [[ -s "$EMIT_FILE" ]]; then
        qa::metrics_record "$EMIT_FILE" >/dev/null
        qa::metrics_render_all_badges
    else
        qa::warn "no perf emit lines — skipping metrics record"
    fi

    qa::step $((++STEP)) "$TOTAL_STEPS" "Regression guard"
    if ! qa::metrics_regression_guard; then
        OVERALL="FAIL"
        /usr/bin/sed -i '' '1s/^# /# REGRESSION - /' "$REPORT_MD"
        qa::fail "perf regression vs last green baseline"
    fi

    qa::step $((++STEP)) "$TOTAL_STEPS" "Publishing badges"
    qa::metrics_push_gist || qa::warn "gist push failed (non-fatal)"
fi

qa::report_end "$REPORT_MD" "$OVERALL"

printf "\n"
printf "report: %s\n" "$REPORT_MD"
printf "log:    %s\n" "$LOG_FILE"
if [[ "$OVERALL" == "PASS" ]]; then
    qa::pass "run-all ($MODE)"
    exit 0
else
    qa::fail "run-all ($MODE)"
    exit 1
fi
