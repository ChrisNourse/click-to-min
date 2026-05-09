# QA VM Setup Guide

One-time setup to create a macOS VM for running the ClickToMin QA suite.

## Requirements

- Apple Silicon Mac (M1+)
- UTM 4.x+ installed from https://mac.getutm.app
- macOS IPSW file (download from Apple: Settings > General > Software Update,
  or https://ipsw.me for specific versions)
- ~60 GB free disk space on host

## Create the VM

1. Open UTM
2. Create a New Virtual Machine > Virtualize > macOS
3. Select your IPSW file (macOS 13+ required, 15.x recommended)
4. Configuration:
   - RAM: **8192 MB** minimum
   - CPU: default (all cores)
   - Disk: **64 GB** minimum (CLT needs ~2 GB, brew ~2 GB, builds ~1 GB)
   - Display: default
   - Network: Shared Network (default — gives 192.168.64.x via DHCP)
5. Name the VM: `macOS` (matches the default in `remote-run.sh`)
6. Boot and complete macOS setup:
   - Create user: `tester` (or any name — configure in `QA_SSH_HOST` env var)
   - Skip Apple ID sign-in
   - Skip Screen Time, Siri, etc.

## Enable SSH

On the VM:
1. System Settings > General > Sharing
2. Enable **Remote Login**
3. Set to allow access for your user

Find the VM's IP (from VM terminal):
```bash
ipconfig getifaddr en0
```

From host, copy your SSH key:
```bash
ssh-copy-id tester@192.168.64.5
```

## Run Bootstrap

From the host:
```bash
scp qa/vm-setup/bootstrap.sh tester@192.168.64.5:~/
ssh tester@192.168.64.5 "chmod +x ~/bootstrap.sh && ~/bootstrap.sh"
```

This installs: CLT, Homebrew, cliclick, builds AXProbe.app, builds ClickToMin.app.

NOTE: The Xcode Command Line Tools install pops a dialog on the VM screen
asking you to agree to the license. Watch the UTM window and click
"Install" / "Agree" when prompted.

## Grant Accessibility (one-time, manual)

On the VM (look at the UTM window):
1. System Settings > Privacy & Security > Accessibility
2. Click the lock to unlock
3. Click '+', navigate to and add ALL of the following:
   - `/Applications/AXProbe.app`
   - `~/click-to-min/ClickToMin.app`
   - `/opt/homebrew/bin/cliclick`
   - `/System/Applications/Utilities/Terminal.app`
4. Ensure all four are toggled ON

NOTE: macOS may also pop up dialogs asking to allow apps to "control your
computer" during the test run. Click "Allow" or "OK" on those if they appear.

## Take a Snapshot

In UTM, right-click the VM > Snapshots > Take Snapshot.
Name it `qa-ready`. This lets you reset to a clean known-good state.

## Usage

From the host project root:
```bash
./qa/remote-run.sh              # full suite (boots VM if stopped)
./qa/remote-run.sh --ci         # CI subset only
./qa/remote-run.sh --keep-alive # leave VM running after
./qa/remote-run.sh --skip-sync  # don't git pull
```

## Configuration

Environment variables (set in shell or `.env`):

| Variable | Default | Description |
|----------|---------|-------------|
| `QA_VM_NAME` | `macOS` | UTM virtual machine name |
| `QA_SSH_HOST` | `tester@192.168.64.5` | SSH user@host for the VM |
| `QA_SSH_KEY` | (agent) | Path to SSH private key |
| `QA_SSH_TIMEOUT` | `90` | Seconds to wait for SSH after VM boot |
| `QA_REMOTE_DIR` | `~/click-to-min` | Repo path on VM |

## Troubleshooting

**VM won't start:** Check UTM is running. `osascript` requires UTM to be open.

**SSH timeout:** VM may need longer to boot. Increase `QA_SSH_TIMEOUT=120`.

**Accessibility revoked after rebuild:** The ad-hoc codesign identity changes.
Re-grant in System Settings, or use the persistent signing cert from CI
(scripts/generate-signing-cert.sh).

**Disk full on VM:** Full Xcode is NOT needed. CLT (~2 GB) is sufficient.
If you installed Xcode.app, remove it: `sudo rm -rf /Applications/Xcode.app`

**cliclick "not permitted":** Grant Accessibility to Terminal.app on the VM.
