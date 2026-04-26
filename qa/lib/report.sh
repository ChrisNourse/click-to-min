#!/usr/bin/env bash
# qa/lib/report.sh — markdown report assembly for ClickToMin QA suites.
#
# Produces a per-run summary at qa/reports/<ts>.md. Perf metrics are now
# owned by qa/lib/metrics.sh (history.jsonl + shields.io badges); this
# file only handles the human-readable run summary.

set -euo pipefail

# Begin a report: write header + metadata.
# Usage: qa::report_begin <report_path> <mode>
#   mode: "FULL" | "CI-SUBSET"
qa::report_begin() {
    local path="$1"
    local mode="$2"
    {
        printf "# ClickToMin QA report — %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf -- "- mode: **%s**\n" "$mode"
        printf -- "- host: \`%s\`\n" "$(uname -n)"
        printf -- "- macOS: \`%s\`\n" "$(sw_vers -productVersion)"
        printf -- "- commit: \`%s\`\n\n" "$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        printf "| Suite | Status | Duration (s) | Log |\n"
        printf "|-------|--------|--------------|-----|\n"
    } > "$path"
}

# Append a suite row.
# Usage: qa::report_row <report_path> <suite> <status> <duration_s> <log_rel>
qa::report_row() {
    local path="$1"
    local suite="$2"
    local status="$3"
    local dur="$4"
    local log_rel="$5"
    printf "| %s | %s | %s | [log](%s) |\n" "$suite" "$status" "$dur" "$log_rel" >> "$path"
}

# Close the report with an aggregate footer.
# Usage: qa::report_end <report_path> <overall_status>
qa::report_end() {
    local path="$1"
    local status="$2"
    printf "\n**Overall: %s**\n" "$status" >> "$path"
}
