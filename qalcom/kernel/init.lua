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
local Network = dofile("/qalcom/lib/network.lua")
local unpack = table.unpack or unpack
local config = Config.load()
Config.apply(UI, config)

local function hasMethod(methods, wanted)
    for _, method in ipairs(methods or {}) do if method == wanted then return true end end
    return false
end

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
    network = "/qalcom/apps/network.lua",
    telemetry = "/qalcom/apps/telemetry.lua",
    network_service = "/qalcom/apps/network_service.lua",
    incidents = "/qalcom/apps/incidents.lua",
    cannon = "/qalcom/apps/cannon.lua",
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
    network = { title = "Network Manager", icon = "N", x = 3, y = 3, width = 56, height = 21 },
    telemetry = { title = "Operations Telemetry", icon = "T", x = 3, y = 3, width = 56, height = 21 },
    network_service = { title = "Network Service", icon = "N", x = 3, y = 3, width = 20, height = 8, service = true, hidden = true },
    incidents = { title = "Incident Response", icon = "!", x = 3, y = 3, width = 56, height = 21 },
    cannon = { title = "CBC Fire Control", icon = "C", x = 3, y = 3, width = 56, height = 21 },
}

local APP_CATEGORIES = {
    terminal = "System", explorer = "Files", calculator = "Tools", monitor = "System",
    peripherals = "Operations", telemetry = "Operations", incidents = "Response", cannon = "Defense",
    network = "Network", infrastructure = "Control", jobs = "Automation", control = "System",
    capabilities = "Security", settings = "System", recovery = "Recovery", logs = "System", account = "Account",
}

local NORMAL_LAUNCHER_APPS = { "terminal", "explorer", "calculator", "monitor", "peripherals", "telemetry", "incidents", "cannon", "network", "infrastructure", "jobs", "control", "capabilities", "settings", "recovery", "logs", "account" }
local SAFE_LAUNCHER_APPS = { "recovery", "logs", "terminal", "calculator", "settings", "peripherals", "telemetry", "network", "infrastructure", "jobs" }
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
    -- dirty means the whole terminal must be repainted (clear + everything).
    -- The region flags below repaint only the taskbar or the notification
    -- boxes without ever touching window content.
    dirty = true,
    taskbarDirty = false,
    notificationsDirty = false,
    mouseInTaskbar = false,
    notificationRects = {},
    nextNotificationExpiry = nil,
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
    local notificationColor = color or UI.colors.accent
    local severity = notificationColor == UI.colors.danger and "danger"
        or notificationColor == UI.colors.warning and "warning"
        or notificationColor == UI.colors.success and "success"
        or "info"
    local item = {
        message = tostring(message),
        color = notificationColor,
        severity = severity,
        expires = os.clock() + (severity == "danger" and 8 or severity == "warning" and 6 or 4),
        offset = math.min(width, 8),
    }
    state.notifications[#state.notifications + 1] = item
    while #state.notifications > 3 do table.remove(state.notifications, 1) end
    UI.animate(item, { offset = 0 }, 0.18, "outQuad")
    state.nextNotificationExpiry = math.min(state.nextNotificationExpiry or math.huge, item.expires)
    -- Notifications live in their own region; no need to clear the desktop.
    state.notificationsDirty = true
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

local function redrawTitlebar(task)
    -- The titlebar row belongs to the frame on the native terminal, so it can
    -- be repainted in place without touching the window's content buffer.
    if not task or task.minimized or task.hidden then return end
    UI.titleBar(native, task.x, task.y, task.width, task.meta.title, task.meta.icon, task == state.focused, task.maximized)
end

local function flushWindow(task)
    -- Repaint one window's frame and content from its own buffer: the same
    -- work the full repaint performs for every visible task.
    if not task or task.minimized or task.hidden then return end
    local surface = UI.colors.surface or colors.white
    local textColor = UI.colors.text or colors.black
    UI.fill(native, task.x, task.y, task.width, task.height, surface)
    UI.titleBar(native, task.x, task.y, task.width, task.meta.title, task.meta.icon, task == state.focused, task.maximized)
    if task.failed then
        local failureSurface = UI.colors.surfaceMuted or UI.colors.surfaceAlt or colors.black
        local failureText = UI.colors.textInverse or colors.white
        task.window.setBackgroundColor(failureSurface)
        task.window.setTextColor(failureText)
        task.window.clear()
        UI.text(task.window, 2, 2, "Application stopped", UI.colors.danger, failureSurface, task.width - 5)
        UI.text(task.window, 2, 4, "Open Control Center", UI.colors.warning, failureSurface, task.width - 5)
        UI.text(task.window, 2, 5, "to restart this process", UI.colors.warning, failureSurface, task.width - 5)
    else
        -- Normalize the shared body surface before each app redraw; individual
        -- screens may still choose their own text colors.
        task.window.setBackgroundColor(surface)
        task.window.setTextColor(textColor)
        task.window.redraw()
    end
end

local function restoreRegion(x, y, width, height)
    -- The launcher is chrome drawn over windows; restoring underneath it would
    -- erase its panel and nothing here redraws it, so escalate to a full
    -- repaint when the region touches an open launcher. This is rare (the
    -- launcher is transient) and only happens while it is actually open.
    if state.launcher and state.launcherRect then
        local rect = state.launcherRect
        if x < rect.x + rect.w and x + width > rect.x and y < rect.y + rect.h and y + height > rect.y then
            state.dirty = true
            return
        end
    end
    -- Re-establish the desktop underneath a chrome layer (notification boxes,
    -- a just-moved window): paint the desktop color across the region, then
    -- flush any windows overlapping it from back to front so their buffers
    -- repaint the correct pixels on top.
    UI.fill(native, x, y, width, height, UI.colors.desktop)
    for _, task in ipairs(state.tasks) do
        if not task.minimized and not task.hidden then
            if x < task.x + task.width and x + width > task.x
                and y < task.y + task.height and y + height > task.y then
                flushWindow(task)
            end
        end
    end
end

local function notificationsOverlap(x, y, width, height)
    for _, rect in ipairs(state.notificationRects or {}) do
        if x < rect.x + rect.w and x + width > rect.x and y < rect.y + rect.h and y + height > rect.y then
            return true
        end
    end
    return false
end

local function moveWindow(task, newX, newY, newWidth, newHeight, repaint)
    if not task or not task.window then return false end
    local oldX, oldY = task.x, task.y
    local oldWidth, oldHeight = task.width, task.height
    newX = tonumber(newX) or oldX
    newY = tonumber(newY) or oldY
    newWidth = tonumber(newWidth) or oldWidth
    newHeight = tonumber(newHeight) or oldHeight
    -- Leave room for the frame and content window. Current callers already
    -- provide larger bounded dimensions, but reject malformed future requests
    -- before changing task state or passing invalid sizes to CC:T.
    if newWidth < 3 or newHeight < 3 then return false end
    if oldX == newX and oldY == newY and oldWidth == newWidth and oldHeight == newHeight then
        return false
    end

    task.x, task.y = newX, newY
    task.width, task.height = newWidth, newHeight
    -- Reposition before any targeted restore. Otherwise restoreRegion can
    -- flush this window's buffer through its old terminal mapping, recreating
    -- the smear that this helper is intended to prevent.
    task.window.reposition(newX + 1, newY + 1, newWidth - 2, newHeight - 2)
    if repaint == false then return true end

    -- Restore both sides of the move: the old rectangle may expose desktop or
    -- lower windows, while the new rectangle may cover windows and chrome.
    restoreRegion(oldX, oldY, oldWidth, oldHeight)
    restoreRegion(newX, newY, newWidth, newHeight)
    if notificationsOverlap(oldX, oldY, oldWidth, oldHeight)
        or notificationsOverlap(newX, newY, newWidth, newHeight) then
        state.notificationsDirty = true
    end
    return true
end

local function focusTask(task)
    if not task or task.modal or task.hidden then return end
    local previous = state.focused
    local index
    for candidateIndex, candidate in ipairs(state.tasks) do
        if candidate == task then index = candidateIndex; break end
    end
    if not index then
        -- A newly spawned task: the full repaint that follows a launch draws it.
        state.focused = task
        return
    end
    table.remove(state.tasks, index)
    state.tasks[#state.tasks + 1] = task
    state.focused = task
    if previous == task and index == #state.tasks then
        -- Already focused and already on top; nothing visible changed.
        return
    end
    -- Raising a window only changes what is on top: dim the old titlebar,
    -- repaint the raised window (frame + content) and the taskbar underline
    -- instead of clearing the whole terminal. If either repaint covered a
    -- notification box, the boxes are redrawn on top afterwards.
    if previous and previous ~= task then redrawTitlebar(previous) end
    flushWindow(task)
    state.taskbarDirty = true
    if notificationsOverlap(task.x, task.y, task.width, task.height)
        or (previous and notificationsOverlap(previous.x, previous.y, previous.width, previous.height)) then
        state.notificationsDirty = true
    end
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

local function minimizeTask(task)
    -- Hide the window, restore the area it vacated (desktop plus any windows
    -- underneath it, in z-order), refresh the taskbar underline, and hand
    -- focus to the next visible task -- all without clearing the terminal.
    if not task or task.minimized then return end
    task.minimized = true
    task.window.setVisible(false)
    restoreRegion(task.x, task.y, task.width, task.height)
    if notificationsOverlap(task.x, task.y, task.width, task.height) then
        state.notificationsDirty = true
    end
    if state.focused == task then focusOtherVisibleTask(task) end
    state.taskbarDirty = true
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
        state.notificationsDirty = true
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

    function context:cannonControl(name, method, ...)
        return Managed.cannonControl(self, name, method, ...)
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

    function context:networkConfig()
        local text = self:readFile("/qalcom/data/network.meta")
        return Network.parseConfig(text or "", "computer-" .. tostring(os.getComputerID()))
    end

    function context:writeNetworkConfig(data)
        if not self:hasCapability("network.configure") then return false, "Network configuration denied" end
        return self:writeFile("/qalcom/data/network.meta", Network.serializeConfig(data))
    end

    function context:networkConfigFile()
        return self:readFile("/qalcom/data/network.meta")
    end

    function context:networkNodes()
        local text = self:readFile("/qalcom/data/nodes.meta")
        return Network.parseNodes(text or "")
    end

    function context:writeNetworkNodes(data)
        if not self:hasCapability("network.pair") then return false, "Node enrollment denied" end
        return self:writeFile("/qalcom/data/nodes.meta", Network.serializeNodes(data))
    end

    function context:writeIncidentData(data)
        if not self:hasCapability("incident.manage") then return false, "Incident management denied" end
        if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
        local file = fs.open("/qalcom/data/incidents.meta", "w")
        if not file then return false, "Unable to save incident records" end
        local ok, reason = pcall(file.write, dofile("/qalcom/lib/incidents.lua").serialize(data))
        pcall(file.close)
        return ok, ok and nil or tostring(reason or "Unable to save incident records")
    end

    function context:networkModems()
        local result = {}
        for _, name in ipairs(self:peripheralNames() or {}) do
            if self:peripheralType(name) == "modem" then result[#result + 1] = name end
        end
        return result
    end

    function context:modemOpen(name, channel)
        if not self:hasCapability("network.receive") then return false, "Network receive denied" end
        local methods = self:peripheralMethods(name)
        if not hasMethod(methods, "open") then return false, "Modem open unavailable" end
        local wrapped = peripheral.wrap(name)
        local ok = wrapped and pcall(wrapped.open, channel)
        return ok == true
    end

    function context:modemTransmit(name, channel, replyChannel, payload)
        if not self:hasCapability("network.send") then return false, "Network send denied" end
        local methods = self:peripheralMethods(name)
        if not hasMethod(methods, "transmit") then return false, "Modem transmit unavailable" end
        local wrapped = peripheral.wrap(name)
        if not wrapped then return false, "Modem unavailable" end
        local ok, reason = pcall(wrapped.transmit, channel, replyChannel, payload)
        return ok, ok and nil or tostring(reason or "Modem transmit failed")
    end

    function context:writeNetworkServiceFile(path, text)
        if task.name ~= "network_service" then return false, "Network service persistence is restricted" end
        if path ~= "/qalcom/data/network.state" and path ~= "/qalcom/data/network.audit" and path ~= "/qalcom/data/nodes.meta" then return false, "Network service path is restricted" end
        if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
        local file = fs.open(path, "w")
        if not file then return false, "Unable to persist network state" end
        local ok, reason = pcall(file.write, tostring(text or ""))
        pcall(file.close)
        return ok, ok and nil or tostring(reason or "Unable to persist network state")
    end

    function context:telemetrySnapshot()
        local Peripherals = dofile("/qalcom/lib/peripherals.lua")
        local Telemetry = dofile("/qalcom/lib/telemetry.lua")
        local text = self:peripheralMetadataFile()
        local metadata = Peripherals.parseMetadata(text or "")
        local devices = Peripherals.inspect(self, metadata, os.clock())
        return Telemetry.snapshot(self, devices, os.clock())
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

    function context:writeJobServiceFile(path, text)
        if task.name ~= "jobs_service" then return false, "Automation service persistence is restricted" end
        if path ~= "/qalcom/data/jobs.history" and path ~= "/qalcom/data/jobs.status" then return false, "Automation service path is restricted" end
        if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
        local file = fs.open(path, "w")
        if not file then return false, "Unable to persist automation state" end
        local ok, reason = pcall(file.write, tostring(text or ""))
        pcall(file.close)
        return ok, ok and nil or tostring(reason or "Unable to persist automation state")
    end

    function context:disableAutomationJobs()
        local path = "/qalcom/data/jobs.meta"
        if not fs.exists(path) then return true end
        local input = fs.open(path, "r")
        if not input then return false, "Unable to read job definitions" end
        local text = input.readAll() or ""
        input.close()
        local data = Jobs.parse(text)
        if data.error then return false, data.error end
        local valid, validation = Jobs.dataValid(data)
        if not valid then return false, validation end
        for _, job in ipairs(data.jobs or {}) do job.paused = true end
        local output = fs.open(path, "w")
        if not output then return false, "Unable to save paused job definitions" end
        local ok, reason = pcall(output.write, Jobs.serialize(data))
        pcall(output.close)
        if not ok then return false, tostring(reason or "Unable to save paused job definitions") end
        Capabilities.audit("jobs-emergency-stop", tostring(self.user or "unknown") .. " recovery")
        os.queueEvent("qalcom_job_reload")
        return true
    end

    function context:jobStatus()
        local text, reason = self:readFile("/qalcom/data/jobs.status")
        local statuses = Jobs.parseStatus(text or "")
        return {
            statuses = statuses,
            summary = Jobs.statusSummary(statuses),
            error = (not text and reason) or nil,
        }
    end

    function context:reloadJobs()
        os.queueEvent("qalcom_job_reload")
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
        info.jobs = self:jobStatus()
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
    if config.safeMode and name ~= "recovery" and name ~= "logs" and name ~= "terminal" and name ~= "calculator" and name ~= "settings" and name ~= "peripherals" and name ~= "telemetry" and name ~= "incidents" and name ~= "cannon" and name ~= "network" and name ~= "infrastructure" and name ~= "jobs" and name ~= "jobs_service" and name ~= "network_service" then
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
        -- The failure screen is painted by the full repaint, so a crash still
        -- needs the whole desktop redrawn.
        state.dirty = true
    elseif coroutine.status(task.co) == "dead" then
        task.state = "stopped"
        task.closeRequested = true
    else
        task.state = "running"
    end
end

local launcherGeometry

local function drawNotifications()
    -- Repaint the top-right notification boxes in place. The boxes are chrome
    -- drawn over the desktop and possibly windows, so the previous boxes are
    -- restored first; the full-repaint path clears state.notificationRects
    -- beforehand so that step is skipped there.
    for _, rect in ipairs(state.notificationRects or {}) do
        restoreRegion(rect.x, rect.y, rect.w, rect.h)
    end
    state.notificationRects = {}
    state.nextNotificationExpiry = nil
    local now = os.clock()
    for index = #state.notifications, 1, -1 do
        if state.notifications[index].expires < now then table.remove(state.notifications, index) end
    end
    for index, item in ipairs(state.notifications) do
        local boxWidth = math.min(width - 4, math.max(18, #item.message + 4))
        local x = math.max(1, math.min(width - boxWidth + 1, width - boxWidth + 1 + math.floor(item.offset or 0)))
        local y = 2 + (index - 1) * 2
        local marker = item.severity == "danger" and "! " or item.severity == "warning" and "~ " or "i "
        local background = item.color
        UI.fill(native, x, y, boxWidth, 1, background)
        local notificationText = item.severity == "warning" and (UI.colors.warningText or UI.colors.text)
            or item.severity == "success" and (UI.colors.successText or UI.colors.text)
            or item.severity == "danger" and (UI.colors.dangerText or UI.colors.textInverse)
            or (UI.colors.infoText or UI.colors.statusText or UI.colors.textInverse)
        UI.text(native, x + 1, y, marker .. item.message, notificationText, background, boxWidth - 2)
        state.notificationRects[#state.notificationRects + 1] = { x = x, y = y, w = boxWidth, h = 1 }
        if not state.nextNotificationExpiry or item.expires < state.nextNotificationExpiry then
            state.nextNotificationExpiry = item.expires
        end
    end
end

local function drawLauncher()
    local menuX, menuY, menuWidth, menuHeight, visibleCount, items, start = launcherGeometry()
    -- Remember the launcher's on-screen extent (plus its one-cell shadow) so
    -- region restores can escalate to a full repaint instead of erasing it.
    state.launcherRect = { x = menuX, y = menuY, w = menuWidth + 1, h = menuHeight + 1 }
    UI.shadow(native, menuX, menuY, menuWidth, menuHeight, 1, UI.colors.shadow)
    UI.panel(native, menuX, menuY, menuWidth, menuHeight, UI.colors.surface, UI.colors.borderStrong)
    UI.fill(native, menuX + 1, menuY + 1, menuWidth - 2, 1, UI.colors.accent)
    UI.text(native, menuX + 2, menuY + 1, "Q  Qalcom", UI.colors.textInverse, UI.colors.accent, menuWidth - 4)
    UI.text(native, menuX + menuWidth - 11, menuY + 1, tostring(state.user or "-"), UI.colors.textInverse, UI.colors.accent, 9)

    local searchBackground = state.launcherSearchFocused and UI.colors.accentLight or UI.colors.surfaceAlt
    local searchForeground = state.launcherSearchFocused and UI.colors.textInverse or UI.colors.text
    UI.fill(native, menuX + 2, menuY + 2, menuWidth - 4, 1, searchBackground)
    local searchText = state.launcherSearch == "" and "Search programs" or state.launcherSearch
    if state.launcherSearchFocused and state.launcherSearch ~= "" then searchText = searchText .. "_" end
    UI.text(native, menuX + 3, menuY + 2, searchText, searchForeground, searchBackground, menuWidth - 6)

    local heading = state.launcherSearch == "" and (#state.recentApps > 0 and "Recent apps" or "All apps") or "Search results"
    if config.safeMode then heading = heading .. " / Safe Mode" end
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
                local foreground = active and UI.colors.textInverse or UI.colors.text
                UI.fill(native, menuX + 2, itemY, menuWidth - 4, 1, background)
                local available = APP_PATHS[name] and fs.exists(APP_PATHS[name])
                local category = APP_CATEGORIES[name] or "Apps"
                local marker = available and "  " or "? "
                local label = marker .. APP_META[name].icon .. "  " .. APP_META[name].title
                if menuWidth >= 30 then label = label .. " [" .. category .. "]" end
                UI.text(native, menuX + 4, itemY, label, foreground, background, menuWidth - 8)
            end
        end
    end
end

local function drawTaskbar()
    local barY = math.max(1, height - 2)
    UI.taskbar(native, width, barY, state.tasks, state.focused, state.launcher, 15, state.mouseX, state.mouseY)
end

local function openLauncher()
    state.launcher = true
    state.launcherSelection = 1
    state.launcherSearch = ""
    state.launcherSearchFocused = true
    -- The launcher is self-contained chrome; draw it over the desktop and
    -- windows in place and refresh the Q button instead of clearing the
    -- whole terminal.
    drawLauncher()
    -- Launcher chrome sits above notifications. Notifications that arrive
    -- while it is open are deferred until closeLauncher restores this region.
    state.notificationsDirty = false
    state.taskbarDirty = true
end

local function closeLauncher()
    if not state.launcher then return end
    local rect = state.launcherRect
    state.launcher = false
    state.launcherSearch = ""
    state.launcherSearchFocused = true
    state.taskbarDirty = true
    -- Restore the panel's area (desktop plus any windows underneath) and
    -- redraw notification boxes the panel was covering.
    if rect then
        restoreRegion(rect.x, rect.y, rect.w, rect.h)
        -- Rebuild the notification layer after restoring the launcher area;
        -- this also handles notifications created while the launcher was open.
        state.notificationsDirty = true
    end
end

local function drawDesktop()
    width, height = native.getSize()
    native.setBackgroundColor(UI.colors.desktop)
    native.setTextColor(colors.white)
    native.clear()

    UI.desktopBackground(native, width, height)

    for _, task in ipairs(state.tasks) do
        if not task.minimized and not task.hidden then
            flushWindow(task)
        end
    end

    for _, task in ipairs(state.tasks) do
        if task.failed and not task.hidden then
            task.window.setVisible(true)
        end
    end

    -- The clear already removed any previous boxes, so skip the restore step.
    state.notificationRects = {}
    drawNotifications()
    if state.launcher then drawLauncher() end
    drawTaskbar()
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
        closeLauncher()
    end
    if y >= height - 2 then
        if activeModal() then return end
        local items = UI.taskbarLayout(width, state.tasks, 15)
        for _, item in ipairs(items) do
            if x >= item.x and x < item.x + item.width then
                if item.kind == "start" then
                    if state.launcher then closeLauncher() else openLauncher() end
                elseif item.kind == "overflow" then
                    openLauncher()
                elseif item.task then
                    local task = item.task
                    if task.minimized then
                        -- A second click restores a minimized task, matching the
                        -- familiar taskbar toggle behavior. focusTask raises and
                        -- repaints it; only notification boxes it may have
                        -- covered need a redraw.
                        task.minimized = false
                        task.window.setVisible(true)
                        focusTask(task)
                        if notificationsOverlap(task.x, task.y, task.width, task.height) then
                            state.notificationsDirty = true
                        end
                    elseif task == state.focused then
                        -- Clicking the active task button minimizes its window
                        -- instead of opening another app-name action/tooltip.
                        minimizeTask(task)
                    else
                        focusTask(task)
                    end
                    state.taskbarDirty = true
                end
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
        closeLauncher()
        return
    end
    focusTask(task)
    if task.minimized then
        task.minimized = false
        task.window.setVisible(true)
        flushWindow(task)
        state.taskbarDirty = true
        if notificationsOverlap(task.x, task.y, task.width, task.height) then
            state.notificationsDirty = true
        end
        return
    end
    if y == task.y and x == task.x + 1 then
        removeTask(task)
        return
    end
    if y == task.y and x == task.x + 3 then
        minimizeTask(task)
        return
    end
    if y == task.y and x == task.x + 5 then
        local newX, newY = task.x, task.y
        local newWidth, newHeight = task.width, task.height
        if task.maximized then
            local restore = task.restoreGeometry
            if restore then
                newX, newY = restore.x, restore.y
                newWidth, newHeight = restore.width, restore.height
            end
            task.maximized = false
            task.restoreGeometry = nil
        else
            task.restoreGeometry = { x = task.x, y = task.y, width = task.width, height = task.height }
            newX, newY = 2, 2
            newWidth, newHeight = math.max(20, width - 2), math.max(8, height - 4)
            task.maximized = true
        end
        moveWindow(task, newX, newY, newWidth, newHeight)
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
        -- Hover only affects the taskbar (tooltip and the Q button highlight),
        -- which never overlaps windows, so repaint just that region instead of
        -- clearing the whole terminal. Applications still receive every
        -- movement for their own hover rendering.
        local inTaskbar = state.mouseY >= height - 2
        if inTaskbar or state.mouseInTaskbar then state.taskbarDirty = true end
        state.mouseInTaskbar = inTaskbar
        if state.focused then
            local task = state.focused
            send(task, { name, nil, event[2] - task.x, event[3] - task.y })
        end
    elseif name == "mouse_drag" then
        state.mouseX, state.mouseY = event[3], event[4]
        if state.drag then
            local task = state.drag.task
            local newX = math.max(2, math.min(width - task.width, event[3] - state.drag.offsetX))
            local newY = math.max(2, math.min(height - task.height - 2, event[4] - state.drag.offsetY))
            if newX ~= task.x or newY ~= task.y then
                -- Pass proposed coordinates without mutating task first;
                -- moveWindow must capture the old rectangle before updating it.
                -- It centralizes reposition-before-restore ordering, both
                -- region restores, and notification overlap bookkeeping.
                moveWindow(task, newX, newY, task.width, task.height)
            end
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
                    closeLauncher()
                    return
                end
            end
            return
        end
        if state.focused then send(state.focused, event) end
    elseif name == "timer" or name == "alarm" or name == "redstone" or name == "term_resize" or name == "peripheral" or name == "peripheral_detach" or name == "disk" or name == "disk_eject" or name == "rednet_message" or name == "modem_message" then
        for _, task in ipairs(state.tasks) do send(task, event) end
    elseif name == "qalcom_network_reload" then
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
                if task.name ~= "recovery" and task.name ~= "logs" and task.name ~= "terminal" and task.name ~= "settings" and task.name ~= "peripherals" and task.name ~= "telemetry" and task.name ~= "incidents" and task.name ~= "cannon" and task.name ~= "network" and task.name ~= "infrastructure" and task.name ~= "jobs" and task.name ~= "jobs_service" and task.name ~= "network_service" then
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
spawn("network_service", { hidden = true })
state.clockTimer = os.startTimer(1)
state.uiTimer = os.startTimer(0.1)
drawDesktop()

while true do
    if state.dirty then
        drawDesktop()
        state.dirty = false
        state.taskbarDirty = false
        state.notificationsDirty = false
    else
        if state.taskbarDirty then
            drawTaskbar()
            state.taskbarDirty = false
        end
        if state.notificationsDirty and not state.launcher then
            drawNotifications()
            state.notificationsDirty = false
        end
    end
    local event = { os.pullEventRaw() }
    if event[1] == "timer" and event[2] == state.clockTimer then
        state.clockTimer = os.startTimer(1)
        dispatch({ "qalcom_tick" })
        -- The per-second clock only changes the taskbar; repaint that region.
        -- Notification boxes repaint on their own expiry timer, not every tick.
        state.taskbarDirty = true
        if state.nextNotificationExpiry and os.clock() >= state.nextNotificationExpiry then
            state.notificationsDirty = true
        end
    elseif event[1] == "timer" and event[2] == state.uiTimer then
        state.uiTimer = os.startTimer(0.1)
        -- Only notification boxes animate, so animation ticks repaint just
        -- the notification region.
        if UI.tick() then state.notificationsDirty = true end
    elseif event[1] == "terminate" then
        state.modifiers.alt = false
        state.modifiers.ctrl = false
        state.modifiers.shift = false
        notify("Ctrl+T is handled by Qalcom; close apps from their title bars.", UI.colors.warning)
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
spawn("network_service", { hidden = true })
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
            local newWidth = math.min(task.width, minimumWidth)
            local newHeight = math.min(task.height, minimumHeight)
            local newX = math.max(2, math.min(task.x, width - newWidth))
            local newY = math.max(2, math.min(task.y, height - newHeight - 2))
            if task.restoreGeometry then
                task.restoreGeometry.width = math.min(task.restoreGeometry.width, minimumWidth)
                task.restoreGeometry.height = math.min(task.restoreGeometry.height, minimumHeight)
                task.restoreGeometry.x = math.max(2, math.min(task.restoreGeometry.x, width - task.restoreGeometry.width))
                task.restoreGeometry.y = math.max(2, math.min(task.restoreGeometry.y, height - task.restoreGeometry.height - 2))
            end
            -- Resize always schedules the full desktop repaint below, so
            -- update the window mapping through the same helper but skip its
            -- targeted restore work.
            moveWindow(task, newX, newY, newWidth, newHeight, false)
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
