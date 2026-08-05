local Config = {}

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

function Config.load()
    defineSettings()
    local themeName = settings.get("qalcom.theme", Config.defaults.theme)
    if not Config.themes[themeName] then themeName = Config.defaults.theme end
    local logLimit = tonumber(settings.get("qalcom.log_limit", Config.defaults.logLimit)) or Config.defaults.logLimit
    logLimit = math.max(50, math.min(1000, math.floor(logLimit)))
    return {
        theme = themeName,
        colors = Config.themes[themeName],
        safeMode = settings.get("qalcom.safe_mode", Config.defaults.safeMode) == true,
        logLimit = logLimit,
    }
end

function Config.setTheme(name)
    if not Config.themes[name] then return false end
    settings.set("qalcom.theme", name)
    settings.save()
    os.queueEvent("qalcom_config_changed")
    return true
end

function Config.setSafeMode(enabled)
    settings.set("qalcom.safe_mode", enabled == true)
    settings.save()
    os.queueEvent("qalcom_config_changed")
    return true
end

function Config.setLogLimit(limit)
    limit = math.max(50, math.min(1000, math.floor(tonumber(limit) or Config.defaults.logLimit)))
    settings.set("qalcom.log_limit", limit)
    settings.save()
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
