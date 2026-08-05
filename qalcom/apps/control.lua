local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local VERSION = dofile("/qalcom/version.lua")

local function taskDetail(task)
    if task.restartLocked then return "restart locked", colors.red end
    if task.failed then return "crashed", colors.red end
    if task.watchdog == "slow" then return "slow", colors.yellow end
    if task.state == "stopped" then return "stopped", UI.colors.muted end
    return task.kind, UI.colors.text
end

return function(ctx)
    local selected = 1
    local info = {}
    local status = "Live system data"

    local function refresh()
        info = ctx:systemInfo()
        if #info.tasks > 0 then
            selected = math.min(selected, #info.tasks)
        else
            selected = 1
        end
    end

    local function render()
        local width, height = ctx.win.getSize()
        local compact = height < 18
        local _, _, contentStart = Screen.begin(ctx.win, "Control Center", status, { ui = UI })

        local footerStart = math.max(contentStart, height - 1)
        local row
        local maxVisibleTasks = math.max(0, footerStart - 5)
        if compact then maxVisibleTasks = math.max(0, footerStart - 5) end
        if #info.tasks > maxVisibleTasks and selected > maxVisibleTasks then selected = math.max(1, maxVisibleTasks) end
        if compact then
            -- At the minimum terminal size, prioritize process recovery over statistics.
            row = 4
            if row < footerStart then
                UI.text(ctx.win, 2, row, "Processes: R restarts failed", UI.colors.accent, UI.colors.surface, width - 3)
                row = row + 1
            end
        else
            row = 5
            local function stat(label, value, color)
                if row < footerStart then
                    UI.text(ctx.win, 2, row, label, UI.colors.muted, UI.colors.surface, math.floor(width * 0.48))
                    UI.text(ctx.win, math.floor(width * 0.5), row, value, color or UI.colors.text, UI.colors.surface, width - math.floor(width * 0.5) - 1)
                    row = row + 1
                end
            end

            stat("Qalcom", VERSION, UI.colors.accent)
            stat("User", tostring(info.user or "-"))
            stat("Computer", tostring(info.computerId))
            stat("Memory", tostring(info.memory))
            stat("Terminal", tostring(info.width) .. " x " .. tostring(info.height))
            stat("Free space", tostring(info.freeSpace))
            stat("Peripherals", tostring(#info.peripherals))
            stat("Modems", tostring(info.modems))
            if row < footerStart then row = row + 1 end
            if row < footerStart then
                UI.text(ctx.win, 2, row, "Processes", UI.colors.accent, UI.colors.surface, width - 3)
                row = row + 1
            end
        end

        for index, task in ipairs(info.tasks) do
            if row >= footerStart or index > maxVisibleTasks then break end
            local active = index == selected
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            local marker = task.failed and "! " or (task.minimized and "_ " or "> ")
            local label = marker .. tostring(task.pid) .. " " .. task.title
            local detail, detailColor = taskDetail(task)
            if task.failed and task.crashReason then detail = tostring(task.crashReason):sub(1, 18) end

            UI.fill(ctx.win, 2, row, width - 3, 1, background)
            UI.text(ctx.win, 3, row, label, foreground, background, math.floor(width * 0.62))
            UI.text(ctx.win, math.floor(width * 0.65), row, detail, detailColor, background, width - math.floor(width * 0.65) - 1)
            row = row + 1
        end

        UI.fill(ctx.win, 1, height - 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, height - 1, "Up/Down select   R restart crashed", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, height, "Esc close   Updates every second", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
    end

    refresh()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then
                selected = math.max(1, selected - 1)
                render()
            elseif value == keys.down then
                selected = math.min(math.max(1, #info.tasks), selected + 1)
                render()
            elseif value == keys.r then
                local task = info.tasks[selected]
                if task and task.failed then
                    local restarted, reason = ctx:restartProcess(task.pid)
                    status = restarted and ("Restart requested for " .. task.title) or (reason or "Restart unavailable for " .. task.title)
                else
                    status = task and task.restartLocked and "Restart limit reached for " .. task.title or "Select a crashed process to restart"
                end
                render()
            elseif value == keys.escape then
                ctx:close()
            end
        elseif event == "mouse_scroll" then
            if value < 0 then selected = math.max(1, selected - 1) else selected = math.min(math.max(1, #info.tasks), selected + 1) end
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then
            refresh()
            render()
        end
    end
end
