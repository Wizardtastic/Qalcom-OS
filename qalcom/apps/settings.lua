local UI = dofile("/qalcom/lib/ui.lua")
local Config = dofile("/qalcom/lib/config.lua")
local VERSION = dofile("/qalcom/version.lua")

return function(ctx)
    local selected = 1
    local editingLabel = false
    local labelInput = ""
    local themes = { "blue", "dark", "green" }
    local categories = { "Personalization", "Account", "Display", "Startup", "Security", "Storage", "Peripherals", "Network", "Recovery" }
    local rowOrder = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 11 }
    local compactRows = { 2, 7, 8, 9, 11 }
    local compactOffset = 1
    local config = Config.load()
    Config.apply(UI, config)

    local function availableRows(height)
        -- Keep the compact view focused on editable settings and recovery.
        if height <= 10 then
            local visibleCount = math.max(1, math.min(4, height - 4))
            local maxOffset = math.max(1, #compactRows - visibleCount + 1)
            compactOffset = math.max(1, math.min(compactOffset, maxOffset))
            local rows = {}
            for index = 1, visibleCount do rows[index] = compactRows[compactOffset + index - 1] end
            return rows
        end
        local count = math.min(#rowOrder, math.max(1, height - 6))
        local rows = {}
        for index = 1, count do rows[index] = rowOrder[index] end
        return rows
    end

    local function saveLabel()
        if labelInput ~= "" then
            os.setComputerLabel(labelInput)
            ctx:notify("Computer label updated", UI.colors.success)
        else
            os.setComputerLabel(nil)
            ctx:notify("Computer label cleared", UI.colors.warning)
        end
        editingLabel = false
    end

    local function render()
        local width, height = ctx.win.getSize()
        local visibleRows = availableRows(height)
        selected = math.min(selected, #visibleRows)
        local compact = height < 10
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        UI.fill(ctx.win, 1, 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, 1, "Qalcom settings", UI.colors.accent, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, 2, compact and "Compact settings" or "Personalize this computer", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.divider(ctx.win, 1, 3, width, UI.colors.border)

        local rows = {
            { "Computer label", os.getComputerLabel() or "(none)" },
            { "Desktop theme", Config.themes[config.theme].name },
            { "Computer ID", tostring(os.getComputerID()) },
            { "OS version", "Qalcom OS " .. VERSION },
            { "Boot mode", "Normal" },
            { "Security", "Local-only services" },
            { "Safe Mode", config.safeMode and "Enabled" or "Disabled" },
            { "Log retention", tostring(config.logLimit) .. " lines" },
            { "Reduced motion", config.reducedMotion and "Enabled" or "Disabled" },
            { "Categories", table.concat(categories, ", ") },
            { "Restore defaults", "Ocean / Safe Mode off / 200 lines" },
        }
        for displayIndex, actualIndex in ipairs(visibleRows) do
            local item = rows[actualIndex]
            local y = 4 + displayIndex
            local active = selected == displayIndex
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            UI.fill(ctx.win, 2, y, width - 3, 1, background)
            UI.text(ctx.win, 3, y, item[1], active and colors.white or UI.colors.muted, background, math.floor(width * 0.52))
            local value = item[2]
            if editingLabel and actualIndex == 1 then value = labelInput .. "_" end
            UI.text(ctx.win, math.floor(width * 0.55), y, value, foreground, background, width - math.floor(width * 0.55) - 1)
        end

        if compact then
            -- All compact rows remain visible; Escape closes because there is no footer row.
        else
            UI.fill(ctx.win, 2, height - 1, width - 3, 2, UI.colors.accentLight)
            if editingLabel then
                UI.text(ctx.win, 3, height - 1, "Type a label, then press Enter", colors.white, UI.colors.accentLight, width - 5)
                UI.text(ctx.win, 3, height, "Escape cancels", colors.white, UI.colors.accentLight, width - 5)
            else
                UI.text(ctx.win, 3, height - 1, "Up/Down select   Enter apply", colors.white, UI.colors.accentLight, width - 5)
                UI.text(ctx.win, 3, height, "Left/Right changes theme", colors.white, UI.colors.accentLight, width - 5)
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

    local function applySelected(actualIndex)
        if actualIndex == 1 then
            labelInput = os.getComputerLabel() or ""
            editingLabel = true
        elseif actualIndex == 2 then
            chooseTheme(1)
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
            elseif value == keys.left and visibleRows[selected] == 2 then
                chooseTheme(-1)
                render()
            elseif value == keys.right and visibleRows[selected] == 2 then
                chooseTheme(1)
                render()
            end
        elseif event == "mouse_click" then
            local displayIndex = y - 4
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
