local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local VERSION = dofile("/qalcom/version.lua")

return function(ctx)
    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "System overview", nil, { ui = UI })

        local row = contentStart
        local footerRow = math.max(1, height)
        local function stat(label, value, color)
            if row < footerRow then
                UI.listRow(ctx.win, 2, row, width - 3, label, value, false, {
                    split = math.floor(width * 0.52),
                    valueColor = color or UI.colors.text,
                    background = UI.colors.surface,
                })
                row = row + 1
            end
        end

        stat("Qalcom version", VERSION, UI.colors.accent)
        stat("Computer ID", tostring(os.getComputerID()))
        stat("Label", os.getComputerLabel() or "(none)")
        stat("Terminal", tostring(select(1, term.getSize())) .. " x " .. tostring(select(2, term.getSize())))
        stat("Updated", os.date("%H:%M:%S"), UI.colors.accent)
        local memory = "unavailable"
        if type(collectgarbage) == "function" then
            local ok, value = pcall(collectgarbage, "count")
            if ok and type(value) == "number" then memory = string.format("%.1f KB", value) end
        end
        stat("Lua memory", memory)

        if height >= 13 then
            row = row + 1
            if row < footerRow then
                UI.sectionHeader(ctx.win, 2, row, width - 3, "Attached peripherals", { background = colors.yellow, foreground = colors.black })
                row = row + 1
                if row < footerRow then
                    UI.meter(ctx.win, 2, row, width - 3, math.min(1, #ctx:peripheralNames() / 8), UI.colors.accent, colors.gray)
                    row = row + 1
                end
                local names = ctx:peripheralNames() or {}
                table.sort(names)
                if #names == 0 then
                    if row < footerRow then UI.text(ctx.win, 3, row, "No peripherals detected", UI.colors.muted, UI.colors.surface, width - 4) end
                else
                    for _, name in ipairs(names) do
                        if row >= footerRow then break end
                        local peripheralType = ctx:peripheralType(name)
                        local types = tostring(peripheralType or "unknown")
                        UI.listRow(ctx.win, 2, row, width - 3, name, types, false, {
                            split = math.floor(width * 0.42),
                            valueColor = UI.colors.muted,
                            background = UI.colors.surface,
                        })
                        row = row + 1
                    end
                end
            end
        end
        UI.badge(ctx.win, 2, footerRow, "LIVE", UI.colors.success, 8)
        UI.text(ctx.win, 12, footerRow, "Peripheral data refreshes automatically", UI.colors.muted, UI.colors.surface, width - 13)
    end

    render()
    while true do
        local event = ctx:pullEvent()
        if event == "qalcom_tick" or event == "term_resize" or event == "peripheral" or event == "peripheral_detach" then
            render()
        end
    end
end
