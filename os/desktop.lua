-- os/desktop.lua — desktop background + desktop icons.
-- Drawn FIRST each frame so windows render on top.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local input  = require("os.input")
local sound  = require("os.sound")
local cfg    = require("os.config")
local programs = require("os.programs")

local M = {}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- Wallpaper renderer (gradient style by default).
local function drawWallpaper()
    local W, H = gfx.width(), gfx.height()
    local wp = cfg.appearance.wallpaper
    if cfg.appearance.wallpaperStyle == "gradient" then
        gfx.gradient(0, 0, W, H, wp.top, wp.bottom, "v")
    elseif cfg.appearance.wallpaperStyle == "solid" then
        gfx.fillRect(0, 0, W, H, wp.top)
    elseif cfg.appearance.wallpaperStyle == "pattern" then
        gfx.fillRect(0, 0, W, H, wp.bottom)
        -- diagonal stripes
        for i = 0, W, 50 do
            gfx.line(i, 0, i + 80, H, theme.c("panel"))
        end
    end
    -- subtle radial vignette overlay
    -- (we approximate by drawing soft concentric rects darker at corners)
end

-- Desktop icons -----------------------------------------------------------
local iconsLayout = nil
local function layoutIcons()
    local topPad = 12
    iconsLayout = {}
    local cw, rh = 72, 84
    local cols = math.floor(gfx.width() / cw) - 1
    for i, app in ipairs(programs.desktopIcons()) do
        local r = math.floor((i-1) / cols)
        local c = (i-1) % cols
        iconsLayout[#iconsLayout+1] = {
            app = app,
            x   = c * cw + topPad,
            y   = r * rh + topPad,
            w   = cw - 8,
            h   = rh - 4,
        }
    end
end

local function drawIcons(hoverId)
    if not iconsLayout then layoutIcons() end
    for _, item in ipairs(iconsLayout) do
        local isHover = (hoverId == item.app.id)
        -- Icon swatch
        local ix, iy, iw, ih = item.x, item.y, item.w, item.h - 16
        local bg = isHover and theme.c("selected") or nil
        if bg then
            gfx.fillRoundRect(ix, iy, iw, item.h, 4, bg)
        end
        local catColor = item.app.category == "system" and theme.c("accent")
                         or (item.app.category == "creative" and theme.c("purpleLight")
                         or (item.app.category == "utility" and theme.c("greenLight")
                         or theme.c("amberDark")))
        local s = 36
        local ww = gfx.textSize(item.app.icon, {size=s, style="bold"})
        gfx.text(item.app.icon, ix + (iw - ww)/2, iy + 8, catColor,
            {size=s, style="bold"})
        -- label
        local labelOpts = {size = dim("fontSizeSmall"), style = "plain"}
        local label = text.ellipsize(item.app.label, iw, labelOpts)
        local lw = gfx.textSize(label, labelOpts)
        gfx.text(label, ix + (iw - lw)/2, iy + iw + 6,
            theme.c("textPrimary"), labelOpts)
    end
end

-- Right-click / context menu ----------------------------------------------
M._ctxMenu = nil
local function drawContextMenu()
    if not M._ctxMenu then return end
    local m = M._ctxMenu
    local x, y, w, h = m.x, m.y, m.w, m.h
    gfx.fillRoundRect(x, y, w, h, 6, theme.c("surfaceHigh"))
    gfx.outlineRect(x, y, w, h, theme.c("borderBright"))
    for _, item in ipairs(m.items) do
        local py = y + 6 + (item.idx - 1) * 26
        local bg = (item.idx == m.hoverIndex) and theme.c("selected") or nil
        if bg then gfx.fillRoundRect(x + 4, py, w - 8, 22, 4, bg) end
        gfx.text(item.label, x + 14, py + 4, theme.c("textPrimary"),
            {size=dim("fontSizeBody"), style="plain"})
    end
end

function M.drawAll()
    drawWallpaper()
    if cfg.appearance.showDesktopIcons then
        layoutIcons()
        local hx, hy = input.cursor()
        local found
        for _, item in ipairs(iconsLayout) do
            if hx >= item.x and hx <= item.x + item.w
                and hy >= item.y and hy <= item.y + item.h then
                found = item.app.id
            end
        end
        drawIcons(found)
    end
    drawContextMenu()
end

-- Hit testing
function M.iconAt(x, y)
    if not iconsLayout then return nil end
    for _, item in ipairs(iconsLayout) do
        if x >= item.x and x <= item.x + item.w
            and y >= item.y and y <= item.y + item.h then
            return item
        end
    end
    return nil
end

function M.hitTestContext(x, y)
    local m = M._ctxMenu
    if not m then return nil end
    if x < m.x or x > m.x + m.w or y < m.y or y > m.y + m.h then
        return m.outsideClose == true and "outside" or nil
    end
    local idx = math.floor((y - m.y - 6) / 26) + 1
    if idx < 1 or idx > #m.items then return nil end
    return m.items[idx].id
end

-- Open a context menu at (x, y)
function M.openContext(x, y, items)
    if not items then
        items = {
            {label = "Open Terminal", id = "terminal"},
            {label = "Open Settings", id = "settings"},
            {label = "Refresh",       id = "refresh"},
            {label = "Change Wallpaper", id = "wallpaper"},
        }
    end
    for i, e in ipairs(items) do e.idx = i end
    M._ctxMenu = {
        x = x, y = y,
        w = 180, h = 6 + #items * 26 + 6,
        items = items,
        hoverIndex = nil,
        outsideClose = true,
    }
end

function M.closeContext() M._ctxMenu = nil end

-- Handle a click event on desktop
function M.onClick(x, y, button)
    -- If context menu visible
    if M._ctxMenu then
        local id = M.hitTestContext(x, y)
        if id == "outside" or id == nil then
            M.closeContext()
            return
        end
        if M.onContextAction then M.onContextAction(id) end
        M.closeContext()
        return
    end
    -- Right-click: open context menu
    if button == 2 then
        sound.beep()
        M.openContext(x, y)
        return
    end
    -- Left-click on an icon -> launch
    local hit = M.iconAt(x, y)
    if hit and M.onLaunch then M.onLaunch(hit.app) end
end

return M
