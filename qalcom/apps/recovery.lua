local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Config = dofile("/qalcom/lib/config.lua")

return function(ctx)
    local selected = 1
    local items = { "Clear notifications", "Reset theme to Windows 11 Dark", "Safe Mode: toggle", "Restore Qalcom defaults", "Open diagnostics", "Open system log", "Return" }
    local status = "Local recovery tools"

    local function visibleItems(height)
        -- Keep the compact recovery view useful: clear, Safe Mode, defaults, and logs.
        if height < 10 then return { 1, 3, 4, 5 } end
        local count = math.min(#items, math.max(1, height - 2))
        local result = {}
        for index = 1, count do result[index] = index end
        return result
    end

    local function render()
        local width, height = ctx.win.getSize()
        local visible = visibleItems(height)
        selected = math.min(selected, #visible)
        local _, _, contentStart = Screen.begin(ctx.win, "Recovery", nil, { ui = UI })
        UI.text(ctx.win, 2, contentStart, status, UI.colors.muted, UI.colors.surface, width - 3)
        for displayIndex, actualIndex in ipairs(visible) do
            local y = contentStart + displayIndex
            local active = displayIndex == selected
            UI.listRow(ctx.win, 2, y, width - 3, items[actualIndex], nil, active, {
                activeBackground = UI.colors.surfaceSelected,
                activeForeground = UI.colors.text,
                background = UI.colors.surface,
            })
        end
    end

    local function choose()
        local visible = visibleItems(select(2, ctx.win.getSize()))
        local actualIndex = visible[selected]
        if actualIndex == 1 then
            ctx:clearNotifications()
            status = "Notifications cleared"
        elseif actualIndex == 2 then
            Config.setTheme("win11dark")
            status = "Theme reset to Windows 11 Dark"
            ctx:notify("Theme reset to Windows 11 Dark", UI.colors.success)
        elseif actualIndex == 3 then
            local config = Config.load()
            Config.setSafeMode(not config.safeMode)
            status = config.safeMode and "Safe Mode enabled now" or "Safe Mode disabled now"
            ctx:notify(status, UI.colors.warning)
        elseif actualIndex == 4 then
            Config.resetDefaults()
            status = "Defaults restored; accounts preserved"
            ctx:notify(status, UI.colors.success)
        elseif actualIndex == 5 then
            local task = ctx:launch("diagnostics")
            status = task and "Opened diagnostics" or "Unable to open diagnostics"
        elseif actualIndex == 6 then
            local task = ctx:launch("logs")
            status = task and "Opened system log" or "Unable to open system log"
        elseif actualIndex == 7 then
            ctx:close()
        end
        render()
    end

    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(#visibleItems(select(2, ctx.win.getSize())), selected + 1); render()
            elseif value == keys.enter then choose()
            elseif value == keys.escape then ctx:close() end
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
