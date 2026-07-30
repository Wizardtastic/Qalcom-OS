-- os/boot.lua — first splash screen after hardware init.
-- Shows Qalcom brand, then runs through startup steps.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local sound  = require("os.sound")
local auth   = require("os.auth")
local cfg    = require("os.config")

local M = {}

local steps = {
    {name = "Initialising graphics",      fn = function() return gfx._stats() end},
    {name = "Creating system directories", fn = function()
        cfg.ensureDirs()
        return true
    end},
    {name = "Bringing up audio subsystem", fn = function() return true end},
    {name = "Loading user accounts",       fn = function() auth.bootstrap(); return true end},
    {name = "Starting login manager",      fn = function() return true end},
}

function M.show()
    -- Background gradient
    local W, H = gfx.width(), gfx.height()
    gfx.gradient(0, 0, W, H, theme.c("blueDeep"), theme.c("surface"), "v")

    -- Big logo
    local logo = "Q"
    local opts  = {size = 120, style = "bold"}
    local lw = gfx.textSize(logo, opts)
    local cx = (W - lw)/2
    local cy = H * 0.30
    gfx.text(logo, cx, cy, theme.c("accent"), opts)

    -- Title
    local titleOpts = {size = theme.dimScaled("fontSizeHero") * 1.4, style = "bold"}
    local tw = gfx.textSize("Qalcom OS", titleOpts)
    gfx.text("Qalcom OS", (W - tw)/2, cy + 120, theme.c("textPrimary"), titleOpts)
    local tagOpts = {size = theme.dimScaled("fontSizeBody"), style = "plain"}
    local tagW = gfx.textSize("Loading…", tagOpts)
    gfx.text("Loading…", (W - tagW)/2, cy + 180, theme.c("textSecondary"), tagOpts)

    gfx.endFrame()
    sound.chime()

    -- Run through steps with a brief visual indicator.
    for _, step in ipairs(steps) do
        local sy = cy + 230
        local opts2 = {size = theme.dimScaled("fontSizeSmall"), style = "plain"}
        local s = step.name
        local sw = gfx.textSize(s, opts2)
        gfx.text("• " .. s, (W - sw)/2, sy, theme.c("textSecondary"), opts2)
        local ok, info = pcall(step.fn)
        if not ok then
            local opts3 = {size = theme.dimScaled("fontSizeSmall"), style = "bold"}
            local errW = gfx.textSize("Error: " .. tostring(info), opts3)
            gfx.text("Error: " .. tostring(info),
                (W - errW)/2, sy + 20, theme.c("danger"), opts3)
        end
        sleep(0.25)
        gfx.endFrame()
    end

    -- Done splash
    gfx.fillRect(0, 0, W, H, theme.c("surface"))
    gfx.text("Q", cx, cy, theme.c("accent"), opts)
    local doneOpts = {size = theme.dimScaled("fontSizeTitle"), style = "bold"}
    local dw = gfx.textSize("Welcome to Qalcom OS", doneOpts)
    gfx.text("Welcome to Qalcom OS", (W - dw)/2, cy + 200,
        theme.c("textPrimary"), doneOpts)
    gfx.endFrame()
    sleep(0.4)
end

return M
