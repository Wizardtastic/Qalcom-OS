-- os/theme.lua — visual identity for Qalcom OS.
-- Centralized color palette + design tokens so apps stay visually consistent.
-- Inspired by the Windows 11 Fluent design + macOS Aqua + a hint of Custom OS.

local M = {}

-- ---------------------------------------------------------------------------
-- COLOR PALETTE (rgb triples, 0-255)
-- Table is keyed by semantic name. Apps should reference these by name.
-- ---------------------------------------------------------------------------
M.colors = {
    -- core
    black       = {  0,   0,   0},
    white       = {255, 255, 255},
    transparent = "transparent", -- sentinel; consumer must handle it

    -- accents (dark)
    blueDark    = { 32,  84, 168},
    blueDeep    = { 14,  34,  68},
    indigo      = { 60,  72, 168},
    teal        = { 28, 130, 140},
    greenDark   = { 40, 130,  60},
    redDark     = {170,  46,  46},
    amberDark   = {198, 132,  20},
    purpleDark  = {108,  60, 144},

    -- accents (light)
    blueLight   = { 70, 130, 230},
    cyanLight   = { 86, 200, 220},
    greenLight  = { 92, 196, 110},
    orangeLight = {238, 152,  68},
    pinkLight   = {228, 110, 168},
    purpleLight = {162, 110, 226},

    -- surfaces
    surface         = { 18,  22,  30}, -- desktop base
    surfaceAlt      = { 28,  34,  44}, -- raised card
    surfaceHigh     = { 42,  50,  62}, -- hovered / active
    panel           = { 36,  42,  54}, -- generic panel (taskbar base)
    titlebar        = { 24,  30,  44}, -- window titlebar dark
    titlebarActive  = { 36,  60, 130}, -- active titlebar blue
    titlebarFocus   = { 44,  78, 168},

    -- text
    textPrimary   = {232, 236, 244},
    textSecondary = {178, 188, 206},
    textMuted     = {120, 132, 152},
    textInverse   = { 16,  20,  28},

    -- semantic
    accent           = { 70, 130, 230}, -- primary accent
    accentHover      = {110, 160, 250},
    accentPressed    = { 46, 100, 200},
    selected         = { 56,  82, 152},
    danger           = {220,  62,  62},
    warning          = {230, 168,  56},
    ok               = { 92, 196, 110},

    -- window controls (Windows-style)
    btnClose    = {236,  84,  84},
    btnMaximize = { 50, 178, 100},
    btnMinimize = {230, 178,  46},

    -- borders / dividers
    border        = { 64,  72,  86},
    borderBright  = {108, 120, 140},
    divider       = { 52,  60,  74},
    shadow        = {  0,   0,   0}, -- alpha-blended via float in real apps
}

-- ---------------------------------------------------------------------------
-- DIMENSIONS (px). These can be scaled by config.scale.
-- 656px display = "1x". "0.85x" scales everything down a bit.
-- ---------------------------------------------------------------------------
M.dim = {
    -- Window chrome
    titlebarH       = 28,
    borderWidth     = 1,
    btnSize         = 16,
    btnGap          = 6,

    -- Taskbar
    taskbarH        = 32,
    startBtnW       = 64,
    clockW          = 140,
    pinnedItemSize  = 28,
    runningItemMinW = 110,

    -- Interaction
    padding         = 8,
    paddingTight    = 4,
    paddingLarge    = 16,

    -- Inputs
    inputH          = 32,
    inputRadius     = 6,
    buttonH         = 30,

    -- Typography
    fontSizeSmall    = 11,
    fontSizeBody     = 14,
    fontSizeTitle    = 18,
    fontSizeHero     = 28,
    fontSizeStatusBar = 14,
}

-- ---------------------------------------------------------------------------
-- TYPOGRAPHY
-- fontFamily, fontStyle, fontSize: sensible defaults.
-- Apps can override per call.
-- ---------------------------------------------------------------------------
M.font = {
    uiFamily  = "Arial",     -- universal; falls back to Monospace on others
    monoFamily = "Monospace",
    styleBold  = "bold",
    stylePlain = "plain",
    styleItalic = "italic",
}

-- ---------------------------------------------------------------------------
-- TIMING
-- ---------------------------------------------------------------------------
M.timing = {
    doubleClickMs = 350,
    dragThresholdPx = 4,
    cursorBlinkMs = 530,
    toastDefaultMs = 3500,
    bootAnimMs    = 1200,
}

-- ---------------------------------------------------------------------------
-- UTILITIES
-- ---------------------------------------------------------------------------
function M.c(name) return M.colors[name] end         -- shorthand color by name
function M.d(name) return M.dim[name] end            -- shorthand dim
function M.dimScaled(name, scale)
    scale = scale or 1
    return math.floor((M.dim[name] or 0) * scale + 0.5)
end
function M.scaleColor(c, k)
    -- multiply RGB by k (clamped). k<1 darkens, k>1 lightens (toward white).
    if c == "transparent" then return c end
    local r, g, b = c[1], c[2], c[3]
    local function adjust(v)
        if k >= 1 then
            return math.floor(v + (255 - v) * (k - 1) + 0.5)
        else
            return math.floor(v * k + 0.5)
        end
    end
    return {math.max(0, math.min(255, adjust(r))),
            math.max(0, math.min(255, adjust(g))),
            math.max(0, math.min(255, adjust(b)))}
end
function M.blend(c1, c2, t) -- linear interpolation, t in [0,1]
    if c1 == "transparent" then return c2 end
    if c2 == "transparent" then return c1 end
    local r = c1[1]*(1-t) + c2[1]*t
    local g = c1[2]*(1-t) + c2[2]*t
    local b = c1[3]*(1-t) + c2[3]*t
    return {math.floor(r+0.5), math.floor(g+0.5), math.floor(b+0.5)}
end
function M.toHex(c) -- "#RRGGBB"
    if c == "transparent" then return "#000000" end
    return string.format("#%02X%02X%02X", c[1], c[2], c[3])
end

return M
