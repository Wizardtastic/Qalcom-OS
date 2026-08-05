local UI = dofile("/qalcom/lib/ui.lua")
local Config = dofile("/qalcom/lib/config.lua")
local VERSION = dofile("/qalcom/version.lua")
local Auth = dofile("/qalcom/lib/auth.lua")
local System = dofile("/qalcom/lib/system.lua")
local Capabilities = dofile("/qalcom/lib/capabilities.lua")
local Roles = dofile("/qalcom/lib/roles.lua")
local Managed = dofile("/qalcom/lib/managed.lua")
local Infrastructure = dofile("/qalcom/lib/infrastructure.lua")
local Jobs = dofile("/qalcom/lib/jobs.lua")
local unpack = table.unpack or unpack
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
    diagnostics = "/qalcom/apps/diagnostics.lua",
    capabilities = "/qalcom/apps/capabilities.lua",
    peripherals = "/qalcom/apps/peripherals.lua",
    infrastructure = "/qalcom/apps/infrastructure.lua",
    jobs = "/qalcom/apps/jobs.lua",
    calculator = "/qalcom/apps/calculator.lua",
    jobs_service = "/qalcom/apps/jobs_service.lua",
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
    diagnostics = { title = "Diagnostics", icon = "D", x = 6, y = 3, width = 48, height = 19 },
    capabilities = { title = "Capabilities", icon = "C", x = 8, y = 3, width = 50, height = 20 },
    peripherals = { title = "Peripheral Manager", icon = "P", x = 4, y = 3, width = 54, height = 21 },
    infrastructure = { title = "Infrastructure", icon = "I", x = 3, y = 3, width = 56, height = 21 },
    jobs = { title = "Automation Jobs", icon = "J", x = 3, y = 3, width = 56, height = 21 },
    calculator = { title = "Calculator", icon = "=", x = 12, y = 4, width = 38, height = 21 },
    jobs_service = { title = "Automation Service", icon = "J", x = 3, y = 3, width = 20, height = 8, service = true, hidden = true },
}

local NORMAL_LAUNCHER_APPS = { "terminal", "explorer", "calculator", "monitor", "peripherals", "infrastructure", "jobs", "control", "capabilities", "settings", "recovery", "logs", "account" }
local SAFE_LAUNCHER_APPS = { "recovery", "logs", "terminal", "calculator", "settings", "peripherals", "infrastructure", "jobs" }
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
local MAX_MANUAL_RESTARTS = 3
local state = {
    user = nil,
    session = 0,
    bootStages = {},
    crashes = {},
    tasks = {},
    nextPid = 100,
    focused = nil,
    launcher = false,
    launcherSelection = 1,
    launcherSearch = "",
    launcherSearchFocused = true,
    recentApps = {},
    notifications = {},
    clockTimer = nil,
    uiTimer = nil,
    dirty = true,
    drag = nil,
    mouseX = 1,
    mouseY = 1,
    modifiers = { alt = false, ctrl = false, shift = false },
}

local function log(message)
    if not fs.exists("/qalcom/logs") then fs.makeDir("/qalcom/logs") end
    local path = "/qalcom/logs/system.log"
    local file = fs.open(path, "a")
    if file then
        file.writeLine(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. tostring(message))
        file.close()
    end
    -- Avoid rewriting the whole file for every event; prune only after it grows beyond a safe estimate.
    local size = fs.getSize and fs.getSize(path) or 0
    local limit = config.logLimit or 200
    if size > limit * 180 then
        local lines = {}
        local existing = fs.open(path, "r")
        if existing then
            local text = existing.readAll() or ""
            existing.close()
            for line in (text .. "\n"):gmatch("(.-)\n") do
                if line ~= "" then lines[#lines + 1] = line end
            end
        end
        while #lines > limit do table.remove(lines, 1) end
        local compacted = fs.open(path, "w")
        if compacted then
            compacted.write(table.concat(lines, "\n") .. "\n")
            compacted.close()
        end
    end
end

local function recordBootStage(stage)
    state.bootStages[#state.bootStages + 1] = { stage = tostring(stage), at = os.clock() }
    while #state.bootStages > 20 do table.remove(state.bootStages, 1) end
    log("stage " .. tostring(stage))
end

local function recordCrash(task, reason)
    local detail = tostring(reason or task.crashReason or "unknown error")
    state.crashes[#state.crashes + 1] = {
        pid = task.pid,
        name = task.name,
        reason = detail,
        restartCount = task.restartCount or 0,
        at = os.clock(),
    }
    while #state.crashes > 20 do table.remove(state.crashes, 1) end
end

local function notify(message, color)
    local item = {
        message = tostring(message),
        color = color or UI.colors.accent,
        expires = os.clock() + 4,
        offset = math.min(width, 8),
    }
    state.notifications[#state.notifications + 1] = item
    while #state.notifications > 3 do table.remove(state.notifications, 1) end
    UI.animate(item, { offset = 0 }, 0.18, "outQuad")
    state.dirty = true
end

local function runCleanup(task)
    if task.cleanupRan then return end
    task.cleanupRan = true
    for index = #task.cleanups, 1, -1 do
        pcall(task.cleanups[index])
    end
end

local function closeAllTasks()
    for index = #state.tasks, 1, -1 do
        local task = state.tasks[index]
        runCleanup(task)
        if task.window then task.window.setVisible(false) end
        task.co = nil
        task.context = nil
        task.window = nil
        table.remove(state.tasks, index)
    end
    state.focused = nil
    state.drag = nil
end

local function removeTask(task)
    runCleanup(task)
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
            if not candidate.modal and not candidate.minimized and not candidate.hidden then
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
    if not task or task.modal or task.hidden then return end
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

local function focusOtherVisibleTask(exclude)
    state.focused = nil
    for index = #state.tasks, 1, -1 do
        local candidate = state.tasks[index]
        if candidate ~= exclude and not candidate.modal and not candidate.minimized and not candidate.hidden then
            focusTask(candidate)
            return candidate
        end
    end
    return nil
end

local function makeContext(task)
    local context = {
        pid = task.pid,
        name = task.name,
        title = task.meta.title,
        user = state.user,
        role = state.role,
        safeMode = config.safeMode == true,
        modifiers = state.modifiers,
        win = task.window,
        declaredCapabilities = Capabilities.namesFor(task.name),
        capabilities = (function()
            local approved = {}
            for _, capability in ipairs(Capabilities.namesFor(task.name)) do
                if Capabilities.effective(state.role, task.name, capability, config.safeMode) then approved[#approved + 1] = capability end
            end
            return approved
        end)(),
        manifest = Capabilities.manifest(task.name),
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
                return unpack(event)
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

    function context:registerCleanup(callback)
        if type(callback) == "function" then
            task.cleanups[#task.cleanups + 1] = callback
            return true
        end
        return false
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

    function context:hasCapability(name)
        return Capabilities.effective(state.role, task.name, name, config.safeMode)
    end

    function context:policy(name)
        return Capabilities.policy(state.role, task.name, name, config.safeMode)
    end

    function context:isSafeMode()
        return config.safeMode == true
    end

    function context:refreshCapabilities()
        self.safeMode = config.safeMode == true
        self.capabilities = {}
        for _, capability in ipairs(self.declaredCapabilities or {}) do
            if Capabilities.effective(state.role, task.name, capability, config.safeMode) then
                self.capabilities[#self.capabilities + 1] = capability
            end
        end
    end

    function context:accounts()
        if state.role ~= Roles.legacyAdministrator then return {} end
        local accounts = Auth.accounts()
        local result = {}
        for _, account in ipairs(accounts) do
            result[#result + 1] = { username = account.username, role = Roles.normalize(account.role) }
        end
        return result
    end

    function context:updateAccountRole(username, role)
        local decision = Capabilities.policy(state.role, task.name, "account.manage", config.safeMode)
        if not decision.allowed then
            Capabilities.auditRoleChange(state.user, state.role, username, nil, role, "denial", "policy")
            return false, decision.reason
        end
        local ok, result, previousRole = Auth.updateRole(username, role, state.role, state.user)
        if not ok then
            Capabilities.auditRoleChange(state.user, state.role, username, nil, role, "denial", tostring(result))
            return false, result
        end
        Capabilities.auditRoleChange(state.user, state.role, username, previousRole, role, "approval")
        return true, result
    end

    function context:audit(action, detail)
        Capabilities.audit(task.name .. "." .. tostring(action), detail)
    end

    function context:requestPower(action)
        local capability = action == "reboot" and "system.reboot" or action == "shutdown" and "system.shutdown"
        local decision = capability and Capabilities.policy(state.role, task.name, capability, config.safeMode) or nil
        if not decision or not decision.allowed then
            local deniedDecision = decision or { role = state.role, capability = capability, allowed = false, reason = "unknown power action" }
            Capabilities.auditDecision(deniedDecision, state.user, "power request action=" .. tostring(action) .. " safeMode=" .. tostring(config.safeMode), "denial")
            notify("Capability denied: " .. tostring(capability or action), UI.colors.danger)
            return false
        end
        if action ~= "reboot" and action ~= "shutdown" then return false end
        local task = spawn("dialog", {
            modal = true,
            dialogTitle = action == "reboot" and "Confirm reboot" or "Confirm shutdown",
            dialogMessage = "Close Qalcom and " .. action .. " this computer?",
        })
        if not task then return false end
        task.context.dialogCallback = function()
            Capabilities.auditDecision(decision, state.user, "confirmed " .. action)
            os.queueEvent("qalcom_power_confirmed", action)
            return true
        end
        task.context.dialogCancelCallback = function()
            Capabilities.auditDecision(decision, state.user, "cancelled " .. action, "cancelled")
        end
        return true
    end

    function context:readPath(path)
        return Managed.pathInfo(self, path)
    end

    function context:listDirectory(path)
        return Managed.listDirectory(self, path)
    end

    function context:readFile(path)
        return Managed.readFile(self, path)
    end

    function context:writeFile(path, text)
        return Managed.writeFile(self, path, text)
    end

    function context:touch(path)
        return Managed.touch(self, path)
    end

    function context:makeDir(path)
        return Managed.makeDir(self, path)
    end

    function context:deletePath(path)
        return Managed.delete(self, path)
    end

    function context:copyPath(source, destination)
        return Managed.copy(self, source, destination)
    end

    function context:movePath(source, destination)
        return Managed.move(self, source, destination)
    end

    function context:peripheralNames()
        return Managed.peripheralNames(self)
    end

    function context:peripheralType(name)
        return Managed.peripheralType(self, name)
    end

    function context:peripheralMethods(name)
        return Managed.peripheralMethods(self, name)
    end

    function context:peripheralRead(name, method, ...)
        return Managed.peripheralRead(self, name, method, ...)
    end

    function context:peripheralInventory()
        return Managed.peripheralInventory(self)
    end

    function context:peripheralMetadataFile()
        return Managed.peripheralMetadataFile(self)
    end

    function context:writePeripheralMetadata(text)
        return Managed.writePeripheralMetadata(self, text)
    end

    function context:redstoneInput(side)
        return Managed.redstoneInput(self, side)
    end

    function context:redstoneOutput(side, value)
        return Managed.redstoneOutput(self, side, value)
    end

    function context:redstoneState(side)
        return Managed.redstoneState(self, side)
    end

    function context:redstoneWrite(side, value)
        return Managed.redstoneWrite(self, side, value)
    end

    function context:infrastructureProfiles()
        local text = self:readFile("/qalcom/data/infrastructure.meta")
        return Infrastructure.parse(text or "")
    end

    function context:writeInfrastructureProfiles(data)
        return self:writeFile("/qalcom/data/infrastructure.meta", Infrastructure.serialize(data))
    end

    function context:infrastructureState(profile)
        return Infrastructure.state(self, profile)
    end

    function context:jobDefinitions()
        local text, reason = self:readFile("/qalcom/data/jobs.meta")
        local data = Jobs.parse(text or "")
        if not text and reason then data.error = reason end
        return data
    end

    function context:writeJobDefinitions(data)
        return self:writeFile("/qalcom/data/jobs.meta", Jobs.serialize(data))
    end

    function context:jobInfrastructureProfiles()
        return self:infrastructureProfiles()
    end

    function context:jobInfrastructureState(profile)
        return self:infrastructureState(profile)
    end

    function context:setComputerLabel(label)
        return Managed.setLabel(self, label)
    end

    function context:managedPower(action)
        return Managed.power(self, action)
    end

    function context:freeSpace()
        if not self:hasCapability("fs.read") then
            local reason = "Capability denied: fs.read"
            self:audit("denied", "fs.read free space")
            self:notify(reason, UI.colors.danger)
            return nil, reason
        end
        if not fs.getFreeSpace then return nil, "Free-space reporting unavailable" end
        local ok, value = pcall(fs.getFreeSpace, "/")
        return ok and value or nil, ok and nil or tostring(value)
    end

    function context:systemDiagnostics()
        local diagnostics = { bootStages = {}, crashes = {} }
        for index, stage in ipairs(state.bootStages) do
            diagnostics.bootStages[index] = { stage = stage.stage, at = stage.at }
        end
        for index, crash in ipairs(state.crashes) do
            diagnostics.crashes[index] = {
                pid = crash.pid,
                name = crash.name,
                reason = crash.reason,
                restartCount = crash.restartCount,
                at = crash.at,
            }
        end
        return diagnostics
    end

    function context:systemInfo()
        local info = System.info(self)

        info.user = state.user
        info.role = state.role
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
                restartLocked = candidate.restartLocked,
                capabilities = Capabilities.namesFor(candidate.name),
                approvedCapabilities = (function()
                    local approved = {}
                    for _, capability in ipairs(Capabilities.namesFor(candidate.name)) do
                        if Capabilities.effective(state.role, candidate.name, capability, config.safeMode) then approved[#approved + 1] = capability end
                    end
                    return approved
                end)(),
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
                local restartCount = candidate.restartCount or 0
                if restartCount >= MAX_MANUAL_RESTARTS then
                    candidate.restartLocked = true
                    state.dirty = true
                    return false, "Restart limit reached"
                end
                options.restartCount = restartCount + 1
                removeTask(candidate)
                return spawn(name, options)
            end
        end
        return nil
    end

    return context
end

local function recordRecentApp(name)
    for index = #state.recentApps, 1, -1 do
        if state.recentApps[index] == name then table.remove(state.recentApps, index) end
    end
    table.insert(state.recentApps, 1, name)
    while #state.recentApps > 6 do table.remove(state.recentApps) end
end

local function startTask(name, options)
    local meta = APP_META[name]
    local path = APP_PATHS[name]
    if config.safeMode and name ~= "recovery" and name ~= "logs" and name ~= "terminal" and name ~= "calculator" and name ~= "settings" and name ~= "peripherals" and name ~= "infrastructure" and name ~= "jobs" and name ~= "jobs_service" then
        notify("Safe Mode blocked " .. tostring(name), UI.colors.warning)
        return nil
    end
    if not meta or not path or not fs.exists(path) then
        notify("Application unavailable: " .. tostring(name), UI.colors.danger)
        Capabilities.audit("launch-denied", name .. " unavailable")
        return nil
    end
    Capabilities.audit("launch", name)

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
        restartLocked = false,
        startedAt = os.clock(),
        lastEventAt = os.clock(),
        eventCount = 0,
        options = options or {},
        session = state.session,
        lastRunDuration = 0,
        watchdog = nil,
        watchdogSince = nil,
        cleanups = {},
        cleanupRan = false,
        hidden = (options and options.hidden) == true or meta.hidden == true,
        maximized = false,
        restoreGeometry = nil,
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
    task.window.setVisible(not task.hidden)
    local resumed, err = coroutine.resume(task.co)
    if not resumed then
        task.failed = tostring(err)
    end
    if task.failed then
        task.state = "crashed"
        task.restartLocked = task.restartCount >= MAX_MANUAL_RESTARTS
        task.crashReason = task.failed
        recordCrash(task, task.failed)
        log("app failure " .. name .. ": " .. task.failed)
        notify(meta.title .. " failed to start", UI.colors.danger)
        state.dirty = true
        return task
    end
    task.state = "running"
    if options and options.fromLauncher then recordRecentApp(name) end
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
    local ok, err = coroutine.resume(task.co, unpack(event))
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
        runCleanup(task)
        task.state = "crashed"
        task.restartLocked = task.restartCount >= MAX_MANUAL_RESTARTS
        task.crashReason = task.failed
        recordCrash(task, task.failed)
        log("app failure " .. task.name .. ": " .. task.failed)
        notify(APP_META[task.name].title .. " stopped; open Control Center to restart", UI.colors.danger)
        if not task.hidden then task.window.setVisible(true) end
        task.minimized = false
        task.closeRequested = false
    elseif coroutine.status(task.co) == "dead" then
        task.state = "stopped"
        task.closeRequested = true
    else
        task.state = "running"
    end
end

local launcherGeometry

local function drawDesktop()
    width, height = native.getSize()
    native.setBackgroundColor(UI.colors.desktop)
    native.setTextColor(colors.white)
    native.clear()

    UI.desktopBackground(native, width, height)

    for _, task in ipairs(state.tasks) do
        local focused = task == state.focused
        if not task.minimized and not task.hidden then
            -- Keep the frame flush with its content; no shadow may protrude into
            -- neighboring windows or the taskbar.
            UI.fill(native, task.x, task.y, task.width, task.height, colors.white)
            UI.titleBar(native, task.x, task.y, task.width, task.meta.title, task.meta.icon, focused, task.maximized)
            if task.failed then
                task.window.setBackgroundColor(colors.black)
                task.window.setTextColor(colors.white)
                task.window.clear()
                UI.text(task.window, 2, 2, "Application stopped", colors.red, colors.black, task.width - 5)
                UI.text(task.window, 2, 4, "Open Control Center", colors.yellow, colors.black, task.width - 5)
                UI.text(task.window, 2, 5, "to restart this process", colors.yellow, colors.black, task.width - 5)
            else
                -- Normalize the shared body surface before each app redraw;
                -- individual screens may still choose their own text colors.
                task.window.setBackgroundColor(colors.white)
                task.window.redraw()
            end
        end
    end

    local now = os.clock()
    for _, task in ipairs(state.tasks) do
        if task.failed and not task.hidden then
            task.window.setVisible(true)
        end
    end
    for index = #state.notifications, 1, -1 do
        if state.notifications[index].expires < now then table.remove(state.notifications, index) end
    end
    for index, item in ipairs(state.notifications) do
        local boxWidth = math.min(width - 4, math.max(18, #item.message + 4))
        local x = math.max(1, math.min(width - boxWidth + 1, width - boxWidth + 1 + math.floor(item.offset or 0)))
        local y = 2 + (index - 1) * 2
        UI.fill(native, x, y, boxWidth, 1, item.color)
        UI.text(native, x + 1, y, item.message, colors.white, item.color, boxWidth - 2)
    end

    if state.launcher then
        local menuX, menuY, menuWidth, menuHeight, visibleCount, items, start = launcherGeometry()
        UI.shadow(native, menuX, menuY, menuWidth, menuHeight, 1, UI.colors.shadow)
        UI.panel(native, menuX, menuY, menuWidth, menuHeight, UI.colors.surface, UI.colors.borderStrong)
        UI.fill(native, menuX + 1, menuY + 1, menuWidth - 2, 1, UI.colors.accent)
        UI.text(native, menuX + 2, menuY + 1, "Q  Qalcom", colors.white, UI.colors.accent, menuWidth - 4)
        UI.text(native, menuX + menuWidth - 11, menuY + 1, tostring(state.user or "-"), UI.colors.lightBlue, UI.colors.accent, 9)

        local searchBackground = state.launcherSearchFocused and UI.colors.accentLight or UI.colors.surfaceAlt
        local searchForeground = state.launcherSearchFocused and colors.white or UI.colors.text
        UI.fill(native, menuX + 2, menuY + 2, menuWidth - 4, 1, searchBackground)
        local searchText = state.launcherSearch == "" and "Search programs" or state.launcherSearch
        if state.launcherSearchFocused and state.launcherSearch ~= "" then searchText = searchText .. "_" end
        UI.text(native, menuX + 3, menuY + 2, searchText, searchForeground, searchBackground, menuWidth - 6)

        local heading = state.launcherSearch == "" and (#state.recentApps > 0 and "Recent apps" or "All apps") or "Search results"
        UI.text(native, menuX + 2, menuY + 3, heading, UI.colors.muted, UI.colors.surface, menuWidth - 4)
        if #items == 0 then
            UI.text(native, menuX + 3, menuY + 4, "No matching programs", UI.colors.muted, UI.colors.surface, menuWidth - 6)
        else
            for offset = 1, visibleCount do
                local index = start + offset - 1
                local name = items[index]
                if name then
                    local itemY = menuY + 3 + offset
                    local active = index == state.launcherSelection
                    local background = active and UI.colors.accentLight or UI.colors.surface
                    local foreground = active and colors.white or UI.colors.text
                    UI.fill(native, menuX + 2, itemY, menuWidth - 4, 1, background)
                    UI.text(native, menuX + 4, itemY, APP_META[name].icon .. "  " .. APP_META[name].title, foreground, background, menuWidth - 8)
                end
            end
        end
    end

    local barY = math.max(1, height - 2)
    UI.taskbar(native, width, barY, state.tasks, state.focused, state.launcher, 15, state.mouseX, state.mouseY)
end

local function hitTask(x, y)
    for index = #state.tasks, 1, -1 do
        local task = state.tasks[index]
        if not task.hidden and x >= task.x and x < task.x + task.width and y >= task.y and y < task.y + task.height then
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

local function launcherItems()
    local query = string.lower(tostring(state.launcherSearch or ""))
    local items = {}
    local seen = {}
    local function add(name)
        if not seen[name] and APP_META[name] and (query == "" or string.find(string.lower(name), query, 1, true) or string.find(string.lower(APP_META[name].title), query, 1, true)) then
            seen[name] = true
            items[#items + 1] = name
        end
    end
    if query == "" then
        for _, name in ipairs(state.recentApps) do
            for _, allowed in ipairs(LAUNCHER_APPS) do
                if name == allowed then add(name) break end
            end
        end
        -- Once an app has been used, keep the Start menu focused on recent
        -- programs; the search field remains the way to reach every app.
        if #items == 0 then
            for _, name in ipairs(LAUNCHER_APPS) do add(name) end
        end
    else
        for _, name in ipairs(LAUNCHER_APPS) do add(name) end
    end
    return items
end

launcherGeometry = function()
    local items = launcherItems()
    local menuWidth = math.min(38, width - 2)
    local barY = math.max(1, height - 2)
    local menuHeight = math.min(barY - 1, math.max(7, math.min(#items + 5, height - 2)))
    local visibleCount = math.max(1, menuHeight - 4)
    local menuX = 1
    -- Leave a clean gap between the menu shadow and the three-row taskbar.
    local menuY = math.max(1, barY - menuHeight - 1)
    if #items > 0 then
        state.launcherSelection = math.max(1, math.min(state.launcherSelection, #items))
    else
        state.launcherSelection = 1
    end
    local start = math.max(1, math.min(state.launcherSelection - visibleCount + 1, math.max(1, #items - visibleCount + 1)))
    return menuX, menuY, menuWidth, menuHeight, visibleCount, items, start
end

local function handleLauncherClick(x, y)
    local menuX, menuY, menuWidth, menuHeight, visibleCount, items, start = launcherGeometry()
    if x < menuX or x >= menuX + menuWidth or y < menuY or y >= menuY + menuHeight then return false end
    if y == menuY + 2 then
        state.launcherSearchFocused = true
        state.dirty = true
        return true
    end
    local index = y - (menuY + 3)
    local actual = start + index - 1
    if index >= 1 and index <= visibleCount and items[actual] then
        state.launcherSelection = actual
        state.launcher = false
        state.launcherSearch = ""
        spawn(items[actual], { fromLauncher = true })
    end
    return true
end

local function handleMouse(button, x, y)
    if state.launcher then
        if handleLauncherClick(x, y) then
            state.dirty = true
            return
        end
        -- Match the normal Start-menu behavior: clicking outside dismisses it,
        -- while the original click can still focus a taskbar item or window.
        state.launcher = false
        state.launcherSearch = ""
        state.launcherSearchFocused = true
        state.dirty = true
    end
    if y >= height - 2 then
        if activeModal() then return end
        local items = UI.taskbarLayout(width, state.tasks, 15)
        for _, item in ipairs(items) do
            if x >= item.x and x < item.x + item.width then
                if item.kind == "start" then
                    state.launcher = not state.launcher
                    state.launcherSelection = 1
                    state.launcherSearch = ""
                    state.launcherSearchFocused = true
                elseif item.kind == "overflow" then
                    state.launcher = true
                    state.launcherSelection = 1
                    state.launcherSearch = ""
                    state.launcherSearchFocused = true
                elseif item.task then
                    local task = item.task
                    if task.minimized then
                        -- A second click restores a minimized task, matching the
                        -- familiar taskbar toggle behavior.
                        task.minimized = false
                        task.window.setVisible(true)
                        focusTask(task)
                    elseif task == state.focused then
                        -- Clicking the active task button minimizes its window
                        -- instead of opening another app-name action/tooltip.
                        task.minimized = true
                        task.window.setVisible(false)
                        focusOtherVisibleTask(task)
                    else
                        focusTask(task)
                    end
                end
                state.dirty = true
                return
            end
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
    if y == task.y and x == task.x + 1 then
        removeTask(task)
        return
    end
    if y == task.y and x == task.x + 3 then
        task.minimized = true
        task.window.setVisible(false)
        if state.focused == task then focusOtherVisibleTask(task) end
        state.dirty = true
        return
    end
    if y == task.y and x == task.x + 5 then
        if task.maximized then
            local restore = task.restoreGeometry
            if restore then
                task.x, task.y = restore.x, restore.y
                task.width, task.height = restore.width, restore.height
                task.window.reposition(task.x + 1, task.y + 1, task.width - 2, task.height - 2)
            end
            task.maximized = false
            task.restoreGeometry = nil
        else
            task.restoreGeometry = { x = task.x, y = task.y, width = task.width, height = task.height }
            task.x, task.y = 2, 2
            task.width, task.height = math.max(20, width - 2), math.max(8, height - 4)
            task.window.reposition(task.x + 1, task.y + 1, task.width - 2, task.height - 2)
            task.maximized = true
        end
        state.dirty = true
        return
    end
    if y == task.y and x >= task.x + 7 then
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
        state.mouseX, state.mouseY = event[3], event[4]
        handleMouse(event[2], event[3], event[4])
    elseif name == "mouse_move" then
        state.mouseX, state.mouseY = event[2], event[3]
        state.dirty = true
    elseif name == "mouse_drag" then
        state.mouseX, state.mouseY = event[3], event[4]
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
        state.mouseX, state.mouseY = event[3], event[4]
        state.drag = nil
        if state.focused then
            local task = state.focused
            send(task, { name, event[2], event[3] - task.x, event[4] - task.y })
        end
    elseif name == "mouse_scroll" then
        state.mouseX, state.mouseY = event[3] or state.mouseX, event[4] or state.mouseY
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
        if state.launcher then
            if name == "char" and state.launcherSearchFocused then
                state.launcherSearch = state.launcherSearch .. tostring(event[2] or "")
                state.launcherSelection = 1
                state.dirty = true
                return
            elseif name == "paste" and state.launcherSearchFocused then
                state.launcherSearch = state.launcherSearch .. tostring(event[2] or "")
                state.launcherSelection = 1
                state.dirty = true
                return
            elseif name == "key" then
                local items = launcherItems()
                if event[2] == keys.backspace and state.launcherSearchFocused then
                    state.launcherSearch = state.launcherSearch:sub(1, math.max(0, #state.launcherSearch - 1))
                    state.launcherSelection = 1
                    state.dirty = true
                    return
                elseif event[2] == keys.up then
                    state.launcherSelection = math.max(1, state.launcherSelection - 1)
                    state.dirty = true
                    return
                elseif event[2] == keys.down then
                    state.launcherSelection = math.min(math.max(1, #items), state.launcherSelection + 1)
                    state.dirty = true
                    return
                elseif event[2] == keys.enter then
                    local selected = items[state.launcherSelection]
                    if selected then
                        state.launcher = false
                        state.launcherSearch = ""
                        spawn(selected, { fromLauncher = true })
                    end
                    return
                elseif event[2] == keys.escape then
                    state.launcher = false
                    state.launcherSearch = ""
                    state.launcherSearchFocused = true
                    state.dirty = true
                    return
                end
            end
            return
        end
        if state.focused then send(state.focused, event) end
    elseif name == "timer" or name == "alarm" or name == "redstone" or name == "term_resize" or name == "peripheral" or name == "peripheral_detach" or name == "disk" or name == "disk_eject" or name == "rednet_message" or name == "modem_message" then
        for _, task in ipairs(state.tasks) do send(task, event) end
    elseif name == "qalcom_config_changed" then
        config = Config.load()
        Config.apply(UI, config)
        for _, task in ipairs(state.tasks) do
            if task.context and task.context.refreshCapabilities then task.context:refreshCapabilities() end
        end
        LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
        if config.safeMode then
            for _, task in ipairs(state.tasks) do
                if task.name ~= "recovery" and task.name ~= "logs" and task.name ~= "terminal" and task.name ~= "settings" and task.name ~= "peripherals" and task.name ~= "infrastructure" and task.name ~= "jobs" and task.name ~= "jobs_service" then
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

recordBootStage("kernel loaded")
log("boot Qalcom OS " .. VERSION)
local authenticated = Auth.login(native, UI, VERSION)
if not authenticated then
    return
end
state.session = state.session + 1
state.user = authenticated.username
state.role = Roles.normalize(authenticated.role, true)
recordBootStage("desktop authenticated")
log("login success: " .. state.user)
Capabilities.audit("login", state.user)
if config.safeMode then notify("Safe Mode enabled", UI.colors.warning) end
notify("Welcome, " .. state.user, UI.colors.accent)
spawn("jobs_service", { hidden = true })
state.clockTimer = os.startTimer(1)
state.uiTimer = os.startTimer(0.1)
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
    elseif event[1] == "timer" and event[2] == state.uiTimer then
        state.uiTimer = os.startTimer(0.1)
        if UI.tick() then state.dirty = true end
    elseif event[1] == "terminate" then
        state.modifiers.alt = false
        state.modifiers.ctrl = false
        state.modifiers.shift = false
        notify("Ctrl+T is handled by Qalcom; close apps from their title bars.", UI.colors.warning)
        state.dirty = true
    elseif event[1] == "qalcom_power_confirmed" then
        closeAllTasks()
        recordBootStage("power " .. tostring(event[2]))
        if event[2] == "reboot" then os.reboot() else os.shutdown() end
    elseif event[1] == "qalcom_logout" then
        closeAllTasks()
        state.launcher = false
        state.launcherSearch = ""
        state.launcherSearchFocused = true
        state.user = nil
        state.role = nil
        state.modifiers.alt = false
        state.modifiers.ctrl = false
        state.modifiers.shift = false
        Capabilities.audit("boot", VERSION)
    local authenticated = Auth.login(native, UI, VERSION)
        if not authenticated then return end
        state.session = state.session + 1
        state.user = authenticated.username
        state.role = Roles.normalize(authenticated.role, true)
        recordBootStage("desktop reauthenticated")
        config = Config.load()
        Config.apply(UI, config)
        for _, task in ipairs(state.tasks) do
            if task.context and task.context.refreshCapabilities then task.context:refreshCapabilities() end
        end
        LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
        log("login success: " .. state.user)
        Capabilities.audit("login", state.user)
        if config.safeMode then notify("Safe Mode enabled", UI.colors.warning) end
        notify("Welcome, " .. state.user, UI.colors.accent)
        spawn("jobs_service", { hidden = true })
        state.clockTimer = os.startTimer(1)
        state.uiTimer = os.startTimer(0.1)
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
            local minimumWidth = math.max(20, width - 2)
            local minimumHeight = math.max(8, height - 4)
            task.width = math.min(task.width, minimumWidth)
            task.height = math.min(task.height, minimumHeight)
            task.x = math.max(2, math.min(task.x, width - task.width))
            task.y = math.max(2, math.min(task.y, height - task.height - 2))
            if task.restoreGeometry then
                task.restoreGeometry.width = math.min(task.restoreGeometry.width, minimumWidth)
                task.restoreGeometry.height = math.min(task.restoreGeometry.height, minimumHeight)
                task.restoreGeometry.x = math.max(2, math.min(task.restoreGeometry.x, width - task.restoreGeometry.width))
                task.restoreGeometry.y = math.max(2, math.min(task.restoreGeometry.y, height - task.restoreGeometry.height - 2))
            end
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
