#!/bin/bash
set -euo pipefail

readonly LABEL="com.user.watchrg"
readonly SCRIPT_NAME="cursor-rg-watcher.sh"
readonly INSTALL_BIN_DIR="$HOME/.local/bin"
readonly INSTALL_SCRIPT="$INSTALL_BIN_DIR/$SCRIPT_NAME"
readonly LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
readonly LAUNCH_AGENT_PLIST="$LAUNCH_AGENT_DIR/$LABEL.plist"
readonly WATCH_PATH="/Applications/Cursor.app/Contents/Resources/app/node_modules/@vscode/ripgrep/bin"
readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SOURCE_SCRIPT="$REPO_DIR/bin/$SCRIPT_NAME"

usage() {
    cat <<EOF
Usage: ./install.sh [--unload-only]

Install cursor-rg-watcher for the current macOS user.

Options:
  --unload-only  Stop and unload the launchd service without removing files.
EOF
}

unload_service() {
    /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
}

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --unload-only)
        unload_service
        printf 'Unloaded %s if it was loaded.\n' "$LABEL"
        exit 0
        ;;
    "")
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [ ! -f "$SOURCE_SCRIPT" ]; then
    printf 'Error: source script not found: %s\n' "$SOURCE_SCRIPT" >&2
    exit 1
fi

/bin/mkdir -p "$INSTALL_BIN_DIR" "$LAUNCH_AGENT_DIR" "$HOME/Library/Logs"
/bin/cp "$SOURCE_SCRIPT" "$INSTALL_SCRIPT"
/bin/chmod 755 "$INSTALL_SCRIPT"

/bin/cat > "$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$INSTALL_SCRIPT</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WatchPaths</key>
	<array>
		<string>$WATCH_PATH</string>
	</array>
	<key>StartInterval</key>
	<integer>10</integer>
	<key>StandardOutPath</key>
	<string>$HOME/Library/Logs/watchrg.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/watchrg.err</string>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$LAUNCH_AGENT_PLIST" >/dev/null
unload_service
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$LAUNCH_AGENT_PLIST"
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$LABEL"

printf 'Installed %s\n' "$INSTALL_SCRIPT"
printf 'Loaded %s\n' "$LAUNCH_AGENT_PLIST"
printf 'Check status with: %s --status\n' "$INSTALL_SCRIPT"
