local Config = {}
local Pure = dofile("/qalcom/lib/pure.lua")
local Palette = dofile("/qalcom/lib/ui/palette.lua")
Config.schemaVersion = 3
local WIN11_DARK_PALETTE = {
[colors.black] = 0x101820,
[colors.gray] = 0x222C36,
[colors.brown] = 0x3E4A56,
[colors.lightGray] = 0xAAB6C0,
[colors.white] = 0xF0F4F7,
[colors.blue] = 0x245AB0,
[colors.lightBlue] = 0x3F7FDB,
[colors.cyan] = 0x7DB9FF,
[colors.lime] = 0x6CCB5F,
[colors.green] = 0x107C10,
[colors.yellow] = 0xF5C518,
[colors.orange] = 0xF7893B,
[colors.red] = 0xF7636B,
[colors.pink] = 0xFF99A4,
[colors.purple] = 0x8764B8,
[colors.magenta] = 0xC264D8,
}
local WIN11_LIGHT_PALETTE = {
[colors.black] = 0x15202A,
[colors.gray] = 0x7B8792,
[colors.brown] = 0xC3CCD4,
[colors.lightGray] = 0xD8DEE4,
[colors.white] = 0xFFFFFF,
[colors.blue] = 0x1E4F9D,
[colors.lightBlue] = 0x2F69C9,
[colors.cyan] = 0x155FC5,
[colors.lime] = 0x0F7B0F,
[colors.green] = 0x107C10,
[colors.yellow] = 0xF7B500,
[colors.orange] = 0xC94F00,
[colors.red] = 0xC42B1C,
[colors.pink] = 0xF7A9A9,
[colors.purple] = 0x8764B8,
[colors.magenta] = 0xC264D8,
}
Config.themes = {
win11dark = {
name = "Qalcom Command Dark",
type = "dark",
palette = WIN11_DARK_PALETTE,
desktop = colors.black, desktopDark = colors.black, desktopGlow = colors.brown, desktopElevated = colors.gray,
surface = colors.gray, surfaceAlt = colors.black, surfaceStrong = colors.gray, surfaceMuted = colors.black, surfaceInset = colors.black,
surfaceSelected = colors.blue, surfaceHover = colors.brown, surfaceDisabled = colors.brown,
border = colors.brown, borderStrong = colors.lightBlue, divider = colors.brown,
text = colors.white, muted = colors.lightGray, textMuted = colors.lightGray, textSubtle = colors.lightGray, textInverse = colors.black,
accent = colors.lightBlue, accentLight = colors.cyan, accentSoft = colors.blue, accentStrong = colors.blue, hover = colors.cyan, focus = colors.lightBlue, info = colors.cyan,
success = colors.lime, successSoft = colors.green, warning = colors.yellow, warningSoft = colors.orange, danger = colors.red, dangerSoft = colors.pink,
shadow = colors.black, button = colors.brown, buttonText = colors.white, buttonActive = colors.lightBlue, section = colors.brown, sectionText = colors.white, taskbar = colors.black, taskbarHover = colors.brown, titleActive = colors.gray, titleInactive = colors.black, titleControl = colors.white, statusText = colors.white, infoText = colors.black, successText = colors.black, dangerText = colors.white, warningText = colors.black,
},
win11light = {
name = "Qalcom Command Light",
type = "light",
palette = WIN11_LIGHT_PALETTE,
desktop = colors.lightGray, desktopDark = colors.brown, desktopGlow = colors.white, desktopElevated = colors.white,
surface = colors.white, surfaceAlt = colors.lightGray, surfaceStrong = colors.white, surfaceMuted = colors.brown, surfaceInset = colors.lightGray,
surfaceSelected = colors.lightBlue, surfaceHover = colors.brown, surfaceDisabled = colors.brown,
border = colors.gray, borderStrong = colors.lightBlue, divider = colors.brown,
text = colors.black, muted = colors.gray, textMuted = colors.gray, textSubtle = colors.gray, textInverse = colors.white,
accent = colors.lightBlue, accentLight = colors.cyan, accentSoft = colors.blue, accentStrong = colors.blue, hover = colors.cyan, focus = colors.lightBlue, info = colors.blue,
success = colors.lime, successSoft = colors.green, warning = colors.yellow, warningSoft = colors.orange, danger = colors.red, dangerSoft = colors.pink,
shadow = colors.gray, button = colors.lightGray, buttonText = colors.black, buttonActive = colors.lightBlue, section = colors.lightGray, sectionText = colors.black, taskbar = colors.white, taskbarHover = colors.brown, titleActive = colors.white, titleInactive = colors.lightGray, titleControl = colors.black, statusText = colors.black, infoText = colors.white, successText = colors.white, dangerText = colors.white, warningText = colors.black,
},
blue = {
name = "Classic Ocean",
type = "light",
desktop = colors.blue, desktopDark = colors.darkBlue, desktopGlow = colors.lightBlue, desktopElevated = colors.lightBlue,
surface = colors.white, surfaceAlt = colors.lightGray, surfaceStrong = colors.white, surfaceMuted = colors.gray, surfaceInset = colors.lightGray,
surfaceSelected = colors.lightBlue, surfaceHover = colors.lightBlue, surfaceDisabled = colors.gray,
border = colors.gray, borderStrong = colors.lightBlue, divider = colors.gray,
text = colors.black, muted = colors.gray, textMuted = colors.gray, textSubtle = colors.gray, textInverse = colors.white,
accent = colors.blue, accentLight = colors.lightBlue, accentSoft = colors.lightBlue, accentStrong = colors.blue, hover = colors.lightBlue, focus = colors.lightBlue, info = colors.lightBlue,
success = colors.lime, successSoft = colors.lime, warning = colors.yellow, warningSoft = colors.yellow, danger = colors.red, dangerSoft = colors.red,
shadow = colors.gray, button = colors.gray, buttonText = colors.black, buttonActive = colors.blue, section = colors.lightGray, sectionText = colors.black, taskbar = colors.lightGray, taskbarHover = colors.gray, titleActive = colors.lightGray, titleInactive = colors.gray, titleControl = colors.black, statusText = colors.white, infoText = colors.white, successText = colors.black, dangerText = colors.white, warningText = colors.black,
},
dark = {
name = "Classic Midnight",
type = "dark",
desktop = colors.black, desktopDark = colors.black, desktopGlow = colors.gray, desktopElevated = colors.gray,
surface = colors.gray, surfaceAlt = colors.black, surfaceStrong = colors.gray, surfaceMuted = colors.black, surfaceInset = colors.black,
surfaceSelected = colors.purple, surfaceHover = colors.purple, surfaceDisabled = colors.gray,
border = colors.gray, borderStrong = colors.purple, divider = colors.gray,
text = colors.white, muted = colors.lightGray, textMuted = colors.lightGray, textSubtle = colors.gray, textInverse = colors.black,
accent = colors.purple, accentLight = colors.magenta, accentSoft = colors.purple, accentStrong = colors.magenta, hover = colors.magenta, focus = colors.magenta, info = colors.cyan,
success = colors.lime, successSoft = colors.lime, warning = colors.yellow, warningSoft = colors.yellow, danger = colors.red, dangerSoft = colors.red,
shadow = colors.black, button = colors.gray, buttonText = colors.black, buttonActive = colors.purple, section = colors.gray, sectionText = colors.white, taskbar = colors.black, taskbarHover = colors.gray, titleActive = colors.gray, titleInactive = colors.black, titleControl = colors.white, statusText = colors.white, infoText = colors.white, successText = colors.black, dangerText = colors.white, warningText = colors.black,
},
green = {
name = "Classic Terminal",
type = "dark",
desktop = colors.green, desktopDark = colors.green, desktopGlow = colors.lime, desktopElevated = colors.lime,
surface = colors.black, surfaceAlt = colors.gray, surfaceStrong = colors.black, surfaceMuted = colors.gray, surfaceInset = colors.black,
surfaceSelected = colors.green, surfaceHover = colors.green, surfaceDisabled = colors.gray,
border = colors.gray, borderStrong = colors.lime, divider = colors.gray,
text = colors.white, muted = colors.lightGray, textMuted = colors.lightGray, textSubtle = colors.gray, textInverse = colors.black,
accent = colors.lime, accentLight = colors.lime, accentSoft = colors.green, accentStrong = colors.lime, hover = colors.lime, focus = colors.lime, info = colors.lime,
success = colors.lime, successSoft = colors.green, warning = colors.yellow, warningSoft = colors.yellow, danger = colors.red, dangerSoft = colors.red,
shadow = colors.black, button = colors.gray, buttonText = colors.black, buttonActive = colors.green, section = colors.gray, sectionText = colors.black, taskbar = colors.black, taskbarHover = colors.gray, titleActive = colors.gray, titleInactive = colors.black, titleControl = colors.white, statusText = colors.white, infoText = colors.black, successText = colors.black, dangerText = colors.white, warningText = colors.black,
},
}
Config.defaults = {
theme = "win11dark",
safeMode = false,
logLimit = 200,
reducedMotion = false,
wallpaper = "solid",
}
Config.wallpapers = { "solid", "dots" }
local function defineSettings()
settings.define("qalcom.schema", {
description = "Qalcom settings schema version",
default = 0,
type = "number",
})
settings.define("qalcom.theme", {
description = "Qalcom desktop theme",
default = Config.defaults.theme,
type = "string",
})
settings.define("qalcom.safe_mode", {
description = "Start Qalcom with recovery tools only",
default = Config.defaults.safeMode,
type = "boolean",
})
settings.define("qalcom.log_limit", {
description = "Maximum retained Qalcom log lines",
default = Config.defaults.logLimit,
type = "number",
})
settings.define("qalcom.reduced_motion", {
description = "Reduce Qalcom UI animation",
default = Config.defaults.reducedMotion,
type = "boolean",
})
settings.define("qalcom.wallpaper", {
description = "Qalcom desktop wallpaper style",
default = Config.defaults.wallpaper,
type = "string",
})
end
local function normalizeWallpaper(value)
for _, style in ipairs(Config.wallpapers) do
if value == style then return value end
end
return Config.defaults.wallpaper
end
local function logChange(message)
if not fs.exists("/qalcom/logs") then fs.makeDir("/qalcom/logs") end
local path = "/qalcom/logs/system.log"
local lines = {}
local existing = fs.open(path, "r")
if existing then
local text = existing.readAll() or ""
existing.close()
for line in (text .. "\n"):gmatch("(.-)\n") do
if line ~= "" then lines[#lines + 1] = line end
end
end
lines[#lines + 1] = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " config " .. tostring(message)
local limit = Pure.clampInteger(settings.get("qalcom.log_limit", Config.defaults.logLimit), 50, 1000, Config.defaults.logLimit)
lines = Pure.retainLines(lines, limit)
local file = fs.open(path, "w")
if file then
file.write(table.concat(lines, "\n") .. "\n")
file.close()
end
end
local function readSetting(name, legacyName, fallback)
local value = settings.get(name)
if value == nil and legacyName then value = settings.get(legacyName) end
if value == nil then value = fallback end
return value
end
local function migrate()
local storedSchema = tonumber(settings.get("qalcom.schema")) or 0
local theme = readSetting("qalcom.theme", "qalcom.desktop_theme", Config.defaults.theme)
if storedSchema < 3 and theme == "blue" then theme = Config.defaults.theme end
local safeMode = readSetting("qalcom.safe_mode", "qalcom.safeMode", Config.defaults.safeMode)
local logLimit = readSetting("qalcom.log_limit", "qalcom.logLimit", Config.defaults.logLimit)
local reducedMotion = readSetting("qalcom.reduced_motion", "qalcom.reducedMotion", Config.defaults.reducedMotion)
local normalizedTheme = Config.themes[theme] and theme or Config.defaults.theme
local normalizedSafeMode = safeMode == true
local normalizedLogLimit = Pure.clampInteger(logLimit, 50, 1000, Config.defaults.logLimit)
local normalizedReducedMotion = reducedMotion == true
local changed = storedSchema ~= Config.schemaVersion
or theme ~= normalizedTheme
or safeMode ~= normalizedSafeMode
or tonumber(logLimit) ~= normalizedLogLimit
or reducedMotion ~= normalizedReducedMotion
or settings.get("qalcom.theme") == nil
or settings.get("qalcom.safe_mode") == nil or settings.get("qalcom.log_limit") == nil
or settings.get("qalcom.reduced_motion") == nil
if changed then
settings.set("qalcom.schema", Config.schemaVersion)
settings.set("qalcom.theme", normalizedTheme)
settings.set("qalcom.safe_mode", normalizedSafeMode)
settings.set("qalcom.log_limit", normalizedLogLimit)
settings.set("qalcom.reduced_motion", normalizedReducedMotion)
settings.save()
logChange("migrated settings to schema " .. tostring(Config.schemaVersion))
end
return changed
end
function Config.load()
local migrated = migrate()
defineSettings()
local themeName = settings.get("qalcom.theme", Config.defaults.theme)
if not Config.themes[themeName] then themeName = Config.defaults.theme end
local logLimit = Pure.clampInteger(settings.get("qalcom.log_limit", Config.defaults.logLimit), 50, 1000, Config.defaults.logLimit)
return {
schemaVersion = Config.schemaVersion,
theme = themeName,
colors = Config.themes[themeName],
safeMode = settings.get("qalcom.safe_mode", Config.defaults.safeMode) == true,
logLimit = logLimit,
reducedMotion = settings.get("qalcom.reduced_motion", Config.defaults.reducedMotion) == true,
wallpaper = normalizeWallpaper(settings.get("qalcom.wallpaper", Config.defaults.wallpaper)),
migrated = migrated,
}
end
local function saveAndNotify(message)
settings.set("qalcom.schema", Config.schemaVersion)
settings.save()
logChange(message)
os.queueEvent("qalcom_config_changed")
return true
end
function Config.setTheme(name)
if not Config.themes[name] then return false end
settings.set("qalcom.theme", name)
return saveAndNotify("theme=" .. name)
end
function Config.setSafeMode(enabled)
settings.set("qalcom.safe_mode", enabled == true)
return saveAndNotify("safe_mode=" .. tostring(enabled == true))
end
function Config.setLogLimit(limit)
limit = Pure.clampInteger(limit, 50, 1000, Config.defaults.logLimit)
settings.set("qalcom.log_limit", limit)
return saveAndNotify("log_limit=" .. tostring(limit))
end
function Config.setReducedMotion(enabled)
settings.set("qalcom.reduced_motion", enabled == true)
return saveAndNotify("reduced_motion=" .. tostring(enabled == true))
end
function Config.setWallpaper(style)
style = normalizeWallpaper(style)
settings.set("qalcom.wallpaper", style)
return saveAndNotify("wallpaper=" .. style)
end
function Config.resetDefaults()
settings.set("qalcom.schema", Config.schemaVersion)
settings.set("qalcom.theme", Config.defaults.theme)
settings.set("qalcom.safe_mode", Config.defaults.safeMode)
settings.set("qalcom.log_limit", Config.defaults.logLimit)
settings.set("qalcom.reduced_motion", Config.defaults.reducedMotion)
settings.set("qalcom.wallpaper", Config.defaults.wallpaper)
settings.save()
logChange("restored defaults")
os.queueEvent("qalcom_config_changed")
return true
end
function Config.apply(UI, config)
local theme = config.colors or Config.themes[Config.defaults.theme] or Config.themes.win11dark
for key, value in pairs(theme) do
if key ~= "name" and key ~= "type" and key ~= "palette" then UI.colors[key] = value end
end
if theme.palette then
Palette.apply(theme.palette)
else
Palette.resetDefaults()
end
UI.colors.desktop = theme.desktop or UI.colors.desktop
UI.colors.desktopDark = theme.desktopDark or UI.colors.desktopDark
UI.colors.desktopGlow = theme.desktopGlow or UI.colors.desktopGlow
UI.colors.desktopElevated = theme.desktopElevated or theme.desktopGlow or UI.colors.desktopElevated
UI.colors.surface = theme.surface or UI.colors.surface
UI.colors.surfaceAlt = theme.surfaceAlt or UI.colors.surfaceAlt
UI.colors.surfaceStrong = theme.surfaceStrong or UI.colors.surfaceStrong
UI.colors.surfaceMuted = theme.surfaceMuted or UI.colors.surfaceMuted
UI.colors.border = theme.border or UI.colors.border
UI.colors.borderStrong = theme.borderStrong or UI.colors.borderStrong
UI.colors.text = theme.text or UI.colors.text
UI.colors.muted = theme.muted or UI.colors.muted
UI.colors.accent = theme.accent or UI.colors.accent
UI.colors.accentLight = theme.accentLight or UI.colors.accentLight
UI.colors.lightBlue = theme.accentLight or UI.colors.lightBlue
UI.colors.hover = theme.hover or UI.colors.hover
UI.colors.success = theme.success or UI.colors.success
UI.colors.warning = theme.warning or UI.colors.warning
UI.colors.danger = theme.danger or UI.colors.danger
UI.colors.shadow = theme.shadow or UI.colors.shadow
if UI.syncTokens then UI.syncTokens(theme) end
if UI.setReducedMotion then UI.setReducedMotion(config.reducedMotion == true) end
end
return Config