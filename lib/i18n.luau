--!nonstrict
-- Shared translation helpers with embedded English fallback, required by
-- widget.luau, shortcut.luau, and panel.luau (each entry runs in its own
-- isolated Luau VM, so this module is re-executed independently per VM —
-- see CLAUDE.md's isolated-VM architecture note).
--
-- noctalia.tr()/noctalia.trp() resolve translations/<lang>.json on builds
-- that ship the plugin i18n catalog; on builds that don't, they return the
-- key verbatim. Fall back to DEFAULTS so raw keys never reach the UI.

local DEFAULTS = {
  -- widget.luau / bar pill
  ["bar.tooltip"] = "Connected Devices",
  ["bar.notifications.one"] = "{count} notification",
  ["bar.notifications.other"] = "{count} notifications",
  ["state.connected"] = "Connected",
  ["state.disconnected"] = "Disconnected",
  ["state.unavailable"] = "Unavailable",
  ["state.no_device"] = "No device",
  ["state.not_paired"] = "Not paired",

  -- panel.luau / device panel
  ["panel.title"] = "Connected Devices",
  ["panel.open_settings"] = "Plugin settings",
  ["panel.battery"] = "Battery",
  ["panel.network"] = "Network",
  ["panel.signal_strength"] = "Signal Strength",
  ["panel.notifications"] = "Notifications",
  ["panel.unknown"] = "Unknown",
  ["panel.signal.0"] = "Very Weak",
  ["panel.signal.1"] = "Weak",
  ["panel.signal.2"] = "Fair",
  ["panel.signal.3"] = "Good",
  ["panel.signal.4"] = "Excellent",
  ["panel.actions.ring"] = "Find device",
  ["panel.actions.ping"] = "Ping",
  ["panel.actions.clipboard"] = "Send clipboard",
  ["panel.actions.wake"] = "Wake up",
  ["panel.actions.browse"] = "Browse files",
  ["panel.actions.share"] = "Send a file",
  ["panel.share_placeholder"] = "~/path/to/file",
  ["panel.share_not_found"] = "File not found: {path}",
  ["panel.share_sent"] = "Sent {path}",
  ["panel.share_sent_multi"] = "Sent {count} files",
  ["panel.clipboard_empty"] = "Clipboard is empty",
  ["panel.clipboard_sent"] = "Clipboard sent to device",
  ["panel.clipboard_too_large"] = "Clipboard is too large to send",
  ["panel.browse_failed"] = "Could not mount the device over SFTP (is sshfs installed?)",
  ["panel.pair"] = "Pair with device",
  ["panel.pair_requested"] = "Confirm the pairing request on your device",
  ["panel.unpair"] = "Unpair",
  ["panel.device_unavailable"] = "Device is currently unavailable",
  ["errors.no_devices"] = "No device running KDE Connect found",
  ["errors.no_devices_hint"] = "Open the KDE Connect app on your phone and make sure both devices are on the same network, then press refresh.",
  ["errors.daemon_title"] = "kdeconnectd does not seem to be running!",
  ["errors.daemon_desc"] = "Make sure the KDE Connect application is installed and the kdeconnectd daemon has been started.",
  ["errors.busctl_title"] = "busctl cannot be found!",
  ["errors.busctl_desc"] = "Make sure busctl (part of systemd) is installed on your system.",
}

-- T(key, subst): matches panel.luau's implementation (a superset of
-- widget.luau's/shortcut.luau's no-arg T(key) — subst is optional).
local function T(key, subst)
  local s = noctalia.tr(key, subst)
  if s == key then
    s = DEFAULTS[key] or key
  end
  -- Apply the {name} substitution unconditionally: noctalia.tr() may or may
  -- not have already substituted depending on the runtime/catalog, and the
  -- gsub is a no-op once the placeholder is already gone.
  if subst ~= nil then
    for name, value in pairs(subst) do
      s = s:gsub("{" .. name .. "}", function()
        return tostring(value)
      end)
    end
  end
  return s
end

-- TP(key, count): matches widget.luau's implementation (panel.luau has no
-- TP of its own — it uses T with named substitutions instead).
local function TP(key, count)
  local s = noctalia.trp(key, count)
  if s == key then
    s = DEFAULTS[key .. (if count == 1 then ".one" else ".other")] or key
    s = s:gsub("{count}", tostring(count))
  end
  return s
end

return { T = T, TP = TP, DEFAULTS = DEFAULTS }
