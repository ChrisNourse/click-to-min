#!/usr/bin/env bash
# scripts/ci-grant-tcc.sh — Grant TCC permissions for CI integration testing.
#
# Grants Accessibility, ListenEvent, PostEvent, and ScreenCapture to the
# specified binaries using csreq blobs for proper runtime validation.
# Must be run with sudo. Requires macOS 13+ (uses named columns for TCC.db).
#
# Usage: sudo scripts/ci-grant-tcc.sh <binary1> [binary2] ...

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <binary1> [binary2] ..." >&2
    exit 1
fi

USER_TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYSTEM_TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

grant_tcc() {
    local bin="$1" service="$2"
    codesign -dr - "$bin" 2>&1 | awk -F ' => ' '/designated/{print $2}' | csreq -r- -b /tmp/csreq.bin
    local csreq_hex
    csreq_hex=$(xxd -p /tmp/csreq.bin | tr -d '\n')
    local sql="INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier_type, indirect_object_identifier) VALUES ('$service','$bin',1,2,3,1,X'$csreq_hex',0,'UNUSED');"
    sqlite3 "$USER_TCC_DB" "$sql" 2>/dev/null || true
    sqlite3 "$SYSTEM_TCC_DB" "$sql" 2>/dev/null \
        && echo "  $service -> $(basename "$bin") OK" \
        || echo "  $service -> $(basename "$bin") FAILED"
}

for bin in "$@"; do
    if [[ ! -f "$bin" ]]; then
        echo "WARN: $bin not found, skipping" >&2
        continue
    fi
    for service in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent kTCCServiceScreenCapture; do
        grant_tcc "$bin" "$service"
    done
done

killall tccd 2>/dev/null || true
echo "TCC grants complete (tccd restarted)"
