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

    -- Big logo (proportional to screen)
    local logo = "Q"
    local logoSize = math.floor(H * 0.20)
    local opts  = {size = logoSize, style = "bold"}
    local lw = gfx.textSize(logo, opts)
    local cx = (W - lw)/2
    local cy = math.floor(H * 0.15)
    gfx.text(logo, cx, cy, theme.c("accent"), opts)

    -- Title
    local titleSize = math.floor(H * 0.12)
    local titleOpts = {size = titleSize, style = "bold"}
    local tw = gfx.textSize("Qalcom OS", titleOpts)
    gfx.text("Qalcom OS", (W - tw)/2, cy + logoSize + 6, theme.c("textPrimary"), titleOpts)
    local tagSize = math.floor(H * 0.07)
    local tagOpts = {size = tagSize, style = "plain"}
    local tagW = gfx.textSize("Loading…", tagOpts)
    gfx.text("Loading…", (W - tagW)/2, cy + logoSize + titleSize + 14, theme.c("textSecondary"), tagOpts)

    gfx.endFrame()
    sound.chime()

    -- Run through steps with a brief visual indicator.
    for _, step in ipairs(steps) do
        local sy = cy + logoSize + titleSize + tagSize + 28
        local stepSize = math.max(7, math.floor(H * 0.05))
        local opts2 = {size = stepSize, style = "plain"}
        local s = step.name
        local sw = gfx.textSize(s, opts2)
        gfx.text("• " .. s, (W - sw)/2, sy, theme.c("textSecondary"), opts2)
        local ok, info = pcall(step.fn)
        if not ok then
            local opts3 = {size = stepSize, style = "bold"}
            local errW = gfx.textSize("Error: " .. tostring(info), opts3)
            gfx.text("Error: " .. tostring(info),
                (W - errW)/2, sy + stepSize + 4, theme.c("danger"), opts3)
        end
        sleep(0.25)
        gfx.endFrame()
    end

    -- Done splash
    gfx.fillRect(0, 0, W, H, theme.c("surface"))
    gfx.text("Q", cx, cy, theme.c("accent"), opts)
    local doneSize = math.floor(H * 0.10)
    local doneOpts = {size = doneSize, style = "bold"}
    local dw = gfx.textSize("Welcome to Qalcom OS", doneOpts)
    gfx.text("Welcome to Qalcom OS", (W - dw)/2, cy + logoSize + 10,
        theme.c("textPrimary"), doneOpts)
    gfx.endFrame()
    sleep(0.4)
end

return M
