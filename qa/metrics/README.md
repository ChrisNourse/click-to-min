# qa/metrics — performance metrics pipeline

This directory is the single source of truth for ClickToMin performance
badges. `qa/run-all.sh` (FULL mode) populates:

- `history.jsonl` — append-only record of every run. One JSON line per run:
  ```
  {"ts":"...","git_sha":"abc123","metrics":{"startup_ms":880,"memory_mb":26.1,...}}
  ```
  Easy to grep / plot / ingest into Snowflake.
- `badges/*.json` — one shields.io endpoint JSON per metric, ready to
  host as Gist files.
- `thresholds.json` — classification policy (green / orange / red) and
  regression multipliers. Edit this file to tune.

## Metrics

| Key                                  | Label       | Unit      | Green  | Orange   | Red    |
|--------------------------------------|-------------|-----------|--------|----------|--------|
| `startup_ms`                         | startup     | ms        | <1000  | 1000-2000 | >2000 |
| `memory_mb`                          | memory      | MB        | <40    | 40-80    | >80    |
| `idle_cpu_wakeups_per_sec`           | idle-cpu    | wakeups/s | <1     | 1-10     | >10    |
| `active_cpu_tap_overhead_us_p50`     | active-cpu  | µs        | <100   | 100-500  | >500   |
| `latency_ms_p50`                     | latency     | ms        | <250   | 250-500  | >500   |

## Bootstrap: one-time Gist setup

README shields.io `endpoint` badges point at raw files in a public GitHub
Gist. The Gist ID is already wired into `README.md` and
`qa/lib/metrics.sh` expects the following env vars to push updates.

1. Create (or reuse) a public Gist with 5 empty placeholder files matching
   the badge filenames:
   - `startup_ms.json`
   - `memory_mb.json`
   - `idle_cpu_wakeups_per_sec.json`
   - `active_cpu_tap_overhead_us_p50.json`
   - `latency_ms_p50.json`

   Each placeholder should contain a valid shields.io payload, e.g.:
   ```json
   {"schemaVersion":1,"label":"startup","message":"pending","color":"lightgrey"}
   ```

2. Copy the Gist ID from the URL (`gist.github.com/<user>/<ID>`).

3. Generate a fine-scoped Personal Access Token with **only** `gist`
   scope at https://github.com/settings/tokens

4. Export both variables in the shell that runs `qa/run-all.sh`:
   ```bash
   export CLICKTOMIN_BADGE_GIST_ID="<ID>"
   export CLICKTOMIN_BADGE_GIST_TOKEN="<PAT>"
   ```
   When missing, metric recording still runs locally; badge push is
   skipped silently.

5. After a green `qa/run-all.sh` run, the Gist files are PATCHed via the
   GitHub API and the README badges refresh on the next shields.io cache
   miss (usually <10 min).

## Regression guard

`qa::metrics_regression_guard` picks the most recent all-green record in
`history.jsonl` as the baseline and flags any metric whose latest value
is `>= warn_multiplier * baseline` (warn) or `>= fail_multiplier *
baseline` (fail). Defaults are 1.25x / 1.5x — edit in `thresholds.json`.

A failed guard flips the run-all exit code to 1 and prefixes the report
markdown header with `REGRESSION -`.
