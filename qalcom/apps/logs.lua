local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local lines = {}
    local scroll = 1
    local status = "Recent system events"
    local filter = "all"

    local function load()
        lines = {}
        local file = fs.open("/qalcom/logs/system.log", "r")
        if file then
            local text = file.readAll() or ""
            file.close()
            for line in (text .. "\n"):gmatch("(.-)\n") do
                if line ~= "" and (filter == "all" or line:lower():find(filter, 1, true)) then lines[#lines + 1] = line end
            end
        end
        if #lines == 0 then lines = { "No system log entries." } end
        local _, height = ctx.win.getSize()
        scroll = math.max(1, math.min(scroll, math.max(1, #lines - math.max(1, height - 5) + 1)))
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "System Log", status, { ui = UI })
        local visible = math.max(1, height - contentStart - 2)
        for row = 1, visible do
            local line = lines[scroll + row - 1]
            if line then UI.text(ctx.win, 2, contentStart + row - 1, line, UI.colors.text, UI.colors.surface, width - 3) end
        end
        UI.fill(ctx.win, 1, height - 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, height - 1, "Up/Down scroll   R refresh   F filter", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, height, "Esc close", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
    end

    load()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            local _, height = ctx.win.getSize()
            local visible = math.max(1, height - 5)
            if value == keys.up then scroll = math.max(1, scroll - 1); render()
            elseif value == keys.down then scroll = math.min(math.max(1, #lines - visible + 1), scroll + 1); render()
            elseif value == keys.r then load(); status = "Log refreshed"; render()
            elseif value == keys.f then
                filter = filter == "all" and "failure" or (filter == "failure" and "login" or "all")
                load()
                status = "Filter: " .. filter
                render()
            elseif value == keys.escape then ctx:close() end
        elseif event == "mouse_scroll" then
            local _, height = ctx.win.getSize()
            local visible = math.max(1, height - 5)
            scroll = value < 0 and math.max(1, scroll - 1) or math.min(math.max(1, #lines - visible + 1), scroll + 1)
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
