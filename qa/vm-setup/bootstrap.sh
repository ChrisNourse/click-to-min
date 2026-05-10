#!/usr/bin/env bash
# qa/vm-setup/bootstrap.sh — first-time QA VM provisioning.
#
# Run this ON the VM after:
#   1. macOS installed in UTM (Apple Virtualization)
#   2. User account created
#   3. SSH enabled (System Settings -> General -> Sharing -> Remote Login)
#   4. SSH key copied from host: ssh-copy-id tester@<ip>
#
# This script is idempotent — safe to re-run.
#
# Usage (from host):
#   scp qa/vm-setup/bootstrap.sh tester@192.168.64.5:~/
#   ssh tester@192.168.64.5 "chmod +x ~/bootstrap.sh && ~/bootstrap.sh"

set -euo pipefail

C_GRN=$'\033[32m'
C_YEL=$'\033[33m'
C_RST=$'\033[0m'

info() { printf "%s[bootstrap]%s %s\n" "$C_GRN" "$C_RST" "$*"; }
warn() { printf "%s[bootstrap]%s %s\n" "$C_YEL" "$C_RST" "$*"; }

USER_NAME="$(whoami)"
info "provisioning QA VM for user: $USER_NAME"

# --- Passwordless sudo -------------------------------------------------------
if sudo -n true 2>/dev/null; then
    info "sudo: already passwordless"
else
    info "sudo: configuring passwordless for $USER_NAME"
    echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER_NAME" >/dev/null
    sudo chmod 440 "/etc/sudoers.d/$USER_NAME"
    info "sudo: done (re-enter password once if prompted)"
fi

# --- Xcode Command Line Tools ------------------------------------------------
if xcode-select -p >/dev/null 2>&1; then
    info "CLT: already installed at $(xcode-select -p)"
else
    info "CLT: installing (this takes a few minutes)..."
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    info "CLT: installed"
fi

# --- Homebrew -----------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
    info "brew: already installed"
else
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        info "brew: found at /opt/homebrew, added to PATH"
    else
        info "brew: installing..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        info "brew: installed"
    fi
    if ! grep -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
fi

# --- cliclick -----------------------------------------------------------------
if command -v cliclick >/dev/null 2>&1; then
    info "cliclick: already installed"
else
    info "cliclick: installing..."
    brew install cliclick
    info "cliclick: installed"
fi

# --- Project directory ---------------------------------------------------------
REPO_DIR="$HOME/click-to-min"
mkdir -p "$REPO_DIR"
info "repo: directory ready at $REPO_DIR (synced via rsync from host)"

# --- Code signing identity for TCC persistence ---------------------------------
CERT_NAME="ClickToMin Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
    info "signing cert: '$CERT_NAME' already in keychain"
else
    info "signing cert: creating '$CERT_NAME' for TCC persistence"
    P12_PASS="localdev"
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/ctm-key.pem -out /tmp/ctm-cert.pem \
        -days 7300 -nodes -subj "/CN=$CERT_NAME" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" 2>/dev/null
    openssl pkcs12 -export -out /tmp/ctm-dev.p12 \
        -inkey /tmp/ctm-key.pem -in /tmp/ctm-cert.pem \
        -passout "pass:$P12_PASS" 2>/dev/null
    security unlock-keychain -p "${USER_PASSWORD:-tester123}" "$KEYCHAIN" 2>/dev/null || true
    security import /tmp/ctm-dev.p12 -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "${USER_PASSWORD:-tester123}" "$KEYCHAIN" >/dev/null 2>&1
    rm -f /tmp/ctm-key.pem /tmp/ctm-cert.pem /tmp/ctm-dev.p12
    info "signing cert: installed"
fi

# --- Build AXProbe + create .app bundle for TCC persistence -------------------
if [[ -d "$REPO_DIR/qa/harness/AXProbe" ]]; then
    info "axprobe: building..."
    (cd "$REPO_DIR" && swift build -c release --package-path qa/harness/AXProbe)
    AXPROBE_BIN="$REPO_DIR/qa/harness/AXProbe/.build/release/axprobe"
    codesign --force --sign - "$AXPROBE_BIN" 2>/dev/null || true

APP_BUNDLE="/Applications/AXProbe.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    info "axprobe: creating $APP_BUNDLE bundle for TCC persistence"
    sudo mkdir -p "$APP_BUNDLE/Contents/MacOS"
    sudo cp "$AXPROBE_BIN" "$APP_BUNDLE/Contents/MacOS/axprobe"
    sudo tee "$APP_BUNDLE/Contents/Info.plist" >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.click-to-min.axprobe</string>
    <key>CFBundleName</key>
    <string>AXProbe</string>
    <key>CFBundleExecutable</key>
    <string>axprobe</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
PLIST
    sudo codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
else
    info "axprobe: $APP_BUNDLE already exists, updating binary"
    sudo cp "$AXPROBE_BIN" "$APP_BUNDLE/Contents/MacOS/axprobe"
    sudo codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

# --- /usr/local/bin/axprobe wrapper -------------------------------------------
WRAPPER="/usr/local/bin/axprobe"
if [[ ! -f "$WRAPPER" ]]; then
    info "axprobe: creating wrapper at $WRAPPER"
    sudo mkdir -p /usr/local/bin
    sudo tee "$WRAPPER" >/dev/null <<'WRAP'
#!/usr/bin/env bash
exec /Applications/AXProbe.app/Contents/MacOS/axprobe "$@"
WRAP
    sudo chmod +x "$WRAPPER"
else
    info "axprobe: wrapper exists at $WRAPPER"
fi

# --- Build ClickToMin.app -----------------------------------------------------
    info "clicktomin: building..."
    (cd "$REPO_DIR" && ./build.sh)
    info "clicktomin: built at $REPO_DIR/ClickToMin.app"
else
    warn "repo source not synced yet — skipping builds. Run remote-run.sh to sync first."
fi

# --- Summary ------------------------------------------------------------------
printf "\n"
info "=== Bootstrap complete ==="
printf "\n"
printf "  ┌─────────────────────────────────────────────────────────┐\n"
printf "  │  ACTION REQUIRED — on the VM screen (UTM window)        │\n"
printf "  └─────────────────────────────────────────────────────────┘\n"
printf "\n"
printf "  Open System Settings -> Privacy & Security -> Accessibility\n"
printf "  Click '+' and add ALL of the following:\n"
printf "\n"
printf "     1. /Applications/AXProbe.app\n"
printf "     2. %s/ClickToMin.app\n" "$REPO_DIR"
printf "     3. /opt/homebrew/Cellar/cliclick/*/bin/cliclick\n"
printf "        (or just: /opt/homebrew/bin/cliclick)\n"
printf "     4. /System/Applications/Utilities/Terminal.app\n"
printf "\n"
printf "  Toggle ALL four ON.\n"
printf "\n"
printf "  NOTE: macOS may also pop up dialogs asking to allow\n"
printf "  apps to 'control your computer' — click Allow/OK on those.\n"
printf "\n"
printf "  After that, run from your host:\n"
printf "    ./qa/remote-run.sh\n"
printf "\n"
printf "  Recommended: take a UTM snapshot now so you can reset to this state.\n"
printf "\n"
