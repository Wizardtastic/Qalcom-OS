-- os/apps/settings.lua — OS settings (theme, wallpaper, users, about...).
-- Sidebar of categories on the left, content panel on the right.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")
local sound  = require("os.sound")
local notif  = require("os.notifications")
local auth   = require("os.auth")
local fsutil = require("os.fsutil")

local M = {w = 540, h = 420, minW = 300, minH = 240, appId = "settings"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

local categories = {
    {id="display",       label="Display",         panel="display"},
    {id="personalize",   label="Personalization", panel="personalization"},
    {id="accounts",      label="Accounts",        panel="accounts"},
    {id="sound",         label="Sound",           panel="sound"},
    {id="about",         label="About",           panel="about"},
}

local function newState()
    return {
        category = "display",
        hover    = nil,
        focus    = nil,
    }
end

local function state(win) win.appState = win.appState or newState(); return win.appState end

function M.init(win)
    state(win)
    win.title = "Settings"
end
function M.destroy() end

local function sidebarGeom(win)
    local pad = dim("padding")
    return {
        x = win.x + pad, y = win.y + dim("titlebarH") + pad,
        w = 150, h = win.h - dim("titlebarH") - pad*2
    }
end

local function contentGeom(win)
    local s = sidebarGeom(win)
    local pad = dim("padding")
    return {
        x = s.x + s.w + pad*2, y = s.y,
        w = win.w - (s.x + s.w - win.x) - pad*3,
        h = s.h,
    }
end

local function drawSidebar(win, state)
    local s = sidebarGeom(win)
    gfx.fillRoundRect(s.x, s.y, s.w, s.h, 4, theme.c("surface"))
    gfx.outlineRect(s.x, s.y, s.w, s.h, theme.c("border"))
    local y = s.y + 8
    for _, c in ipairs(categories) do
        local hot = state.category == c.id
        if hot then
            gfx.fillRoundRect(s.x + 4, y, s.w - 8, 28, 4, theme.c("selected"))
        end
        gfx.text(c.label, s.x + 12, y + (28 - dim("fontSizeBody"))/2,
            theme.c("textPrimary"), {size=dim("fontSizeBody"), style="plain"})
        y = y + 32
    end
end

local function drawDisplayPanel(win, state)
    local c = contentGeom(win)
    gfx.fillRoundRect(c.x, c.y, c.w, c.h, 4, theme.c("surface"))
    gfx.outlineRect(c.x, c.y, c.w, c.h, theme.c("border"))
    gfx.text("Display", c.x + 12, c.y + 8, theme.c("textPrimary"),
        {size = dim("fontSizeTitle"), style = "bold"})

    -- Resolution info
    gfx.text(("Canvas: %dx%d  (%s)"):format(gfx.width(), gfx.height(),
        gfx.isDirectGPU() and "DirectGPU" or "Term fallback"),
        c.x + 14, c.y + 36, theme.c("textSecondary"),
        {size = dim("fontSizeBody"), style = "plain"})
    if gfx.isDirectGPU() then
        local stats = gfx._stats()
        gfx.text(("DisplayID: %s  |  monitor blocks: %dx%d  |  multiplier: %d"):format(
            tostring(stats.displayId),
            cfg.display.monitorW, cfg.display.monitorH, cfg.display.multiplier),
            c.x + 14, c.y + 54, theme.c("textMuted"),
            {size = dim("fontSizeSmall"), style = "plain"})
    end

    -- UI scale buttons
    local opts = {size = dim("fontSizeBody"), style = "plain"}
    gfx.text("UI scale:", c.x + 14, c.y + 86,
        theme.c("textPrimary"), opts)
    local scales = {0.85, 1.0, 1.15}
    local bx = c.x + 80
    for _, s in ipairs(scales) do
        local isHot = (cfg.appearance.uiScale == s)
        local bg = isHot and theme.c("accent") or theme.c("surfaceHigh")
        gfx.fillRoundRect(bx, c.y + 70, 60, 22, 4, bg)
        gfx.outlineRect(bx, c.y + 70, 60, 22, theme.c("border"))
        local label = (s * 100) .. "%"
        local tw = gfx.textSize(label, opts)
        gfx.text(label, bx + (60 - tw)/2, c.y + (90 - opts.size)/2,
            theme.c("textPrimary"), opts)
        bx = bx + 66
    end
    gfx.text("Restart OS for ui-scale changes to take effect.",
        c.x + 14, c.y + 100, theme.c("textMuted"),
        {size = dim("fontSizeSmall"), style = "italic"})
end

local function drawPersonalizationPanel(win, state)
    local c = contentGeom(win)
    gfx.fillRoundRect(c.x, c.y, c.w, c.h, 4, theme.c("surface"))
    gfx.outlineRect(c.x, c.y, c.w, c.h, theme.c("border"))
    gfx.text("Personalization", c.x + 12, c.y + 8, theme.c("textPrimary"),
        {size = dim("fontSizeTitle"), style = "bold"})

    -- Wallpaper style buttons
    gfx.text("Wallpaper style:", c.x + 14, c.y + 36,
        theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "plain"})
    local styles = {"gradient", "solid", "pattern"}
    local bx = c.x + 130
    for _, st in ipairs(styles) do
        local isHot = (cfg.appearance.wallpaperStyle == st)
        local bg = isHot and theme.c("accent") or theme.c("surfaceHigh")
        gfx.fillRoundRect(bx, c.y + 22, 90, 26, 6, bg)
        gfx.outlineRect(bx, c.y + 22, 90, 26, theme.c("border"))
        gfx.text(st, bx + 12, c.y + (40 - dim("fontSizeBody"))/2,
            theme.c("textPrimary"),
            {size = dim("fontSizeBody"), style = "plain"})
        bx = bx + 96
    end

    -- Wallpaper swatches (top/bottom colors)
    gfx.text("Wallpaper colors:", c.x + 14, c.y + 72,
        theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "plain"})

    -- 3 swatches
    local palette = {
        {top = {32, 46, 86},   bottom = {8, 14, 28},   label = "Navy"},
        {top = {86, 30, 110},  bottom = {16, 8, 26},   label = "Purple"},
        {top = {28, 80, 60},   bottom = {10, 24, 18},  label = "Forest"},
        {top = {120, 60, 40},  bottom = {22, 14, 8},   label = "Sunset"},
    }
    local sx = c.x + 14
    local sy = c.y + 88
    for _, p in ipairs(palette) do
        local isSel = (cfg.appearance.wallpaper.top[1] == p.top[1]) and
                      (cfg.appearance.wallpaper.top[2] == p.top[2]) and
                      (cfg.appearance.wallpaper.top[3] == p.top[3])
        gfx.gradient(sx, sy, 80, 50, p.top, p.bottom, "v")
        gfx.outlineRect(sx, sy, 80, 50, isSel and theme.c("accent") or theme.c("border"))
        gfx.text(p.label, sx + 4, sy + 50 + 4, theme.c("textSecondary"),
            {size = dim("fontSizeSmall"), style = "plain"})
        sx = sx + 86
    end
end

local function drawAccountsPanel(win, state)
    local c = contentGeom(win)
    gfx.fillRoundRect(c.x, c.y, c.w, c.h, 4, theme.c("surface"))
    gfx.outlineRect(c.x, c.y, c.w, c.h, theme.c("border"))
    gfx.text("Accounts", c.x + 12, c.y + 8, theme.c("textPrimary"),
        {size = dim("fontSizeTitle"), style = "bold"})

    local names = auth.list()
    if #names == 0 then
        gfx.text("No users.", c.x + 14, c.y + 36, theme.c("textMuted"),
            {size = dim("fontSizeBody"), style = "plain"})
    end
    local y = c.y + 36
    for _, name in ipairs(names) do
        local u = auth.users[name]
        gfx.text(string.format("• %s  (role: %s)", name, u.role or "user"),
            c.x + 14, y, theme.c("textPrimary"),
            {size = dim("fontSizeBody"), style = "plain"})
        y = y + 22
    end

    -- Create-user button
    local bx, by = c.x + 14, c.y + c.h - 36
    gfx.fillRoundRect(bx, by, 130, 26, 4, theme.c("accent"))
    gfx.outlineRect(bx, by, 130, 26, theme.c("border"))
    gfx.text("+ Add user", bx + 14, by + (26 - dim("fontSizeBody"))/2,
        theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "bold"})
end

local function drawSoundPanel(win, state)
    local c = contentGeom(win)
    gfx.fillRoundRect(c.x, c.y, c.w, c.h, 4, theme.c("surface"))
    gfx.outlineRect(c.x, c.y, c.w, c.h, theme.c("border"))
    gfx.text("Sound", c.x + 12, c.y + 8, theme.c("textPrimary"),
        {size = dim("fontSizeTitle"), style = "bold"})

    -- speaker detection
    local speaker = peripheral and peripheral.find and peripheral.find("speaker")
    if speaker then
        gfx.text("Speaker detected ✓", c.x + 14, c.y + 36,
            theme.c("ok"), {size = dim("fontSizeBody"), style = "plain"})
    else
        gfx.text("No speaker. (place one nearby to enable sounds.)",
            c.x + 14, c.y + 36, theme.c("textMuted"),
            {size = dim("fontSizeBody"), style = "plain"})
    end

    -- test buttons
    local labels = {"Test chime", "Test click", "Test error"}
    local bx = c.x + 14
    local by = c.y + 70
    if speaker then
        for _, l in ipairs(labels) do
            gfx.fillRoundRect(bx, by, 110, 26, 4, theme.c("surfaceHigh"))
            gfx.outlineRect(bx, by, 110, 26, theme.c("border"))
            gfx.text(l, bx + 14, by + (26 - dim("fontSizeBody"))/2,
                theme.c("textPrimary"),
                {size = dim("fontSizeBody"), style = "plain"})
            bx = bx + 116
        end
    end
end

local function drawAboutPanel(win, state)
    local c = contentGeom(win)
    gfx.fillRoundRect(c.x, c.y, c.w, c.h, 4, theme.c("surface"))
    gfx.outlineRect(c.x, c.y, c.w, c.h, theme.c("border"))
    gfx.text("About Qalcom OS", c.x + 12, c.y + 8, theme.c("textPrimary"),
        {size = dim("fontSizeTitle"), style = "bold"})
    gfx.text("Version 0.1.0", c.x + 14, c.y + 36,
        theme.c("textSecondary"),
        {size = dim("fontSizeBody"), style = "plain"})
    gfx.text("Built on ComputerCraft: Tweaked using CC:DirectGPU.",
        c.x + 14, c.y + 56, theme.c("textSecondary"),
        {size = dim("fontSizeBody"), style = "plain"})
    gfx.text("Inspired by LevelOS / Ursa OS, themed after Windows + macOS.",
        c.x + 14, c.y + 76, theme.c("textSecondary"),
        {size = dim("fontSizeBody"), style = "plain"})
    gfx.text("Lua runtime; CC:Tweaked provides the API.",
        c.x + 14, c.y + 96, theme.c("textMuted"),
        {size = dim("fontSizeSmall"), style = "italic"})
end

local panels = {
    display = drawDisplayPanel,
    personalization = drawPersonalizationPanel,
    accounts = drawAccountsPanel,
    sound = drawSoundPanel,
    about = drawAboutPanel,
}

function M.paint(win, cx, cy, cw, ch)
    local s = state(win)
    drawSidebar(win, s)
    local fn = panels[s.category] or drawDisplayPanel
    fn(win, s)
end

local function pointInRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function M.onEvent(win, ev, lx, ly)
    local s = state(win)
    local ax, ay = lx + win.x + 0, ly + win.y + dim("titlebarH")
    if ev.type == "mouse_move" then
        -- nothing
    end
    if ev.type == "mouse_down" then
        sound.beep()
        -- Sidebar
        local sb = sidebarGeom(win)
        if pointInRect(ax, ay, sb) then
            local idx = math.floor((ay - sb.y - 8) / 32) + 1
            if idx >= 1 and idx <= #categories then
                s.category = categories[idx].id
            end
            return
        end
        -- Wallpaper swatches handle
        if s.category == "personalization" then
            local c = contentGeom(win)
            local sx = c.x + 14
            local sy = c.y + 88
            local palette = {
                {top = {32, 46, 86},   bottom = {8, 14, 28},   label = "Navy"},
                {top = {86, 30, 110},  bottom = {16, 8, 26},   label = "Purple"},
                {top = {28, 80, 60},   bottom = {10, 24, 18},  label = "Forest"},
                {top = {120, 60, 40},  bottom = {22, 14, 8},   label = "Sunset"},
            }
            for _, p in ipairs(palette) do
                if ax >= sx and ax <= sx + 80 and ay >= sy and ay <= sy + 50 then
                    cfg.appearance.wallpaper.top = p.top
                    cfg.appearance.wallpaper.bottom = p.bottom
                    fsutil.write((cfg.paths.osRoot or "/os") .. "/config/user_pref.lua",
                        "return " .. fsutil.serialize(cfg.appearance) .. "\n")
                    notif.push({title="Wallpaper changed",
                        body = "Saved "..p.label.." wallpaper.",
                        level="ok"})
                    return
                end
                sx = sx + 86
            end
            -- Style buttons
            local bx0 = c.x + 130
            local styles = {"gradient", "solid", "pattern"}
            for _, st in ipairs(styles) do
                if ax >= bx0 and ax <= bx0 + 90 and ay >= c.y + 22 and ay <= c.y + 48 then
                    cfg.appearance.wallpaperStyle = st
                    fsutil.write((cfg.paths.osRoot or "/os") .. "/config/user_pref.lua",
                        "return " .. fsutil.serialize(cfg.appearance) .. "\n")
                    notif.push({title="Wallpaper style",
                        body="Set to "..st, level="ok"})
                    return
                end
                bx0 = bx0 + 96
            end
        end
    end
end

return M
