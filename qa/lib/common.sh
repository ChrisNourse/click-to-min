#!/usr/bin/env bash
# qa/lib/common.sh — shared helpers for ClickToMin QA scripts.
#
# Source from any qa/*.sh script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/common.sh
#   source "$SCRIPT_DIR/lib/common.sh"
#
# Dependency-light: pure bash + coreutils + Xcode toolchain. No jq, no python.

set -euo pipefail

# Resolve project root relative to this file (qa/lib/common.sh -> ../..).
QA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA_DIR="$(cd "$QA_LIB_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$QA_DIR/.." && pwd)"
QA_REPORTS_DIR="$QA_DIR/reports"
QA_HARNESS_DIR="$QA_DIR/harness/AXProbe"

# Ensure Homebrew bin dirs are on PATH so tools like cliclick resolve even
# under non-login shells (SSH, CI, launchd). Apple-silicon brew lives at
# /opt/homebrew/bin; Intel brew at /usr/local/bin.
for brew_bin in /opt/homebrew/bin /usr/local/bin; do
    if [[ -d "$brew_bin" && ":$PATH:" != *":$brew_bin:"* ]]; then
        PATH="$brew_bin:$PATH"
    fi
done
export PATH

# Color output. Disable if not a TTY or NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    QA_C_RED=$'\033[31m'
    QA_C_GRN=$'\033[32m'
    QA_C_YEL=$'\033[33m'
    QA_C_DIM=$'\033[2m'
    QA_C_RST=$'\033[0m'
else
    QA_C_RED=""
    QA_C_GRN=""
    QA_C_YEL=""
    QA_C_DIM=""
    QA_C_RST=""
fi

# --- Logging -----------------------------------------------------------------

qa::info() { printf "%s[qa]%s %s\n" "$QA_C_DIM" "$QA_C_RST" "$*"; }
qa::pass() { printf "%sPASS%s %s\n" "$QA_C_GRN" "$QA_C_RST" "$*"; }
qa::fail() { printf "%sFAIL%s %s\n" "$QA_C_RED" "$QA_C_RST" "$*" >&2; }
qa::warn() { printf "%sWARN%s %s\n" "$QA_C_YEL" "$QA_C_RST" "$*" >&2; }

# Step progress banner. Use from orchestrators to mark which phase is active.
# Usage: qa::step <current> <total> <label>
qa::step() {
    local cur="$1" total="$2" label="$3"
    printf "\n%s==> [%s/%s] %s%s\n" "$QA_C_GRN" "$cur" "$total" "$label" "$QA_C_RST"
}

# --- Paths -------------------------------------------------------------------

# Timestamped report path (markdown). Prints to stdout.
qa::report_path() {
    local stamp
    stamp="$(date +%Y-%m-%d-%H%M%S)"
    printf "%s/%s.md" "$QA_REPORTS_DIR" "$stamp"
}

# Timestamped report directory for per-suite logs. Prints to stdout.
qa::report_dir() {
    local stamp
    stamp="$(date +%Y-%m-%d-%H%M%S)"
    local dir="$QA_REPORTS_DIR/$stamp"
    mkdir -p "$dir"
    printf "%s" "$dir"
}

# --- Prereq checks -----------------------------------------------------------

qa::require_cliclick() {
    if ! command -v cliclick >/dev/null 2>&1; then
        qa::fail "cliclick not found. Install with: brew install cliclick"
        return 1
    fi
}

# Preflight: Swift toolchain must actually launch.
#
# On mismatched Command Line Tools installs (common on fresh macOS 15 VMs)
# `swift-package` aborts with a dyld "Symbol not found" in llbuild. We detect
# that by running `swift build --help`, which exercises the broken path
# without compiling anything. Errors go to a capture so we can fingerprint
# the dyld mismatch vs other failures.
#
# If --auto-repair is passed and the toolchain is broken, triggers
# `xcode-select --install` (which shows a GUI dialog) and surfaces a
# remediation path for a full Xcode install.
qa::require_swift_toolchain() {
    local auto_repair=0
    if [[ "${1:-}" == "--auto-repair" ]]; then
        auto_repair=1
    fi
    local err
    if ! err="$(swift build --help 2>&1 >/dev/null)"; then
        qa::fail "Swift toolchain is broken."
        printf "  %s\n" "$err" | head -4 >&2
        local active_dev
        active_dev="$(xcode-select -p 2>/dev/null || echo unknown)"
        qa::fail "Active developer dir: $active_dev"
        if grep -q 'llbuild' <<<"$err"; then
            qa::fail "Likely cause: Command Line Tools llbuild.framework mismatch."
        fi
        if [[ "$auto_repair" -eq 1 ]]; then
            qa::warn "Attempting repair via 'xcode-select --install' (GUI dialog)."
            xcode-select --install 2>/dev/null || true
            qa::warn "If that opens a dialog, accept it. If Xcode.app is installed:"
            qa::warn "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
            qa::warn "  sudo xcodebuild -runFirstLaunch"
            qa::warn "Re-run this script after the toolchain repair completes."
        else
            qa::fail "Remediation:"
            qa::fail "  Option 1 (Xcode): sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
            qa::fail "                    sudo xcodebuild -runFirstLaunch"
            qa::fail "  Option 2 (CLT):   sudo rm -rf /Library/Developer/CommandLineTools"
            qa::fail "                    sudo xcode-select --install"
            qa::fail "  Or run: ./qa/run-all.sh --repair-toolchain"
        fi
        return 1
    fi
}

qa::require_axprobe() {
    local bin="$QA_HARNESS_DIR/.build/release/axprobe"
    if [[ ! -x "$bin" ]]; then
        qa::fail "axprobe not built. Run: swift build -c release --package-path $QA_HARNESS_DIR"
        return 1
    fi
}

# Preflight: AXProbe must have Accessibility granted.
# Relies on axprobe exit code from its `is-trusted` subcommand.
qa::require_axprobe_granted() {
    qa::require_axprobe
    local bin
    bin="$(qa::axprobe_bin)"
    if ! "$bin" is-trusted >/dev/null 2>&1; then
        qa::fail "axprobe lacks Accessibility permission."
        qa::fail "Grant: System Settings -> Privacy & Security -> Accessibility -> add $bin"
        return 1
    fi
}

# Print path to the axprobe binary. Prefers the /usr/local/bin/axprobe shell
# wrapper (which forwards through /Applications/AXProbe.app via `open -W -a`
# so TCC can hold the Accessibility grant on macOS 15); falls back to the raw
# swift build output on systems where a bare adhoc CLI works.
qa::axprobe_bin() {
    if [[ -x /usr/local/bin/axprobe ]]; then
        printf "%s" "/usr/local/bin/axprobe"
    else
        printf "%s" "$QA_HARNESS_DIR/.build/release/axprobe"
    fi
}

# --- Build / launch ---------------------------------------------------------

# Build ClickToMin.app via build.sh. Idempotent.
qa::build_release() {
    qa::require_swift_toolchain || return 1
    qa::info "building ClickToMin.app (release)"
    # Keep stdout visible (build.sh prints progress). Errors propagate.
    (cd "$PROJECT_ROOT" && ./build.sh)
    if [[ ! -d "$PROJECT_ROOT/ClickToMin.app" ]]; then
        qa::fail "ClickToMin.app not produced by build.sh"
        return 1
    fi
}

# Build the AXProbe harness in release mode.
qa::build_axprobe() {
    qa::require_swift_toolchain || return 1
    qa::info "building AXProbe (release) — this takes 1-3 min on first build"
    # Keep swift-build output visible so long builds show progress and real
    # errors surface instead of getting swallowed by /dev/null.
    swift build -c release --package-path "$QA_HARNESS_DIR"
    local bin="$QA_HARNESS_DIR/.build/release/axprobe"
    if [[ ! -x "$bin" ]]; then
        qa::fail "axprobe not produced at $bin"
        return 1
    fi
    # Swift's linker produces an `adhoc,linker-signed` signature, which macOS
    # TCC treats as a non-code-signed binary and refuses to cache Accessibility
    # grants for. Re-sign with a real ad-hoc signature so toggling axprobe ON
    # in System Settings actually sticks across rebuilds.
    codesign --force --sign - "$bin" >/dev/null 2>&1 || qa::warn "codesign re-sign failed on $bin"

    # On macOS 15 a bare CLI cannot hold a TCC grant — axprobe must run inside
    # /Applications/AXProbe.app via `open -W -a`. If that bundle exists, warn
    # when its embedded binary is older than the just-built one so the user
    # knows to run qa/shared/refresh-axprobe-bundle.sh (requires sudo, which
    # we deliberately DON'T invoke from this tee'd orchestrator — the password
    # prompt can't be answered).
    local app="/Applications/AXProbe.app"
    if [[ -d "$app" ]]; then
        local app_bin="$app/Contents/MacOS/axprobe"
        if [[ -f "$app_bin" && "$bin" -nt "$app_bin" ]]; then
            qa::warn "$app has a stale embedded axprobe."
            qa::warn "Refresh with: sudo ./qa/shared/refresh-axprobe-bundle.sh"
            qa::warn "Until you do, the wrapper at /usr/local/bin/axprobe runs old code."
        fi
    fi

    qa::info "axprobe built: $bin"
}

# Block until Accessibility permission is granted to the axprobe binary.
# Polls `axprobe is-trusted` every 3s. Prints the exact path to grant once,
# then a concise spinner-style dot line so the user can walk away and come
# back. Honors AX_GATE_TIMEOUT (seconds, default 600 = 10 min) to avoid
# infinite hangs in unattended/CI runs. Returns 0 when trusted, 1 on timeout.
qa::require_accessibility() {
    # Prefer /usr/local/bin/axprobe if it exists — on macOS 15 it's the
    # shell wrapper that forwards through /Applications/AXProbe.app via
    # `open -W -a`, which is the only invocation path that picks up the
    # bundle's TCC Accessibility grant. Fall back to the raw swift build
    # binary on older systems where a bare adhoc CLI can hold TCC grants.
    local bin
    if [[ -x /usr/local/bin/axprobe ]]; then
        bin="/usr/local/bin/axprobe"
    else
        bin="$QA_HARNESS_DIR/.build/release/axprobe"
    fi
    if [[ ! -x "$bin" ]]; then
        qa::fail "axprobe not built — cannot check Accessibility"
        return 1
    fi
    # Resolve the symlink — TCC stores permissions against the canonical path
    # (arm64-apple-macosx/release/axprobe), and adding via the `.build/release`
    # symlink in Finder sometimes results in a TCC entry that doesn't match
    # what AXIsProcessTrusted() sees. Always show/add the resolved path.
    local real_bin
    real_bin="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$bin" 2>/dev/null || echo "$bin")"
    if "$real_bin" is-trusted >/dev/null 2>&1; then
        qa::pass "Accessibility already granted to axprobe"
        return 0
    fi

    local timeout="${AX_GATE_TIMEOUT:-600}"
    qa::warn "Accessibility permission NOT granted to axprobe."
    printf "\n"
    printf "  Grant it now so the suite can drive AX queries:\n"
    printf "    1. System Settings -> Privacy & Security -> Accessibility\n"
    printf "    2. Click '+' -> press Cmd+Shift+G -> paste this binary path:\n"
    printf "       %s\n" "$real_bin"
    printf "    3. Toggle it ON.\n"
    printf "\n"
    printf "  Also grant ClickToMin.app the same way once it's built (the\n"
    printf "  suite will remind you if/when it needs that too).\n"
    printf "\n"
    qa::info "waiting up to ${timeout}s for grant (polling every 3s)…"

    local waited=0
    while (( waited < timeout )); do
        if "$real_bin" is-trusted >/dev/null 2>&1; then
            printf "\n"
            qa::pass "Accessibility granted after ${waited}s"
            return 0
        fi
        printf "."
        sleep 3
        waited=$(( waited + 3 ))
    done
    printf "\n"
    qa::fail "Accessibility not granted within ${timeout}s — aborting"
    return 1
}

# Launch ClickToMin.app. Optional env vars passed through.
# Usage: qa::launch_app [ENV_VAR=value ...]
qa::launch_app() {
    qa::info "launching ClickToMin.app"
    # Ensure a clean launch so lifecycle signposts fire in this test window.
    # If a prior suite (or crashed run) left ClickToMin alive, `open` would
    # just activate it — no new signposts — and smoke tests would fail.
    if pgrep -x ClickToMin >/dev/null 2>&1; then
        osascript -e 'tell application "ClickToMin" to quit' >/dev/null 2>&1 || true
        local j
        for j in 1 2 3 4 5; do
            pgrep -x ClickToMin >/dev/null 2>&1 || break
            sleep 0.3
        done
        pkill -x ClickToMin 2>/dev/null || true
        sleep 0.3
    fi
    env "$@" open "$PROJECT_ROOT/ClickToMin.app"
    # Give AppKit time to register the app AND let ClickToMin install its
    # CGEventTap. Under orchestrator load on slower hosts (e.g. VMs), 1s is
    # too tight — the first Dock click after launch can hit the tap before
    # it's armed, so the mutation never fires and wait-until-minimized
    # times out.
    sleep 2.5
}

# Quit ClickToMin via AppleScript. Asserts the process exits.
qa::quit_app() {
    osascript -e 'tell application "ClickToMin" to quit' >/dev/null 2>&1 || true
    # allow graceful shutdown
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if ! pgrep -x ClickToMin >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    qa::warn "ClickToMin did not exit cleanly; sending SIGTERM"
    pkill -x ClickToMin || true
}

qa::assert_process_running() {
    local name="$1"
    if ! pgrep -x "$name" >/dev/null 2>&1; then
        qa::fail "$name is not running"
        return 1
    fi
}

qa::assert_process_not_running() {
    local name="$1"
    if pgrep -x "$name" >/dev/null 2>&1; then
        qa::fail "$name unexpectedly still running"
        return 1
    fi
}

# Capture `log stream` output filtered by subsystem/category for N seconds.
# Prints the captured log to stdout. Requires no Accessibility permission.
#
# Note: this captures events emitted during the window only. If you need to
# observe signposts that fire as part of launch, either (a) start this in
# the background before launching, or (b) use `qa::log_show_last` after the
# launch window closes to read the past N seconds.
#
# Usage: qa::log_stream_capture <category> <seconds>
#   category: lifecycle | pipeline | "" (all subsystem traffic)
qa::log_stream_capture() {
    local category="$1"
    local seconds="$2"
    local predicate='subsystem == "com.click-to-min"'
    if [[ -n "$category" ]]; then
        predicate="$predicate && category == \"$category\""
    fi
    local tmp
    tmp="$(mktemp -t clicktomin-logstream)"
    # `log stream` runs until killed. Background it, wait N seconds, kill.
    # `--info --debug` is required: ClickToMin signposts are emitted at
    # os_log type .info which `log stream` hides by default.
    /usr/bin/log stream --style syslog --info --debug --predicate "$predicate" >"$tmp" 2>/dev/null &
    local log_pid=$!
    sleep "$seconds"
    kill "$log_pid" 2>/dev/null || true
    wait "$log_pid" 2>/dev/null || true
    cat "$tmp"
    rm -f "$tmp"
}

# Read the *past* N seconds of log events filtered by subsystem/category.
# Use this to observe signposts that fire during app launch (which `log
# stream` would miss because it only sees future events).
#
# Usage: qa::log_show_last <category> <seconds>
qa::log_show_last() {
    local category="$1"
    local seconds="$2"
    local predicate='subsystem == "com.click-to-min"'
    if [[ -n "$category" ]]; then
        predicate="$predicate && category == \"$category\""
    fi
    # `--info --debug` is required: all ClickToMin signposts are emitted at
    # os_log type .info, which `log show` hides by default.
    /usr/bin/log show --style syslog --info --debug --last "${seconds}s" --predicate "$predicate" 2>/dev/null
}
