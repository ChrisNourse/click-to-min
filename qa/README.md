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
- `/System/Applications/Utilities/Terminal.app`

Also click "Allow" on any popup dialogs asking to control the computer.

### 5. Update QA_SSH_HOST

Set the VM IP in your shell so `run.sh` connects to the right place:
```bash
export QA_SSH_HOST="tester@192.168.64.x"
```

Or add it to your `.zshrc`/`.bashrc` to persist across sessions.

Done. `./qa/run.sh` works from now on.

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

Performance thresholds and history are in `qa/metrics/thresholds.json`.
See that file for green/orange/red classification values.

## CI

The `qa-smoke` job in `.github/workflows/ci.yml` runs on every PR:
- Builds AXProbe
- Runs `01-smoke.sh` (no Accessibility needed)

## Troubleshooting

- **VM won't start**: UTM must be open (AppleScript needs it running)
- **SSH timeout**: `export QA_SSH_TIMEOUT=120`
- **TCC revoked after rebuild**: The skip-rebuild logic in `lib/common.sh`
  prevents this. If it happens, re-grant ClickToMin.app in System Settings.
- **xctrace errors**: Requires full Xcode. Suite skips gracefully with CLT only.
- **cliclick permission**: Grant `/System/Applications/Utilities/Terminal.app` Accessibility on the VM.
