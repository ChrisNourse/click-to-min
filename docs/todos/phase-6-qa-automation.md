# Phase 6 — QA Automation Suite

**Goal**: Replace the manual Layer 2 / Layer 3 checklist from the original `phase-6-qa-perf.md` (archived under `completed/`) with a repeatable, scripted test suite. Must produce a markdown report per run and auto-populate `PERF.md` with current-release baselines.

**Parallelism**: 6a and the AX harness block everything else. 6b, 6c, 6d, 6e can land independently once 6a is in. 6f is the last piece (orchestrator + reporter) and closes the phase.

**Exit criteria**:
- `./qa/run-all.sh` runs end-to-end on a maintainer workstation and emits `qa/reports/<timestamp>.md` with pass/fail per suite
- `PERF.md` v0.1.0 row is populated from a real run (memory MB, idle CPU %, click→minimize latency ms)
- README documents: `brew install cliclick`, grant Accessibility to the harness binary, run `./qa/run-all.sh`
- CI runs the CI-safe subset (build + bundle + plist lint) automatically; the AX-dependent suites remain local-only and are documented as such

**Scope limits (non-automatable, accepted)**:
- First-grant Accessibility flow (TCC is SIP-protected; can't script a grant)
- Sleep/wake permission re-check (requires real sleep + admin)
- Display hot-plug (can't fake a monitor replug in software)
- These stay as a 3-item manual checklist, tracked as T-6.7

---

### T-6.1 — `qa/` scaffold + shared library
- **Owner**: unassigned
- **Depends on**: none
- **Blocks**: T-6.2–T-6.7
- **Files**: `qa/lib/common.sh`, `qa/.gitignore`, `qa/README.md`
- **Description**: Create the `qa/` directory tree. `common.sh` provides shared helpers: `qa::log_stream_capture <category> <seconds>`, `qa::build_release`, `qa::launch_app`, `qa::quit_app`, `qa::assert_process_running`, timestamped report paths, color output, `set -euo pipefail` boilerplate.
- **Acceptance criteria**:
  - [x] `qa/lib/common.sh` sources cleanly under `bash -n`
  - [x] Helpers are unit-smokeable by calling each in isolation (e.g. `qa::build_release` produces `ClickToMin.app`)
  - [x] `qa/README.md` documents prerequisites: Xcode CLT, `cliclick` (brew), Accessibility grant for both `ClickToMin.app` and the `AXProbe` harness
  - [x] `qa/reports/` is gitignored but the directory is kept via `.gitkeep`
- **Verification step**:
  - Run `shellcheck qa/lib/common.sh qa/*.sh` once other scripts exist; should be clean at every stage
- **Notes**: Keep helpers dependency-light — no `jq`, no Python. Pure bash + coreutils + Xcode toolchain.

### T-6.2 — `AXProbe` harness (Swift CLI)
- **Owner**: unassigned
- **Depends on**: T-6.1
- **Blocks**: T-6.3, T-6.4, T-6.5
- **Files**: `qa/harness/AXProbe/Package.swift`, `qa/harness/AXProbe/Sources/AXProbe/main.swift`, `qa/harness/AXProbe/README.md`
- **Description**: Tiny Swift executable that queries AX state and exits 0/1 with structured stdout. Subcommands:
  - `axprobe is-minimized <bundle-id>` — reads focused window of frontmost app whose bundle id matches, prints `minimized=true|false`, exits 0
  - `axprobe window-count <bundle-id>` — prints integer count of visible windows
  - `axprobe frontmost-bundle-id` — prints current `NSWorkspace.frontmostApplication.bundleIdentifier`
  - `axprobe wait-until-minimized <bundle-id> --timeout 2.0` — polls at 25ms, exits 0 on success, 2 on timeout
- **Acceptance criteria**:
  - [x] Builds via `swift build --package-path qa/harness/AXProbe`
  - [x] Exits non-zero if Accessibility is not granted; error message explains grant path
  - [x] All 4 subcommands covered by a `qa/harness/AXProbe/Tests` test target with in-memory fakes
  - [x] Documented requirement: user grants Accessibility to the compiled `axprobe` binary once (separate from `ClickToMin.app`)
- **Verification step**:
  - With Safari visible and focused: `axprobe is-minimized com.apple.Safari` → `minimized=false`; then `osascript -e 'tell app "System Events" to keystroke "m" using command down'` → re-run → `minimized=true`
- **Notes**: Keep this binary tiny — it is the assertion engine for every click test.

### T-6.3 — `qa/01-smoke.sh`
- **Owner**: unassigned
- **Depends on**: T-6.1
- **Blocks**: T-6.6
- **Files**: `qa/01-smoke.sh`
- **Description**: CI-safe build / bundle / signature / plist smoke. Replicates the existing CI `bundle-check` but phrased as a local-runnable QA suite, plus a launch + log-stream signpost assertion.
- **Acceptance criteria**:
  - [x] `swift build -c release` succeeds
  - [x] `./build.sh` produces `ClickToMin.app`
  - [x] `codesign --verify --verbose ClickToMin.app` passes
  - [x] `plutil -lint Resources/Info.plist` passes
  - [x] Launches `.app`, captures 10s of `log stream --predicate 'subsystem == "com.click-to-min"'`, asserts all three `lifecycle` signposts fire: *permission granted* (or *awaiting permission* if not pre-granted), *monitor installed*, *Dock PID refreshed*
  - [x] Quits cleanly via `osascript -e 'tell application "ClickToMin" to quit'`; asserts no stray process via `pgrep -x ClickToMin`
- **Verification step**:
  - Fresh checkout: `./qa/01-smoke.sh` exits 0; grep the emitted report for `PASS: smoke`
- **Notes**: This is the only suite safe to run in CI. Wire it into `ci.yml` as an optional job that runs on every PR.

### T-6.4 — `qa/02-core-behavior.sh`
- **Owner**: unassigned
- **Depends on**: T-6.2
- **Blocks**: T-6.6
- **Files**: `qa/02-core-behavior.sh`
- **Description**: Scripts the 3-click cycle against Safari (or a configurable target app). Uses `cliclick` to hit Dock coordinates (discovered via a helper that queries `AXDockFrameProvider` output through a debug log signpost) and `axprobe` to assert outcomes. Also measures click→minimize latency via log timestamps.
- **Acceptance criteria**:
  - [x] Case 1: background app → Dock click → `frontmost-bundle-id` becomes target (no minimize)
  - [x] Case 2: target frontmost → Dock click → `axprobe wait-until-minimized target --timeout 0.5` succeeds
  - [x] Case 3: after Case 2, Dock click → `is-minimized` becomes `false` (macOS restore, no interference)
  - [x] Full 3-click cycle completes in under 3s wall-clock
  - [x] Click→minimize latency p95 across 20 trials recorded and compared to `PERF.md` threshold (default <50ms)
- **Verification step**:
  - `./qa/02-core-behavior.sh --app com.apple.Safari --trials 20`; report shows `p50=<x>ms p95=<y>ms`
- **Notes**: Dock-item coordinate discovery: add a one-shot `--emit-dock-rects` debug flag to `ClickToMin` that logs the current `AXDockFrameProvider` rects at `.info` level, then grep from log stream. Keep behind a `DEBUG` build flag or env var so it does not ship.

### T-6.5 — `qa/03-edge-cases.sh`
- **Owner**: unassigned
- **Depends on**: T-6.2
- **Blocks**: T-6.6
- **Files**: `qa/03-edge-cases.sh`
- **Description**: The scriptable subset of Edge Cases from PLAN.md.
- **Acceptance criteria**:
  - [x] Frozen-app timeout: launch target, `kill -STOP <pid>`, click Dock icon, pipeline log shows return within 500ms, `kill -CONT <pid>` restore
  - [x] Rapid double-click debounce: 2 clicks at 50ms interval → exactly one `minimize dispatched` log line
  - [x] Click during launch animation: `open -a <target>`, immediate Dock click within 100ms → no crash, no assertion
  - [x] Multi-window: target with 2 open windows, click Dock while frontmost → only focused window minimizes, `window-count` drops by exactly 1
  - [x] Right-click + ctrl-click on Dock item → no `minimize dispatched` log entry (deliberate scope)
- **Verification step**:
  - `./qa/03-edge-cases.sh`; report lists pass/fail per sub-case
- **Notes**: Skip long-press preview and Recent Applications — both are state-dependent and require a seeded Dock layout; document as manual.

### T-6.6 — `qa/04-dock-config.sh`
- **Owner**: unassigned
- **Depends on**: T-6.2
- **Blocks**: T-6.6
- **Files**: `qa/04-dock-config.sh`
- **Description**: Drives Dock configuration via `defaults` and verifies `AXDockFrameProvider` cache refresh.
- **Acceptance criteria**:
  - [x] Baseline: record current Dock settings (orientation, tilesize, autohide) so the script restores on exit (trap EXIT)
  - [x] Resize: `defaults write com.apple.dock tilesize -int 96 && killall Dock` → log shows frame refresh within 2s
  - [x] Move: orientation left → right → bottom → log shows refresh for each
  - [x] Auto-hide on → one click on the configured edge strip minimizes target; auto-hide off → frame re-cached to full Dock rect
  - [x] Cleanup: restores baseline on exit even if a sub-case fails
- **Verification step**:
  - Run against a fresh Dock config, confirm Dock is in its original state after exit
- **Notes**: `defaults write com.apple.dock …; killall Dock` races: sleep 1s after `killall` before asserting frame refresh to give the Dock process time to relaunch.

### T-6.7 — `qa/05-perf-instruments.sh`
- **Owner**: unassigned
- **Depends on**: T-6.2
- **Blocks**: T-6.8
- **Files**: `qa/05-perf-instruments.sh`, `qa/lib/xctrace-parse.sh`
- **Description**: Wraps `xctrace record` for Time Profiler and Allocations templates. Parses the exported traces and emits the columns `PERF.md` expects. The parser is the fragile part — keep the assertions loose (presence of symbol in top-N, not exact %) so minor Xcode upgrades do not break the suite.
- **Acceptance criteria**:
  - [x] Time Profiler, 1000 clicks **outside** Dock: `AXUIElementCopyElementAtPosition` does not appear in the top-10 heaviest stacks
  - [x] Time Profiler, 1000 clicks **inside** Dock: `AXUIElementCopyElementAtPosition` appears but accounts for <30% of sample time
  - [x] Allocations, 5min idle: resident memory mean <10 MB, peak <15 MB
  - [x] Allocations, 500 Dock clicks: net heap growth <200 KB (i.e., no per-click leak)
  - [x] Emits structured stdout ready to paste into `PERF.md`
- **Verification step**:
  - Run on a Release-built `.app`; diff the emitted block against the current `PERF.md` manually on first run to sanity-check parsing
- **Notes**: If `xctrace export` output schema changes on an Xcode upgrade, this task may break silently — include a self-check that asserts the expected CSV columns exist before parsing, and fails loudly with a clear message otherwise.

### T-6.8 — Manual checklist (non-automatable)
- **Owner**: maintainer
- **Depends on**: none (orthogonal)
- **Blocks**: release
- **Files**: `qa/MANUAL-CHECKLIST.md`
- **Description**: Three items that cannot be scripted. Maintainer runs before each release tag; initials + date in the file, committed as part of the release PR.
- **Acceptance criteria**:
  - [x] TCC first-grant flow: fresh checkout, unsigned quarantine cleared, launch → prompt fires → grant → menu bar icon active, clicks intercepted
  - [x] Sleep/wake re-check: `pmset sleepnow`, wake, confirm monitor still running (log stream shows re-check)
  - [x] Display hot-plug: unplug external monitor (if any) → click Dock on remaining screen → minimize still works → replug → log shows frame refresh
- **Verification step**:
  - Initials + date appended to `qa/MANUAL-CHECKLIST.md` on each release
- **Notes**: If the maintainer has no external display, the hot-plug item is marked N/A with a note — not skipped silently.

### T-6.9 — `qa/run-all.sh` orchestrator + report writer + PERF.md integration
- **Owner**: unassigned
- **Depends on**: T-6.3–T-6.7
- **Blocks**: release
- **Files**: `qa/run-all.sh`, `qa/lib/report.sh`, updates `PERF.md`, updates `README.md`
- **Description**: Top-level runner. Executes suites in order, captures pass/fail + timing per suite, writes `qa/reports/<YYYY-MM-DD-HHMMSS>.md`, and updates the `Current` column of `PERF.md` in place. On a `--baseline` flag, also updates the `Baseline` column (used once, at v0.1.0 release).
- **Acceptance criteria**:
  - [x] `./qa/run-all.sh` runs all CI-safe + AX-dependent suites in sequence
  - [x] `./qa/run-all.sh --ci` runs only the CI-safe subset (suite 01) and exits cleanly on a non-grantable runner
  - [x] `./qa/run-all.sh --baseline` writes both the Baseline and Current columns of `PERF.md`
  - [x] Report file is a clean markdown table, one row per suite, with links to per-suite logs in `qa/reports/<timestamp>/`
  - [x] Regression guard: if any `PERF.md` Current value regresses >20% vs. Baseline, exit code 1 and the report header is flagged `REGRESSION`
  - [x] README gets a new "Running the QA suite" section pointing at `qa/run-all.sh` and listing prereqs
- **Verification step**:
  - `./qa/run-all.sh --baseline` on a clean release build: report marked `PASS`, `PERF.md` populated, Baseline and Current columns equal
- **Notes**: Wire the CI-safe subset into `.github/workflows/ci.yml` as a new `qa-smoke` job that runs after `bundle-check`.

---

## Common Failure Patterns (pre-merge check)

- [x] `cliclick` not documented as a prereq — suite fails with cryptic "command not found" instead of a clear message
- [x] AXProbe binary not granted Accessibility — every suite fails identically; add a preflight check in `common.sh` that runs `AXIsProcessTrusted()` via AXProbe and prints the grant path if missing
- [x] Dock config suite does not restore state on failure — leaves maintainer's Dock mangled; verify the `trap EXIT` restore path by intentionally failing a sub-case
- [x] `xctrace` parser hard-codes column indices — Xcode upgrade silently breaks perf numbers; enforce column-name assertion
- [x] Perf regression >20% merged without release-notes mention — `run-all.sh --baseline` flag must be explicit, not default, so accidental re-baselining can't hide a regression
- [x] CI-safe suite confused with full suite — clearly label in output which subset ran

## Completed

<!-- Move finished tasks here -->
