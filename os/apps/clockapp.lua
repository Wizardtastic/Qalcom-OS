-- os/apps/clockapp.lua — Clock.
-- Big digital time + centered analog clock dial with sweeping hands.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")

local M = {w = 360, h = 380, minW = 220, minH = 220, appId = "clockapp"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

function M.init(win) win.title = "Clock" end
function M.destroy() end

local function nowDate()
    local d = os.date("*t")
    return d
end

local function drawDigital(cx, cy, w, h, d)
    local opts = {size = 60, style = "bold"}
    local s = string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
    local tw = gfx.textSize(s, opts)
    gfx.text(s, cx + (w - tw)/2, cy + 8, theme.c("textPrimary"), opts)
    -- date
    local dateStr = os.date("%A, %B %d %Y")
    local dOpts = {size = dim("fontSizeTitle"), style = "plain"}
    local dw = gfx.textSize(dateStr, dOpts)
    gfx.text(dateStr, cx + (w - dw)/2, cy + 80, theme.c("textSecondary"), dOpts)
end

local function drawAnalog(cx, cy, w, h, d)
    local radius = math.min(w, h) / 2 - 20
    local midX, midY = cx + w/2, cy + h/2 + 40

    -- outer dial
    gfx.circle(midX, midY, radius, theme.c("border"), false)
    gfx.circle(midX, midY, radius - 4, theme.c("borderBright"), false)
    -- tick marks
    for i = 0, 59 do
        local ang = (i / 60) * 2 * math.pi
        local x1 = midX + math.cos(ang - math.pi/2) * (radius - 4)
        local y1 = midY + math.sin(ang - math.pi/2) * (radius - 4)
        local inner = (i % 5 == 0) and 12 or 4
        local x2 = midX + math.cos(ang - math.pi/2) * (radius - 4 - inner)
        local y2 = midY + math.sin(ang - math.pi/2) * (radius - 4 - inner)
        local col = (i % 5 == 0) and theme.c("textPrimary") or theme.c("textMuted")
        gfx.line(x1, y1, x2, y2, col)
    end

    -- numbers — 12, 3, 6, 9
    local nOpts = {size = dim("fontSizeBody"), style = "bold"}
    local labels = { {12, 0, -1}, {3, 1, 0}, {6, 0, 1}, {9, -1, 0} }
    for _, lab in ipairs(labels) do
        local n, dx, dy = lab[1], lab[2], lab[3]
        local nx = midX + dx * (radius - 22) - 4
        local ny = midY + dy * (radius - 22) - 6
        local ns = tostring(n)
        local nw = gfx.textSize(ns, nOpts)
        gfx.text(ns, nx + (16 - nw)/2, ny + (16 - nOpts.size)/2,
            theme.c("textPrimary"), nOpts)
    end

    -- hands
    local function hand(angleDeg, length, thick, color)
        local ang = (angleDeg - 90) * math.pi / 180
        local x = midX + math.cos(ang) * length
        local y = midY + math.sin(ang) * length
        gfx.line(midX, midY, x, y, color)
        -- a subtle thicker dot at the tip
        gfx.circle(x, y, thick, color, true)
    end
    local sec = d.sec + (d.hour == 0 and d.min == 0 and d.sec == 0 and 0 or 0)
    -- second hand
    hand(d.sec * 6, radius - 14, 2, theme.c("danger"))
    -- minute hand
    hand((d.min + d.sec/60) * 6, radius - 24, 3, theme.c("textPrimary"))
    -- hour hand (24-hour clock: each hour is 15 deg)
    local hourAng = ((d.hour % 12) + d.min/60) * 30
    hand(hourAng, radius - 50, 5, theme.c("accent"))
    -- center pivot
    gfx.circle(midX, midY, 6, theme.c("textPrimary"), true)
    gfx.circle(midX, midY, 3, theme.c("surface"), true)
end

function M.paint(win, cx, cy, cw, ch)
    local d = nowDate()
    local pad = dim("padding")
    -- digital panel
    local dg = {x=cx, y=cy, w=cw, h=120}
    gfx.fillRoundRect(dg.x, dg.y, dg.w, dg.h, 6, theme.c("surface"))
    gfx.outlineRect(dg.x, dg.y, dg.w, dg.h, theme.c("border"))
    drawDigital(dg.x, dg.y, dg.w, dg.h, d)

    -- analog panel
    local ag = {x=cx, y=cy + 140, w=cw, h=ch - 140 - pad}
    drawAnalog(ag.x, ag.y, ag.w, ag.h, d)
end

return M
