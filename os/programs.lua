-- os/programs.lua — application registry.
-- Each app declares its metadata, kicker function etc. so the desktop,
-- start menu and task manager can launch and list them uniformly.

local M = {}

-- Each program entry has:
--   {
--     id, label, icon (symbol or path), category,
--     launch = function(env) -> coroutine, -- main app coroutine
--     description,  -- shown in start menu
--   }
--
-- The launch function takes the parent environment (currently the window
-- manager; it returns a function the WM calls each tick and on each event).
-- Returning `nil` means "run a single frame"; returning a function means
-- "I'll redraw myself within an existing window using the provided context".

M.registry = {
    {
        id    = "explorer",
        label = "File Explorer",
        icon  = "EX",  -- text glyph fallback
        description = "Browse your files, system and user home.",
        launch = function(env) return require("os.apps.explorer")(env) end,
        category = "system",
        pinned = true,
        desktop = true,
    },
    {
        id    = "taskmgr",
        label = "Task Manager",
        icon  = "TM",
        description = "View and end running apps, see system stats.",
        launch = function(env) return require("os.apps.taskmgr")(env) end,
        category = "system",
        pinned = true,
        desktop = true,
    },
    {
        id    = "notepad",
        label = "Notepad",
        icon  = "NP",
        description = "Quick plain-text editor.",
        launch = function(env) return require("os.apps.notepad")(env) end,
        category = "utility",
        pinned = true,
        desktop = false,
    },
    {
        id    = "clockapp",
        label = "Clock",
        icon  = "CL",
        description = "Big analog + digital clock.",
        launch = function(env) return require("os.apps.clockapp")(env) end,
        category = "utility",
        pinned = true,
        desktop = false,
    },
    {
        id    = "calculator",
        label = "Calculator",
        icon  = "CA",
        description = "Standard arithmetic.",
        launch = function(env) return require("os.apps.calculator")(env) end,
        category = "utility",
        pinned = false,
        desktop = false,
    },
    {
        id    = "paint",
        label = "Paint",
        icon  = "PT",
        description = "Pixel art canvas in the OS color palette.",
        launch = function(env) return require("os.apps.paint")(env) end,
        category = "creative",
        pinned = false,
        desktop = false,
    },
    {
        id    = "settings",
        label = "Settings",
        icon  = "ST",
        description = "Theme, wallpaper and user preferences.",
        launch = function(env) return require("os.apps.settings")(env) end,
        category = "system",
        pinned = true,
        desktop = true,
    },
    {
        id    = "about",
        label = "About Qalcom OS",
        icon  = "AB",
        description = "Version info and credits.",
        launch = function(env) return require("os.apps.about")(env) end,
        category = "system",
        pinned = false,
        desktop = true,
    },
}

function M.byId(id)
    for _, p in ipairs(M.registry) do
        if p.id == id then return p end
    end
    return nil
end

function M.all() return M.registry end
function M.pinned()
    local out = {}
    for _, p in ipairs(M.registry) do
        if p.pinned then out[#out+1] = p end
    end
    return out
end
function M.desktopIcons()
    local out = {}
    for _, p in ipairs(M.registry) do
        if p.desktop then out[#out+1] = p end
    end
    return out
end
function M.byCategory()
    local out = {}
    for _, p in ipairs(M.registry) do
        out[p.category] = out[p.category] or {}
        table.insert(out[p.category], p)
    end
    return out
end

return M
