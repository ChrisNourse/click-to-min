# qa/ — ClickToMin QA Automation

One-command test runner for the full ClickToMin QA suite. Tests run in a macOS
VM via UTM to avoid disrupting your workspace.

## Quick Start

```bash
./qa/run.sh                # boot VM, sync, run all suites, fetch report
./qa/run.sh --ci           # CI-safe subset only (no VM needed)
./qa/run.sh --keep-alive   # leave VM running after
./qa/run.sh --skip-sync    # don't rsync to VM
```

Reports land in `qa/reports/<timestamp>.md` with inline metrics and warnings.

## First-Time VM Setup

### 1. Create VM in UTM

1. Open UTM → Create New → Virtualize → macOS
2. Let it download the IPSW (or select one manually)
3. Config: **8 GB RAM**, **4 cores**, **64 GB disk**
4. Name: `macOS` (or set `QA_VM_NAME` env var)
5. Boot, create user `tester`, skip Apple ID/Siri/Screen Time

### 2. Enable SSH

On the VM: System Settings → General → Sharing → **Remote Login** ON.

Find the VM's IP — open Terminal on the VM and run:
```bash
ipconfig getifaddr en0
```
It will be something like `192.168.64.x` (UTM shared networking uses this range).

From your host, copy your SSH key:
```bash
ssh-copy-id tester@192.168.64.x   # replace x with the IP from above
```

Verify passwordless login works:
```bash
ssh tester@192.168.64.x "echo ok"
```

### 3. Run Bootstrap

```bash
scp qa/vm-setup/bootstrap.sh tester@<IP>:~/
ssh tester@<IP> "chmod +x ~/bootstrap.sh && ~/bootstrap.sh"
```

Installs: Xcode CLT, Homebrew, cliclick, AXProbe.app, ClickToMin.app.

NOTE: CLT install pops a dialog on the VM screen — click "Install"/"Agree".

### 4. Grant Accessibility (one-time, on VM screen)

System Settings → Privacy & Security → Accessibility → add ALL:
- `/Applications/AXProbe.app`
- `~/click-to-min/ClickToMin.app`
- `/opt/homebrew/bin/cliclick`
- Terminal.app

Also click "Allow" on any popup dialogs asking to control the computer.

### 5. Snapshot

Right-click VM in UTM → Take Snapshot → name it `qa-ready`.

Done. `./qa/run.sh` works from now on.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `QA_VM_NAME` | `macOS` | UTM virtual machine name |
| `QA_SSH_HOST` | `tester@192.168.64.5` | SSH user@host |
| `QA_SSH_KEY` | (agent) | SSH private key path |
| `QA_SSH_TIMEOUT` | `90` | Seconds to wait for SSH after boot |
| `QA_REMOTE_DIR` | `~/click-to-min` | Repo path on VM |

## Suites

| Script | What | Needs AX? | Needs Xcode? |
|--------|------|-----------|--------------|
| 00-startup | Cold launch timing | Yes | No |
| 01-smoke | Build, codesign, signposts | No | No |
| 02-core-behavior | 3-click cycle + latency | Yes | No |
| 03-edge-cases | Frozen app, debounce, multi-window, modifiers | Yes | No |
| 04-dock-config | Tile size, orientation, auto-hide | Yes | No |
| 05-perf-instruments | RSS, CPU, tap overhead, xctrace | Yes | xctrace only |
| 06-settings | Enable/disable toggle, icon-hide | Yes | No |

## Metrics

Performance metrics are recorded in `qa/metrics/history.jsonl` and classified
against thresholds in `qa/metrics/thresholds.json`:

| Metric | Green | Orange | Red |
|--------|-------|--------|-----|
| startup | <1000ms | 1-2s | >2s |
| memory | <40MB | 40-80MB | >80MB |
| idle-cpu | <1 wake/s | 1-10 | >10 |
| tap-overhead | <100us | 100-500us | >500us |
| latency | <250ms | 250-500ms | >500ms |

## Layout

```
qa/
├── run.sh              host-side orchestrator (UTM + rsync + SSH)
├── README.md           this file
├── MANUAL-CHECKLIST.md non-automatable items (sleep/wake, display hot-plug)
├── suites/             test scripts + orchestrator
│   ├── run-all.sh      suite runner (called by run.sh on the VM)
│   ├── 00-startup.sh .. 06-settings.sh
├── lib/                shared bash helpers
│   ├── common.sh       build, launch, log, assertion helpers
│   ├── report.sh       markdown report + enrichment
│   ├── metrics.sh      history, badges, regression guard
│   └── xctrace-parse.sh
├── harness/AXProbe/    Swift CLI for AX queries
├── metrics/            thresholds + badge output
├── reports/            timestamped run output (gitignored)
└── vm-setup/
    └── bootstrap.sh    first-time VM provisioning
```

## CI

The `qa-smoke` job in `.github/workflows/ci.yml` runs on every PR:
- Builds AXProbe
- Runs `01-smoke.sh` (no Accessibility needed)

## Troubleshooting

- **VM won't start**: UTM must be open (AppleScript needs it running)
- **SSH timeout**: Increase `QA_SSH_TIMEOUT=120`
- **TCC revoked after rebuild**: The skip-rebuild logic in `lib/common.sh`
  prevents this. If it happens, re-grant ClickToMin.app in System Settings.
- **xctrace errors**: Requires full Xcode. Suite skips gracefully with CLT only.
- **cliclick permission**: Grant Terminal.app Accessibility on the VM.
