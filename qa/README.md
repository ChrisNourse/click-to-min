# qa/ — ClickToMin QA Testing

## Overview

ClickToMin has three test layers:

| Layer | Where | What it tests |
|-------|-------|---------------|
| Unit tests | `swift test` (CI, macos-14) | Core logic with fakes (pipeline, geometry, debounce) |
| Integration test | CI (macos-26) | Real pipeline end-to-end via `--test-click` |
| Full QA suite | Local VM | Real mouse clicks via cliclick, all edge cases |

CI tests run automatically on every PR and block releases. The full QA suite
runs locally/on-VM for comprehensive validation including timing, performance,
and visual verification.

## CI Integration Test

Runs on `macos-26` GitHub-hosted runner. Tests the real pipeline (AX hit test,
PID match, URL match, debounce, actual minimize) without synthetic HID events.

```bash
# What CI runs:
scripts/ci-integration-test.sh com.apple.TextEdit
```

How it works:
1. `scripts/ci-grant-tcc.sh` grants Accessibility/ListenEvent/PostEvent/ScreenCapture
   to ClickToMin and AXProbe using csreq blobs (required for TCC runtime validation)
2. Launches target app (TextEdit), finds its Dock tile via AXProbe
3. Launches ClickToMin with `--test-click X,Y` (AX coordinates of Dock tile center)
4. App's pipeline receives the injected click and minimizes the window
5. AXProbe verifies the window actually minimized

This catches any break in: coordinate handling, Dock geometry, AX queries,
PID/URL matching, debounce logic, or the minimize call itself.

## Full QA Suite (Local/VM)

One-command test runner using real mouse events. Run before releases for
comprehensive validation including timing and performance.

```bash
./qa/suites/run-all.sh             # full local run (suites 00..06)
./qa/suites/run-all.sh --ci        # CI-safe subset only (01-smoke)
```

Reports land in `qa/reports/<timestamp>.md` with inline metrics and warnings.

### VM Setup (first time)

1. Create VM in UTM: Virtualize → macOS, 8 GB RAM, 4 cores, 64 GB disk
2. Create user `tester`, enable Remote Login (SSH)
3. `ssh-copy-id tester@<IP>` from host
4. Run bootstrap: `scp qa/vm-setup/bootstrap.sh tester@<IP>:~/ && ssh tester@<IP> "chmod +x ~/bootstrap.sh && ~/bootstrap.sh"`
5. Grant Accessibility on VM to: ClickToMin.app, AXProbe.app, cliclick, Terminal.app
6. `export QA_SSH_HOST="tester@<IP>"`

### Suites

| Script | What | Needs AX? |
|--------|------|-----------|
| 00-startup | Cold launch timing | Yes |
| 01-smoke | Build, codesign, signposts | No |
| 02-core-behavior | 3-click cycle + latency | Yes |
| 03-edge-cases | Frozen app, debounce, multi-window, modifiers | Yes |
| 04-dock-config | Tile size, orientation, auto-hide | Yes |
| 05-perf-instruments | RSS, CPU, tap overhead, xctrace | Yes |
| 06-settings | Enable/disable toggle, icon-hide | Yes |

## Manual Checklist

Items that cannot be automated. Run before every release tag.

### M1 — First-grant flow

1. Remove ClickToMin from Accessibility settings
2. Launch — should show "permission missing, polling started" in logs
3. Grant Accessibility
4. Within 5s: "permission granted, DockWatcher installed" + "global click monitor installed"
5. Dock-click a frontmost app's tile → minimizes

### M2 — Sleep/wake cycle

1. Verify minimize works
2. Sleep machine ≥60s, wake
3. Dock-click same app → must minimize within 500ms
4. Dock-click different app → must minimize

### M3 — Display hot-plug

1. Attach/detach external display (or change resolution)
2. Dock-click a tile without relaunching → must minimize
3. Logs should show "dock frame refreshed"

### M4 — Hide icon + relaunch

1. Hide menu bar icon via toggle
2. Open ClickToMin.app from Applications
3. Icon reappears within 2s, all menu items functional

### M5 — Clean brew install

1. `brew install --cask chrisnourse/clicktomin/click-to-min`
2. Launch — no Gatekeeper warning
3. Accessibility prompt fires normally

### M6 — Brew upgrade preserves TCC

1. Install, grant Accessibility, verify minimize works
2. `brew upgrade --cask click-to-min`
3. Must work without re-granting Accessibility

### M7 — Codesign identity stable

1. `codesign -dvv /Applications/ClickToMin.app 2>&1 | grep -E "Authority|Identifier"`
2. After upgrade, same Identifier and Authority

## Metrics

Performance thresholds in `qa/metrics/thresholds.json`. History in
`qa/metrics/history.jsonl` (append-only, informational).

## Troubleshooting

- **VM won't start**: UTM must be open (AppleScript needs it running)
- **SSH timeout**: `export QA_SSH_TIMEOUT=120`
- **TCC revoked after rebuild**: skip-rebuild logic in `lib/common.sh` prevents this
- **xctrace errors**: requires full Xcode; suite skips gracefully with CLT only
- **CI integration test fails**: check `scripts/ci-grant-tcc.sh` output for TCC grant issues
