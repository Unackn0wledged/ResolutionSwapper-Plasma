#!/usr/bin/env bash
# Loads a file from add-edid-mode.py at every boot, or removes that again.
#
#   sudo tools/install-edid-override.sh DP-2 edid/DP-2.bin
#   sudo tools/install-edid-override.sh --remove DP-2
set -euo pipefail

tools=$(dirname "$(readlink -f "$0")")
loader=/usr/local/bin/resolution-swapper-load-edid
unit=/etc/systemd/system/resolution-swapper-edid@.service
data=/etc/resolution-swapper

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo." >&2
    exit 1
fi

if [ "${1:-}" = "--remove" ]; then
    connector=${2:?Usage: install-edid-override.sh --remove CONNECTOR}
    systemctl disable --now "resolution-swapper-edid@$connector.service" || true
    rm -f "$data/$connector.bin"
    rmdir --ignore-fail-on-non-empty "$data" 2>/dev/null || true
    if ! ls "$data"/*.bin >/dev/null 2>&1; then
        rm -f "$loader" "$unit"
        systemctl daemon-reload
    fi
    echo "Removed. The override stays active until you reboot."
    exit 0
fi

connector=${1:?Usage: install-edid-override.sh CONNECTOR FILE}
file=${2:?Usage: install-edid-override.sh CONNECTOR FILE}

# A base EDID is 128 bytes, and each extension block adds another 128.
size=$(stat -c %s "$file")
if [ "$size" -lt 128 ] || [ $((size % 128)) -ne 0 ] || ! edid-decode "$file" >/dev/null 2>&1; then
    echo "$file does not look like an EDID." >&2
    exit 1
fi

install -D -m 644 "$file" "$data/$connector.bin"
install -m 755 "$tools/load-edid-override.sh" "$loader"
install -m 644 "$tools/resolution-swapper-edid@.service" "$unit"
systemctl daemon-reload
systemctl enable --now "resolution-swapper-edid@$connector.service"
echo "Installed. $connector gets this EDID from the next boot on."
