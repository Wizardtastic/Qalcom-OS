-- os/login.lua — login screen.
-- Renders a centered card on the animated desktop wallpaper before
-- handing control off to session.lua.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local input  = require("os.input")
local sound  = require("os.sound")
local auth   = require("os.auth")
local cfg    = require("os.config")

local M = {}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- Centered login card
local function cardGeom()
    local W, H = gfx.width(), gfx.height()
    -- Card must fit comfortably within the pixel canvas (306×171 on
    -- an advanced computer in mode 2).  Scale relative to the screen
    -- so the layout adapts if the terminal is resized or a monitor is
    -- used.
    local cardW = math.floor(W * 0.75 + 0.5)
    local cardH = math.floor(H * 0.80 + 0.5)
    return {
        x = math.floor((W - cardW)/2 + 0.5),
        y = math.floor((H - cardH)/2 + 0.5),
        w = cardW, h = cardH,
        W = W, H = H,
    }
end

local function drawCard(g, state)
    -- Soft drop shadow behind card.
    if gfx.isDirectGPU() then
        for i = 0, 5 do
            local a = 0.45 * (1 - i/5)
            local c = {0, 0, 0}
            gfx.fillRect(g.x + i, g.y + g.h + i, g.w, 1, c[1], c[2], c[3])
            gfx.fillRect(g.x + g.w + i, g.y + i, 1, g.h + i, c[1], c[2], c[3])
        end
    end

    -- Card body
    gfx.fillRoundRect(g.x, g.y, g.w, g.h, 8, theme.c("surfaceAlt"))
    gfx.outlineRect(g.x, g.y, g.w, g.h, theme.c("borderBright"))

    -- Logo lock-up (proportional to card height)
    local logoY = g.y + math.floor(g.h * 0.06)
    local logoSize = math.max(24, math.floor(g.h * 0.35))
    local logoGlyph = "Q"
    local logoOpts = {size = logoSize, style = "bold"}
    local lw = gfx.textSize(logoGlyph, logoOpts)
    gfx.text(logoGlyph, g.x + (g.w - lw)/2, logoY, theme.c("accent"), logoOpts)

    local titleSize = math.max(10, math.floor(g.h * 0.11))
    gfx.text("Qalcom OS", g.x, logoY + logoSize + 4,
        theme.c("textPrimary"),
        {size = titleSize, style = "bold"})

    local subTxt = "Sign in to continue"
    local subSize = math.max(8, math.floor(g.h * 0.07))
    local sW = gfx.textSize(subTxt, {size = subSize, style = "plain"})
    gfx.text(subTxt, g.x + (g.w - sW)/2, logoY + logoSize + titleSize + 10,
        theme.c("textSecondary"),
        {size = subSize, style = "plain"})

    -- User chip (proportional)
    local chipW = math.floor(g.w * 0.60)
    local chipH = math.max(20, math.floor(g.h * 0.14))
    local chipX = g.x + (g.w - chipW)/2
    local chipY = g.y + math.floor(g.h * 0.52)
    gfx.fillRoundRect(chipX, chipY, chipW, chipH, 5, theme.c("surface"))
    gfx.outlineRect(chipX, chipY, chipW, chipH, theme.c("border"))
    local label = state.user or ""
    local chipFontSize = math.max(8, math.floor(g.h * 0.09))
    local lOpts = {size = chipFontSize, style = "plain"}
    local lw2 = gfx.textSize(label, lOpts)
    gfx.text(label, chipX + (chipW - lw2)/2, chipY + (chipH - lOpts.size)/2,
        theme.c("textPrimary"), lOpts)

    -- Password input (proportional)
    local passW = math.floor(g.w * 0.78)
    local passH = math.max(18, math.floor(g.h * 0.13))
    local passX = g.x + (g.w - passW)/2
    local passY = chipY + chipH + math.floor(g.h * 0.06)
    gfx.fillRoundRect(passX, passY, passW, passH, 5, theme.c("surface"))
    gfx.outlineRect(passX, passY, passW, passH, theme.c("border"))

    -- mask input
    local masked = string.rep("●", #(state.pwd or ""))
    if state.cursorVisible then
        masked = masked .. "▏"
    end
    local passFontSize = math.max(8, math.floor(g.h * 0.07))
    local maskOpts = {size = passFontSize, style = "plain"}
    gfx.text(masked, passX + 8, passY + (passH - maskOpts.size)/2,
        theme.c("textPrimary"), maskOpts)
    local ph = "Password"
    if #(state.pwd or "") == 0 then
        local pw = gfx.textSize(ph, maskOpts)
        gfx.text(ph, passX + 8, passY + (passH - maskOpts.size)/2,
            theme.c("textMuted"), maskOpts)
    end

    -- Error message
    if state.error then
        local errSize = math.max(7, math.floor(g.h * 0.06))
        local opts = {size = errSize, style = "plain"}
        local ew = gfx.textSize(state.error, opts)
        gfx.text(state.error, g.x + (g.w - ew)/2, passY + passH + 4,
            theme.c("danger"), opts)
    end

    -- Sign-in button (proportional, near bottom)
    local btnW = math.floor(g.w * 0.55)
    local btnH = math.max(18, math.floor(g.h * 0.14))
    local btnX = g.x + (g.w - btnW)/2
    local btnY = g.y + g.h - btnH - math.floor(g.h * 0.08)
    local hot = state.hotSubmit
    gfx.fillRoundRect(btnX, btnY, btnW, btnH, 5,
        hot and theme.c("accentPressed") or theme.c("accent"))
    gfx.outlineRect(btnX, btnY, btnW, btnH, theme.c("borderBright"))
    local bTxt = "Sign in"
    local btnFontSize = math.max(8, math.floor(g.h * 0.09))
    local bopts = {size = btnFontSize, style = "bold"}
    local bw = gfx.textSize(bTxt, bopts)
    gfx.text(bTxt, btnX + (btnW - bw)/2, btnY + (btnH - bopts.size)/2,
        theme.c("textPrimary"), bopts)
end

-- ---------------------------------------------------------------------------
local wallpaperY = 0
local function drawWallpaper()
    local W, H = gfx.width(), gfx.height()
    local top = cfg.appearance.wallpaper.top
    local bottom = cfg.appearance.wallpaper.bottom
    gfx.gradient(0, 0, W, H, top, bottom, "v")
    -- soft moving glow circles
    local t = (os.epoch and os.epoch("utc") or 0) / 3000
    for i = 1, 5 do
        local cx = math.floor(math.sin(t + i) * (W*0.6) + W/2)
        local cy = math.floor(math.cos(t*1.3 + i*1.7) * (H*0.6) + H/2)
        local r = 80 + i * 30
        gfx.circle(cx, cy, r,
            (i % 2 == 0) and {60, 90, 180, 90} or {80, 90, 180, 80},
            false)
    end
end

-- Returns true once user successfully authenticates; mutates state.
local function trySubmit(state)
    if auth.verify(state.user or "", state.pwd or "") then
        return true
    end
    state.attempts = (state.attempts or 0) + 1
    state.error = string.format("Invalid password.  Attempt %d of %d.",
        state.attempts, cfg.security.lockoutAttempts)
    if state.attempts >= cfg.security.lockoutAttempts then
        state.error = "Too many failed attempts. Wait a moment."
    end
    sound.error()
    state.pwd = ""
    return false
end

function M.run()
    local state = {
        user = cfg.security.defaultUser or "admin",
        pwd  = "",
        cursorVisible = true,
        attempts = 0,
        hotSubmit = false,
    }
    -- First-time convenience: if the user's stored password equals the
    -- username (the default we seed on bootstrap) we'll auto-submit.
    local autoSubmit = auth.verify(state.user, state.user)

    -- Main login loop
    local lastCursorToggle = os.epoch and os.epoch("utc") or 0
    while true do
        drawWallpaper()
        drawCard(cardGeom(), state)

        gfx.endFrame()

        -- Blinking cursor
        local now = os.epoch and os.epoch("utc") or 0
        if now - lastCursorToggle >= theme.timing.cursorBlinkMs then
            state.cursorVisible = not state.cursorVisible
            lastCursorToggle = now
        end

        if autoSubmit then
            autoSubmit = false
            state.pwd = state.user
            if trySubmit(state) then
                return { name = state.user, role = auth.users[state.user].role or "user" }
            end
        end

        local ev = input.poll(0.5)
        if ev then
            if ev.type == "char" then
                if ev.ch == "\b" then
                    if state.pwd and #state.pwd > 0 then
                        state.pwd = state.pwd:sub(1, -2)
                    end
                elseif ev.ch and ev.ch ~= "\n" and ev.ch ~= "\r" then
                    state.pwd = (state.pwd or "") .. ev.ch
                end
            elseif ev.type == "key" then
                if ev.key == keys.enter or ev.key == keys.numPadEnter then
                    if trySubmit(state) then
                        return { name = state.user, role = auth.users[state.user].role or "user" }
                    end
                elseif ev.key == keys.escape then
                    state.pwd = ""
                    state.error = nil
                elseif ev.key == keys.tab then
                    -- cycle users if more than 1
                    local names = auth.list()
                    if #names > 1 then
                        local i = 1
                        for j, n in ipairs(names) do
                            if n == state.user then i = j end
                        end
                        state.user = names[(i % #names) + 1]
                    end
                end
            end
        end
    end
end

return M
