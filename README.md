# Noctalia KDE Connect (v5)

A Noctalia v5 (Luau) port of the legacy v4 QML plugin by WerWolv, integrating your mobile devices into a panel using KDE Connect.

<img width="430" height="504" alt="image" src="https://github.com/user-attachments/assets/207e0ba8-43d0-432f-b291-d29f89027cbb" />

## Features

- Support for multiple devices, with a persisted "main device" selector
- Bar widget: connection-state glyph + battery percentage of the main device
  - Left-click, right-click, and middle-click actions are all configurable per-widget: None, Open panel, Find device (ring), Ping, Send clipboard, Refresh devices (left-click defaults to Open panel, right/middle default to None)
  - These are set from Noctalia's **Bar layout editor** (open the bar's widget settings for the KDE Connect pill), not from Settings → Plugins — Noctalia's plugin-settings page only shows plugin-level settings (`poll_interval`, `browse_command`), not per-widget ones
  - Scroll to cycle the main device (only shown up when 2+ devices are paired)
  - Optional "hide when no device is reachable"
- Control-center shortcut tile showing device name, battery, and connection state
- Device panel:
  - A device mock-up image (phone/tablet/desktop, matching the paired device's type) next to the device name
  - Battery charge + charging state, mobile network type, signal strength, notification count shown as a compact row of icon+value chips (text labels are optional — enable the `show_stat_labels` setting to show them)
  - Ring (find my phone), ping, send clipboard text, wake up the screen
  - Send a file (type or paste a path — one per line for multiple files), browse device files over SFTP
    - No native file picker or drag-and-drop is available to plugin panels in the current Noctalia API, so typing/pasting a path is the only option today — but a pasted `file://` URI (e.g. from a file manager's "Copy Path" action) or a quoted path works too, not just a bare path
    - "Browse files" opens the SFTP mount with `xdg-open` by default; if your default file manager is a Flatpak app (e.g. Flatpak Dolphin) it typically can't see that mount due to sandboxing — set the `browse_command` setting to a non-Flatpak file manager or a `flatpak run --filesystem=host ...` override
  - Pair (with verification key) / unpair
  - Quick "open plugin settings" button in the panel header (shows `poll_interval`/`browse_command` only — see the bar-widget note above for click-action settings)
  - Clear error states when `busctl` is missing or `kdeconnectd` is not running
  - Note: `open_near_click` is declared in the manifest but has no effect yet — as of Noctalia v5.0.0-beta.7, panel toggles from Luau plugins (bar widget, control-center tile, or CLI) never carry the click position, so the panel always opens at the default attached position. Upstream limitation; the setting will start working once Noctalia routes plugin-widget panel toggles through its anchored path.

## Requirements

- `kdeconnectd` running on the user session (install the KDE Connect app)
- `busctl` (part of systemd)
- `sshfs` + `libfuse` for the "Browse files" action (optional)

## Install (Plugin Source - recommended)

Add https://github.com/Antik79/noctalia-plugins as a plugin source in Noctalia v5 settings.
Then enable it under **Settings → Plugins** (the local directory is discovered as a built-in source), add the bar widget from the Add-widget picker, and add the shortcut from the control-center shortcut settings.

## Install (local development)

```sh
mkdir -p ~/.local/share/noctalia/plugins
cp -r kde-connect ~/.local/share/noctalia/plugins/
```

Then enable it under **Settings → Plugins** (the local directory is discovered as a built-in source), add the bar widget from the Add-widget picker, and add the shortcut from the control-center shortcut settings.

## IPC

```sh
noctalia msg panel-toggle antik/kde-connect:panel
noctalia msg plugin antik/kde-connect:monitor all ring      # ring main device
noctalia msg plugin antik/kde-connect:monitor all ping      # ping main device
noctalia msg plugin antik/kde-connect:monitor all refresh   # force rediscovery
```

## Architecture

```
plugin.toml       manifest: service + widget + shortcut + panel + settings
service.luau      polls kdeconnectd over D-Bus (busctl --json=short), publishes
                  one atomic snapshot on the plugin state channel ("kdec")
widget.luau       bar pill, purely state-driven
shortcut.luau     control-center tile, purely state-driven
panel.luau        device panel; runs its own busctl calls for actions
lib/              shared modules (i18n, glyphs, images) required by the
                  entries above via relative require() — each isolated VM
                  gets its own instance, this is source reuse, not shared state
assets/           bundled device-mockup images used by the panel
```

The service batches per-device D-Bus reads into a single subprocess per device (`Properties.GetAll` on the device, battery, and connectivity interfaces plus `activeNotifications`), so a poll costs 2 + N processes instead of the legacy's 1 + 10·N.

## Notes vs. the legacy v4 plugin

- v5 has no file-picker widget, so "Send file" takes a path in a text input instead of opening a picker.
- "Wake up" is a regular action button (same `remotecontrol` single-click trick).
- `forceOnNetworkChange` is sent once per daemon lifetime and on manual refresh, instead of every poll.
- The main-device preference persists to `main_device.txt` inside the plugin directory (v5 plugins cannot write settings programmatically).

## License & attribution

This plugin is a Noctalia v5 (Luau) port by antik of the original v4 QML plugin "KDE Connect" by WerWolv ([https://github.com/WerWolv/noctalia-kde-connect](https://github.com/WerWolv/noctalia-kde-connect), also distributed via [https://github.com/noctalia-dev/legacy-v4-plugins](https://github.com/noctalia-dev/legacy-v4-plugins)). Both the original and this port are licensed under the GNU GPL v2.0 (see LICENSE).
