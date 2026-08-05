local UI = dofile("/qalcom/lib/ui.lua")
local VERSION = dofile("/qalcom/version.lua")

return function(ctx)
    local function render()
        local width, height = ctx.win.getSize()
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()

        UI.fill(ctx.win, 1, 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, 1, "System overview", UI.colors.accent, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, 2, os.date("%H:%M:%S"), UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.divider(ctx.win, 1, 3, width, UI.colors.border)

        local row = 5
        local footerRow = math.max(1, height)
        local function stat(label, value, color)
            if row < footerRow then
                UI.text(ctx.win, 3, row, label, UI.colors.muted, UI.colors.surface, math.floor(width * 0.52))
                UI.text(ctx.win, math.floor(width * 0.55), row, value, color or UI.colors.text, UI.colors.surface, width - math.floor(width * 0.55) - 1)
                row = row + 1
            end
        end

        stat("Qalcom version", VERSION, UI.colors.accent)
        stat("Computer ID", tostring(os.getComputerID()))
        stat("Label", os.getComputerLabel() or "(none)")
        stat("Terminal", tostring(select(1, term.getSize())) .. " x " .. tostring(select(2, term.getSize())))
        local memory = "unavailable"
        if type(collectgarbage) == "function" then
            local ok, value = pcall(collectgarbage, "count")
            if ok and type(value) == "number" then memory = string.format("%.1f KB", value) end
        end
        stat("Lua memory", memory)

        if height >= 13 then
            row = row + 1
            if row < footerRow then
                UI.text(ctx.win, 3, row, "Attached peripherals", UI.colors.accent, UI.colors.surface, width - 4)
                row = row + 1
                local names = {}
                local okNames, listed = pcall(peripheral.getNames)
                if okNames and type(listed) == "table" then names = listed end
                table.sort(names)
                if #names == 0 then
                    UI.text(ctx.win, 3, row, "No peripherals detected", UI.colors.muted, UI.colors.surface, width - 4)
                else
                    for _, name in ipairs(names) do
                        if row >= footerRow then break end
                        local okType, peripheralType = pcall(peripheral.getType, name)
                        local types = okType and tostring(peripheralType or "unknown") or "unknown"
                        UI.text(ctx.win, 3, row, name, UI.colors.text, UI.colors.surface, math.floor(width * 0.42))
                        UI.text(ctx.win, math.floor(width * 0.44), row, types, UI.colors.muted, UI.colors.surface, width - math.floor(width * 0.44) - 1)
                        row = row + 1
                    end
                end
            end
        end
        UI.text(ctx.win, 2, footerRow, "Live updates enabled", UI.colors.muted, UI.colors.surface, width - 3)
    end

    render()
    while true do
        local event = ctx:pullEvent()
        if event == "qalcom_tick" or event == "term_resize" or event == "peripheral" or event == "peripheral_detach" then
            render()
        end
    end
end
