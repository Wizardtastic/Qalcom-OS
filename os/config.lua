-- os/config.lua — central OS configuration.
-- Qalcom OS paints its UI directly onto the advanced computer's own screen
-- via **CC:Graphics** (CraftOS-PC gfxmode port). No external monitor stack
-- required.
--
-- Edit `display.graphicsMode` if you want to drop to mode 1 (4-bit, 16
-- colors).  Most users will leave it at 2 (8-bit, 256 colors).

local M = {}

-- -------------------------------------------------------------------
-- HARDWARE / DISPLAY
-- graphicsMode:
--   1 = 16-color pixel surface (slightly larger surface, anchor palette)
--   2 = 256-color pixel surface (default — full RGB approximation)
-- Both modes are 0-indexed pixel cells; this OS targets mode 2.
-- -------------------------------------------------------------------
M.display = {
    graphicsMode     = 2,    -- 1 | 2
    requireGraphics  = false, -- if true, halt on missing CC:Graphics
}

-- Default pixel dimensions for an ADVANCED COMPUTER in graphics mode 2.
-- These are not hard-coded at runtime; gfx.init() reads term.getSize(mode)
-- dynamically. The numbers below are a hint for the splash / docs only.
M.expected = {
    width  = 306, -- approx = 51 cell columns * 6 px per cell
    height = 171, -- approx = 19 cell rows * 9 px per cell
}

-- -------------------------------------------------------------------
-- PATHS
-- -------------------------------------------------------------------
M.paths = {
    osRoot      = "/os",
    apps        = "/os/apps",
    users       = "/users",
    homes       = "/home",
    fonts       = "/os/fonts",
    wallpapers  = "/os/wallpapers",
    data        = "/os/data",
    config      = "/os/config",     -- config files live here
    sysLogs     = "/os/logs",
}

-- -------------------------------------------------------------------
-- APPEARANCE
-- -------------------------------------------------------------------
M.appearance = {
    theme           = "default-dark",
    wallpaperStyle  = "gradient", -- "gradient" | "solid" | "pattern"
    wallpaper       = {
        top    = { 32,  46,  86},
        bottom = {  8,  14,  28},
    },
    showDesktopIcons = true,
    taskbarPosition  = "bottom",  -- "bottom"
    uiScale          = 1.0,       -- multiplier for theme.dim
}

-- -------------------------------------------------------------------
-- SECURITY
-- -------------------------------------------------------------------
M.security = {
    defaultUser      = "admin",
    lockoutAttempts  = 5,
}

-- -------------------------------------------------------------------
-- DEFAULTS for new users
-- -------------------------------------------------------------------
M.profile = {
    shell = "shell",
    preferredApps = {},
}

-- -------------------------------------------------------------------
-- User preferences
-- Loads /os/config/user_pref.lua (created by `settings.lua`) on top of the
-- defaults above.  Anything saved in the file overrides the defaults.
-- -------------------------------------------------------------------
function M.loadUserPrefs()
    local p = M.paths.config .. "/user_pref.lua"
    if not fs.exists(p) then return end
    local fn, err = loadfile(p)
    if not fn then return end
    local ok, prefs = pcall(fn)
    if not ok or type(prefs) ~= "table" then return end
    -- Merge keys onto appearance so the in-memory M.appearance picks up
    -- user-chosen wallpaper styles, swatches, UI scale, etc.
    if prefs.wallpaperStyle then M.appearance.wallpaperStyle = prefs.wallpaperStyle end
    if prefs.wallpaper and type(prefs.wallpaper) == "table" then
        if prefs.wallpaper.top then M.appearance.wallpaper.top = prefs.wallpaper.top end
        if prefs.wallpaper.bottom then M.appearance.wallpaper.bottom = prefs.wallpaper.bottom end
    end
    if type(prefs.uiScale) == "number" then M.appearance.uiScale = prefs.uiScale end
    if prefs.theme then M.appearance.theme = prefs.theme end
    if prefs.taskbarPosition then M.appearance.taskbarPosition = prefs.taskbarPosition end
    if type(prefs.graphicsMode) == "number" then M.display.graphicsMode = prefs.graphicsMode end
end

-- -------------------------------------------------------------------
-- helper: ensure the directory tree exists
-- -------------------------------------------------------------------
function M.ensureDirs()
    local function mkdirs(path)
        if not fs.exists(path) then fs.makeDir(path) end
    end
    for _, p in pairs(M.paths) do
        if type(p) == "string" then
            -- create each intermediate dir
            local prefix = ""
            for seg in p:gmatch("[^/]+") do
                prefix = prefix .. "/" .. seg
                mkdirs(prefix)
            end
        end
    end
end

return M
