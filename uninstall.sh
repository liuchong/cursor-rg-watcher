#!/bin/bash
set -euo pipefail

readonly LABEL="com.user.watchrg"
readonly INSTALL_SCRIPT="$HOME/.local/bin/cursor-rg-watcher.sh"
readonly LEGACY_INSTALL_SCRIPT="$HOME/.local/bin/watch_and_delete_cursor_rg.sh"
readonly LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
/bin/rm -f -- "$LAUNCH_AGENT_PLIST"
/bin/rm -f -- "$INSTALL_SCRIPT"

printf 'Uninstalled %s.\n' "$LABEL"
if [ -f "$LEGACY_INSTALL_SCRIPT" ]; then
    printf 'Legacy script still exists: %s\n' "$LEGACY_INSTALL_SCRIPT"
fi
