-- os/apps/about.lua — About Qalcom OS.
-- Big logo + copyright + version + credits.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")

local M = {minW = 160, minH = 120, appId = "about"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

function M.init(win) win.title = "About Qalcom OS" end
function M.destroy() end

function M.paint(win, cx, cy, cw, ch)
    local pad = dim("padding")

    -- hero card (proportional to client area)
    local heroH = math.floor(ch * 0.45)
    local hero = {x=cx+pad, y=cy+pad, w=cw-2*pad, h=heroH}
    gfx.fillRoundRect(hero.x, hero.y, hero.w, hero.h, 6, theme.c("surface"))
    gfx.outlineRect(hero.x, hero.y, hero.w, hero.h, theme.c("border"))

    -- logo
    local logo = "Q"
    local logoSize = math.floor(hero.h * 0.50)
    local lOpts = {size = logoSize, style = "bold"}
    local lw = gfx.textSize(logo, lOpts)
    gfx.text(logo, hero.x + 8, hero.y + (hero.h - lOpts.size)/2,
        theme.c("accent"), lOpts)

    -- title
    local titleSize = math.floor(hero.h * 0.18)
    local tOpts = {size = titleSize, style = "bold"}
    gfx.text("Qalcom OS", hero.x + logoSize + 16, hero.y + 8,
        theme.c("textPrimary"), tOpts)
    local subSize = math.floor(hero.h * 0.12)
    local subOpts = {size = subSize, style = "plain"}
    gfx.text("Version 0.1.0", hero.x + logoSize + 16, hero.y + 8 + titleSize + 4,
        theme.c("textSecondary"), subOpts)
    local tinySize = math.max(7, math.floor(hero.h * 0.08))
    gfx.text("MIT-licensed open source.",
        hero.x + logoSize + 16, hero.y + 8 + titleSize + subSize + 10,
        theme.c("textMuted"), {size = tinySize, style = "plain"})

    -- About body
    local body = {
        "Qalcom OS is a graphical operating system",
        "for ComputerCraft: Tweaked powered by",
        "CC:Graphics for full RGB rendering.",
        "",
        "Inspired by LevelOS, Ursa OS, and modern",
        "desktop operating systems.",
    }
    local bodySize = math.max(7, math.floor(ch * 0.08))
    local opts = {size = bodySize, style = "plain"}
    local by = cy + heroH + pad*2
    for i, line in ipairs(body) do
        if by + (i-1)*(opts.size + 2) < cy + ch - 20 then
            gfx.text(line, cx + pad, by + (i-1)*(opts.size + 2),
                theme.c("textSecondary"), opts)
        end
    end
end

return M
