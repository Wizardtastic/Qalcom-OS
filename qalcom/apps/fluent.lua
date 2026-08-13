local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Canvas = dofile("/qalcom/lib/ui/canvas.lua")
local PixelPalette = dofile("/qalcom/lib/ui/pixel_palette.lua")
local PixelFont = dofile("/qalcom/lib/ui/pixelfont.lua")

return function(ctx)
    local S = PixelPalette.slots
    local plan = PixelPalette.plan()
    local rect = Canvas.rect

    local function restoreText()
        -- Leave graphics mode and put the Fluent text palette back (mode 2 may
        -- have reset slots 0-15), then let the kernel repaint the desktop.
        Canvas.exit()
        local okConfig, Config = pcall(dofile, "/qalcom/lib/config.lua")
        local okPalette, Palette = pcall(dofile, "/qalcom/lib/ui/palette.lua")
        if okConfig and okPalette then
            local cfg = Config.load()
            local theme = Config.themes[cfg.theme]
            if theme and theme.palette then Palette.apply(theme.palette) else Palette.resetDefaults() end
        end
    end

    -- Restore text mode even if this app crashes while holding the screen.
    ctx:registerCleanup(restoreText)

    -- A plain text screen drawn to this app's own window. Because it is drawn to
    -- ctx.win (not the graphics plane), the window is never blank -- if graphics
    -- mode fails to engage, this message stays visible with an explanation.
    local function renderInfo(lines)
        local width, height = ctx.win.getSize()
        local shell = Screen.app(ctx.win, "Fluent Desktop", {
            ui = UI,
            status = "256-color Windows 11 preview",
            statusColor = UI.colors.accent,
        })
        local start = shell.body.y
        local y = start + 2
        for _, line in ipairs(lines) do
            if y < height then
                UI.text(ctx.win, 2, y, line, UI.colors.text, UI.colors.surface, width - 3)
                y = y + 1
            end
        end
        UI.text(ctx.win, 2, height, "Esc close", UI.colors.textSubtle or UI.colors.muted, UI.colors.surface, width - 3)
    end

    local function runInfo(lines)
        renderInfo(lines)
        while true do
            local event, value = ctx:pullEvent()
            if event == "key" and value == keys.escape then ctx:close(); return
            elseif event == "term_resize" or event == "qalcom_tick" then renderInfo(lines) end
        end
    end

    local function drawCard(cx, cy, cw, ch, title, tile)
        Canvas.shadow(cx, cy, cw, ch, 6, plan.shadow)
        Canvas.roundedRect(cx, cy, cw, ch, S.card, 6)
        PixelFont.draw(rect, cx + 7, cy + 7, title, S.text, 1, 1)
        Canvas.rect(cx + 7, cy + 18, cw - 14, 1, S.accent)
        Canvas.roundedRect(cx + 7, cy + 24, 20, 20, tile, 4)
        for i = 0, 2 do Canvas.rect(cx + 34, cy + 26 + i * 7, math.max(1, cw - 46), 3, S.cardBorder) end
    end

    local function render()
        local W, H = Canvas.size()
        if not W then return end
        Canvas.freeze()
        Canvas.gradientV(0, 0, W, H, plan.wallpaper)

        local time = os.date("%H:%M")
        local clockScale = math.max(2, math.floor(W / 60))
        local clockW = PixelFont.width(time, clockScale, clockScale)
        local clockX = math.max(0, math.floor((W - clockW) / 2))
        local clockY = math.max(4, math.floor(H * 0.16))
        PixelFont.draw(rect, clockX, clockY, time, S.text, clockScale, clockScale)

        local markScale = math.max(1, math.floor(clockScale / 2))
        local mark = "QALCOM OS"
        local markW = PixelFont.width(mark, markScale, markScale)
        PixelFont.draw(rect, math.floor((W - markW) / 2), math.max(2, clockY - PixelFont.cellH * markScale - 6), mark, S.accent, markScale, markScale)

        local date = os.date("%m / %d")
        local dateScale = markScale
        local dateW = PixelFont.width(date, dateScale, dateScale)
        PixelFont.draw(rect, math.floor((W - dateW) / 2), clockY + PixelFont.cellH * clockScale + 6, date, S.textMuted, dateScale, dateScale)

        local cardW = math.max(60, math.floor(W * 0.30))
        local cardH = math.max(40, math.floor(H * 0.30))
        local cardsY = math.floor(H * 0.50)
        local gap = math.floor(W * 0.06)
        local totalW = cardW * 2 + gap
        local firstX = math.floor((W - totalW) / 2)
        drawCard(firstX, cardsY, cardW, cardH, "TERMINAL", plan.tiles[2])
        drawCard(firstX + cardW + gap, cardsY, cardW, cardH, "CONTROL", plan.tiles[4])

        local barH = math.max(16, math.floor(H * 0.12))
        local barY = H - barH
        Canvas.rect(0, barY, W, barH, S.acrylicLight)
        Canvas.rect(0, barY, W, 1, S.acrylic)
        local tileSize = barH - 8
        local tgap = math.max(3, math.floor(tileSize / 4))
        local count = #plan.tiles
        local clusterW = (count + 1) * (tileSize + tgap) - tgap
        local tx = math.max(2, math.floor((W - clusterW) / 2))
        local ty = barY + math.floor((barH - tileSize) / 2)
        Canvas.roundedRect(tx, ty, tileSize, tileSize, S.startPill, 4)
        PixelFont.draw(rect, tx + math.floor((tileSize - PixelFont.cellW) / 2), ty + math.floor((tileSize - PixelFont.cellH) / 2), "Q", S.acrylic, 1, 1)
        tx = tx + tileSize + tgap
        for i = 1, count do
            Canvas.roundedRect(tx, ty, tileSize, tileSize, plan.tiles[i], 4)
            tx = tx + tileSize + tgap
        end
        local trayText = os.date("%H:%M")
        PixelFont.draw(rect, W - PixelFont.width(trayText, 1, 1) - 6, barY + math.floor((barH - PixelFont.cellH) / 2), trayText, S.text, 1, 1)

        local hint = "PRESS ANY KEY TO RETURN"
        PixelFont.draw(rect, math.floor((W - PixelFont.width(hint, 1, 1)) / 2), barY - 12, hint, S.textMuted, 1, 1)

        Canvas.unfreeze()
    end

    -- No graphics mod: explain and stay in text mode.
    if not Canvas.available() then
        runInfo({
            "This preview needs the CC:Graphics mod",
            "(or CraftOS-PC) for 256-color graphics.",
            "",
            "The everyday desktop already uses the",
            "Windows 11 dark theme in text mode.",
        })
        return
    end

    -- Draw a notice first so the window is never blank if the mode switch fails.
    renderInfo({ "Starting the 256-color preview..." })
    if not Canvas.enter() then
        runInfo({
            "Graphics mode 2 did not engage here.",
            "It needs an Advanced (color) computer",
            "with CC:Graphics (or CraftOS-PC).",
            "",
            "The desktop stays in text-mode Fluent.",
        })
        return
    end
    local W = Canvas.size()
    if not W or W < 12 then
        restoreText()
        runInfo({ "Could not read the graphics screen size.", "This host may not support graphics mode 2." })
        return
    end

    PixelPalette.apply(plan)
    if not PixelPalette.verified(plan) then
        -- The host accepted graphics mode but did not store the extended palette
        -- (some graphics APIs ignore writes above slot 15, and the mod's
        -- grayscale mode on non-colour terminals rewrites them). The scene
        -- would render flat gray or black, so leave graphics mode and explain.
        restoreText()
        runInfo({
            "This host did not keep the 256-color",
            "palette, so the preview would look",
            "flat gray or black. It needs an",
            "Advanced (color) computer with CC:",
            "Graphics (or CraftOS-PC).",
            "",
            "The desktop stays in text-mode Fluent.",
        })
        return
    end
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" or event == "mouse_click" or event == "char" then
            restoreText()
            ctx:redraw()
            ctx:close()
            return
        elseif event == "qalcom_tick" or event == "timer" or event == "term_resize" then
            render()
        end
    end
end
