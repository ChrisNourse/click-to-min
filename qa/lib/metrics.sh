#!/usr/bin/env bash
# qa/lib/metrics.sh — performance metric recording + badge publishing.
#
# Responsibilities:
#   * Parse per-suite emit files (key=value lines) into a single JSON record.
#   * Classify each metric color vs qa/metrics/thresholds.json (green/orange/red).
#   * Append the record to qa/metrics/history.jsonl (append-only, grep/Snowflake-friendly).
#   * Run the regression guard: compare to the previous green run; warn at
#     warn_multiplier, fail at fail_multiplier.
#   * Render shields.io endpoint JSON for each metric and (optionally) push
#     the payload to a GitHub Gist so the README badges go dynamic.
#
# Source from an orchestrator:
#   source "$SCRIPT_DIR/lib/metrics.sh"
#
# Dependency-light: bash + coreutils + python3 (for JSON). No jq.

# shellcheck disable=SC2155
QA_METRICS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/metrics"
QA_METRICS_HISTORY="$QA_METRICS_DIR/history.jsonl"
QA_METRICS_THRESHOLDS="$QA_METRICS_DIR/thresholds.json"
QA_METRICS_BADGES_DIR="$QA_METRICS_DIR/badges"

# ---------- helpers ---------------------------------------------------------

# Classify a numeric value against a metric's thresholds.
# Usage: qa::metric_color <metric_key> <value>
# Prints: green | orange | red
qa::metric_color() {
    local key="$1" value="$2"
    /usr/bin/python3 - "$QA_METRICS_THRESHOLDS" "$key" "$value" <<'PY'
import json, sys
thresholds_path, key, value = sys.argv[1], sys.argv[2], float(sys.argv[3])
with open(thresholds_path) as f:
    t = json.load(f)
m = t["metrics"].get(key)
if not m:
    print("lightgrey"); sys.exit(0)
if value < m["green_max"]:
    print("brightgreen")
elif value < m["orange_max"]:
    print("orange")
else:
    print("red")
PY
}

# Render a shields.io endpoint JSON file for one metric.
# Usage: qa::metric_render_badge <metric_key> <value>
# Writes to $QA_METRICS_BADGES_DIR/<metric_key>.json
qa::metric_render_badge() {
    local key="$1" value="$2"
    mkdir -p "$QA_METRICS_BADGES_DIR"
    local out="$QA_METRICS_BADGES_DIR/${key}.json"
    /usr/bin/python3 - "$QA_METRICS_THRESHOLDS" "$key" "$value" "$out" <<'PY'
import json, sys
thresholds_path, key, value, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
value_f = float(value)
with open(thresholds_path) as f:
    t = json.load(f)
m = t["metrics"].get(key, {})
label = m.get("label", key)
unit = m.get("unit", "")
if value_f < m.get("green_max", float("inf")):
    color = "brightgreen"
elif value_f < m.get("orange_max", float("inf")):
    color = "orange"
else:
    color = "red"
# Format: integers stay integer, floats trim to 2 dp.
if value_f == int(value_f):
    msg = f"{int(value_f)} {unit}".strip()
else:
    msg = f"{value_f:.2f} {unit}".strip()
payload = {"schemaVersion": 1, "label": label, "message": msg, "color": color}
with open(out, "w") as f:
    json.dump(payload, f)
    f.write("\n")
print(out)
PY
}

# Append one record to history.jsonl with all metrics from the emit file(s).
# Usage: qa::metrics_record <emit_file>
#   emit file is a key=value file produced by suites (e.g. startup_ms=850).
# Returns 0 always; prints the JSON line on stdout.
qa::metrics_record() {
    local emit="$1"
    mkdir -p "$QA_METRICS_DIR"
    /usr/bin/python3 - "$emit" "$QA_METRICS_HISTORY" <<'PY'
import json, os, sys, datetime, subprocess
emit_path, history_path = sys.argv[1], sys.argv[2]
metrics = {}
with open(emit_path) as f:
    for line in f:
        line = line.strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        try:
            metrics[k] = float(v)
        except ValueError:
            metrics[k] = v
# Git SHA if available.
sha = os.environ.get("QA_GIT_SHA", "")
if not sha:
    try:
        sha = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        pass
record = {
    "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git_sha": sha,
    "metrics": metrics,
}
line = json.dumps(record, separators=(",", ":"))
with open(history_path, "a") as f:
    f.write(line + "\n")
print(line)
PY
}

# Regression guard: compare the latest record against the previous all-green
# record in history.jsonl.
# Usage: qa::metrics_regression_guard
# Exit: 0 on PASS/warn, 1 on fail.
qa::metrics_regression_guard() {
    /usr/bin/python3 - "$QA_METRICS_HISTORY" "$QA_METRICS_THRESHOLDS" <<'PY'
import json, sys
hist_path, thresh_path = sys.argv[1], sys.argv[2]
try:
    with open(hist_path) as f:
        lines = [json.loads(l) for l in f if l.strip()]
except FileNotFoundError:
    print("[metrics] no history yet — skipping regression guard")
    sys.exit(0)
if len(lines) < 2:
    print("[metrics] <2 records — nothing to compare against")
    sys.exit(0)
with open(thresh_path) as f:
    t = json.load(f)
warn_x = t["regression_guard"]["warn_multiplier"]
fail_x = t["regression_guard"]["fail_multiplier"]

latest = lines[-1]["metrics"]
# Baseline = most recent prior record where all metrics were green.
def is_green(m):
    for k, v in m.items():
        if k not in t["metrics"]:
            continue
        if not isinstance(v, (int, float)):
            continue
        if v >= t["metrics"][k]["green_max"]:
            return False
    return True
baseline = None
for rec in reversed(lines[:-1]):
    if is_green(rec["metrics"]):
        baseline = rec
        break
if baseline is None:
    print("[metrics] no green baseline in history — skipping regression guard")
    sys.exit(0)

failed = False
warned = False
for k, v in latest.items():
    if k not in baseline["metrics"] or k not in t["metrics"]:
        continue
    b = baseline["metrics"][k]
    if not isinstance(v, (int, float)) or not isinstance(b, (int, float)) or b == 0:
        continue
    ratio = v / b
    if ratio >= fail_x:
        print(f"[metrics] FAIL regression: {k} {b:.2f} -> {v:.2f} ({ratio:.2f}x)")
        failed = True
    elif ratio >= warn_x:
        print(f"[metrics] WARN regression: {k} {b:.2f} -> {v:.2f} ({ratio:.2f}x)")
        warned = True
if not failed and not warned:
    print("[metrics] regression guard: all metrics within tolerance")
sys.exit(1 if failed else 0)
PY
}

# Render all 5 badges from the latest history record.
# Usage: qa::metrics_render_all_badges
qa::metrics_render_all_badges() {
    /usr/bin/python3 - "$QA_METRICS_HISTORY" "$QA_METRICS_THRESHOLDS" "$QA_METRICS_BADGES_DIR" <<'PY'
import json, os, sys
hist_path, thresh_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out_dir, exist_ok=True)
with open(hist_path) as f:
    lines = [json.loads(l) for l in f if l.strip()]
if not lines:
    print("[metrics] history empty — nothing to render")
    sys.exit(0)
latest = lines[-1]["metrics"]
with open(thresh_path) as f:
    t = json.load(f)
for key, meta in t["metrics"].items():
    v = latest.get(key)
    if v is None:
        continue
    try:
        v = float(v)
    except (TypeError, ValueError):
        continue
    if v < meta["green_max"]:
        color = "brightgreen"
    elif v < meta["orange_max"]:
        color = "orange"
    else:
        color = "red"
    if v == int(v):
        msg = f"{int(v)} {meta['unit']}".strip()
    else:
        msg = f"{v:.2f} {meta['unit']}".strip()
    payload = {
        "schemaVersion": 1,
        "label": meta["label"],
        "message": msg,
        "color": color,
    }
    with open(os.path.join(out_dir, f"{key}.json"), "w") as f:
        json.dump(payload, f)
        f.write("\n")
    print(f"[metrics] {meta['label']}: {msg} ({color})")
PY
}

# Push all rendered badge JSONs to a GitHub Gist. Requires:
#   CLICKTOMIN_BADGE_GIST_ID   — gist ID (once, bootstrap via qa/metrics/README.md)
#   CLICKTOMIN_BADGE_GIST_TOKEN — PAT with `gist` scope
# Skipped silently if either env var is missing (CI-friendly).
qa::metrics_push_gist() {
    local gist_id="${CLICKTOMIN_BADGE_GIST_ID:-${QA_BADGE_GIST_ID:-}}"
    local gist_token="${CLICKTOMIN_BADGE_GIST_TOKEN:-${GIST_SECRET:-}}"
    if [[ -z "$gist_id" || -z "$gist_token" ]]; then
        qa::info "[metrics] gist env vars not set — skipping badge push"
        return 0
    fi
    if [[ ! -d "$QA_METRICS_BADGES_DIR" ]]; then
        qa::warn "[metrics] no badges directory — skipping gist push"
        return 0
    fi
    CLICKTOMIN_BADGE_GIST_ID="$gist_id" CLICKTOMIN_BADGE_GIST_TOKEN="$gist_token" \
    /usr/bin/python3 - "$QA_METRICS_BADGES_DIR" <<PY
import json, os, sys, urllib.request
badges_dir = sys.argv[1]
gist_id = os.environ["CLICKTOMIN_BADGE_GIST_ID"]
token = os.environ["CLICKTOMIN_BADGE_GIST_TOKEN"]
files = {}
for name in os.listdir(badges_dir):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(badges_dir, name)) as f:
        files[name] = {"content": f.read()}
payload = json.dumps({"files": files}).encode()
req = urllib.request.Request(
    f"https://api.github.com/gists/{gist_id}",
    data=payload,
    method="PATCH",
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "clicktomin-qa",
    },
)
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(f"[metrics] gist push: HTTP {resp.status}")
except Exception as e:
    print(f"[metrics] gist push failed: {e}", file=sys.stderr)
    sys.exit(1)
PY
}
