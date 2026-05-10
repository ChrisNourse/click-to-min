#!/usr/bin/env bash
# qa/remote-run.sh — one-command QA runner using UTM + SSH.
#
# Boots the QA VM via AppleScript, syncs the current branch, runs the full
# suite, fetches the report back to the host, and prints an enriched summary.
#
# Prerequisites:
#   - UTM installed at /Applications/UTM.app
#   - VM created and bootstrapped (see qa/vm-setup/README.md)
#   - SSH key copied to VM (ssh-copy-id)
#
# Usage:
#   ./qa/remote-run.sh              # full suite
#   ./qa/remote-run.sh --ci         # CI-safe subset only
#   ./qa/remote-run.sh --keep-alive # don't stop VM after run
#   ./qa/remote-run.sh --skip-sync  # don't git pull on VM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QA_VM_NAME="${QA_VM_NAME:-macOS}"
QA_SSH_HOST="${QA_SSH_HOST:-tester@192.168.64.5}"
QA_SSH_KEY="${QA_SSH_KEY:-}"
QA_REMOTE_DIR="${QA_REMOTE_DIR:-~/click-to-min}"
QA_SSH_TIMEOUT="${QA_SSH_TIMEOUT:-90}"

MODE=""
KEEP_ALIVE=0
SKIP_SYNC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci) MODE="--ci"; shift ;;
        --keep-alive) KEEP_ALIVE=1; shift ;;
        --skip-sync) SKIP_SYNC=1; shift ;;
        -h|--help)
            printf "Usage: %s [--ci] [--keep-alive] [--skip-sync]\n" "$0"
            exit 0
            ;;
        *) printf "unknown flag: %s\n" "$1" >&2; exit 1 ;;
    esac
done

SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
if [[ -n "$QA_SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$QA_SSH_KEY")
fi

C_GRN=$'\033[32m'
C_RED=$'\033[31m'
C_DIM=$'\033[2m'
C_RST=$'\033[0m'

info() { printf "%s[qa-remote]%s %s\n" "$C_DIM" "$C_RST" "$*"; }
pass() { printf "%sPASS%s %s\n" "$C_GRN" "$C_RST" "$*"; }
fail() { printf "%sFAIL%s %s\n" "$C_RED" "$C_RST" "$*" >&2; }

utm_status() {
    osascript -e "tell application \"UTM\" to get status of virtual machine named \"$QA_VM_NAME\"" 2>/dev/null
}

utm_start() {
    osascript -e "tell application \"UTM\" to start virtual machine named \"$QA_VM_NAME\"" 2>/dev/null
}

utm_stop() {
    osascript -e "tell application \"UTM\" to stop virtual machine named \"$QA_VM_NAME\"" 2>/dev/null
}

wait_ssh() {
    local elapsed=0
    while (( elapsed < QA_SSH_TIMEOUT )); do
        if ssh "${SSH_OPTS[@]}" "$QA_SSH_HOST" "true" 2>/dev/null; then
            return 0
        fi
        sleep 3
        elapsed=$(( elapsed + 3 ))
        printf "."
    done
    printf "\n"
    return 1
}

remote() {
    ssh "${SSH_OPTS[@]}" "$QA_SSH_HOST" "$@"
}

info "VM: $QA_VM_NAME | Host: $QA_SSH_HOST"

STATUS="$(utm_status || echo unknown)"
if [[ "$STATUS" == "started" ]]; then
    info "VM already running"
elif [[ "$STATUS" == "stopped" || "$STATUS" == "paused" ]]; then
    info "starting VM..."
    utm_start
    sleep 5
else
    fail "VM status: $STATUS — cannot proceed"
    exit 1
fi

info "waiting for SSH..."
if ! wait_ssh; then
    fail "SSH not reachable within ${QA_SSH_TIMEOUT}s"
    exit 1
fi
printf "\n"
info "SSH connected"

BRANCH="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
SHA="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
info "branch: $BRANCH ($SHA)"

if [[ "$SKIP_SYNC" -eq 0 ]]; then
    info "syncing working tree to VM via rsync..."
    remote "mkdir -p $QA_REMOTE_DIR" 2>/dev/null
    rsync -az --delete \
        --exclude '.build' \
        --exclude '.git' \
        --exclude 'ClickToMin.app' \
        --exclude '.swiftpm' \
        --exclude 'qa/reports' \
        --exclude 'qa/harness/AXProbe/.build' \
        --exclude 'clicktomin-release.p12' \
        -e "ssh ${SSH_OPTS[*]}" \
        "$PROJECT_ROOT/" "$QA_SSH_HOST:$QA_REMOTE_DIR/"
    info "synced"
fi

info "running QA suite${MODE:+ ($MODE)}..."
REMOTE_RC=0
REMOTE_OUTPUT="$(remote "eval \"\$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)\" && cd $QA_REMOTE_DIR && ./qa/run-all.sh $MODE 2>&1" || true)"
REMOTE_RC=$?

printf "%s\n" "$REMOTE_OUTPUT"

REPORT_LINE="$(grep '^report:' <<<"$REMOTE_OUTPUT" || true)"
REPORT_PATH="${REPORT_LINE#report: }"
REPORT_PATH="${REPORT_PATH## }"

if [[ -z "$REPORT_PATH" ]]; then
    REPORT_DIR_REMOTE="$(remote "ls -td $QA_REMOTE_DIR/qa/reports/2* 2>/dev/null | head -1" || true)"
    REPORT_PATH="${REPORT_DIR_REMOTE%.md}"
fi

REPORT_BASENAME="$(basename "${REPORT_PATH%.md}" 2>/dev/null || echo "unknown")"
LOCAL_REPORT_DIR="$PROJECT_ROOT/qa/reports/$REPORT_BASENAME"
mkdir -p "$LOCAL_REPORT_DIR"

info "fetching report..."
scp -r "${SSH_OPTS[@]}" "$QA_SSH_HOST:$QA_REMOTE_DIR/qa/reports/$REPORT_BASENAME/*" "$LOCAL_REPORT_DIR/" 2>/dev/null || true
scp "${SSH_OPTS[@]}" "$QA_SSH_HOST:$QA_REMOTE_DIR/qa/reports/${REPORT_BASENAME}.md" "$PROJECT_ROOT/qa/reports/" 2>/dev/null || true

if [[ -f "$PROJECT_ROOT/qa/reports/${REPORT_BASENAME}.md" ]]; then
    info "generating enriched report..."
    source "$SCRIPT_DIR/lib/report.sh"
    qa::enrich_report "$PROJECT_ROOT/qa/reports/${REPORT_BASENAME}.md" "$LOCAL_REPORT_DIR"
fi

if [[ "$KEEP_ALIVE" -eq 0 ]]; then
    info "stopping VM..."
    utm_stop || true
fi

printf "\n"
if grep -q "PASS run-all" <<<"$REMOTE_OUTPUT"; then
    pass "QA suite passed"
    info "report: qa/reports/${REPORT_BASENAME}.md"
    exit 0
else
    fail "QA suite failed"
    info "report: qa/reports/${REPORT_BASENAME}.md"
    info "logs: qa/reports/$REPORT_BASENAME/"
    exit 1
fi
