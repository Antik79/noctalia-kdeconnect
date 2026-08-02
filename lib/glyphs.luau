--!nonstrict
-- Glyph-mapping helpers, lifted verbatim from panel.luau (mirrors the legacy
-- plugin's icon choices), required by panel.luau. widget.luau/shortcut.luau
-- use their own small inline glyph picks and don't need this module.
--
-- cellStrengthText is deliberately NOT here — it needs T() for translated
-- signal-strength labels and stays local to panel.luau.

local function batteryGlyph(pct, charging): string
  if pct < 0 then
    return "battery-exclamation"
  end
  if charging then
    return "battery-charging-2"
  end
  if pct < 5 then
    return "battery"
  elseif pct < 25 then
    return "battery-1"
  elseif pct < 50 then
    return "battery-2"
  elseif pct < 75 then
    return "battery-3"
  end
  return "battery-4"
end

local CELL_TYPE_GLYPHS = {
  ["5G"] = "signal-5g",
  ["LTE"] = "signal-4g",
  ["HSPA"] = "signal-h",
  ["UMTS"] = "signal-3g",
  ["EDGE"] = "signal-e",
  ["GPRS"] = "signal-g",
  ["GSM"] = "signal-2g",
  ["CDMA"] = "signal-3g",
  ["CDMA2000"] = "signal-3g",
  ["iDEN"] = "signal-2g",
}

local function cellTypeGlyph(cellType): string
  return CELL_TYPE_GLYPHS[cellType] or "wave-square"
end

local function cellStrengthGlyph(strength): string
  if strength >= 0 and strength <= 4 then
    return `antenna-bars-{strength + 1}`
  end
  return "antenna-bars-off"
end

local DEVICE_TYPE_GLYPHS = {
  ["phone"] = "device-mobile",
  ["tablet"] = "device-tablet",
  ["desktop"] = "device-desktop",
  ["laptop"] = "device-desktop",
  ["tv"] = "device-desktop",
}

local function deviceTypeGlyph(deviceType: string): string
  if deviceType == nil or deviceType == "" then
    return "device-mobile"
  end
  return DEVICE_TYPE_GLYPHS[deviceType] or "device-mobile"
end

return {
  batteryGlyph = batteryGlyph,
  cellTypeGlyph = cellTypeGlyph,
  cellStrengthGlyph = cellStrengthGlyph,
  deviceTypeGlyph = deviceTypeGlyph,
}
