#!/usr/bin/env bash
# qa/lib/report.sh — markdown report assembly for ClickToMin QA suites.
#
# Produces a per-run summary at qa/reports/<ts>.md. The enrichment pass
# (qa::enrich_report) parses .kv and .log files to produce a single
# self-contained report with metrics, warnings, and signposts inline.

set -euo pipefail

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

qa::report_row() {
    local path="$1"
    local suite="$2"
    local status="$3"
    local dur="$4"
    local log_rel="$5"
    printf "| %s | %s | %s | [log](%s) |\n" "$suite" "$status" "$dur" "$log_rel" >> "$path"
}

qa::report_end() {
    local path="$1"
    local status="$2"
    printf "\n**Overall: %s**\n" "$status" >> "$path"
}

# Enrich an existing report with inline metrics, warnings, and details.
# Called post-run (typically from remote-run.sh after fetching logs).
#
# Usage: qa::enrich_report <report.md> <report_dir>
#   report.md  — the summary markdown produced by run-all.sh
#   report_dir — directory containing .kv and .log files
qa::enrich_report() {
    local report="$1"
    local report_dir="$2"

    if [[ ! -f "$report" || ! -d "$report_dir" ]]; then
        return 0
    fi

    local enriched="${report%.md}-enriched.md"

    /usr/bin/python3 - "$report" "$report_dir" "$enriched" <<'PY'
import sys, os, re
from pathlib import Path

report_path, report_dir, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

report_dir = Path(report_dir)
original = Path(report_path).read_text()

metrics = {}
warnings = []
suite_notes = {}
signposts = ""

for kv_file in sorted(report_dir.glob("*.kv")):
    suite_name = kv_file.stem
    for line in kv_file.read_text().splitlines():
        line = line.strip()
        if not line or "=" not in line or line == "PASS":
            continue
        key, val = line.split("=", 1)
        if key in ("PASS", "FAIL"):
            continue
        try:
            metrics[key] = float(val)
        except ValueError:
            metrics[key] = val

for log_file in sorted(report_dir.glob("*.log")):
    suite_name = log_file.stem.replace(".sh", "")
    content = log_file.read_text()
    notes = []
    for line in content.splitlines():
        if "WARN" in line:
            warnings.append(f"- {suite_name}: {line.strip()}")
            warn_text = line.strip()
            if warn_text.startswith("WARN "):
                warn_text = warn_text[5:]
            notes.append(warn_text)
        if "latency" in line.lower() and ("p50" in line or "p95" in line):
            m = re.search(r'p50=(\d+)ms', line)
            m2 = re.search(r'p95=(\d+)ms', line)
            if m:
                notes.append(f"p50={m.group(1)}ms")
            if m2:
                notes.append(f"p95={m2.group(1)}ms")
    if notes:
        suite_notes[suite_name] = "; ".join(notes)
    if "01-smoke" in log_file.name:
        sig_lines = [l for l in content.splitlines() if "com.click-to-min" in l]
        if sig_lines:
            signposts = "\n".join(sig_lines[-8:])

header_match = re.search(r'^(# .+?)(?=\n\|)', original, re.DOTALL)
header = header_match.group(1).strip() if header_match else original.split("\n|")[0]

lines = original.splitlines()
commit_line = next((l for l in lines if l.startswith("- commit:")), "")
commit = re.search(r'`(.+?)`', commit_line)
commit_sha = commit.group(1) if commit else "unknown"
host_line = next((l for l in lines if l.startswith("- host:")), "")
macos_line = next((l for l in lines if l.startswith("- macOS:")), "")
mode_line = next((l for l in lines if l.startswith("- mode:")), "")

table_lines = [l for l in lines if l.startswith("| ") and "Suite" not in l and "---" not in l]
total_suites = len(table_lines)
pass_count = sum(1 for l in table_lines if "PASS" in l)
total_duration = sum(int(re.search(r'\d+', l.split("|")[3]).group()) for l in table_lines if re.search(r'\d+', l.split("|")[3]))
overall = "PASS" if pass_count == total_suites else "FAIL"

out = []
out.append(f"# ClickToMin QA Report")
out.append("")
out.append("## Summary")
out.append(f"- Commit: `{commit_sha}`")
out.append(host_line)
out.append(macos_line)
out.append(mode_line)
out.append(f"- Result: **{overall}** ({pass_count}/{total_suites} suites)")
out.append(f"- Duration: {total_duration // 60}m {total_duration % 60}s")
out.append("")

metric_display = [
    ("startup_ms", "Startup", "ms"),
    ("memory_mb", "Memory (idle RSS)", "MB"),
    ("idle_cpu_wakeups_per_sec", "Idle CPU wakeups", "/s"),
    ("active_cpu_tap_overhead_us_p50", "Tap overhead (p50)", "us"),
    ("latency_ms_p50", "Click-to-minimize (p50)", "ms"),
    ("idle_rss_mean_mb", "RSS mean", "MB"),
    ("idle_rss_peak_mb", "RSS peak", "MB"),
    ("idle_cpu_mean_pct", "CPU mean", "%"),
    ("idle_cpu_peak_pct", "CPU peak", "%"),
    ("p50_ms", "Latency p50", "ms"),
    ("p95_ms", "Latency p95", "ms"),
]

displayed_metrics = [(label, f"{metrics[key]:.2f}" if isinstance(metrics.get(key), float) and metrics[key] != int(metrics[key]) else str(int(metrics[key])) if isinstance(metrics.get(key), float) else str(metrics.get(key, "")), unit) for key, label, unit in metric_display if key in metrics]

if displayed_metrics:
    out.append("## Metrics")
    out.append("| Metric | Value | Unit |")
    out.append("|--------|-------|------|")
    for label, val, unit in displayed_metrics:
        out.append(f"| {label} | {val} | {unit} |")
    out.append("")

out.append("## Suite Results")
out.append("| Suite | Status | Duration | Notes |")
out.append("|-------|--------|----------|-------|")
for tl in table_lines:
    parts = [p.strip() for p in tl.split("|") if p.strip()]
    if len(parts) >= 3:
        suite = parts[0]
        status = parts[1]
        dur = parts[2]
        note_key = suite.replace(".sh", "")
        notes = suite_notes.get(note_key, "")
        out.append(f"| {suite} | {status} | {dur} | {notes} |")
out.append("")

if warnings:
    out.append("## Warnings")
    for w in warnings:
        out.append(w)
    out.append("")

if signposts:
    out.append("## Lifecycle Signposts")
    out.append("```")
    out.append(signposts)
    out.append("```")
    out.append("")

Path(output_path).write_text("\n".join(out) + "\n")
print(f"Enriched report: {output_path}")
PY

    if [[ -f "$enriched" ]]; then
        mv "$enriched" "$report"
    fi
}
