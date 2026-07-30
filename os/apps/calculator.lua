-- os/apps/calculator.lua — Standard arithmetic calculator.
-- Buttons in a 4x4 grid.  Click-button keyboard.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")
local sound  = require("os.sound")
local notif  = require("os.notifications")

local M = {w = 320, h = 420, minW = 220, minH = 280, appId = "calculator"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- Buttons layout (4 columns x 5 rows). Each entry: {label, kind, [w-span]}.
local layout = {
    {{"C", "clr"},   {"±", "neg"},   {"%", "pct"}, {"÷", "op", "/"}},
    {{"7", "n", "7"}, {"8", "n", "8"}, {"9", "n", "9"}, {"×", "op", "*"}},
    {{"4", "n", "4"}, {"5", "n", "5"}, {"6", "n", "6"}, {"−", "op", "-"}},
    {{"1", "n", "1"}, {"2", "n", "2"}, {"3", "n", "3"}, {"+", "op", "+"}},
    {{"0", "n", "0", wspan=2},       {".", "dot"},    {"=", "eq"}},
}

local function newState()
    return {
        display = "0",
        pending = nil,
        op      = nil,
        accum   = nil,
        editing = true,
        status  = "",
        hover   = nil,
    }
end

local function state(win) win.appState = win.appState or newState(); return win.appState end

function M.init(win)
    state(win)
    win.title = "Calculator"
end
function M.destroy() end

local function apply(s, op, a, b)
    if op == "+" then return a + b
    elseif op == "−" or op == "-" then return a - b
    elseif op == "×" or op == "*" then return a * b
    elseif op == "÷" or op == "/" then
        if b == 0 then s.status = "Cannot divide by 0"; return a end
        return a / b
    end
    return b
end

local function press(win, but, s)
    local kind = but[2]
    if kind == "n" or kind == "dot" then
        local v = but[3] or "."
        if s.editing then
            if s.display == "0" and v ~= "." then s.display = v
            elseif v == "." and s.display:find("%.") then -- duplicate dot
            else s.display = s.display .. v end
        else
            s.display = v
            s.editing = true
        end
        s.status = ""
    elseif kind == "clr" then
        s.display = "0"; s.pending = nil; s.op = nil; s.accum = nil
        s.editing = true; s.status = ""
    elseif kind == "neg" then
        if s.display:sub(1,1) == "-" then s.display = s.display:sub(2)
        elseif s.display ~= "0" then s.display = "-" .. s.display end
    elseif kind == "pct" then
        local v = tonumber(s.display) or 0
        s.display = tostring(v / 100)
    elseif kind == "op" then
        local v = tonumber(s.display) or 0
        if s.accum and s.op then
            s.accum = apply(s, s.op, s.accum, v)
            s.display = tostring(s.accum)
        else
            s.accum = v
        end
        s.op = but[3]
        s.editing = false
    elseif kind == "eq" then
        if s.accum and s.op then
            local v = tonumber(s.display) or 0
            local r = apply(s, s.op, s.accum, v)
            s.display = tostring(r)
            s.accum = nil; s.op = nil; s.editing = false
        end
    end
end

local function drawDisplay(win, state)
    local pad = dim("padding")
    local displayY = win.y + dim("titlebarH") + pad
    local displayH = 56
    gfx.fillRoundRect(win.x + pad, displayY, win.w - 2*pad, displayH, 6,
        theme.c("surface"))
    gfx.outlineRect(win.x + pad, displayY, win.w - 2*pad, displayH, theme.c("border"))
    local txt = state.display
    local opts = {size = 32, style = "bold"}
    -- Trim to fit
    while #txt > 0 and gfx.textSize(txt, opts) > (win.w - 2*pad - 12) do
        txt = txt:sub(1, -2)
    end
    local tw = gfx.textSize(txt, opts)
    gfx.text(txt, win.x + win.w - pad - 6 - tw, displayY + (displayH - opts.size)/2,
        theme.c("textPrimary"), opts)
    -- status line
    if state.status and #state.status > 0 then
        local sOpts = {size = dim("fontSizeSmall"), style = "plain"}
        gfx.text(state.status, win.x + pad + 6, displayY + displayH - sOpts.size - 4,
            theme.c("danger"), sOpts)
    end
end

local function drawKeypad(win, state)
    local pad = dim("padding")
    local layoutY = win.y + dim("titlebarH") + 56 + pad*2 + 4
    local cellH = 48
    local availW = win.w - 2*pad
    local cellW = math.floor(availW / 4) - 3
    for r, row in ipairs(layout) do
        local col = 1
        for _, but in ipairs(row) do
            local wspan = but.wspan or 1
            local bx = win.x + pad + (col-1)*(cellW + 3)
            local by = layoutY + (r-1)*(cellH + 4)
            local bw = wspan * (cellW + 3) - 3
            -- color decision
            local bg = theme.c("surfaceHigh")
            local fg = theme.c("textPrimary")
            if but[2] == "op" then bg = theme.c("accent"); fg = theme.c("textPrimary")
            elseif but[2] == "eq" then bg = theme.c("btnMaximize"); fg = theme.c("textPrimary")
            elseif but[2] == "clr" then bg = theme.c("btnClose"); fg = theme.c("textPrimary")
            end
            local isHot = state.hover and state.hover.r == r and state.hover.c == col
            if isHot then bg = theme.scaleColor(bg, 0.85) end
            gfx.fillRoundRect(bx, by, bw, cellH, 6, bg)
            gfx.outlineRect(bx, by, bw, cellH, theme.c("border"))
            local opts = {size = dim("fontSizeTitle"), style = "bold"}
            local lbl = but[1]
            local tw = gfx.textSize(lbl, opts)
            gfx.text(lbl, bx + (bw - tw)/2, by + (cellH - opts.size)/2,
                fg, opts)
            col = col + wspan
        end
    end
end

function M.paint(win, cx, cy, cw, ch)
    local s = state(win)
    drawDisplay(win, s)
    drawKeypad(win, s)
end

function M.onEvent(win, ev, lx, ly)
    local s = state(win)
    local pad = dim("padding")
    local layoutY = win.y + dim("titlebarH") + 56 + pad*2 + 4
    local cellH = 48
    local cellW = math.floor((win.w - 2*pad) / 4) - 3
    if ev.type == "mouse_move" or ev.type == "mouse_drag" then
        local ax, ay = lx + win.x + 0, ly + win.y + dim("titlebarH")
        s.hover = nil
        if ay >= layoutY and ay <= layoutY + #layout*(cellH + 4) then
            local row = math.floor((ay - layoutY) / (cellH + 4)) + 1
            for r, lrow in ipairs(layout) do
                if r == row then
                    local xOff = 0
                    for _, b in ipairs(lrow) do
                        local bx = win.x + pad + xOff
                        local bw = (b.wspan or 1) * (cellW + 3) - 3
                        if ax >= bx and ax <= bx + bw then
                            s.hover = {r=r, c=1, btn=b}
                            break
                        end
                        xOff = xOff + (b.wspan or 1) * (cellW + 3)
                    end
                end
            end
        end
    end
    if ev.type == "mouse_down" then
        if s.hover and s.hover.btn then
            sound.beep()
            press(win, s.hover.btn, s)
        end
    end
end

return M
