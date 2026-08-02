--!nonstrict
-- KDE Connect [[shortcut]] entry — control-center tile.
--
-- Shows the main device's name (and battery when known), highlighted while the
-- device is reachable and paired. Clicking toggles the device panel.

local PANEL_ID = "antik/kde-connect:panel"

local snap = noctalia.state.get("kdec")

-- Translation helper with embedded English fallback, shared via lib/i18n.luau.
local i18n = require("./lib/i18n.luau")
local T = i18n.T

local function mainDevice()
  if type(snap) ~= "table" or type(snap.devices) ~= "table" then
    return nil
  end
  for _, d in ipairs(snap.devices) do
    if d.id == snap.mainId then
      return d
    end
  end
  return nil
end

local function render()
  local main = mainDevice()
  local label = "KDE Connect"
  local active = false

  if snap == nil or not snap.busctl or not snap.daemon then
    label = T("state.unavailable")
  elseif main == nil then
    label = T("state.no_device")
  else
    label = main.name
    if main.reachable and main.paired then
      active = true
      if main.battery >= 0 then
        label = `{main.name} {main.battery}%`
      end
    end
  end

  shortcut.setLabel(label)
  shortcut.setIcon("device-mobile", "device-mobile-off")
  shortcut.setActive(active)
  shortcut.setEnabled(true)
end

noctalia.state.watch("kdec", function(value)
  snap = value
  render()
end)

render()

function onClick()
  noctalia.togglePanel(PANEL_ID)
end
