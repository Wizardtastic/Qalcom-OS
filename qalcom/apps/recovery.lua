local UI = dofile("/qalcom/lib/ui.lua")
local Config = dofile("/qalcom/lib/config.lua")

return function(ctx)
    local selected = 1
    local items = { "Clear notifications", "Reset desktop theme", "Safe Mode: toggle", "Open system log", "Return" }
    local status = "Local recovery tools"

    local function visibleItems(height)
        -- Reserve the final compact row for controls; keep the log shortcut visible.
        if height < 10 then return { 1, 2, 3, 4 } end
        local count = math.min(#items, math.max(1, height - 6))
        local result = {}
        for index = 1, count do result[index] = index end
        return result
    end

    local function render()
        local width, height = ctx.win.getSize()
        local visible = visibleItems(height)
        selected = math.min(selected, #visible)
        local compact = height < 10
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        UI.fill(ctx.win, 1, 1, width, 3, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, 1, "Recovery", UI.colors.accent, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, 2, status, UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.divider(ctx.win, 1, 3, width, UI.colors.border)
        for displayIndex, actualIndex in ipairs(visible) do
            local y = 4 + displayIndex
            local active = displayIndex == selected
            local background = active and UI.colors.accentLight or UI.colors.surface
            UI.fill(ctx.win, 2, y, width - 3, 1, background)
            UI.text(ctx.win, 3, y, items[actualIndex], active and colors.white or UI.colors.text, background, width - 5)
        end
        if compact then
            -- All core recovery actions remain visible; Escape closes without a footer.
        else
            UI.text(ctx.win, 2, height - 1, "Up/Down select   Enter apply", UI.colors.muted, UI.colors.surface, width - 3)
            UI.text(ctx.win, 2, height, "Esc close", UI.colors.muted, UI.colors.surface, width - 3)
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
            local task = ctx:launch("logs")
            status = task and "Opened system log" or "Unable to open system log"
        elseif actualIndex == 5 then
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
