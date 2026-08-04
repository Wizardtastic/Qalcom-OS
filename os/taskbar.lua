-- os/taskbar.lua — bottom task bar.
-- Drawn last (on top of everything except start menu / context menus).

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local input  = require("os.input")
local wm     = require("os.wm")
local cfg    = require("os.config")
local sound  = require("os.sound")

local M = {}
M.openMenu = nil  -- "start" | nil

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- helpers -------------------------------------------------------------
local function iconBox(x, y, sz, glyph, accent)
    local radius = 4
    gfx.fillRoundRect(x, y, sz, sz, radius, theme.c("surfaceHigh"))
    gfx.outlineRect(x, y, sz, sz, theme.c("border"), 1)
    -- tiny corner accent for default glyph color
    local labelColor = accent or theme.c("textPrimary")
    local sz2 = math.floor(sz * 0.6 + 0.5)
    local measured = gfx.textSize(glyph, {size=sz2, style="bold"})
    gfx.text(glyph, x + (sz - measured)/2, y + (sz - sz2)/2 - 0.5,
        labelColor, {size=sz2, style="bold"})
end

-- static: Computed geometry ------------------------------------------------
M.geometry = nil
local function computeGeom()
    local W = gfx.width() or 306
    local H = gfx.height() or 171
    local H_  = dim("taskbarH") or 28
    local startBtnW = dim("startBtnW") or 52
    local clockW = dim("clockW") or 100
    M.geometry = {
        W = W, H = H,
        barY     = H - H_,
        barH     = H_,
        startX   = 4,
        startW   = startBtnW,
        pinnedX  = startBtnW + 8,
        pinnedW  = 220,
        trayX    = W - clockW - 8,
        clockW   = clockW,
        runningX = 0, -- recomputed below
    }
end
M.computeGeom = computeGeom

-- clock --------------------------------------------------------------------
local function drawClock(now)
    local g = M.geometry
    if not g then return end
    local x, y, w, h = g.trayX, g.barY, g.clockW, g.barH
    -- background
    gfx.fillRoundRect(x, y, w, h, 4, theme.c("surfaceHigh"))
    -- time string
    local hh = string.format("%02d", now.hour or 0)
    local mm = string.format("%02d", now.min or 0)
    local ss = string.format("%02d", now.sec or 0)
    local timeText = hh .. ":" .. mm .. ":" .. ss
    -- Date: os.date("*t") has no .date field, so build it from components.
    -- Accepts a pre-formatted string (now.date) or a components table.
    local date
    if type(now.date) == "string" and #now.date > 0 then
        date = now.date
    elseif now.month and now.day then
        date = string.format("%02d/%02d/%02d", now.month, now.day, (now.year or 2000) % 100)
    else
        date = ""
    end
    -- Header
    local dateOpts = {size = dim("fontSizeSmall"), style = theme.font.stylePlain}
    local timeOpts = {size = dim("fontSizeStatusBar"), style = theme.font.styleBold}
    local timeW, timeH = gfx.textSize(timeText, timeOpts)
    local dateW = gfx.textSize(date, dateOpts)
    local cx = x + (w - math.max(timeW, dateW)) / 2 + 4
    gfx.text(timeText, cx, y + (h - timeH)/2 - 3,
        theme.c("textPrimary"), timeOpts)
    gfx.text(date, x + w - dateW - 8, y + h - dateOpts.size - 4,
        theme.c("textSecondary"), dateOpts)
end

-- start button -------------------------------------------------------------
local function drawStartButton(hover)
    local g = M.geometry
    if not g or not g.startX or not g.barY or not g.startW or not g.barH then return end
    local x, y = g.startX, g.barY + 4
    local w, h = g.startW - 4, g.barH - 8
    local bg = hover and theme.c("accentHover") or theme.c("accent")
    gfx.fillRoundRect(x, y, w, h, 6, bg)
    gfx.outlineRect(x, y, w, h, theme.c("border"), 1)
    -- Qalcom glyph (italic "Q▼" gives a Windows-Start feel)
    local label = "Qalcom"
    local labelOpts = {size = dim("fontSizeTitle"), style = theme.font.styleBold}
    local lw, lh = gfx.textSize(label, labelOpts)
    gfx.text(label, x + (w - lw)/2, y + (h - lh)/2 - 0.5,
        theme.c("textPrimary"), labelOpts)
    -- tiny "▴" arrow
    local arrow = "▴"
    local arrowOpts = {size = 8, style = theme.font.stylePlain}
    local aw = gfx.textSize(arrow, arrowOpts)
    gfx.text(arrow, x + w - aw - 6, y + 6, theme.c("textPrimary"), arrowOpts)
end

-- pinned app tray ----------------------------------------------------------
local function drawPinned(registry, hover)
    local g = M.geometry
    if not g or not g.pinnedX or not g.barY or not g.barH then return end
    if not g.pinnedItems then return end
    local x = g.pinnedX
    local y = g.barY
    local itemSize = dim("pinnedItemSize")
    for i, app in ipairs(g.pinnedItems) do
        local px = x + (i-1)*(itemSize + dim("paddingTight"))
        local py = y + (g.barH - itemSize)/2
        local isHover = hover and hover.app == app.id
        local bg = isHover and theme.c("surfaceHigh") or theme.c("surfaceAlt")
        gfx.fillRoundRect(px, py, itemSize, itemSize, 4, bg)
        gfx.outlineRect(px, py, itemSize, itemSize, theme.c("border"), 1)
        -- accent dot for category
        local catColor = app.category == "system" and theme.c("accent")
                         or (app.category == "creative" and theme.c("purpleLight")
                         or (app.category == "utility" and theme.c("greenLight")
                         or theme.c("amberDark")))
        -- glyph inside
        local s = itemSize - 8
        local ww = gfx.textSize(app.icon, {size=s, style="bold"})
        gfx.text(app.icon, px + (itemSize - ww)/2, py + 2,
            catColor, {size = s, style="bold"})
    end
end

-- running apps strip -------------------------------------------------------
local function drawRunning(hover)
    local g = M.geometry
    if not g or not g.runningX or not g.barY or not g.barH then return end
    if not g.runningItems then return end
    local x = g.runningX
    local y = g.barY
    local h = g.barH
    for i, win in ipairs(g.runningItems) do
        local w_ = dim("runningItemMinW")
        local px = x + (i-1) * (w_ + 4)
        local isHover = hover and hover.win == win.id
        local bg = (win.id == wm.focus and theme.c("selected"))
                   or (isHover and theme.c("surfaceHigh") or theme.c("surfaceAlt"))
        gfx.fillRoundRect(px, y + 4, w_, h - 8, 4, bg)
        gfx.outlineRect(px, y + 4, w_, h - 8, theme.c("border"), 1)
        -- title
        local title = text.ellipsize(win.title, w_ - 16, {size=dim("fontSizeBody"), style="plain"})
        local measured = gfx.textSize(title, {size=dim("fontSizeSmall"), style="plain"})
        gfx.text(title, px + 8, y + (h - measured)/2,
            theme.c("textPrimary"), {size=dim("fontSizeSmall"), style="plain"})
    end
end

-- tray icons (volume, network) --------------------------------------------
local function drawTrayIcons()
    local g = M.geometry
    if not g or not g.barY or not g.barH or not g.trayX then return end
    local y = g.barY + 4
    local h = g.barH - 8
    local sz = h - 4
    local x = g.trayX - sz - 8
    -- Volume icon (just a glyph)
    gfx.fillRoundRect(x, y, sz, sz, 4, theme.c("surfaceHigh"))
    gfx.outlineRect(x, y, sz, sz, theme.c("border"), 1)
    gfx.text("♪", x + (sz - gfx.textSize("♪", {size=sz-6, style="bold"}))/2,
        y + 2, theme.c("greenLight"), {size=sz-6, style="bold"})
end

-- main draw ----------------------------------------------------------------
function M.drawAll(hover)
    computeGeom()
    local g = M.geometry

    -- background bar
    gfx.fillRect(0, g.barY, g.W, g.barH, theme.c("panel"))
    gfx.fillRect(0, g.barY, g.W, 1, theme.c("borderBright"))

    -- pinned: filtered list from registry.setpinnedIfAvailable
    local programs = require("os.programs")
    g.pinnedItems = programs.pinned()

    -- running: visible windows
    g.runningItems = wm.visible()
    -- layout calc: place pinned near start, running after pinned, then tray
    local itemSize = dim("pinnedItemSize")
    g.pinnedW = #g.pinnedItems * (itemSize + dim("paddingTight")) + 4
    g.runningX = g.pinnedX + g.pinnedW + 12
    local runMinW = dim("runningItemMinW")
    local runW = #g.runningItems * (runMinW + 4)
    if g.runningX + runW + dim("clockW") + 32 > g.W then
        g.runningX = g.W - runW - dim("clockW") - 32
    end

    drawStartButton(hover and hover.zone == "start")
    drawPinned(programs, hover)
    drawRunning(hover)
    drawTrayIcons()
    drawClock(os and os.date and os.date("*t") or {hour=0,min=0,sec=0,date=""})
end

-- Hit testing --------------------------------------------------------------
function M.hitTest(x, y)
    local g = M.geometry
    if not g or not g.barY or not g.barH then return nil end
    if y >= g.barY and y <= g.barY + g.barH then
        -- start
        if x >= g.startX and x <= g.startX + g.startW then
            return {zone="start"}
        end
        -- pinned
        for i, app in ipairs(g.pinnedItems or {}) do
            local px = g.pinnedX + (i-1)*(dim("pinnedItemSize")+dim("paddingTight"))
            if x >= px and x <= px + dim("pinnedItemSize") then
                return {zone="pinned", app=app.id, appObj=app}
            end
        end
        -- running
        for i, w in ipairs(g.runningItems or {}) do
            local px = g.runningX + (i-1)*(dim("runningItemMinW") + 4)
            if x >= px and x <= px + dim("runningItemMinW") then
                return {zone="running", win=w.id}
            end
        end
        -- tray area before clock: ping for start on bare taskbar
        return {zone="taskbar"}
    end
    return nil
end

-- Handle a click that hit the taskbar. Returns true if consumed.
function M.onClick(zone, x, y)
    if zone == "start" then
        sound.beep()
        M.openMenu = not M.openMenu
        return true
    end
    if zone == "pinned" then
        sound.beep()
        -- trigger WM launch via a hook into the dashboard
        if M.onLaunchPinned then M.onLaunchPinned(zone.appObj) end
        return true
    end
    if zone == "running" then
        sound.beep()
        -- toggle focus & minimize
        local win = wm.byId(zone.win)
        if not win then return true end
        if win.state == "minimized" then
            win.state = "normal"
            wm.focusWindow(win.id)
        elseif wm.focus == win.id then
            wm.minimize(win.id)
        else
            wm.focusWindow(win.id)
        end
        return true
    end
    if zone == "taskbar" then
        -- Toggle start menu
        M.openMenu = not M.openMenu
        return true
    end
    return false
end

-- Close any open popup menu.
function M.closeMenu() M.openMenu = nil end

return M
