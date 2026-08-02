--!nonstrict
-- KDE Connect [[panel]] entry — the device panel.
--
-- Reads the service's "kdec" snapshot and renders one of:
--   * error cards   (busctl missing / daemon down / no devices)
--   * pairing card  (request pairing + verification key)
--   * offline card  (device unreachable + unpair)
--   * device card   (battery / network / signal / notifications + actions)
--
-- Actions run their own busctl calls (entries are isolated VMs); status data
-- always comes from the service so there is a single source of truth.
--
-- Share supports multiple files: the input is multiline, one path per line
-- (newline-only split — paths may contain spaces). Every listed path must
-- exist or nothing is sent; on success all files fire-and-forget via
-- shareUrl and the input is cleared by re-keying it (see shareGeneration).

local BUSCTL = "busctl --user"
local SERVICE = "org.kde.kdeconnect"

local snap = noctalia.state.get("kdec")
local isOpen = false
local sharePath = ""
local shareFeedback = "" -- one-line feedback under the share input
local shareGeneration = 0 -- bumped to re-key (and thus clear) the uncontrolled share input
local nonce = 0 -- monotonic counter for state-channel requests (os.clock() is CPU time and can collide)

-- ── translations with embedded English fallback ───────────────────────────────
-- noctalia.tr() resolves translations/<lang>.json on builds that ship the plugin
-- i18n catalog; on builds that don't, it returns the key verbatim. Fall back to
-- English defaults so raw keys never reach the UI. Shared with the other
-- entries via lib/i18n.luau (each isolated VM gets its own instance).

local i18n = require("./lib/i18n.luau")
local T, TP = i18n.T, i18n.TP

-- ── helpers ───────────────────────────────────────────────────────────────────

local function sanitizeId(id): string
  return (tostring(id):gsub("[^%w_%-]", ""))
end

local function devicePath(id): string
  return "/modules/kdeconnect/devices/" .. sanitizeId(id)
end

local function shellQuote(s): string
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function callCmd(objPath, itf, member, args): string
  local cmd = `{BUSCTL} call --json=short {SERVICE} {objPath} {itf} {member}`
  if args then
    cmd ..= " " .. args
  end
  return cmd
end

local function fireAndForget(objPath, itf, member, args)
  noctalia.runAsync(callCmd(objPath, itf, member, args) .. " >/dev/null 2>&1")
end

local function firstReturn(text)
  if text == nil or text == "" then
    return nil
  end
  local ok, parsed = pcall(noctalia.json.decode, text)
  if not ok then
    return nil
  end
  if type(parsed) ~= "table" or parsed.data == nil then
    return nil
  end
  if type(parsed.data) == "table" then
    return parsed.data[1]
  end
  return parsed.data
end

local function requestRefresh()
  nonce += 1
  noctalia.state.set("kdec.refresh", { nonce = nonce })
end

local function devices()
  if type(snap) == "table" and type(snap.devices) == "table" then
    return snap.devices
  end
  return {}
end

local function currentDevice()
  for _, d in ipairs(devices()) do
    if snap ~= nil and d.id == snap.mainId then
      return d
    end
  end
  return nil
end

-- ── glyph mapping (mirrors the legacy plugin) ─────────────────────────────────

local glyphs = require("./lib/glyphs.luau")
local batteryGlyph, cellTypeGlyph, cellStrengthGlyph = glyphs.batteryGlyph, glyphs.cellTypeGlyph, glyphs.cellStrengthGlyph
local images = require("./lib/images.luau")

-- Restores the device mock-up graphic the legacy v4 QML plugin had (this
-- Luau port originally dropped it for a plain glyph). Renders a bundled
-- silhouette image per device type when one exists, falling back to the
-- generic glyph (ui.image has no tint prop, so this is a fixed-color asset
-- rather than a theme-colored one — see lib/images.luau).
local function deviceVisual(dev, size: number)
  local path = images.deviceTypeImagePath(dev.type)
  if path ~= nil then
    return ui.image({ path = path, fit = "contain", width = size, height = size })
  end
  return ui.glyph({ name = glyphs.deviceTypeGlyph(dev.type), size = size, color = "on_surface_variant" })
end

local function cellStrengthText(strength): string
  if strength >= 0 and strength <= 4 then
    return T(`panel.signal.{strength}`)
  end
  return T("panel.unknown")
end

-- ── UI building blocks ────────────────────────────────────────────────────────

local function statRow(glyph, label, value)
  return ui.row({ gap = 12, align = "center" }, {
    ui.glyph({ name = glyph, size = 24, color = "on_surface" }),
    ui.column({ gap = 2 }, {
      ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = value, fontSize = 14, fontWeight = "medium", color = "on_surface" }),
    }),
  })
end

local function messageCard(glyph, title, description)
  local children = {
    ui.glyph({ name = glyph, size = 48, color = "on_surface_variant" }),
    ui.label({ text = title, fontSize = 15, fontWeight = "medium", color = "on_surface_variant", textAlign = "center", maxLines = 3 }),
  }
  if description ~= nil and description ~= "" then
    table.insert(children, ui.label({ text = description, fontSize = 12, color = "on_surface_variant", textAlign = "center", maxLines = 5 }))
  end
  return ui.column({ flexGrow = 1, gap = 12, align = "center", justify = "center", paddingH = 16 }, children)
end

local function actionButton(glyph, textKey, onClick)
  return ui.button({
    glyph = glyph,
    text = T(textKey),
    fontSize = 12,
    glyphSize = 14,
    variant = "secondary",
    contentAlign = "start",
    flexGrow = 1,
    onClick = onClick,
  })
end

-- ── cards ─────────────────────────────────────────────────────────────────────

local function pairingCard(dev)
  local children = {
    deviceVisual(dev, 48),
    ui.label({ text = dev.name, fontSize = 18, fontWeight = "bold", color = "on_surface" }),
    ui.button({
      text = T("panel.pair"),
      variant = "primary",
      enabled = not dev.pairRequested,
      onClick = "onPair",
    }),
  }
  if dev.pairRequested then
    table.insert(children, ui.label({
      text = T("panel.pair_requested"),
      fontSize = 12,
      color = "on_surface_variant",
      textAlign = "center",
    }))
    if dev.verificationKey ~= "" then
      table.insert(children, ui.row({ gap = 8, align = "center", justify = "center" }, {
        ui.glyph({ name = "key", size = 24, color = "on_surface" }),
        ui.label({ text = dev.verificationKey, fontSize = 15, fontWeight = "bold", color = "primary" }),
      }))
    end
  end
  return ui.column({ flexGrow = 1, gap = 12, align = "center", justify = "center" }, children)
end

local function offlineCard(dev)
  return ui.column({ flexGrow = 1, gap = 12, align = "center", justify = "center" }, {
    ui.glyph({ name = "device-mobile-off", size = 48, color = "on_surface_variant" }),
    ui.label({ text = dev.name, fontSize = 16, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = T("panel.device_unavailable"), fontSize = 13, color = "on_surface_variant", textAlign = "center" }),
    ui.button({ text = T("panel.unpair"), variant = "destructive", onClick = "onUnpair" }),
  })
end

local function deviceCard(dev)
  local notifValue = tostring(dev.notifications)
  local batteryValue = if dev.battery >= 0 then `{dev.battery}%` else T("panel.unknown")
  local networkValue = if dev.cellType ~= "" then dev.cellType else T("panel.unknown")

  -- Multi-file share: one path per line. In a multiline ui.input, Enter
  -- inserts a newline and onSubmit only fires on Ctrl+Enter — keep both
  -- onChange and onSubmit wired so the send button and Ctrl+Enter agree.
  local shareChildren = {
    ui.label({ text = T("panel.actions.share"), fontSize = 12, fontWeight = "medium", color = "on_surface_variant" }),
    ui.row({ gap = 8, align = "center" }, {
      ui.input({
        -- ui.input is uncontrolled: giving it a new key forces recreation,
        -- which is how we clear it after a successful send (see shareFile).
        key = "share_path_" .. shareGeneration,
        placeholder = T("panel.share_placeholder"),
        fontSize = 12,
        flexGrow = 1,
        multiline = true,
        onChange = "onShareChanged",
        onSubmit = "onShareSubmit",
      }),
      ui.button({ glyph = "send", variant = "primary", onClick = "onShareClicked" }),
    }),
  }
  if shareFeedback ~= "" then
    table.insert(shareChildren, ui.label({ text = shareFeedback, fontSize = 11, color = "on_surface_variant", maxLines = 2 }))
  end

  return ui.scroll({ flexGrow = 1, gap = 16 }, {
    -- Device visual + name
    ui.row({ gap = 12, align = "center" }, {
      deviceVisual(dev, 48),
      ui.label({ text = dev.name, fontSize = 18, fontWeight = "bold", color = "on_surface" }),
    }),

    -- Stats
    ui.column({ gap = 12, fill = "surface_variant/0.5", radius = 9, padding = 12 }, {
      statRow(batteryGlyph(dev.battery, dev.charging), T("panel.battery"), batteryValue),
      statRow(cellTypeGlyph(dev.cellType), T("panel.network"), networkValue),
      statRow(cellStrengthGlyph(dev.cellStrength), T("panel.signal_strength"), cellStrengthText(dev.cellStrength)),
      statRow("bell", T("panel.notifications"), notifValue),
    }),

    -- Actions
    ui.column({ gap = 8 }, {
      ui.row({ gap = 8 }, {
        actionButton("radar", "panel.actions.ring", "onRing"),
        actionButton("send", "panel.actions.ping", "onPing"),
      }),
      ui.row({ gap = 8 }, {
        actionButton("clipboard-text", "panel.actions.clipboard", "onSendClipboard"),
        actionButton("power", "panel.actions.wake", "onWake"),
      }),
      ui.row({ gap = 8 }, {
        actionButton("folder-search", "panel.actions.browse", "onBrowse"),
      }),
    }),

    -- Share a file
    ui.column({ gap = 8 }, shareChildren),

    -- Unpair
    ui.row({ justify = "end" }, {
      ui.button({ text = T("panel.unpair"), glyph = "unlink", fontSize = 11, glyphSize = 14, variant = "ghost", onClick = "onUnpair" }),
    }),
  })
end

-- ── root render ───────────────────────────────────────────────────────────────

local function body()
  if snap == nil or not snap.busctl then
    return messageCard("exclamation-circle", T("errors.busctl_title"), T("errors.busctl_desc"))
  end
  if not snap.daemon then
    return messageCard("exclamation-circle", T("errors.daemon_title"), T("errors.daemon_desc"))
  end

  local dev = currentDevice()
  if dev == nil then
    return messageCard("device-mobile-off", T("errors.no_devices"), T("errors.no_devices_hint"))
  end
  if not dev.paired then
    if dev.reachable then
      return pairingCard(dev)
    end
    return offlineCard(dev)
  end
  if not dev.reachable then
    return offlineCard(dev)
  end
  return deviceCard(dev)
end

local function deviceSelector()
  local list = devices()
  if #list < 2 then
    return nil
  end
  local names = {}
  local selected = 0
  for i, d in ipairs(list) do
    names[i] = d.name
    if snap ~= nil and d.id == snap.mainId then
      selected = i - 1
    end
  end
  return ui.select({ options = names, selectedIndex = selected, onChange = "onDeviceSelected" })
end

local function render()
  if not isOpen then
    return
  end
  local children = {
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "device-mobile", size = 20, color = "primary" }),
      ui.label({ text = T("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "settings", variant = "ghost", tooltip = T("panel.open_settings"), onClick = "onOpenSettings" }),
      ui.button({ glyph = "refresh", variant = "ghost", onClick = "onRefresh" }),
      ui.button({ glyph = "x", variant = "ghost", onClick = "onCloseClicked" }),
    }),
  }
  local selector = deviceSelector()
  if selector ~= nil then
    table.insert(children, selector)
  end
  table.insert(children, body())
  panel.render(ui.column({ flexGrow = 1, gap = 14 }, children))
end

noctalia.state.watch("kdec", function(value)
  snap = value
  render()
end)

-- ── panel lifecycle ───────────────────────────────────────────────────────────

function onOpen(_context)
  isOpen = true
  shareFeedback = ""
  snap = noctalia.state.get("kdec")
  requestRefresh()
  render()
end

function onClose()
  isOpen = false
end

function onCloseClicked()
  panel.close()
end

function onOpenSettings()
  -- Closes this panel first (PanelManager::openPluginSettings()), then opens
  -- this plugin's own settings page — no other plugin's.
  noctalia.openSettings()
end

function onRefresh()
  shareFeedback = ""
  render()
  requestRefresh()
end

function onDeviceSelected(index, _text)
  local list = devices()
  local i = (tonumber(index) or 0) + 1
  local dev = list[i]
  if dev ~= nil then
    shareFeedback = ""
    render()
    nonce += 1
    noctalia.state.set("kdec.setMain", { id = dev.id, nonce = nonce })
  end
end

-- ── device actions ────────────────────────────────────────────────────────────

local function withCurrentId(): string?
  local dev = currentDevice()
  if dev == nil then
    return nil
  end
  return sanitizeId(dev.id)
end

function onPing()
  local id = withCurrentId()
  if id then
    fireAndForget(devicePath(id) .. "/ping", "org.kde.kdeconnect.device.ping", "sendPing")
  end
end

function onRing()
  local id = withCurrentId()
  if id then
    fireAndForget(devicePath(id) .. "/findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring")
  end
end

function onWake()
  local id = withCurrentId()
  if id then
    -- Same trick as the legacy plugin: a remote-control "singleclick" wakes the screen.
    fireAndForget(devicePath(id) .. "/remotecontrol", "org.kde.kdeconnect.device.remotecontrol",
      "sendCommand", 'a{sv} 1 singleclick b true')
  end
end

function onSendClipboard()
  local id = withCurrentId()
  if id == nil then
    return
  end
  local text = noctalia.clipboardText()
  if text == nil or text == "" then
    noctalia.notifyError(T("panel.title"), T("panel.clipboard_empty"))
    return
  end
  fireAndForget(devicePath(id) .. "/share", "org.kde.kdeconnect.device.share",
    "shareText", "s " .. shellQuote(text))
  noctalia.notify(T("panel.title"), T("panel.clipboard_sent"))
end

function onBrowse()
  local id = withCurrentId()
  if id == nil then
    return
  end
  local sftp = devicePath(id) .. "/sftp"
  -- browse_command overrides xdg-open — useful when the default file manager
  -- is a Flatpak app that can't see the SFTP mount kdeconnectd creates.
  local browseCmd = tostring(noctalia.getConfig("browse_command") or "")
  -- Mount over SFTP (needs sshfs), then open the first exposed directory.
  noctalia.runAsync(callCmd(sftp, "org.kde.kdeconnect.device.sftp", "mountAndWait"), function(_res)
    noctalia.runAsync(callCmd(sftp, "org.kde.kdeconnect.device.sftp", "getDirectories"), function(res)
      local dirs = firstReturn(res.stdout)
      if type(dirs) == "table" then
        for path, _label in pairs(dirs) do
          if browseCmd ~= "" then
            noctalia.runAsync(browseCmd .. " " .. shellQuote(path))
          else
            noctalia.runAsync("xdg-open " .. shellQuote(path))
          end
          return
        end
      end
      noctalia.notifyError(T("panel.title"), T("panel.browse_failed"))
    end)
  end)
end

function onShareChanged(value)
  sharePath = tostring(value or "")
end

local function shareFile()
  local id = withCurrentId()
  if id == nil then
    return
  end
  local paths = {}
  for _, line in ipairs(string.split(sharePath, "\n")) do
    local trimmed = noctalia.string.trim(line)
    if trimmed ~= "" then
      table.insert(paths, noctalia.expandPath(trimmed))
    end
  end
  if #paths == 0 then
    return
  end
  for _, path in ipairs(paths) do
    if not noctalia.fileExists(path) then
      shareFeedback = T("panel.share_not_found", { path = path })
      render()
      return
    end
  end
  for _, path in ipairs(paths) do
    fireAndForget(devicePath(id) .. "/share", "org.kde.kdeconnect.device.share",
      "shareUrl", "s " .. shellQuote("file://" .. path))
  end
  shareFeedback = if #paths == 1 then T("panel.share_sent", { path = paths[1] }) else TP("panel.share_sent_multi", #paths)
  sharePath = ""
  shareGeneration += 1
  render()
end

function onShareClicked()
  shareFile()
end

function onShareSubmit(value)
  sharePath = tostring(value or "")
  shareFile()
end

function onPair()
  local id = withCurrentId()
  if id then
    fireAndForget(devicePath(id), "org.kde.kdeconnect.device", "requestPairing")
    requestRefresh()
  end
end

function onUnpair()
  local id = withCurrentId()
  if id then
    fireAndForget(devicePath(id), "org.kde.kdeconnect.device", "unpair")
    requestRefresh()
  end
end
