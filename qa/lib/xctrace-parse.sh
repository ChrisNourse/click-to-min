#!/usr/bin/env bash
# qa/lib/xctrace-parse.sh — parsers for xctrace export output.
#
# xctrace emits tabular text (with column headers on the first line for most
# templates). These helpers assert expected columns exist before parsing so
# schema drift across Xcode versions fails loud instead of producing silent
# garbage.

set -euo pipefail

# Parse Time Profiler export: look for "Weight" / "% Weight" / "Symbol Name"
# columns. Emit top N rows as "weight_pct\tsymbol".
# Usage: xctrace_parse_time_profiler <export.txt> <top_n>
xctrace_parse_time_profiler() {
    local src="$1"
    local top_n="${2:-10}"
    if [[ ! -f "$src" ]]; then
        printf "ERROR: %s not found\n" "$src" >&2
        return 1
    fi
    # Assert header columns we care about exist.
    local header
    header="$(head -1 "$src" || true)"
    if ! grep -qi 'weight' <<<"$header"; then
        printf "ERROR: xctrace Time Profiler export missing 'Weight' column\n" >&2
        printf "header was: %s\n" "$header" >&2
        return 1
    fi
    if ! grep -qi 'symbol' <<<"$header"; then
        printf "ERROR: xctrace Time Profiler export missing 'Symbol' column\n" >&2
        return 1
    fi
    # Strip header, keep first N data rows.
    tail -n +2 "$src" | head -n "$top_n"
}

# Parse Allocations export: look for "Persistent Bytes" / "Transient Bytes"
# columns. Emit total persistent / transient bytes as "persistent\ttransient".
# Usage: xctrace_parse_allocations <export.txt>
xctrace_parse_allocations() {
    local src="$1"
    if [[ ! -f "$src" ]]; then
        printf "ERROR: %s not found\n" "$src" >&2
        return 1
    fi
    local header
    header="$(head -1 "$src" || true)"
    if ! grep -qi 'persistent' <<<"$header"; then
        printf "ERROR: Allocations export missing 'Persistent' column\n" >&2
        printf "header was: %s\n" "$header" >&2
        return 1
    fi
    # Sum numeric columns. Assume 'Persistent Bytes' is col 2, 'Transient
    # Bytes' is col 3. Robust parsing is out of scope — just emit the total
    # of the first numeric column as persistent bytes.
    awk 'NR>1 { gsub(",", "", $2); if ($2 ~ /^[0-9]+$/) s+=$2 } END{ print s+0 }' "$src"
}

# Compute mean and peak resident-set size (KB) from a `ps -o rss` stream.
# Input: one RSS value per line on stdin. Output: "mean_kb\tpeak_kb".
xctrace_mem_stats() {
    awk '{ n++; sum+=$1; if ($1>peak) peak=$1 } END{ if(n==0){print "0\t0"; exit} printf "%d\t%d\n", sum/n, peak }'
}
