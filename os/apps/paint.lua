-- os/apps/paint.lua — pixel-paint canvas.
-- Two-zone layout: a fixed left palette + a fixed top toolbar,
-- a free-form canvas in the middle.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")
local sound  = require("os.sound")
local notif  = require("os.notifications")
local fsutil = require("os.fsutil")

local M = {w = 600, h = 420, minW = 320, minH = 220, appId = "paint"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

local palette = {
    {0,0,0},       {255,255,255},   {170,170,170},   {85,85,85},
    {255,85,85},   {255,170,85},    {255,255,85},    {85,255,85},
    {85,255,255},  {85,170,255},    {85,85,255},     {255,85,255},
    {170,85,170},  {170,170,255},   {170,255,170},   {255,170,170},
}

local function newState()
    return {
        canvas    = {},          -- canvas[y*ww+x] = r,g,b (r,g,b = 0..255)
        ww        = 0,           -- width
        hh        = 0,           -- height
        color     = {0,0,0},
        hoverPal  = nil,
        tool      = "brush",     -- "brush" | "spray" | "erase"
        size      = 3,
        drawing   = false,
        canvasX   = 80, canvasY = 12,    -- canvas offset within client
        canvasW   = 400, canvasH = 280,
    }
end

local function state(win) win.appState = win.appState or newState(); return win.appState end

function M.init(win)
    state(win)
    win.title = "Paint — Untitled"
end

function M.destroy() end

local function ensureCanvas(s, w, h)
    s.ww = w; s.hh = h
    if #s.canvas == 0 then
        -- initialize white
        for i = 1, w*h do
            s.canvas[i] = {255,255,255}
        end
    end
end

local function setPixel(s, x, y, col)
    if x < 0 or x >= s.ww or y < 0 or y >= s.hh then return end
    s.canvas[y*s.ww + x + 1] = {col[1], col[2], col[3]}
    -- Draw on screen
    if gfx.isDirectGPU() then
        gfx.fillRect(s.canvasX + x, s.canvasY + y, 1, 1, col)
    else
        gfx.pixel(s.canvasX + x, s.canvasY + y, col)
    end
end

local function stamp(s, cx_, cy_, col)
    local r = s.size
    for dy = -r, r do
        for dx = -r, r do
            if dx*dx + dy*dy <= r*r then
                if s.tool == "spray" then
                    if math.random() < 0.5 then
                        setPixel(s, cx_+dx, cy_+dy, col)
                    end
                else
                    setPixel(s, cx_+dx, cy_+dy, col)
                end
            end
        end
    end
end

-- Toolbar at top
local function drawToolbar(win, state)
    local tbY = win.y + dim("titlebarH")
    gfx.fillRect(win.x, tbY, win.w, 28, theme.c("surface"))
    gfx.outlineRect(win.x, tbY, win.w, 28, theme.c("border"))

    -- Tools
    local tools = {{l="Brush", k="brush"}, {l="Spray", k="spray"}, {l="Erase", k="erase"}}
    local x = win.x + 6
    for _, t in ipairs(tools) do
        local isHot = state.tool == t.k
        local bg = isHot and theme.c("accent") or theme.c("surfaceHigh")
        gfx.fillRoundRect(x, tbY + 4, 60, 20, 4, bg)
        gfx.outlineRect(x, tbY + 4, 60, 20, theme.c("border"))
        gfx.text(t.l, x + 6, tbY + (28 - dim("fontSizeBody"))/2,
            theme.c("textPrimary"),
            {size = dim("fontSizeSmall"), style = "bold"})
        x = x + 66
    end

    -- Brush size
    gfx.text(("Size: " .. state.size), x + 8, tbY + (28 - dim("fontSizeBody"))/2,
        theme.c("textSecondary"), {size=dim("fontSizeBody"), style="plain"})

    -- Color preview (top right)
    local px = win.x + win.w - 36
    gfx.fillRoundRect(px, tbY + 4, 28, 20, 4, state.color)
    gfx.outlineRect(px, tbY + 4, 28, 20, theme.c("border"))
end

-- Left palette
local function drawPalette(win, state)
    local padX = win.x + 4
    local padY = win.y + dim("titlebarH") + 36
    gfx.fillRoundRect(padX, padY, 64, palette and #palette or 0 * 18 + 8, 6, theme.c("surface"))
end

local function drawCanvas(win, state)
    local x0 = win.x + 80
    local y0 = win.y + dim("titlebarH") + 36
    local cw = win.w - 84
    local chh = win.h - dim("titlebarH") - 36 - 6
    -- bg
    gfx.fillRect(x0, y0, cw, chh, theme.c("surfaceAlt"))
    gfx.outlineRect(x0, y0, cw, chh, theme.c("border"))

    state.canvasX, state.canvasY, state.canvasW, state.canvasH = x0+4, y0+4, cw-8, chh-8
    ensureCanvas(state, state.canvasW, state.canvasH)

    -- Re-draw canvas (in case state was not initialized)
    if gfx.isDirectGPU() then
        -- blit each pixel
        for yy = 0, state.hh - 1 do
            for xx = 0, state.ww - 1 do
                local c = state.canvas[yy*state.ww + xx + 1]
                if c then gfx.pixel(x0 + 4 + xx, y0 + 4 + yy, c) end
            end
        end
    else
        -- term fallback: paint dots where color != white
        for yy = 0, state.hh - 1 do
            for xx = 0, state.ww - 1 do
                local c = state.canvas[yy*state.ww + xx + 1]
                if c and not (c[1]==255 and c[2]==255 and c[3]==255) then
                    gfx.pixel(x0 + 4 + xx, y0 + 4 + yy, c)
                end
            end
        end
    end
end

function M.paint(win, cx, cy, cw, ch)
    local s = state(win)
    drawPalette(win, s)
    drawToolbar(win, s)
    drawCanvas(win, s)

    -- Draw brush cursor
    local mx, my = (input_cursor() )
    if mx >= s.canvasX and mx < s.canvasX + s.canvasW
        and my >= s.canvasY and my < s.canvasY + s.canvasH then
        local lx, ly = mx - s.canvasX, my - s.canvasY
        gfx.outlineRect(lx - s.size + s.canvasX, ly - s.size + s.canvasY,
            s.size*2+1, s.size*2+1, theme.c("accent"), 1)
    end
end

local function input_cursor()
    local input = require("os.input")
    return input.cursor()
end

function M.onEvent(win, ev, lx, ly)
    local s = state(win)
    local ax, ay = lx + win.x + 0, ly + win.y + dim("titlebarH")
    -- Palette on left
    local palX = win.x + 8
    local palY = win.y + dim("titlebarH") + 40
    if ay >= palY and ax < win.x + 76 then
        local row = math.floor((ay - palY) / 18)
        if row >= 0 and row < #palette then
            s.hoverPal = palette[row + 1] or {0,0,0}
            if ev.type == "mouse_down" then
                s.color = s.hoverPal
                sound.beep()
            end
        end
    end
    -- Toolbar (top)
    local tbY = win.y + dim("titlebarH")
    if ay >= tbY and ay <= tbY + 28 then
        local tools = {{l="Brush", k="brush"}, {l="Spray", k="spray"}, {l="Erase", k="erase"}}
        local x = win.x + 6
        for _, t in ipairs(tools) do
            if ax >= x and ax <= x + 60 then
                if ev.type == "mouse_down" then
                    s.tool = t.k
                    if t.k == "erase" then s.color = {255,255,255} end
                    sound.beep()
                end
            end
            x = x + 66
        end
        -- size adjust: click left half decreases, right half increases
        if ax >= x and ax <= x + 80 then
            if ev.type == "mouse_down" then
                if ax < x + 40 then s.size = math.max(1, s.size - 1)
                else s.size = math.min(20, s.size + 1) end
            end
        end
    end

    -- Canvas drawing
    if ax >= s.canvasX and ax < s.canvasX + s.canvasW
        and ay >= s.canvasY and ay < s.canvasY + s.canvasH then
        local lx2, ly2 = ax - s.canvasX, ay - s.canvasY
        if ev.type == "mouse_down" then
            s.drawing = true
            stamp(s, lx2, ly2, s.color)
        elseif ev.type == "mouse_drag" and s.drawing then
            stamp(s, lx2, ly2, s.color)
        elseif ev.type == "mouse_up" then
            s.drawing = false
        end
    elseif ev.type == "mouse_up" then
        s.drawing = false
    end
end

return M
