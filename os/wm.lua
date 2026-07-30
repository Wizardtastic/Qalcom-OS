-- os/wm.lua — Window manager.
-- Manages ordered windows with titlebars, three control buttons (close,
-- maximize, minimize), dragging, focus, and event dispatch.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local sound  = require("os.sound")
local input  = require("os.input")

local M = {}
M.windows   = {}    -- list of {id, x,y,w,h, title, win, state, dragging, app, ...}
M.modal     = nil   -- currently-shown modal stack
M.nextId    = 1
M.focus     = nil   -- id of focused window
M.hover     = nil

local DRAG_THRESHOLD = theme.timing.dragThresholdPx
local function getScale() return require("os.config").appearance.uiScale or 1 end
local function dimScaled(name)
    return theme.dimScaled(name, getScale())
end

-- Window state machine
local STATE_NORMAL  = "normal"
local STATE_MIN     = "minimized"
local STATE_MAX     = "maximized"
local STATE_SNAP    = "snapped-left"
local STATE_SNAP_R  = "snapped-right"

local function notifyFocusChangeIfNeeded()
    -- Reserved for future hooks
end

-- ---------------------------------------------------------------------------
-- Window creation
-- ---------------------------------------------------------------------------
M.new = function(opts)
    opts = opts or {}
    local id = M.nextId; M.nextId = M.nextId + 1
    local w, h = opt_scaler(opts, dimScaled)
    local win = {
        id       = id,
        title    = opts.title or "Window",
        x        = opts.x or 60,
        y        = opts.y or 60,
        w        = w,
        h        = h,
        minW     = opts.minW or 200,
        minH     = opts.minH or 120,
        state    = STATE_NORMAL,
        prevGeo  = nil,           -- saved on max
        app      = opts.app,       -- function (win, "paint"), (win, "event", event), (win, "key", key), (win, "char", ch)
        payload  = opts.payload or {},
        z        = #M.windows + 1,
        dragging = opts.dragging or false,
        dragOffX = 0,
        dragOffY = 0,
        dragW    = 0,
        dragH    = 0,
        modal    = opts.modal or false,
        resizable = opts.resizable ~= false,
    }
    M.windows[#M.windows+1] = win
    M.focus = id
    return win
end

local function opt_scaler(opts, dimFn)
    local scale = getScale()
    -- Derive sensible defaults from the actual screen size so windows fit
    -- on the pixel canvas regardless of resolution.
    local screenW = gfx.width()
    local screenH = gfx.height() - dimScaled("taskbarH")
    local w = opts.w or math.floor(screenW * 0.70)
    local h = opts.h or math.floor(screenH * 0.70)
    if type(w) == "string" then w = math.floor(dimFn(w) * scale + 0.5) end
    if type(h) == "string" then h = math.floor(dimFn(h) * scale + 0.5) end
    return w, h
end

-- Bring to front / focus a window
function M.focusWindow(id)
    for i, w in ipairs(M.windows) do
        if w.id == id and w.state ~= STATE_MIN then
            table.remove(M.windows, i)
            w.z = #M.windows + 1
            M.windows[#M.windows+1] = w
            M.focus = id
            return true
        end
    end
    return false
end

function M.close(id)
    for i, w in ipairs(M.windows) do
        if w.id == id then
            -- tell app to clean up
            if w.app and w.app.destroy then
                pcall(w.app.destroy, w)
            end
            table.remove(M.windows, i)
            -- focus the next topmost non-modal
            for j = #M.windows, 1, -1 do
                if M.windows[j].state ~= STATE_MIN then
                    M.focus = M.windows[j].id
                    break
                end
            end
            if M.focus == id then M.focus = nil end
            return true
        end
    end
    return false
end

local function byId(id)
    for _, w in ipairs(M.windows) do
        if w.id == id then return w end
    end
    return nil
end
M.byId = byId

-- Close all windows belonging to an app id (used when "End Task" pressed).
function M.endByAppId(appId)
    local alive = {}
    for _, w in ipairs(M.windows) do
        local keep = true
        if w.app and w.app.appId == appId then
            if w.app.destroy then pcall(w.app.destroy, w) end
            keep = false
        end
        if keep then alive[#alive+1] = w end
    end
    M.windows = alive
end

function M.minimize(id)
    local w = byId(id); if not w then return end
    w.state = STATE_MIN
    M.focus = nil
end

function M.toggleMaximize(id)
    local w = byId(id); if not w then return end
    if w.state == STATE_MAX then
        if w.prevGeo then
            w.x, w.y, w.w, w.h = w.prevGeo.x, w.prevGeo.y, w.prevGeo.w, w.prevGeo.h
            w.state = STATE_NORMAL
        end
    else
        w.prevGeo = { x = w.x, y = w.y, w = w.w, h = w.h }
        local taskbarH = dimScaled("taskbarH")
        local margin = 8
        w.x = margin
        w.y = margin
        w.w = gfx.width() - margin*2
        w.h = gfx.height() - taskbarH - margin*2
        w.state = STATE_MAX
    end
end

-- ---------------------------------------------------------------------------
-- Hit testing: returns either nil, or {win=.., region=.., ...}
-- region: "titlebar" | "min" | "max" | "close" | "client"
-- ---------------------------------------------------------------------------
local function hitTest(win, x, y)
    local tbH = dimScaled("titlebarH")
    local btn = dimScaled("btnSize")
    local pad = dimScaled("btnGap")
    local closeX = win.x + win.w - pad - btn
    local maxX   = closeX - btn - pad
    local minX   = maxX - btn - pad

    if x >= win.x and x <= win.x + win.w and y >= win.y and y <= win.y + tbH then
        if win.state ~= STATE_MAX then
            if y >= win.y and y <= win.y + tbH then
                if x >= closeX and x <= closeX + btn then return "close" end
                if x >= maxX   and x <= maxX + btn  then return "max" end
                if x >= minX   and x <= minX + btn  then return "min" end
                return "titlebar"
            end
        else
            return "titlebar"
        end
    end
    if x >= win.x and x <= win.x + win.w and y >= win.y + tbH and y <= win.y + win.h then
        return "client"
    end
    return nil
end
M.hitTest = hitTest

local function windowAt(x, y)
    -- topmost first; honours the modal stack when one is active.
    local vis = M.modal and { M.modal } or M.windows
    for i = #vis, 1, -1 do
        local w = vis[i]
        if w.state ~= STATE_MIN then
            local r = hitTest(w, x, y)
            if r then return w, r end
        end
    end
    return nil, nil
end
M.windowAt = windowAt

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function drawTitleBar(win)
    local tbH = dimScaled("titlebarH")
    local col = (win.id == M.focus) and theme.c("titlebarActive") or theme.c("titlebar")
    gfx.fillRect(win.x, win.y, win.w, tbH, col)
    gfx.outlineRect(win.x, win.y, win.w, tbH, theme.c("borderBright"), 1)

    -- Title text
    local titleOpts = { size = theme.dimScaled("fontSizeBody", getScale()),
                        style = theme.font.styleBold }
    local tx, ty = text.centerX(win.title, 0, win.w - 80, titleOpts)
    gfx.text(win.title, win.x + tx, win.y + (tbH - titleOpts.size)/2 + 1,
        theme.c("textPrimary"), titleOpts)

    -- Buttons (close, max, min) — only when not maximized (so users can
    -- still grab titlebar). Actually keep them.
    local btnSize = dimScaled("btnSize")
    local pad = dimScaled("btnGap")
    local cy = win.y + (tbH - btnSize) / 2
    local cx_close = win.x + win.w - pad - btnSize
    local cx_max   = cx_close - btnSize - pad
    local cx_min   = cx_max - btnSize - pad

    -- Close button	local cx_, cy_ = input.cursor()
    local hoverClose = (M.hover == win.id and cx_ >= cx_close)
    local function btn(x, color, glyph)
        gfx.fillRoundRect(x, cy, btnSize, btnSize, 3, color)
        gfx.outlineRect(x, cy, btnSize, btnSize, theme.c("borderBright"), 1)
        -- glyph
        if gfx.textSize then
            local sz = theme.dimScaled("fontSizeSmall", getScale())
            local w = gfx.textSize(glyph, {size=sz, style="bold"})
            gfx.text(glyph, x + (btnSize - w)/2, cy + (btnSize - sz)/2 - 0.5,
                theme.c("textInverse"), {size=sz, style="bold"})
        end
    end
    btn(cx_close, theme.c("btnClose"), "×")
    btn(cx_max,   theme.c("btnMaximize"), "□")
    btn(cx_min,   theme.c("btnMinimize"), "—")
end

local function drawShadow(win)
    -- drop shadow (only when not maximized)
    if win.state == STATE_MAX then return end
    local off = 6
    -- DirectGPU only:
    if gfx.isDirectGPU() then
        for i = 0, off-1 do
            local c = { 0, 0, 0 }
            -- Right edge
            gfx.fillRect(win.x + win.w + i, win.y + i, 1, win.h, c[1], c[2], c[3])
            -- Bottom edge
            gfx.fillRect(win.x + i, win.y + win.h + i, win.w, 1, c[1], c[2], c[3])
        end
    end
end

local function clientRect(win)
    local tbH = dimScaled("titlebarH")
    return win.x, win.y + tbH, win.w, win.h - tbH
end

function M.clientRect(win) return clientRect(win) end

-- ---------------------------------------------------------------------------
-- Render all windows (back to front).
-- ---------------------------------------------------------------------------
function M.drawAll()
    -- Pass 1: shadow and frames (back to front)
    for _, w in ipairs(M.windows) do
        if w.state ~= STATE_MIN then drawShadow(w) end
    end
    -- Pass 2: client body then chrome
    for _, w in ipairs(M.windows) do
        if w.state ~= STATE_MIN then
            -- Background of client area
            local cx, cy, cw, ch = clientRect(w)
            gfx.fillRect(cx, cy, cw, ch, theme.c("surfaceAlt"))
            gfx.outlineRect(w.x, w.y, w.w, w.h, theme.c("border"), 1)

            -- Let app paint the client area
            if w.app and w.app.paint then
                pcall(w.app.paint, w, cx, cy, cw, ch)
            end

            -- Chrome on top
            drawTitleBar(w)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Main dispatch loop chunk: handle one event.
-- ---------------------------------------------------------------------------
function M.dispatchEvent(ev)
    local x, y = ev.x, ev.y
    local win, region = M.windowAt(x, y)

    if ev.type == "mouse_down" then
        sound.beep()
        if not win then return false end
        -- focus
        M.focusWindow(win.id)
        -- region-specific action
        if region == "close" then
            M.close(win.id)
            return true
        elseif region == "min" then
            M.minimize(win.id)
            return true
        elseif region == "max" then
            M.toggleMaximize(win.id)
            return true
        elseif region == "titlebar" and win.state ~= STATE_MAX then
            win.dragging = true
            win.dragOffX = x - win.x
            win.dragOffY = y - win.y
            return true
        end
        -- client region click — forward
        if win.app and win.app.onEvent then
            local cx, cy = clientRect(win)
            pcall(win.app.onEvent, win, ev, x - cx, y - cy)
        end
        return true
    end

    if ev.type == "mouse_drag" then
        for _, w in ipairs(M.windows) do
            if w.dragging and w.state ~= STATE_MAX then
                w.x = (x - w.dragOffX)
                w.y = (y - w.dragOffY)
                -- Clamp to screen
                if w.y < 0 then w.y = 0 end
                local tbH = dimScaled("taskbarH")
                if w.y + w.h > gfx.height() - tbH then w.y = gfx.height() - tbH - w.h end
                if w.x + w.w < 30 then w.x = 30 - w.w end
                if w.x > gfx.width() - 30 then w.x = gfx.width() - 30 end
            end
        end
        return false  -- also propagate to client for content dragging
    end

    if ev.type == "mouse_up" then
        for _, w in ipairs(M.windows) do
            if w.dragging then
                w.dragging = false
            end
        end
    end

    if ev.type == "key" or ev.type == "char" then
        -- send to focused window
        local target = byId(M.focus)
        if target and target.app then
            if ev.type == "key" and target.app.onKey then
                pcall(target.app.onKey, target, ev)
            elseif ev.type == "char" and target.app.onChar then
                pcall(target.app.onChar, target, ev)
            end
        end
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- "Pump" - the caller runs this in their main loop with an event.
-- The WM updates hover state too.
-- ---------------------------------------------------------------------------
local function contains(win, x, y)
    return x >= win.x and x <= win.x + win.w and y >= win.y and y <= win.y + win.h
end

function M.pump(ev)
    -- Hover state
    if ev.x and ev.y then
        local w, _ = (M.windowAt and M.windowAt(ev.x, ev.y)) or windowAt(ev.x, ev.y)
        M.hover = w and w.id or nil
    end
    -- Dispatch
    return M.dispatchEvent(ev)
end

-- Iterate only visible windows.
function M.visible()
    local out = {}
    for _, w in ipairs(M.windows) do
        if w.state ~= STATE_MIN then out[#out+1] = w end
    end
    return out
end

return M
