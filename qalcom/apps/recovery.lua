local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Config = dofile("/qalcom/lib/config.lua")

return function(ctx)
    local selected = 1
    local items = { "Clear notifications", "Reset desktop theme", "Safe Mode: toggle", "Disable all automation jobs", "Restore Qalcom defaults", "Open diagnostics", "Open system log", "Return" }
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
            local background = active and UI.colors.accentLight or UI.colors.surface
            UI.listRow(ctx.win, 2, y, width - 3, items[actualIndex], nil, active, {
                activeBackground = UI.colors.accentLight,
                activeForeground = colors.white,
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
            Config.setTheme("blue")
            status = "Theme reset to Ocean"
            ctx:notify("Theme reset to Ocean", UI.colors.success)
        elseif actualIndex == 3 then
            local config = Config.load()
            Config.setSafeMode(not config.safeMode)
            status = config.safeMode and "Safe Mode enabled now" or "Safe Mode disabled now"
            ctx:notify(status, UI.colors.warning)
        elseif actualIndex == 4 then
            local ok, reason
            if ctx.disableAutomationJobs then
                ok, reason = ctx:disableAutomationJobs()
            else
                local data = ctx.jobDefinitions and ctx:jobDefinitions() or nil
                if data then
                    for _, job in ipairs(data.jobs or {}) do job.paused = true end
                    ok, reason = ctx:writeJobDefinitions(data)
                else
                    ok, reason = false, "Automation recovery unavailable"
                end
            end
            if ok then
                status = "All automation jobs paused"
            else
                status = reason or "Unable to disable automation"
                ctx:notify(status, ok and UI.colors.warning or UI.colors.danger)
                if ctx.reloadJobs then ctx:reloadJobs() end
            end
        elseif actualIndex == 5 then
            Config.resetDefaults()
            status = "Defaults restored; accounts preserved"
            ctx:notify(status, UI.colors.success)
        elseif actualIndex == 6 then
            local task = ctx:launch("diagnostics")
            status = task and "Opened diagnostics" or "Unable to open diagnostics"
        elseif actualIndex == 7 then
            local task = ctx:launch("logs")
            status = task and "Opened system log" or "Unable to open system log"
        elseif actualIndex == 8 then
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
