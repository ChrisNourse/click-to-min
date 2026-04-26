# qa/ — ClickToMin QA automation

Scripted replacement for the manual Layer 2/3 checklist. Produces a
timestamped markdown report per run and can update `PERF.md` in place.

## Prereqs

- macOS 13+ workstation (matches `CI` runner `macos-14`)
- Xcode Command Line Tools
- `cliclick` — `brew install cliclick`
- Accessibility granted to **both**:
  1. `ClickToMin.app` (project root; built by `./build.sh`)
  2. `qa/harness/AXProbe/.build/release/axprobe` (built by `swift build -c release --package-path qa/harness/AXProbe`)

System Settings → Privacy & Security → Accessibility → `+` → add both binaries.

The preflight in `qa/lib/common.sh` prints the exact grant path if either
binary is missing permission.

## Layout

```
qa/
  lib/            shared bash helpers (common.sh, report.sh, xctrace-parse.sh)
  harness/AXProbe Swift CLI that queries AX state for assertions
  reports/        timestamped run reports (gitignored)
  01-smoke.sh     CI-safe: build / bundle / plist / signpost smoke
  02-core-behavior.sh   3-click cycle vs Safari (AX-dependent)
  03-edge-cases.sh      frozen app, debounce, multi-window, etc.
  04-dock-config.sh     Dock resize / move / auto-hide (AX-dependent)
  05-perf-instruments.sh xctrace Time Profiler + Allocations
  run-all.sh      orchestrator + report writer + PERF.md updater
  MANUAL-CHECKLIST.md    three items that can't be scripted
```

## Run

```bash
# CI-safe subset (no Accessibility required; runs in GitHub Actions)
./qa/run-all.sh --ci

# Full local run (requires Accessibility grant)
./qa/run-all.sh

# Populate PERF.md Baseline column (use once, at release cut)
./qa/run-all.sh --baseline

# Override the default log path (defaults to qa/reports/<ts>/run-all.log)
./qa/run-all.sh --log-file /tmp/qa.log
```

## Reports

Written to `qa/reports/<YYYY-MM-DD-HHMMSS>.md` with pass/fail per suite
and a link to the per-suite log directory at
`qa/reports/<YYYY-MM-DD-HHMMSS>/`.

## Notes

- `qa/MANUAL-CHECKLIST.md` covers the non-automatable items (first-grant
  flow, sleep/wake, display hot-plug). Run before every release tag.
- Scripts are shellcheck-clean. Run `shellcheck qa/lib/*.sh qa/*.sh`.
- Pure bash + coreutils + Xcode toolchain. No jq, no python.
