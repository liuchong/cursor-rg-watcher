# cursor-rg-watcher

> [!WARNING]
> Cursor thoughtfully ships an `rg` that sometimes reimagines "search" as "CPU benchmark."
> This project helps that visionary little space heater relocate to Trash, where innovation belongs.

`cursor-rg-watcher` is a macOS `launchd` watcher for one exact file inside `Cursor.app`:

```text
/Applications/Cursor.app/Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg
```

When that file appears, the watcher moves it to the user's Trash instead of deleting it directly.

## Safety Behavior

- Only the exact hard-coded `rg` path is handled.
- Directories are refused and never recursively removed.
- The file is moved to `~/.Trash`, not removed with `rm`.
- A newly downloaded or upgraded `Cursor.app` build is skipped until Cursor has successfully launched.
- A `Cursor.app` bundle that was modified recently is treated as installing and skipped temporarily.
- After first launch, a verification grace period is observed before moving anything from the app bundle.
- Actions that move, skip, fail, pause, or resume send a macOS notification.
- Logs are written to `~/rg_deleted.log`.

## Install

```bash
./install.sh
```

The installer copies:

- `bin/cursor-rg-watcher.sh` to `~/.local/bin/cursor-rg-watcher.sh`
- a generated launchd plist to `~/Library/LaunchAgents/com.user.watchrg.plist`

It then loads and starts the launchd service.

## Commands

```bash
~/.local/bin/cursor-rg-watcher.sh --status
```

```bash
~/.local/bin/cursor-rg-watcher.sh --pause 60
```

```bash
~/.local/bin/cursor-rg-watcher.sh --resume
```

```bash
~/.local/bin/cursor-rg-watcher.sh --test-notify
```

```bash
~/.local/bin/cursor-rg-watcher.sh --mark-launched
```

## Recommended Cursor Upgrade Flow

Before upgrading Cursor:

```bash
~/.local/bin/cursor-rg-watcher.sh --pause 60
```

After Cursor upgrades and opens successfully:

```bash
~/.local/bin/cursor-rg-watcher.sh --resume
```

The watcher also has a guard for new Cursor builds: if the current app build has not launched yet, it skips moving `rg` and notifies once for that build.

It also treats recent writes inside `Cursor.app` as an install/update in progress and waits before moving anything. The default stability window is 180 seconds and can be overridden with `CURSOR_RG_WATCHER_INSTALL_STABLE_SECONDS`.

After the current Cursor build is first observed running, the watcher waits another 300 seconds before moving `rg`. This avoids touching the app while macOS or Cursor is still doing first-launch verification. Override it with `CURSOR_RG_WATCHER_VERIFY_GRACE_SECONDS`.

## Uninstall

```bash
./uninstall.sh
```

This unloads the launchd service and removes the installed plist and script. Runtime state under `~/.local/state` and logs are kept for inspection.

## Files

- `bin/cursor-rg-watcher.sh`: watcher and control CLI
- `launchagents/com.user.watchrg.plist`: checked-in plist copy for reference
- `install.sh`: install and load the launchd service
- `uninstall.sh`: unload and remove installed files
