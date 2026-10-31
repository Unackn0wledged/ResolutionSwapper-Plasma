#!/usr/bin/env bash
# Installs the widget for the current user, or upgrades an existing install.
set -euo pipefail

id=com.github.unackn0wledged.resolutionswapper
package="$(dirname "$(readlink -f "$0")")/package"

if kpackagetool6 --type Plasma/Applet --show "$id" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$package"
    echo "Upgraded. Restart Plasma to load the new version:"
    echo "  systemctl --user restart plasma-plasmashell"
else
    kpackagetool6 --type Plasma/Applet --install "$package"
    echo "Installed. Add \"Resolution Swapper\" from the Add Widgets panel."
fi
