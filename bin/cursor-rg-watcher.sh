#!/bin/bash
set -u

readonly TARGET="/Applications/Cursor.app/Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg"
readonly ALLOWED_TARGET="/Applications/Cursor.app/Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg"
readonly CURSOR_APP="/Applications/Cursor.app"
readonly CURSOR_INFO_PLIST="$CURSOR_APP/Contents/Info.plist"
readonly USER_HOME="${HOME:-/Users/liu}"
readonly LOG="$USER_HOME/rg_deleted.log"
readonly STATE_DIR="$USER_HOME/.local/state"
readonly PAUSE_FILE="$STATE_DIR/cursor_rg_watcher.pause_until"
readonly LAUNCHED_FILE="$STATE_DIR/cursor_rg_watcher.launched_fingerprint"
readonly SKIP_NOTIFY_FILE="$STATE_DIR/cursor_rg_watcher.skip_notified_fingerprint"
readonly TRASH_DIR="$USER_HOME/.Trash"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--help|--status|--pause MINUTES|--resume|--mark-launched|--test-notify]

Safely moves only this exact file to Trash when it exists:
  $TARGET

Options:
  --help          Show this help text.
  --status        Show whether deletion is active or paused.
  --pause MINUTES Pause deletion for the given number of minutes.
  --resume        Resume deletion immediately.
  --mark-launched Mark the current Cursor.app build as safely launched.
  --test-notify   Send a macOS notification to verify notification permission.

Default mode is used by launchd: check the target once, move it to Trash if it
is a regular file or symlink, and exit quietly if it does not exist.
EOF
}

notify() {
    local title="$1"
    local message="$2"

    /usr/bin/osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"
}

ensure_state_dir() {
    /bin/mkdir -p "$STATE_DIR"
}

now_epoch() {
    /bin/date '+%s'
}

format_epoch() {
    /bin/date -r "$1" '+%Y-%m-%d %H:%M:%S'
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$CURSOR_INFO_PLIST" 2>/dev/null || printf 'unknown'
}

cursor_fingerprint() {
    local short_version
    local build_version
    local app_mtime

    short_version="$(plist_value CFBundleShortVersionString)"
    build_version="$(plist_value CFBundleVersion)"
    app_mtime="$(/usr/bin/stat -f '%m' "$CURSOR_APP" 2>/dev/null || printf 'unknown')"

    printf '%s|%s|%s\n' "$short_version" "$build_version" "$app_mtime"
}

cursor_running() {
    /bin/ps -axo command= | /usr/bin/awk '
        $0 == "/Applications/Cursor.app/Contents/MacOS/Cursor" ||
        index($0, "/Applications/Cursor.app/Contents/MacOS/Cursor ") == 1 {
            found = 1
        }
        END {
            exit found ? 0 : 1
        }
    '
}

mark_current_cursor_launched() {
    ensure_state_dir
    cursor_fingerprint > "$LAUNCHED_FILE"
    /bin/rm -f -- "$SKIP_NOTIFY_FILE"
}

cursor_build_has_launched() {
    local current
    current="$(cursor_fingerprint)"

    if [ -f "$LAUNCHED_FILE" ] && [ "$(/bin/cat "$LAUNCHED_FILE" 2>/dev/null || true)" = "$current" ]; then
        return 0
    fi

    if cursor_running; then
        mark_current_cursor_launched
        log "marked current Cursor build as launched"
        return 0
    fi

    return 1
}

notify_skip_unlaunched_once() {
    local current
    current="$(cursor_fingerprint)"
    ensure_state_dir

    if [ -f "$SKIP_NOTIFY_FILE" ] && [ "$(/bin/cat "$SKIP_NOTIFY_FILE" 2>/dev/null || true)" = "$current" ]; then
        return 0
    fi

    printf '%s\n' "$current" > "$SKIP_NOTIFY_FILE"
    log "skipped target because current Cursor build has not launched yet"
    notify "Cursor rg watcher" "检测到 Cursor 新版本尚未启动，暂不移动 rg"
}

trash_target() {
    local timestamp
    local destination

    /bin/mkdir -p "$TRASH_DIR"
    timestamp="$(/bin/date '+%Y%m%d-%H%M%S')"
    destination="$TRASH_DIR/rg.cursor-watcher.$timestamp.$$"

    if /bin/mv "$TARGET" "$destination"; then
        printf '%s\n' "$destination"
        return 0
    fi

    return 1
}

pause_until() {
    if [ ! -f "$PAUSE_FILE" ]; then
        return 1
    fi

    local until
    until="$(/bin/cat "$PAUSE_FILE" 2>/dev/null || true)"
    case "$until" in
        ''|*[!0-9]*)
            /bin/rm -f -- "$PAUSE_FILE"
            return 1
            ;;
    esac

    if [ "$(now_epoch)" -lt "$until" ]; then
        printf '%s\n' "$until"
        return 0
    fi

    /bin/rm -f -- "$PAUSE_FILE"
    log "pause expired, deletion resumed"
    notify "Cursor rg watcher" "暂停已到期，已恢复删除"
    return 1
}

status() {
    local until
    if until="$(pause_until)"; then
        printf 'Paused until %s\n' "$(format_epoch "$until")"
        return 0
    fi

    printf 'Active\n'
    if cursor_build_has_launched; then
        printf 'Cursor build: launched\n'
    else
        printf 'Cursor build: not launched yet; deletion will be skipped\n'
    fi
}

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --status)
        status
        exit 0
        ;;
    --pause)
        minutes="${2:-}"
        case "$minutes" in
            ''|*[!0-9]*)
                printf 'Error: --pause requires a positive integer minute value.\n' >&2
                exit 2
                ;;
        esac
        if [ "$minutes" -lt 1 ] || [ "$minutes" -gt 10080 ]; then
            printf 'Error: --pause minutes must be between 1 and 10080.\n' >&2
            exit 2
        fi
        ensure_state_dir
        until="$(( $(now_epoch) + minutes * 60 ))"
        printf '%s\n' "$until" > "$PAUSE_FILE"
        log "paused deletion until $(format_epoch "$until")"
        notify "Cursor rg watcher" "已暂停删除，直到 $(format_epoch "$until")"
        printf 'Paused until %s\n' "$(format_epoch "$until")"
        exit 0
        ;;
    --resume)
        /bin/rm -f -- "$PAUSE_FILE"
        log "deletion resumed manually"
        notify "Cursor rg watcher" "已恢复删除"
        printf 'Active\n'
        exit 0
        ;;
    --mark-launched)
        mark_current_cursor_launched
        log "current Cursor build marked as launched manually"
        notify "Cursor rg watcher" "已标记当前 Cursor 版本为已启动"
        printf 'Marked current Cursor build as launched.\n'
        exit 0
        ;;
    --test-notify)
        notify "Cursor rg watcher" "通知测试：如果你看到这条，权限可用"
        printf 'Sent test notification.\n'
        exit 0
        ;;
    "")
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if pause_until >/dev/null; then
    exit 0
fi

if [ "$TARGET" != "$ALLOWED_TARGET" ]; then
    log "refused unexpected target $TARGET"
    notify "Cursor rg watcher" "安全拒绝：目标路径异常"
    exit 64
fi

if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    exit 0
fi

if ! cursor_build_has_launched; then
    notify_skip_unlaunched_once
    exit 0
fi

if [ -d "$TARGET" ] && [ ! -L "$TARGET" ]; then
    log "refused to delete directory $TARGET"
    notify "Cursor rg watcher" "安全拒绝：目标是目录，未删除"
    exit 65
fi

if trash_path="$(trash_target)"; then
    log "moved $TARGET to Trash at $trash_path"
    notify "Cursor rg watcher" "已将 Cursor 内置 rg 移到废纸篓"
    exit 0
fi

log "failed to move $TARGET to Trash"
notify "Cursor rg watcher" "移到废纸篓失败，请查看 $LOG"
exit 1
