local UI = dofile("/qalcom/lib/ui.lua")
local Config = dofile("/qalcom/lib/config.lua")
local VERSION = dofile("/qalcom/version.lua")
local Auth = dofile("/qalcom/lib/auth.lua")
local System = dofile("/qalcom/lib/system.lua")
local config = Config.load()
Config.apply(UI, config)

local APP_PATHS = {
    terminal = "/qalcom/apps/terminal.lua",
    explorer = "/qalcom/apps/explorer.lua",
    monitor = "/qalcom/apps/monitor.lua",
    settings = "/qalcom/apps/settings.lua",
    account = "/qalcom/apps/account.lua",
    editor = "/qalcom/apps/editor.lua",
    dialog = "/qalcom/apps/dialog.lua",
    control = "/qalcom/apps/control.lua",
    logs = "/qalcom/apps/logs.lua",
    recovery = "/qalcom/apps/recovery.lua",
}

local APP_META = {
    terminal = { title = "Terminal", icon = ">_", x = 3, y = 3, width = 38, height = 16 },
    explorer = { title = "File Explorer", icon = ">", x = 10, y = 5, width = 42, height = 17 },
    monitor = { title = "System Monitor", icon = "#", x = 18, y = 4, width = 40, height = 18, service = true },
    settings = { title = "Settings", icon = "*", x = 25, y = 6, width = 38, height = 17 },
    account = { title = "Account", icon = "@", x = 14, y = 5, width = 38, height = 17 },
    editor = { title = "Text Viewer", icon = "[]", x = 6, y = 4, width = 48, height = 19 },
    dialog = { title = "Confirm", icon = "?", x = 12, y = 7, width = 34, height = 12 },
    control = { title = "Control Center", icon = "!", x = 5, y = 3, width = 48, height = 20 },
    logs = { title = "System Log", icon = "L", x = 4, y = 3, width = 48, height = 19 },
    recovery = { title = "Recovery", icon = "R", x = 7, y = 4, width = 42, height = 16 },
}

local NORMAL_LAUNCHER_APPS = { "terminal", "explorer", "monitor", "control", "settings", "recovery", "logs", "account" }
local SAFE_LAUNCHER_APPS = { "recovery", "logs", "terminal", "settings" }
local LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS

local native = term.native()
local width, height = native.getSize()
if width < 30 or height < 14 then
    term.redirect(native)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Qalcom OS needs a terminal of at least 30 x 14.")
    print("Resize the terminal or use CraftOS recovery.")
    return
end
local state = {
    user = nil,
    session = 0,
    tasks = {},
    nextPid = 100,
    focused = nil,
    launcher = false,
    launcherSelection = 1,
    notifications = {},
    clockTimer = nil,
    dirty = true,
    drag = nil,
    modifiers = { alt = false, ctrl = false, shift = false },
}

local function log(message)
    if not fs.exists("/qalcom/logs") then fs.makeDir("/qalcom/logs") end
    local path = "/qalcom/logs/system.log"
    local lines = {}
    local existing = fs.open(path, "r")
    if existing then
        local text = existing.readAll() or ""
        existing.close()
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if line ~= "" then lines[#lines + 1] = line end
        end
    end
    lines[#lines + 1] = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. tostring(message)
    local limit = config.logLimit or 200
    while #lines > limit do table.remove(lines, 1) end
    local file = fs.open(path, "w")
    if file then
        file.write(table.concat(lines, "\n") .. "\n")
        file.close()
    end
end

local function notify(message, color)
    state.notifications[#state.notifications + 1] = {
        message = tostring(message),
        color = color or UI.colors.accent,
        expires = os.clock() + 4,
    }
    while #state.notifications > 3 do table.remove(state.notifications, 1) end
    state.dirty = true
end

local function closeAllTasks()
    for index = #state.tasks, 1, -1 do
        local task = state.tasks[index]
        if task.window then task.window.setVisible(false) end
        table.remove(state.tasks, index)
    end
    state.focused = nil
    state.drag = nil
end

local function removeTask(task)
    if task.window then task.window.setVisible(false) end
    for index, candidate in ipairs(state.tasks) do
        if candidate == task then
            table.remove(state.tasks, index)
            break
        end
    end
    if state.focused == task then
        state.focused = nil
        for index = #state.tasks, 1, -1 do
            local candidate = state.tasks[index]
            if not candidate.modal and not candidate.minimized then
                state.focused = candidate
                break
            end
        end
        if state.focused then state.focused.window.setVisible(true) end
    end
    state.drag = nil
    state.dirty = true
end

local function focusTask(task)
    if not task or task.modal then return end
    state.focused = task
    for index, candidate in ipairs(state.tasks) do
        if candidate == task then
            table.remove(state.tasks, index)
            state.tasks[#state.tasks + 1] = task
            break
        end
    end
    state.dirty = true
end

local spawn

local function makeContext(task)
    local context = {
        pid = task.pid,
        name = task.name,
        title = task.meta.title,
        user = state.user,
        modifiers = state.modifiers,
        win = task.window,
        session = state.session,
        generation = state.session,
    }

    function context:pullEvent(filter)
        while task.session == state.session do
            local event = { coroutine.yield() }
            if task.session ~= state.session then
                task.closeRequested = true
                return "qalcom_session_invalid"
            end
            if not filter or event[1] == filter then
                return table.unpack(event)
            end
        end
        task.closeRequested = true
        return "qalcom_session_invalid"
    end

    function context:notify(message, color)
        notify(message, color)
    end

    function context:clearNotifications()
        state.notifications = {}
        state.dirty = true
    end

    function context:close()
        task.closeRequested = true
    end

    function context:redraw()
        state.dirty = true
    end

    function context:launch(name, options)
        return spawn(name, options)
    end

    function context:processCount()
        return #state.tasks
    end

    function context:sessionIsCurrent()
        return task.session == state.session
    end

    function context:log(message)
        log("[" .. task.name .. "] " .. tostring(message))
    end

    function context:systemInfo()
        local info = System.info()
        info.user = state.user
        info.tasks = {}
        for _, candidate in ipairs(state.tasks) do
            info.tasks[#info.tasks + 1] = {
                pid = candidate.pid,
                name = candidate.name,
                title = candidate.meta.title,
                minimized = candidate.minimized,
                failed = candidate.failed,
                state = candidate.state,
                kind = candidate.kind,
                crashReason = candidate.crashReason,
                restartCount = candidate.restartCount,
                age = os.clock() - candidate.startedAt,
                lastEventAge = os.clock() - candidate.lastEventAt,
                eventCount = candidate.eventCount,
                watchdog = candidate.watchdog,
                watchdogSince = candidate.watchdogSince,
                lastRunDuration = candidate.lastRunDuration,
            }
        end
        return info
    end

    function context:restartProcess(pid)
        for _, candidate in ipairs(state.tasks) do
            if candidate.pid == pid and candidate.failed then
                local name = candidate.name
                local options = {}
                for key, value in pairs(candidate.options or {}) do options[key] = value end
                options.restartCount = (candidate.restartCount or 0) + 1
                removeTask(candidate)
                return spawn(name, options)
            end
        end
        return nil
    end

    return context
end

local function startTask(name, options)
    local meta = APP_META[name]
    local path = APP_PATHS[name]
    if config.safeMode and name ~= "recovery" and name ~= "logs" and name ~= "terminal" and name ~= "settings" then
        notify("Safe Mode blocked " .. tostring(name), UI.colors.warning)
        return nil
    end
    if not meta or not path or not fs.exists(path) then
        notify("Application unavailable: " .. tostring(name), UI.colors.danger)
        return nil
    end

    local w = math.min(meta.width, math.max(20, width - 2))
    local h = math.min(meta.height, math.max(8, height - 4))
    local x = math.max(2, math.min(meta.x, width - w))
    local y = math.max(2, math.min(meta.y, height - h - 2))
    local task = {
        pid = state.nextPid,
        name = name,
        meta = meta,
        x = x,
        y = y,
        width = w,
        height = h,
        closeRequested = false,
        minimized = false,
        failed = nil,
        state = "starting",
        crashReason = nil,
        kind = meta.service and "service" or "application",
        restartCount = (options and options.restartCount) or 0,
        startedAt = os.clock(),
        lastEventAt = os.clock(),
        eventCount = 0,
        options = options or {},
        session = state.session,
        lastRunDuration = 0,
        watchdog = nil,
        watchdogSince = nil,
    }
    state.nextPid = state.nextPid + 1
    task.window = window.create(native, x + 1, y + 1, w - 2, h - 2, true)
    task.modal = task.options.modal == true
    task.context = makeContext(task)
    for key, value in pairs(task.options) do task.context[key] = value end

    local ok, app = pcall(dofile, path)
    if not ok or type(app) ~= "function" then
        task.window.setVisible(false)
        notify("Could not load " .. meta.title, UI.colors.danger)
        log("load failure " .. name .. ": " .. tostring(app))
        return nil
    end

    task.co = coroutine.create(function()
        local success, err = pcall(app, task.context)
        if not success then task.failed = tostring(err) end
    end)
    state.tasks[#state.tasks + 1] = task
    if task.modal then
        state.focused = task
    else
        focusTask(task)
    end
    task.window.setVisible(true)
    local resumed, err = coroutine.resume(task.co)
    if not resumed then
        task.failed = tostring(err)
    end
    if task.failed then
        task.state = "crashed"
        task.crashReason = task.failed
        log("app failure " .. name .. ": " .. task.failed)
        notify(meta.title .. " failed to start", UI.colors.danger)
        state.dirty = true
        return task
    end
    task.state = "running"
    state.dirty = true
    return task
end

spawn = function(name, options)
    return startTask(name, options)
end

local function send(task, event)
    if not task or not coroutine or coroutine.status(task.co) == "dead" then return end
    if task.session ~= state.session then return end
    task.eventCount = task.eventCount + 1
    local started = os.clock()
    local ok, err = coroutine.resume(task.co, table.unpack(event))
    local finished = os.clock()
    task.lastEventAt = finished
    task.lastRunDuration = finished - started
    if task.lastRunDuration > 1 then
        task.watchdog = "slow"
        task.watchdogSince = task.watchdogSince or finished
    elseif task.watchdog == "slow" then
        task.watchdog = nil
        task.watchdogSince = nil
    end
    if not ok then task.failed = tostring(err) end
    if task.failed then
        task.state = "crashed"
        task.crashReason = task.failed
        log("app failure " .. task.name .. ": " .. task.failed)
        notify(APP_META[task.name].title .. " stopped; open Control Center to restart", UI.colors.danger)
        task.window.setVisible(true)
        task.minimized = false
        task.closeRequested = false
    elseif coroutine.status(task.co) == "dead" then
        task.state = "stopped"
        task.closeRequested = true
    else
        task.state = "running"
    end
end

local function drawDesktop()
    width, height = native.getSize()
    native.setBackgroundColor(UI.colors.desktop)
    native.setTextColor(colors.white)
    native.clear()

    UI.fill(native, 1, 1, width, height - 2, UI.colors.desktop)
    UI.text(native, 2, 2, "QALCOM", colors.white, UI.colors.desktop, 10)
    UI.text(native, 2, 3, "A calm command center", colors.lightBlue, UI.colors.desktop, math.min(28, width - 3))
    UI.text(native, width - 18, 2, "User: " .. tostring(state.user or "-"), colors.lightBlue, UI.colors.desktop, 17)

    for _, task in ipairs(state.tasks) do
        local focused = task == state.focused
        local titleColor = focused and UI.colors.accent or UI.colors.border
        if not task.minimized then
            UI.fill(native, task.x, task.y, task.width, task.height, UI.colors.border)
            UI.fill(native, task.x + 1, task.y, task.width - 2, 1, titleColor)
            UI.text(native, task.x + 2, task.y, task.meta.icon .. "  " .. task.meta.title, colors.white, titleColor, task.width - 10)
            UI.text(native, task.x + task.width - 7, task.y, "-", colors.white, UI.colors.muted, 1)
            UI.text(native, task.x + task.width - 4, task.y, "x", colors.white, colors.red, 1)
            if task.failed then
                task.window.setBackgroundColor(colors.black)
                task.window.setTextColor(colors.white)
                task.window.clear()
                UI.text(task.window, 2, 2, "Application stopped", colors.red, colors.black, task.width - 5)
                UI.text(task.window, 2, 4, "Open Control Center", colors.yellow, colors.black, task.width - 5)
                UI.text(task.window, 2, 5, "to restart this process", colors.yellow, colors.black, task.width - 5)
            else
                task.window.redraw()
            end
        end
    end

    local now = os.clock()
    for _, task in ipairs(state.tasks) do
        if task.failed then
            task.window.setVisible(true)
        end
    end
    for index = #state.notifications, 1, -1 do
        if state.notifications[index].expires < now then table.remove(state.notifications, index) end
    end
    for index, item in ipairs(state.notifications) do
        local boxWidth = math.min(width - 4, math.max(18, #item.message + 4))
        local x = width - boxWidth - 1
        local y = 2 + (index - 1) * 2
        UI.fill(native, x, y, boxWidth, 1, item.color)
        UI.text(native, x + 1, y, item.message, colors.white, item.color, boxWidth - 2)
    end

    if state.launcher then
        local menuWidth = math.min(34, width - 4)
        local menuHeight = math.min(height - 2, #LAUNCHER_APPS + 3)
        local menuX = 2
        local menuY = math.max(2, height - menuHeight - 2)
        UI.fill(native, menuX, menuY, menuWidth, menuHeight, UI.colors.surface)
        UI.fill(native, menuX, menuY, menuWidth, 2, UI.colors.accent)
        UI.text(native, menuX + 2, menuY, "Qalcom", colors.white, UI.colors.accent, menuWidth - 3)
        UI.text(native, menuX + 2, menuY + 1, "Pinned apps", colors.lightBlue, UI.colors.accent, menuWidth - 3)
        local names = LAUNCHER_APPS
        UI.text(native, menuX + 2, menuY + 2, "Use arrows, Enter, or click", UI.colors.muted, UI.colors.surface, menuWidth - 3)
        for index, name in ipairs(names) do
            local itemY = menuY + 2 + index
            local active = index == state.launcherSelection
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            UI.fill(native, menuX + 1, itemY, menuWidth - 2, 1, background)
            UI.text(native, menuX + 3, itemY, APP_META[name].icon .. "  " .. APP_META[name].title, foreground, background, menuWidth - 6)
        end
    end

    local barY = height - 1
    local trayWidth = 15
    UI.fill(native, 1, barY, width, 2, colors.lightGray)
    UI.button(native, 2, barY, 10, "[S] Start", state.launcher)
    local x = 14
    for _, task in ipairs(state.tasks) do
        local label = task.meta.icon .. (task.minimized and " + " or " ") .. task.meta.title
        local buttonWidth = math.min(16, math.max(8, #label + 2))
        UI.button(native, x, barY, buttonWidth, label, task == state.focused and not task.minimized)
        x = x + buttonWidth + 1
        if x > width - trayWidth - 1 then break end
    end
    UI.text(native, width - trayWidth, barY, os.date("%H:%M"), UI.colors.text, colors.lightGray, 6)
    UI.text(native, width - 8, barY, "ID " .. tostring(os.getComputerID()), UI.colors.muted, colors.lightGray, 7)
end

local function hitTask(x, y)
    for index = #state.tasks, 1, -1 do
        local task = state.tasks[index]
        if x >= task.x and x < task.x + task.width and y >= task.y and y < task.y + task.height then
            return task
        end
    end
end

local function activeModal()
    for _, task in ipairs(state.tasks) do
        if task.modal then return task end
    end
    return nil
end

local function handleLauncherClick(x, y)
    local menuWidth = math.min(34, width - 4)
    local menuHeight = math.min(height - 2, #LAUNCHER_APPS + 3)
    local menuX = 2
    local menuY = math.max(2, height - menuHeight - 2)
    if x < menuX or x >= menuX + menuWidth or y < menuY or y >= menuY + menuHeight then return false end
    local index = y - (menuY + 2)
    local names = LAUNCHER_APPS
    if index >= 1 and index <= #names then
        state.launcher = false
        spawn(names[index])
    end
    return true
end

local function handleMouse(button, x, y)
    if state.launcher and handleLauncherClick(x, y) then
        state.dirty = true
        return
    end
    if y >= height - 1 then
        if activeModal() then return end
        if x >= 2 and x < 12 then
            state.launcher = not state.launcher
            state.launcherSelection = 1
            state.dirty = true
            return
        end
        local cursor = 14
        for _, task in ipairs(state.tasks) do
            local label = task.meta.icon .. (task.minimized and " + " or " ") .. task.meta.title
            local buttonWidth = math.min(16, math.max(8, #label + 2))
            if x >= cursor and x < cursor + buttonWidth then
                task.minimized = not task.minimized
                task.window.setVisible(not task.minimized)
                focusTask(task)
                return
            end
            cursor = cursor + buttonWidth + 1
        end
        return
    end

    local task = hitTask(x, y)
    local modal = activeModal()
    if modal then
        send(modal, { "mouse_click", button, x - modal.x, y - modal.y })
        return
    end
    if not task then
        state.launcher = false
        state.dirty = true
        return
    end
    focusTask(task)
    if task.minimized then
        task.minimized = false
        task.window.setVisible(true)
        state.dirty = true
        return
    end
    if y == task.y and x >= task.x + task.width - 5 then
        removeTask(task)
        return
    end
    if y == task.y and x >= task.x + task.width - 8 then
        task.minimized = true
        task.window.setVisible(false)
        state.dirty = true
        return
    end
    if y == task.y then
        state.drag = { task = task, offsetX = x - task.x, offsetY = y - task.y }
        return
    end
    if y > task.y and y <= task.y + task.height - 2 then
        send(task, { "mouse_click", button, x - task.x, y - task.y })
    end
end

local function dispatch(event)
    local name = event[1]
    if name == "mouse_click" then
        handleMouse(event[2], event[3], event[4])
    elseif name == "mouse_drag" then
        if state.drag then
            local task = state.drag.task
            task.x = math.max(2, math.min(width - task.width, event[3] - state.drag.offsetX))
            task.y = math.max(2, math.min(height - task.height - 2, event[4] - state.drag.offsetY))
            task.window.reposition(task.x + 1, task.y + 1)
            state.dirty = true
        elseif state.focused then
            local task = state.focused
            send(task, { name, event[2], event[3] - task.x, event[4] - task.y })
        end
    elseif name == "mouse_up" then
        state.drag = nil
        if state.focused then
            local task = state.focused
            send(task, { name, event[2], event[3] - task.x, event[4] - task.y })
        end
    elseif name == "mouse_scroll" then
        if state.focused then send(state.focused, event) end
    elseif name == "key" or name == "char" or name == "paste" or name == "key_up" then
        if name == "key" then
            if event[2] == keys.leftAlt or event[2] == keys.rightAlt then state.modifiers.alt = true end
            if event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then state.modifiers.ctrl = true end
            if event[2] == keys.leftShift or event[2] == keys.rightShift then state.modifiers.shift = true end
            if state.modifiers.alt and event[2] == keys.tab then
                -- Modal tasks own the desktop until they close; never switch behind one.
                if activeModal() then return end
                local candidates = {}
                for _, task in ipairs(state.tasks) do
                    if not task.modal and not task.minimized then candidates[#candidates + 1] = task end
                end
                if #candidates > 1 then
                    local currentIndex = 0
                    for index, task in ipairs(candidates) do
                        if task == state.focused then currentIndex = index end
                    end
                    focusTask(candidates[(currentIndex % #candidates) + 1])
                end
                return
            end
            if state.modifiers.alt and event[2] == keys.f4 and state.focused then
                state.focused.closeRequested = true
                return
            end
        elseif name == "key_up" then
            if event[2] == keys.leftAlt or event[2] == keys.rightAlt then state.modifiers.alt = false end
            if event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then state.modifiers.ctrl = false end
            if event[2] == keys.leftShift or event[2] == keys.rightShift then state.modifiers.shift = false end
        end
        if name == "key" and state.launcher then
            if event[2] == keys.up then
                state.launcherSelection = math.max(1, state.launcherSelection - 1)
                state.dirty = true
                return
            elseif event[2] == keys.down then
                state.launcherSelection = math.min(#LAUNCHER_APPS, state.launcherSelection + 1)
                state.dirty = true
                return
            elseif event[2] == keys.enter then
                state.launcher = false
                spawn(LAUNCHER_APPS[state.launcherSelection])
                return
            elseif event[2] == keys.escape then
                state.launcher = false
                state.dirty = true
                return
            end
        end
        if state.focused then send(state.focused, event) end
    elseif name == "timer" or name == "alarm" or name == "redstone" or name == "term_resize" or name == "peripheral" or name == "peripheral_detach" or name == "disk" or name == "disk_eject" or name == "rednet_message" or name == "modem_message" then
        for _, task in ipairs(state.tasks) do send(task, event) end
    elseif name == "qalcom_config_changed" then
        config = Config.load()
        Config.apply(UI, config)
        LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
        if config.safeMode then
            for _, task in ipairs(state.tasks) do
                if task.name ~= "recovery" and task.name ~= "logs" and task.name ~= "terminal" and task.name ~= "settings" then
                    task.closeRequested = true
                end
            end
        end
        state.dirty = true
        for _, task in ipairs(state.tasks) do send(task, event) end
    elseif name == "qalcom_tick" then
        for _, task in ipairs(state.tasks) do
            send(task, event)
        end
    end
end

log("boot Qalcom OS " .. VERSION)
local authenticated = Auth.login(native, UI, VERSION)
if not authenticated then
    return
end
state.session = state.session + 1
state.user = authenticated.username
log("login success: " .. state.user)
if config.safeMode then notify("Safe Mode enabled", UI.colors.warning) end
notify("Welcome, " .. state.user, UI.colors.accent)
state.clockTimer = os.startTimer(1)
drawDesktop()

while true do
    if state.dirty then
        drawDesktop()
        state.dirty = false
    end
    local event = { os.pullEventRaw() }
    if event[1] == "timer" and event[2] == state.clockTimer then
        state.clockTimer = os.startTimer(1)
        dispatch({ "qalcom_tick" })
        state.dirty = true
    elseif event[1] == "terminate" then
        state.modifiers.alt = false
        state.modifiers.ctrl = false
        state.modifiers.shift = false
        notify("Ctrl+T is handled by Qalcom; close apps from their title bars.", UI.colors.warning)
        state.dirty = true
    elseif event[1] == "qalcom_logout" then
        closeAllTasks()
        state.launcher = false
        state.user = nil
        state.modifiers.alt = false
        state.modifiers.ctrl = false
        state.modifiers.shift = false
        local authenticated = Auth.login(native, UI, VERSION)
        if not authenticated then return end
        state.session = state.session + 1
        state.user = authenticated.username
        config = Config.load()
        Config.apply(UI, config)
        LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
        log("login success: " .. state.user)
        if config.safeMode then notify("Safe Mode enabled", UI.colors.warning) end
        notify("Welcome, " .. state.user, UI.colors.accent)
        state.clockTimer = os.startTimer(1)
        state.dirty = true
    elseif event[1] == "term_resize" then
        width, height = native.getSize()
        while width < 30 or height < 14 do
            native.setBackgroundColor(colors.black)
            native.setTextColor(colors.yellow)
            native.clear()
            native.setCursorPos(1, 1)
            native.write("Qalcom needs 30 x 14 minimum. Resize to continue.")
            state.dirty = false
            os.pullEventRaw("term_resize")
            width, height = native.getSize()
        end
        for _, task in ipairs(state.tasks) do
            task.width = math.min(task.width, math.max(20, width - 2))
            task.height = math.min(task.height, math.max(8, height - 4))
            task.x = math.max(2, math.min(task.x, width - task.width))
            task.y = math.max(2, math.min(task.y, height - task.height - 2))
            task.window.reposition(task.x + 1, task.y + 1, task.width - 2, task.height - 2)
        end
        state.dirty = true
        dispatch(event)
    else
        dispatch(event)
    end

    for index = #state.tasks, 1, -1 do
        local task = state.tasks[index]
        if task.closeRequested then removeTask(task) end
    end
end
