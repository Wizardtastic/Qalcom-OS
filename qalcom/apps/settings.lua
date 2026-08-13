local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Config = dofile("/qalcom/lib/config.lua")
local VERSION = dofile("/qalcom/version.lua")
local Roles = dofile("/qalcom/lib/roles.lua")

return function(ctx)
    local selected = 1
    local editingLabel = false
    local labelInput = ""
    local themes = { "win11dark", "win11light", "blue", "dark", "green" }
    local wallpapers = Config.wallpapers or { "solid", "dots" }
    local function wallpaperLabel(style)
        return (tostring(style or "solid"):gsub("^%l", string.upper))
    end
    local categories = { "Personalization", "Account", "Display", "Startup", "Security", "Storage", "Peripherals", "Network", "Recovery" }
    local rowOrder = { 1, 2, 12, 3, 4, 5, 6, 7, 8, 9, 11 }
    local compactRows = { 2, 12, 7, 8, 9, 11 }
    local compactOffset = 1
    local config = Config.load()
    Config.apply(UI, config)

    local function availableRows(height)
        -- Keep the compact view focused on editable settings and recovery.
        if height <= 10 then
            local visibleCount = math.max(1, math.min(4, height - 2))
            local maxOffset = math.max(1, #compactRows - visibleCount + 1)
            compactOffset = math.max(1, math.min(compactOffset, maxOffset))
            local rows = {}
            for index = 1, visibleCount do rows[index] = compactRows[compactOffset + index - 1] end
            return rows
        end
        local count = math.min(#rowOrder, math.max(1, height - 2))
        local rows = {}
        for index = 1, count do rows[index] = rowOrder[index] end
        return rows
    end

    local function saveLabel()
        local ok, reason
        if labelInput ~= "" then
            ok, reason = ctx:setComputerLabel(labelInput)
        else
            ok, reason = ctx:setComputerLabel(nil)
        end
        if ok then
            ctx:notify(labelInput ~= "" and "Computer label updated" or "Computer label cleared", labelInput ~= "" and UI.colors.success or UI.colors.warning)
            editingLabel = false
        else
            ctx:notify(reason or "Computer label change denied", UI.colors.danger)
        end
    end

    local function render()
        local width, height = ctx.win.getSize()
        local visibleRows = availableRows(height)
        selected = math.min(selected, #visibleRows)
        local compact = height < 10
        local shell = Screen.app(ctx.win, "Qalcom Settings", { ui = UI })
        local contentStart = shell.body.y

        local rows = {
            { "Computer label", os.getComputerLabel() or "(none)" },
            { "Desktop theme", Config.themes[config.theme].name },
            { "Computer ID", tostring(os.getComputerID()) },
            { "OS version", "Qalcom OS " .. VERSION },
            { "Boot mode", "Normal" },
            { "Security", "Role: " .. tostring((Roles.definition(ctx.role) or {}).label or "Unknown") },
            { "Safe Mode", config.safeMode and "Enabled" or "Disabled" },
            { "Log retention", tostring(config.logLimit) .. " lines" },
            { "Reduced motion", config.reducedMotion and "Enabled" or "Disabled" },
            { "Categories", table.concat(categories, ", ") },
            { "Restore defaults", "Win11 Dark / Safe Mode off / 200 lines" },
            [12] = { "Wallpaper", wallpaperLabel(config.wallpaper) },
        }
        for displayIndex, actualIndex in ipairs(visibleRows) do
            local item = rows[actualIndex]
            local y = contentStart + displayIndex - 1
            local active = selected == displayIndex
            local rowBackground = active and UI.colors.surfaceSelected or UI.colors.surface
            -- Safe Mode (7) and Reduced motion (9) render as Fluent switches.
            if actualIndex == 7 or actualIndex == 9 then
                local on = actualIndex == 7 and config.safeMode or config.reducedMotion
                UI.toggle(ctx.win, 2, y, width - 3, item[1], on == true, {
                    background = rowBackground,
                    foreground = active and UI.colors.text or UI.colors.text,
                })
            else
                local value = item[2]
                if editingLabel and actualIndex == 1 then value = labelInput .. "_" end
                UI.listRow(ctx.win, 2, y, width - 3, item[1], value, active, {
                    split = math.floor(width * 0.55),
                    activeBackground = UI.colors.surfaceSelected,
                    activeForeground = UI.colors.text,
                    valueColor = active and UI.colors.text or UI.colors.textMuted,
                    foreground = active and UI.colors.text or UI.colors.text,
                    background = UI.colors.surface,
                })
            end
        end

    end

    local function chooseTheme(direction)
        local index = 1
        for i, name in ipairs(themes) do if name == config.theme then index = i end end
        index = ((index - 1 + direction) % #themes) + 1
        config.theme = themes[index]
        config.colors = Config.themes[config.theme]
        Config.setTheme(config.theme)
        Config.apply(UI, config)
        ctx:notify("Theme: " .. config.colors.name, UI.colors.accent)
    end

    local function chooseWallpaper(direction)
        local index = 1
        for i, style in ipairs(wallpapers) do if style == config.wallpaper then index = i end end
        index = ((index - 1 + direction) % #wallpapers) + 1
        config.wallpaper = wallpapers[index]
        Config.setWallpaper(config.wallpaper)
        ctx:notify("Wallpaper: " .. wallpaperLabel(config.wallpaper), UI.colors.accent)
    end

    local function applySelected(actualIndex)
        if actualIndex == 1 then
            labelInput = os.getComputerLabel() or ""
            editingLabel = true
        elseif actualIndex == 2 then
            chooseTheme(1)
        elseif actualIndex == 12 then
            chooseWallpaper(1)
        elseif actualIndex == 7 then
            Config.setSafeMode(not config.safeMode)
            config = Config.load()
            ctx:notify(config.safeMode and "Safe Mode enabled" or "Safe Mode disabled", UI.colors.warning)
        elseif actualIndex == 8 then
            Config.setLogLimit(config.logLimit >= 1000 and 50 or config.logLimit + 50)
            config = Config.load()
            ctx:notify("Log retention: " .. tostring(config.logLimit), UI.colors.accent)
        elseif actualIndex == 9 then
            Config.setReducedMotion(not config.reducedMotion)
            config = Config.load()
            ctx:notify(config.reducedMotion and "Reduced motion enabled" or "Animations enabled", UI.colors.accent)
        elseif actualIndex == 11 then
            Config.resetDefaults()
            config = Config.load()
            Config.apply(UI, config)
            ctx:notify("Qalcom defaults restored; accounts preserved", UI.colors.success)
        end
    end

    render()
    while true do
        local event, value, x, y = ctx:pullEvent()
        local visibleRows = availableRows(select(2, ctx.win.getSize()))
        if editingLabel then
            if event == "char" then
                if #labelInput < 24 then labelInput = labelInput .. value end
                render()
            elseif event == "paste" then
                labelInput = labelInput .. tostring(value):sub(1, 24 - #labelInput)
                render()
            elseif event == "key" then
                if value == keys.backspace then
                    labelInput = labelInput:sub(1, math.max(0, #labelInput - 1))
                    render()
                elseif value == keys.enter then
                    saveLabel()
                    render()
                elseif value == keys.escape then
                    editingLabel = false
                    render()
                end
            elseif event == "term_resize" or event == "qalcom_tick" then
                render()
            end
        elseif event == "key" then
            if value == keys.up then
                if selected > 1 then
                    selected = selected - 1
                elseif compactOffset > 1 then
                    compactOffset = compactOffset - 1
                end
                render()
            elseif value == keys.down then
                if selected < #visibleRows then
                    selected = selected + 1
                elseif select(2, ctx.win.getSize()) <= 10 and compactOffset < #compactRows - #visibleRows + 1 then
                    compactOffset = compactOffset + 1
                end
                render()
            elseif value == keys.enter then
                applySelected(visibleRows[selected])
                render()
            elseif value == keys.left and visibleRows[selected] == 12 then
                chooseWallpaper(-1)
                render()
            elseif value == keys.right and visibleRows[selected] == 12 then
                chooseWallpaper(1)
                render()
            elseif value == keys.left and visibleRows[selected] == 2 then
                chooseTheme(-1)
                render()
            elseif value == keys.right and visibleRows[selected] == 2 then
                chooseTheme(1)
                render()
            end
        elseif event == "mouse_click" then
            local displayIndex = y - 1
            if displayIndex >= 1 and displayIndex <= #visibleRows then
                selected = displayIndex
                applySelected(visibleRows[selected])
                render()
            end
        elseif event == "qalcom_config_changed" or event == "term_resize" or event == "qalcom_tick" then
            config = Config.load()
            Config.apply(UI, config)
            render()
        end
    end
end
