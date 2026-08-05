local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local diagnostics = ctx:systemDiagnostics()
    local lines = {}
    local scroll = 1

    local function rebuild()
        lines = { "Boot stages" }
        for _, stage in ipairs(diagnostics.bootStages or {}) do
            lines[#lines + 1] = string.format("%.2f  %s", stage.at or 0, tostring(stage.stage))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Recent crashes"
        for _, crash in ipairs(diagnostics.crashes or {}) do
            lines[#lines + 1] = string.format("PID %s  %s", tostring(crash.pid), tostring(crash.name))
            lines[#lines + 1] = "  " .. tostring(crash.reason):sub(1, 60)
            lines[#lines + 1] = "  restarts: " .. tostring(crash.restartCount or 0)
        end
        if #lines == 4 then lines[#lines + 1] = "No crash records." end
    end

    local function render()
        local width, height = ctx.win.getSize()
        local visible = math.max(1, height - 5)
        scroll = math.max(1, math.min(scroll, math.max(1, #lines - visible + 1)))
        local _, _, contentStart = Screen.begin(ctx.win, "Qalcom Diagnostics", "Boot stages and recent application crashes", { ui = UI })
        for row = 1, visible do
            local line = lines[scroll + row - 1]
            if line then UI.text(ctx.win, 2, contentStart + row - 1, line, UI.colors.text, UI.colors.surface, width - 3) end
        end
        UI.fill(ctx.win, 1, height - 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, height - 1, "Up/Down scroll   R refresh", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, height, "Esc close", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
    end

    rebuild()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            local _, height = ctx.win.getSize()
            local visible = math.max(1, height - 5)
            if value == keys.up then scroll = math.max(1, scroll - 1); render()
            elseif value == keys.down then scroll = math.min(math.max(1, #lines - visible + 1), scroll + 1); render()
            elseif value == keys.r then diagnostics = ctx:systemDiagnostics(); rebuild(); render()
            elseif value == keys.escape then ctx:close() end
        elseif event == "mouse_scroll" then
            local _, height = ctx.win.getSize()
            local visible = math.max(1, height - 5)
            scroll = value < 0 and math.max(1, scroll - 1) or math.min(math.max(1, #lines - visible + 1), scroll + 1)
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
