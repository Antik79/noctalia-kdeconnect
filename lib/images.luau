--!nonstrict
-- Bundled device-mockup image paths, keyed by kdeconnect device type
-- ("phone"|"tablet"|"desktop"|"laptop"|"tv"). Restores the visual the
-- legacy v4 QML plugin had (a device mock-up graphic) which this Luau
-- port originally dropped in favor of a plain glyph.
--
-- barWidget.setImage/ui.image resolve paths relative to the plugin's own
-- directory, so these are given relative to the plugin root, not this file.
-- Returns nil for unmapped types so callers fall back to a glyph
-- (lib/glyphs.luau's deviceTypeGlyph).

local DEVICE_TYPE_IMAGES = {
  ["phone"] = "assets/device-phone.svg",
  ["tablet"] = "assets/device-tablet.svg",
  ["desktop"] = "assets/device-desktop.svg",
  ["laptop"] = "assets/device-desktop.svg",
  ["tv"] = "assets/device-desktop.svg",
}

local function deviceTypeImagePath(deviceType: string?): string?
  if deviceType == nil or deviceType == "" then
    return nil
  end
  return DEVICE_TYPE_IMAGES[deviceType]
end

return { deviceTypeImagePath = deviceTypeImagePath }
