local Config = {}
local Pure = dofile("/qalcom/lib/pure.lua")

Config.schemaVersion = 1
Config.themes = {
    blue = { name = "Ocean", desktop = colors.blue, accent = colors.blue, accentLight = colors.lightBlue },
    dark = { name = "Midnight", desktop = colors.black, accent = colors.purple, accentLight = colors.magenta },
    green = { name = "Terminal", desktop = colors.green, accent = colors.lime, accentLight = colors.lime },
}

Config.defaults = {
    theme = "blue",
    safeMode = false,
    logLimit = 200,
}

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
    -- Read raw values before defining current settings so defaults cannot hide legacy keys.
    local storedSchema = tonumber(settings.get("qalcom.schema")) or 0
    local theme = readSetting("qalcom.theme", "qalcom.desktop_theme", Config.defaults.theme)
    local safeMode = readSetting("qalcom.safe_mode", "qalcom.safeMode", Config.defaults.safeMode)
    local logLimit = readSetting("qalcom.log_limit", "qalcom.logLimit", Config.defaults.logLimit)
    local normalizedTheme = Config.themes[theme] and theme or Config.defaults.theme
    local normalizedSafeMode = safeMode == true
    local normalizedLogLimit = Pure.clampInteger(logLimit, 50, 1000, Config.defaults.logLimit)
    local changed = storedSchema ~= Config.schemaVersion
        or theme ~= normalizedTheme
        or safeMode ~= normalizedSafeMode
        or tonumber(logLimit) ~= normalizedLogLimit
        or settings.get("qalcom.theme") == nil
        or settings.get("qalcom.safe_mode") == nil
        or settings.get("qalcom.log_limit") == nil

    if changed then
        settings.set("qalcom.schema", Config.schemaVersion)
        settings.set("qalcom.theme", normalizedTheme)
        settings.set("qalcom.safe_mode", normalizedSafeMode)
        settings.set("qalcom.log_limit", normalizedLogLimit)
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

function Config.resetDefaults()
    settings.set("qalcom.schema", Config.schemaVersion)
    settings.set("qalcom.theme", Config.defaults.theme)
    settings.set("qalcom.safe_mode", Config.defaults.safeMode)
    settings.set("qalcom.log_limit", Config.defaults.logLimit)
    settings.save()
    logChange("restored defaults")
    os.queueEvent("qalcom_config_changed")
    return true
end

function Config.apply(UI, config)
    local theme = config.colors or Config.themes.blue
    UI.colors.desktop = theme.desktop
    UI.colors.accent = theme.accent
    UI.colors.accentLight = theme.accentLight
    if config.theme == "dark" then
        UI.colors.desktopDark = colors.gray
    else
        UI.colors.desktopDark = colors.darkBlue
    end
end

return Config
