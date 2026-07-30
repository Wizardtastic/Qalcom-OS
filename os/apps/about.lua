-- os/apps/about.lua — About Qalcom OS.
-- Big logo + copyright + version + credits.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local cfg    = require("os.config")

local M = {w = 460, h = 360, minW = 280, minH = 220, appId = "about"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

function M.init(win) win.title = "About Qalcom OS" end
function M.destroy() end

function M.paint(win, cx, cy, cw, ch)
    local pad = dim("padding")

    -- hero card
    local hero = {x=cx+pad, y=cy+pad, w=cw-2*pad, h=120}
    gfx.fillRoundRect(hero.x, hero.y, hero.w, hero.h, 8, theme.c("surface"))
    gfx.outlineRect(hero.x, hero.y, hero.w, hero.h, theme.c("border"))

    -- logo
    local logo = "Q"
    local lOpts = {size = 80, style = "bold"}
    local lw = gfx.textSize(logo, lOpts)
    gfx.text(logo, hero.x + 16, hero.y + (hero.h - lOpts.size)/2,
        theme.c("accent"), lOpts)

    -- title
    local tOpts = {size = dim("fontSizeHero"), style = "bold"}
    gfx.text("Qalcom OS", hero.x + 110, hero.y + 18,
        theme.c("textPrimary"), tOpts)
    local subOpts = {size = dim("fontSizeBody"), style = "plain"}
    gfx.text("Version 0.1.0", hero.x + 110, hero.y + 50,
        theme.c("textSecondary"), subOpts)
    gfx.text("© Qalcom Foundation (fictional). Free MIT-licensed sample.",
        hero.x + 110, hero.y + 70, theme.c("textMuted"),
        {size = dim("fontSizeSmall"), style = "italic"})

    -- About body
    local body = {
        "Qalcom OS is a graphical operating system for ComputerCraft: Tweaked",
        "powered by the CC:DirectGPU mod for full RGB rendering at up to",
        "656×648 pixels (4× scaling).",
        "",
        "Inspired by LevelOS, Ursa OS, and the visual language of modern",
        "desktop operating systems (Windows 11 Fluent, macOS Aqua).",
        "",
        "Lua runtime.  All code MIT-licensed — modify freely.",
    }
    local opts = {size = dim("fontSizeBody"), style = "plain"}
    local by = cy + hero.h + pad*2
    for i, line in ipairs(body) do
        gfx.text(line, cx + pad, by + (i-1)*(opts.size + 4),
            theme.c("textSecondary"), opts)
    end

    -- Credits
    local crY = cy + ch - 90
    gfx.text("Credits", cx + pad, crY,
        theme.c("textPrimary"), {size = dim("fontSizeTitle"), style = "bold"})
    local credits = {
        "• ComputerCraft: Tweaked — the Lua computer framework.",
        "• CC:DirectGPU — RGB monitor rendering (TikTop101).",
        "• LevelOS / Ursa OS — design inspiration.",
    }
    for i, line in ipairs(credits) do
        gfx.text(line, cx + pad, crY + 22 + (i-1)*(opts.size + 2),
            theme.c("textSecondary"), opts)
    end
end

return M
