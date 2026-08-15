local UI = dofile("/qalcom/lib/ui.lua")
local Config = dofile("/qalcom/lib/config.lua")
local VERSION = dofile("/qalcom/version.lua")
local Auth = dofile("/qalcom/lib/auth.lua")
local System = dofile("/qalcom/lib/system.lua")
local Capabilities = dofile("/qalcom/lib/capabilities.lua")
local Roles = dofile("/qalcom/lib/roles.lua")
local Managed = dofile("/qalcom/lib/managed.lua")
local Network = dofile("/qalcom/lib/network.lua")
local Palette = dofile("/qalcom/lib/ui/palette.lua")
local unpack = table.unpack or unpack
local config = Config.load()
local nativePalette = Palette.snapshot()
Config.apply(UI, config)
local function hasMethod(methods, wanted)
for _, method in ipairs(methods or {}) do if method == wanted then return true end end
return false
end
local APP_PATHS = {
terminal = "/qalcom/apps/terminal.lua",
explorer = "/qalcom/apps/explorer.lua",
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
calculator = "/qalcom/apps/calculator.lua",
network = "/qalcom/apps/network.lua",
telemetry = "/qalcom/apps/telemetry.lua",
network_service = "/qalcom/apps/network_service.lua",
cannon = "/qalcom/apps/cannon.lua",
fluent = "/qalcom/apps/fluent.lua",
}
local APP_META = {
terminal = { title = "Terminal", icon = ">_", x = 3, y = 3, width = 38, height = 16 },
explorer = { title = "File Explorer", icon = ">", x = 10, y = 5, width = 42, height = 17 },
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
calculator = { title = "Calculator", icon = "=", x = 12, y = 4, width = 38, height = 21 },
network = { title = "Network Manager", icon = "N", x = 3, y = 3, width = 56, height = 21 },
telemetry = { title = "Operations Telemetry", icon = "T", x = 3, y = 3, width = 56, height = 21 },
network_service = { title = "Network Service", icon = "N", x = 3, y = 3, width = 20, height = 8, service = true, hidden = true },
cannon = { title = "CBC Fire Control", icon = "C", x = 3, y = 3, width = 56, height = 21 },
fluent = { title = "Fluent Desktop", icon = "Fl", x = 6, y = 3, width = 42, height = 16 },
}
local APP_CATEGORIES = {
terminal = "System", explorer = "Files", calculator = "Tools",
peripherals = "Operations", telemetry = "Operations", cannon = "Defense",
network = "Network", control = "System",
capabilities = "Security", settings = "System", recovery = "Recovery", logs = "System", account = "Account",
fluent = "Tools",
}
local NORMAL_LAUNCHER_APPS = { "fluent", "terminal", "explorer", "calculator", "peripherals", "telemetry", "cannon", "network", "control", "capabilities", "settings", "recovery", "logs", "account" }
local SAFE_LAUNCHER_APPS = { "recovery", "logs", "terminal", "calculator", "settings", "peripherals", "telemetry", "network" }
local LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
local native = term.native()
local width, height = native.getSize()
local function shellMetrics()
return UI.metricsFor and UI.metricsFor(width, height) or UI.metrics
end
local function taskbarHeight()
local metrics = shellMetrics()
return math.max(1, tonumber(metrics.taskbarHeight) or 1)
end
local function taskbarY()
return math.max(1, height - taskbarHeight() + 1)
end
if width < 30 or height < 14 then
Palette.restore(nativePalette)
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
powerMenu = false,
powerSelection = 1,
contextMenu = false,
contextMenuSelection = 1,
contextMenuItems = {},
contextMenuTarget = nil,
contextMenuAnchorX = 1,
contextMenuAnchorY = 1,
contextMenuRect = nil,
fileClipboard = nil,
recentApps = {},
notifications = {},
clockTimer = nil,
uiTimer = nil,
dirty = true,
taskbarDirty = false,
notificationsDirty = false,
mouseInTaskbar = false,
notificationRects = {},
nextNotificationExpiry = nil,
drag = nil,
mouseX = 1,
mouseY = 1,
captionHover = nil,
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
state.contextMenu = false
state.contextMenuTarget = nil
state.contextMenuRect = nil
state.fileClipboard = nil
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
if state.contextMenuTarget == task then
state.contextMenu = false
state.contextMenuTarget = nil
state.contextMenuRect = nil
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
local function captionHoverFor(task)
if not task or task.minimized or task.hidden then return nil end
if state.mouseY ~= task.y then return nil end
local caps = UI.captionButtons(task.x, task.y, task.width)
if not caps then return nil end
if caps.close and state.mouseX == caps.close.x then return "close" end
if caps.minimize and state.mouseX == caps.minimize.x then return "minimize" end
if caps.maximize and state.mouseX == caps.maximize.x then return "maximize" end
return nil
end
local function redrawTitlebar(task)
if not task or task.minimized or task.hidden then return end
local focused = task == state.focused
local hovered = focused and captionHoverFor(task) or nil
UI.titleBar(native, task.x, task.y, task.width, task.meta.title, task.meta.icon, focused, task.maximized, hovered)
UI.windowFrame(native, task.x, task.y, task.width, task.height, focused)
end
local function flushWindow(task)
if not task or task.minimized or task.hidden then return end
local surface = UI.colors.surface or colors.white
local textColor = UI.colors.text or colors.black
UI.fill(native, task.x, task.y, task.width, task.height, surface)
local focused = task == state.focused
local hovered = focused and captionHoverFor(task) or nil
UI.titleBar(native, task.x, task.y, task.width, task.meta.title, task.meta.icon, focused, task.maximized, hovered)
UI.windowFrame(native, task.x, task.y, task.width, task.height, focused)
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
task.window.setBackgroundColor(surface)
task.window.setTextColor(textColor)
task.window.redraw()
end
end
local function restoreRegion(x, y, width, height)
if state.launcher and state.launcherRect then
local rect = state.launcherRect
if x < rect.x + rect.w and x + width > rect.x and y < rect.y + rect.h and y + height > rect.y then
state.dirty = true
return
end
end
if state.contextMenu and state.contextMenuRect then
local rect = state.contextMenuRect
if x < rect.x + rect.w + 1 and x + width > rect.x and y < rect.y + rect.h + 1 and y + height > rect.y then
state.dirty = true
return
end
end
UI.desktopRegion(native, x, y, width, height, config.wallpaper)
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
local function recompositeAbove(task)
if not task or task.minimized or task.hidden then return end
local above = false
for _, other in ipairs(state.tasks) do
if other == task then
above = true
elseif above and not other.minimized and not other.hidden
and task.x < other.x + other.width and task.x + task.width > other.x
and task.y < other.y + other.height and task.y + task.height > other.y then
flushWindow(other)
end
end
if notificationsOverlap(task.x, task.y, task.width, task.height) then
state.notificationsDirty = true
end
if state.launcher or state.contextMenu or state.powerMenu then
state.dirty = true
end
end
local function moveWindow(task, newX, newY, newWidth, newHeight, repaint)
if not task or not task.window then return false end
local oldX, oldY = task.x, task.y
local oldWidth, oldHeight = task.width, task.height
newX = tonumber(newX) or oldX
newY = tonumber(newY) or oldY
newWidth = tonumber(newWidth) or oldWidth
newHeight = tonumber(newHeight) or oldHeight
if newWidth < 3 or newHeight < 3 then return false end
if oldX == newX and oldY == newY and oldWidth == newWidth and oldHeight == newHeight then
return false
end
task.x, task.y = newX, newY
task.width, task.height = newWidth, newHeight
task.window.reposition(newX + 1, newY + 1, newWidth - 2, newHeight - 2)
if repaint == false then return true end
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
state.focused = task
return
end
table.remove(state.tasks, index)
state.tasks[#state.tasks + 1] = task
state.focused = task
if previous == task and index == #state.tasks then
return
end
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
function context:getFileClipboard()
if not state.fileClipboard then return nil end
return {
path = state.fileClipboard.path,
name = state.fileClipboard.name,
directory = state.fileClipboard.directory == true,
}
end
function context:setFileClipboard(clipboard)
if type(clipboard) ~= "table" or type(clipboard.path) ~= "string" then
state.fileClipboard = nil
return false
end
state.fileClipboard = {
path = clipboard.path,
name = clipboard.name or fs.getName(clipboard.path),
directory = clipboard.directory == true,
}
return true
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
if config.safeMode and name ~= "recovery" and name ~= "logs" and name ~= "terminal" and name ~= "calculator" and name ~= "settings" and name ~= "peripherals" and name ~= "telemetry" and name ~= "cannon" and name ~= "network" and name ~= "network_service" then
notify("Safe Mode blocked " .. tostring(name), UI.colors.warning)
return nil
end
if not meta or not path or not fs.exists(path) then
notify("Application unavailable: " .. tostring(name), UI.colors.danger)
Capabilities.audit("launch-denied", name .. " unavailable")
return nil
end
Capabilities.audit("launch", name)
local metrics = shellMetrics()
local desiredWidth = meta.width
local desiredHeight = meta.height
if not meta.service and not (options and options.modal) then
local widthFactor = metrics.tier == "command" and 0.68 or (metrics.tier == "wide" and 0.58 or (metrics.tier == "standard" and 0.52 or 0))
local heightFactor = metrics.tier == "command" and 0.72 or (metrics.tier == "wide" and 0.68 or (metrics.tier == "standard" and 0.62 or 0))
if widthFactor > 0 then desiredWidth = math.max(desiredWidth, math.floor(width * widthFactor)) end
if heightFactor > 0 then desiredHeight = math.max(desiredHeight, math.floor((height - taskbarHeight()) * heightFactor)) end
end
local maxWindowWidth = math.max(3, width - math.max(2, metrics.outerPadding * 2))
local maxWindowHeight = math.max(3, height - taskbarHeight() - math.max(1, metrics.outerPadding))
local w = math.min(desiredWidth, maxWindowWidth)
local h = math.min(desiredHeight, maxWindowHeight)
w = math.max(3, w)
h = math.max(3, h)
local x = math.max(2, math.min(meta.x, width - w))
local y = math.max(2, math.min(meta.y, height - h - taskbarHeight() + 1))
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
state.dirty = true
elseif coroutine.status(task.co) == "dead" then
task.state = "stopped"
task.closeRequested = true
else
task.state = "running"
end
end
local function broadcast(event)
for _, task in ipairs(state.tasks) do
send(task, event)
recompositeAbove(task)
end
end
local CONTEXT_MENU_ITEMS = {
{ id = "folder", label = "New folder" },
{ id = "text", label = "New .txt file" },
{ id = "lua", label = "New .lua file" },
}
local function contextMenuSelection(target)
target = target or state.contextMenuTarget
local raw = target and target.context and target.context.contextSelection
if type(raw) ~= "table" or raw.parent or type(raw.path) ~= "string" then return nil end
local path = fs.combine("/", raw.path)
if path:sub(1, 1) ~= "/" then path = "/" .. path end
return {
path = path == "" and "/" or path,
name = tostring(raw.name or fs.getName(path)),
dir = raw.dir == true,
}
end
local function contextMenuIsExplorer(target)
return target and target.name == "explorer" and target.context ~= nil
end
local function contextMenuItemsFor(target)
local items = {}
for _, item in ipairs(CONTEXT_MENU_ITEMS) do items[#items + 1] = item end
local selection = contextMenuSelection(target)
if contextMenuIsExplorer(target) then
if selection then
if not selection.dir then items[#items + 1] = { id = "open-editor", label = "Open with Editor" } end
items[#items + 1] = { id = "rename", label = "Rename selected" }
items[#items + 1] = { id = "delete", label = "Delete selected" }
items[#items + 1] = { id = "copy", label = "Copy selected" }
end
if state.fileClipboard then items[#items + 1] = { id = "paste", label = "Paste here" } end
end
items[#items + 1] = { id = "refresh", label = "Refresh view" }
items[#items + 1] = { id = "cancel", label = "Cancel" }
return items
end
local function contextMenuActor()
local actor = { name = "context-menu", role = state.role }
function actor:hasCapability(capability)
return Capabilities.effective(state.role, "explorer", capability, config.safeMode)
end
function actor:policy(capability)
return Capabilities.policy(state.role, "explorer", capability, config.safeMode)
end
function actor:audit(action, detail)
Capabilities.audit("context-menu." .. tostring(action), detail)
end
function actor:notify(message, color)
notify(message, color)
end
return actor
end
local function contextMenuPath()
local task = state.contextMenuTarget
local path = task and task.context and task.context.contextPath or "/"
path = tostring(path or "/"):gsub("[\\r\\n]", " "):sub(1, 120)
local normalized = fs.combine("/", path)
if normalized:sub(1, 1) ~= "/" then normalized = "/" .. normalized end
return normalized == "" and "/" or normalized
end
local function contextMenuGeometry()
local path = contextMenuPath()
local menuWidth = math.max(22, #path + 6)
for _, item in ipairs(state.contextMenuItems or CONTEXT_MENU_ITEMS) do
menuWidth = math.max(menuWidth, #item.label + 4)
end
menuWidth = math.min(menuWidth, math.max(10, width - 2))
local menuHeight = #(state.contextMenuItems or CONTEXT_MENU_ITEMS) + 2
local menuX = math.max(1, math.min(width - menuWidth + 1, state.contextMenuAnchorX or 1))
local barY = taskbarY()
local menuY = (state.contextMenuAnchorY or 1) + 1
local highestY = math.max(1, barY - menuHeight)
if menuY > highestY then menuY = highestY end
menuY = math.max(1, math.min(menuY, math.max(1, height - menuHeight + 1)))
state.contextMenuRect = { x = menuX, y = menuY, w = menuWidth, h = menuHeight }
return state.contextMenuRect, path
end
local function drawContextMenu()
if not state.contextMenu then return end
local rect, path = contextMenuGeometry()
local items = state.contextMenuItems or CONTEXT_MENU_ITEMS
UI.shadow(native, rect.x, rect.y, rect.w, rect.h, 1, UI.colors.shadow)
UI.panel(native, rect.x, rect.y, rect.w, rect.h, UI.colors.surfaceRaised or UI.colors.surface, UI.colors.borderStrong)
UI.sectionHeader(native, rect.x + 1, rect.y + 1, math.max(1, rect.w - 2),
"Create in " .. UI.clampText(path, math.max(1, rect.w - 6)), {
background = UI.colors.surfaceInset,
foreground = UI.colors.textSecondary or UI.colors.muted,
})
for index, item in ipairs(items) do
local itemY = rect.y + 1 + index
local active = index == state.contextMenuSelection
local background = active and (UI.colors.surfaceSelected or UI.colors.accentSoft) or (UI.colors.surfaceRaised or UI.colors.surface)
local foreground = active and (UI.colors.textInverse or UI.colors.text) or (UI.colors.textPrimary or UI.colors.text)
UI.fill(native, rect.x + 1, itemY, math.max(1, rect.w - 2), 1, background)
if active then UI.fill(native, rect.x + 1, itemY, 1, 1, UI.colors.focus or UI.colors.accent) end
UI.text(native, rect.x + 2, itemY, item.label, foreground, background, math.max(1, rect.w - 4))
end
end
local function closeContextMenu()
if not state.contextMenu then return end
state.contextMenu = false
state.contextMenuItems = {}
state.contextMenuTarget = nil
state.contextMenuRect = nil
state.dirty = true
end
local function contextMenuUniquePath(base, stem, extension)
extension = extension or ""
for suffix = 0, 99 do
local suffixText = suffix == 0 and "" or " " .. tostring(suffix)
local candidate = fs.combine(base, stem .. suffixText .. extension)
if candidate:sub(1, 1) ~= "/" then candidate = "/" .. candidate end
if not fs.exists(candidate) then return candidate end
end
return nil
end
local function contextMenuRefreshTarget(target)
if target and target.name == "explorer" then
send(target, { "qalcom_context_refresh" })
end
end
local function createContextEntry(id)
local actor = contextMenuActor()
local base = contextMenuPath()
local path, content
if id == "folder" then
path = contextMenuUniquePath(base, "New Folder", "")
elseif id == "text" then
path = contextMenuUniquePath(base, "New Text File", ".txt")
content = ""
elseif id == "lua" then
path = contextMenuUniquePath(base, "New Lua Script", ".lua")
content = "-- Qalcom Lua script" .. string.char(10) .. string.char(10)
end
if not path then
actor:notify("Unable to find an unused name", UI.colors.danger)
return false
end
local ok, reason
if id == "folder" then
ok, reason = Managed.makeDir(actor, path)
elseif content ~= nil then
ok, reason = Managed.writeFile(actor, path, content)
else
ok, reason = Managed.touch(actor, path)
end
if not ok then
actor:notify(reason or "Create operation denied", UI.colors.danger)
return false
end
actor:audit("create", tostring(path))
actor:notify("Created " .. fs.getName(path), UI.colors.success)
local target = state.contextMenuTarget
closeContextMenu()
contextMenuRefreshTarget(target)
return true
end
local function contextMenuItemInfo(actor, item)
if not item or item.parent or type(item.path) ~= "string" then return nil, "No Explorer item selected" end
local info, reason = Managed.pathInfo(actor, item.path)
if not info or not info.exists then return nil, reason or "Selected item no longer exists" end
return info
end
local function contextMenuOpenEditor()
local target = state.contextMenuTarget
local item = contextMenuSelection(target)
if not item or item.dir then return false end
local actor = contextMenuActor()
local info, reason = contextMenuItemInfo(actor, item)
if not info then actor:notify(reason, UI.colors.danger); return false end
closeContextMenu()
local task = spawn("editor", { path = item.path, fromContextMenu = true })
if not task then
actor:notify("Unable to open " .. item.name, UI.colors.danger)
return false
end
actor:audit("open-editor", item.path)
return true
end
local function contextMenuCopy()
local target = state.contextMenuTarget
local item = contextMenuSelection(target)
local actor = contextMenuActor()
local info, reason = contextMenuItemInfo(actor, item)
if not info then actor:notify(reason, UI.colors.danger); return false end
state.fileClipboard = { path = item.path, name = item.name, directory = info.directory == true }
actor:audit("copy", item.path)
actor:notify("Copied " .. item.name, UI.colors.success)
closeContextMenu()
return true
end
local function contextMenuPaste()
local target = state.contextMenuTarget
if not contextMenuIsExplorer(target) then return false end
local clipboard = state.fileClipboard
local actor = contextMenuActor()
if not clipboard or type(clipboard.path) ~= "string" then
actor:notify("Clipboard is empty", UI.colors.warning)
closeContextMenu()
return false
end
local sourceInfo, sourceReason = Managed.pathInfo(actor, clipboard.path)
if not sourceInfo or not sourceInfo.exists then
actor:notify(sourceReason or "Clipboard item no longer exists", UI.colors.danger)
closeContextMenu()
return false
end
local base = contextMenuPath()
local name = tostring(clipboard.name or fs.getName(clipboard.path)):gsub("[\\r\\n/\\\\]", "")
if name == "" or name == "." or name == ".." then
actor:notify("Clipboard name is invalid", UI.colors.danger)
closeContextMenu()
return false
end
local destination = fs.combine(base, name)
local destinationInfo, destinationReason = Managed.pathInfo(actor, destination)
if not destinationInfo then
actor:notify(destinationReason or "Unable to inspect paste destination", UI.colors.danger)
closeContextMenu()
return false
end
if destinationInfo.exists then
actor:notify("Already exists: " .. name, UI.colors.warning)
closeContextMenu()
return false
end
if sourceInfo.directory and (destination == clipboard.path or destination:sub(1, #clipboard.path + 1) == clipboard.path .. "/") then
actor:notify("Cannot paste a folder into itself", UI.colors.danger)
closeContextMenu()
return false
end
local ok, reason = Managed.copy(actor, clipboard.path, destination)
if not ok then
actor:notify(reason or "Paste failed", UI.colors.danger)
closeContextMenu()
return false
end
actor:audit("paste", clipboard.path .. " -> " .. destination)
actor:notify("Pasted " .. name, UI.colors.success)
closeContextMenu()
contextMenuRefreshTarget(target)
return true
end
local function contextMenuRename(target, item)
local actor = contextMenuActor()
local info, reason = contextMenuItemInfo(actor, item)
if not info then actor:notify(reason, UI.colors.danger); return false end
if info.readOnly then
actor:notify("Read-only: " .. item.name, UI.colors.danger)
return false
end
closeContextMenu()
local task = spawn("dialog", {
modal = true,
dialogTitle = "Rename " .. item.name .. "?",
dialogMessage = "Choose a new name, then confirm.",
dialogInput = true,
dialogInputLabel = "New name",
dialogInputValue = item.name,
})
if not task then
actor:notify("Unable to open rename dialog", UI.colors.danger)
return false
end
task.context.dialogInputCallback = function(value)
local newName = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
if newName == "" then return false, "Name cannot be empty" end
if newName == "." or newName == ".." then return false, "Invalid name" end
if #newName > 64 then return false, "Name is limited to 64 characters" end
if newName:find("/", 1, true) or newName:find("\\", 1, true) then
return false, "Name cannot contain path separators or control characters"
end
for index = 1, #newName do
if newName:byte(index) < 32 then
return false, "Name cannot contain path separators or control characters"
end
end
if newName == item.name then
actor:notify("Name unchanged", UI.colors.info)
return true
end
local destination = fs.combine(fs.getDir(item.path), newName)
local destinationInfo, destinationReason = Managed.pathInfo(actor, destination)
if not destinationInfo then return false, destinationReason or "Unable to inspect new name" end
if destinationInfo.exists then return false, "Already exists: " .. newName end
local ok, moveReason = Managed.move(actor, item.path, destination)
if not ok then return false, moveReason or "Rename failed" end
actor:audit("rename", item.path .. " -> " .. destination)
actor:notify("Renamed to " .. newName, UI.colors.success)
contextMenuRefreshTarget(target)
return true
end
return true
end
local function contextMenuDelete(target, item)
local actor = contextMenuActor()
local info, reason = contextMenuItemInfo(actor, item)
if not info then actor:notify(reason, UI.colors.danger); return false end
if info.readOnly then
actor:notify("Read-only: " .. item.name, UI.colors.danger)
return false
end
closeContextMenu()
local task = spawn("dialog", {
modal = true,
dialogTitle = "Delete " .. item.name .. "?",
dialogMessage = info.directory and "Folder contents will also be removed." or "This cannot be undone.",
})
if not task then
actor:notify("Unable to open delete confirmation", UI.colors.danger)
return false
end
task.context.dialogCallback = function()
local currentInfo, currentReason = contextMenuItemInfo(actor, item)
if not currentInfo then return false, currentReason or "Item no longer exists" end
if currentInfo.readOnly then return false, "Read-only path" end
local ok, deleteReason = Managed.delete(actor, item.path)
if not ok then return false, deleteReason or "Delete failed" end
actor:audit("delete", item.path)
actor:notify("Deleted " .. item.name, UI.colors.success)
contextMenuRefreshTarget(target)
return true
end
return true
end
local function invokeContextMenu(index)
local items = state.contextMenuItems or CONTEXT_MENU_ITEMS
local item = items[index]
if not item then return end
local target = state.contextMenuTarget
local selection = contextMenuSelection(target)
if item.id == "cancel" then
closeContextMenu()
elseif item.id == "refresh" then
closeContextMenu()
contextMenuRefreshTarget(target)
elseif item.id == "open-editor" then
contextMenuOpenEditor()
elseif item.id == "rename" then
contextMenuRename(target, selection)
elseif item.id == "delete" then
contextMenuDelete(target, selection)
elseif item.id == "copy" then
contextMenuCopy()
elseif item.id == "paste" then
contextMenuPaste()
else
createContextEntry(item.id)
end
end
local function contextMenuHover(x, y)
local rect = contextMenuGeometry()
local index = y - rect.y - 1
if x >= rect.x + 1 and x < rect.x + rect.w - 1 and index >= 1 and index <= #(state.contextMenuItems or CONTEXT_MENU_ITEMS) then
if state.contextMenuSelection ~= index then
state.contextMenuSelection = index
state.dirty = true
end
end
end
local function handleContextMenuClick(x, y)
local rect = contextMenuGeometry()
local index = y - rect.y - 1
if x >= rect.x + 1 and x < rect.x + rect.w - 1 and index >= 1 and index <= #(state.contextMenuItems or CONTEXT_MENU_ITEMS) then
invokeContextMenu(index)
else
closeContextMenu()
end
end
local function handleContextMenuKey(key)
local count = #(state.contextMenuItems or CONTEXT_MENU_ITEMS)
if key == keys.up then
state.contextMenuSelection = math.max(1, state.contextMenuSelection - 1)
state.dirty = true
elseif key == keys.down then
state.contextMenuSelection = math.min(count, state.contextMenuSelection + 1)
state.dirty = true
elseif key == keys.enter then
invokeContextMenu(state.contextMenuSelection)
elseif key == keys.escape then
closeContextMenu()
end
end
local function openContextMenu(x, y, target)
state.launcher = false
state.powerMenu = false
state.contextMenu = true
state.contextMenuTarget = target
state.contextMenuItems = contextMenuItemsFor(state.contextMenuTarget)
state.contextMenuSelection = 1
state.contextMenuAnchorX = math.floor(tonumber(x) or 1)
state.contextMenuAnchorY = math.floor(tonumber(y) or 1)
contextMenuGeometry()
state.dirty = true
end
local launcherGeometry
local function drawNotifications()
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
local boxWidth = math.min(width - 4, math.max(18, #item.message + 6))
local x = math.max(1, math.min(width - boxWidth + 1, width - boxWidth + 1 + math.floor(item.offset or 0)))
local y = 2 + (index - 1) * 2
local accentColor = item.color
local cardBackground = UI.colors.surfaceRaised or UI.colors.surfaceStrong or UI.colors.surface
local glyph = item.severity == "danger" and "!" or item.severity == "warning" and "~"
or item.severity == "success" and "+" or "i"
UI.fill(native, x, y, boxWidth, 1, cardBackground)
UI.fill(native, x, y, 1, 1, accentColor)
UI.text(native, x + 1, y, glyph, accentColor, cardBackground, 1)
UI.text(native, x + 3, y, item.message, UI.colors.textPrimary or UI.colors.text, cardBackground, boxWidth - 4)
state.notificationRects[#state.notificationRects + 1] = { x = x, y = y, w = boxWidth, h = 1 }
if not state.nextNotificationExpiry or item.expires < state.nextNotificationExpiry then
state.nextNotificationExpiry = item.expires
end
end
end
local POWER_ACTIONS = {
{ id = "logout", label = "Sign out" },
{ id = "reboot", label = "Reboot" },
{ id = "shutdown", label = "Shut down" },
}
local function recentLauncherItems()
local recents = {}
local seen = {}
for _, name in ipairs(state.recentApps or {}) do
if not seen[name] and APP_META[name] then
for _, allowed in ipairs(LAUNCHER_APPS) do
if name == allowed then seen[name] = true; recents[#recents + 1] = name; break end
end
end
end
return recents
end
local function shellRequestPower(action)
local capability = action == "reboot" and "system.reboot" or action == "shutdown" and "system.shutdown" or nil
if not capability then return false end
local safeDenied = config.safeMode == true
local roleAllowed = Roles.allows(state.role, capability)
if safeDenied or not roleAllowed then
Capabilities.audit("power-denied", tostring(state.user or "unknown") .. " " .. action .. " safeMode=" .. tostring(config.safeMode == true))
notify("Power action denied: " .. action, UI.colors.danger)
return false
end
local task = spawn("dialog", {
modal = true,
dialogTitle = action == "reboot" and "Confirm reboot" or "Confirm shutdown",
dialogMessage = "Close Qalcom and " .. action .. " this computer?",
})
if not task then return false end
task.context.dialogCallback = function()
Capabilities.audit("power", tostring(state.user or "unknown") .. " confirmed " .. action)
os.queueEvent("qalcom_power_confirmed", action)
return true
end
task.context.dialogCancelCallback = function()
Capabilities.audit("power", tostring(state.user or "unknown") .. " cancelled " .. action)
end
return true
end
local function powerMenuRects(g)
local menuWidth = math.min(g.panelWidth - 2, 12)
local count = #POWER_ACTIONS
local mx = math.min(g.powerRect.x, g.panelX + g.panelWidth - menuWidth - 1)
mx = math.max(g.panelX + 1, mx)
local my = math.max(g.panelY + 1, g.footerY - count)
local rects = {}
for index, action in ipairs(POWER_ACTIONS) do
rects[index] = { x = mx, y = my + index - 1, w = menuWidth, index = index, action = action }
end
return rects, mx, my, menuWidth, count
end
local function triggerPowerAction(id)
state.powerMenu = false
state.launcher = false
if id == "logout" then
os.queueEvent("qalcom_logout")
elseif id == "reboot" or id == "shutdown" then
shellRequestPower(id)
end
state.dirty = true
end
local function drawLauncher()
local g = launcherGeometry()
state.launcherRect = { x = g.panelX, y = g.panelY, w = g.panelWidth + 1, h = g.panelHeight + 1 }
UI.shadow(native, g.panelX, g.panelY, g.panelWidth, g.panelHeight, 1, UI.colors.shadow)
UI.panel(native, g.panelX, g.panelY, g.panelWidth, g.panelHeight, UI.colors.surfaceRaised or UI.colors.surface, UI.colors.borderStrong)
UI.fill(native, g.innerX, g.searchY, g.innerWidth, 1, UI.colors.surfaceInset)
local searchText = state.launcherSearch == "" and "Search apps" or state.launcherSearch
local searchColor = state.launcherSearch == "" and (UI.colors.textSecondary or UI.colors.textMuted or UI.colors.muted) or UI.colors.textPrimary or UI.colors.text
if state.launcherSearchFocused and state.launcherSearch ~= "" then searchText = searchText .. "_" end
UI.text(native, g.innerX + 1, g.searchY, searchText, searchColor, UI.colors.surfaceInset, g.innerWidth - 2)
local heading = state.launcherSearch == "" and "Pinned" or "Search results"
if config.safeMode then heading = heading .. "  -  Safe Mode" end
UI.sectionHeader(native, g.innerX, g.headingY, g.innerWidth, heading, {
background = UI.colors.surfaceInset,
foreground = UI.colors.textSecondary or UI.colors.textMuted or UI.colors.muted,
})
if #g.items == 0 then
UI.text(native, g.innerX, g.gridTop, "No matching apps", UI.colors.textSecondary or UI.colors.textMuted or UI.colors.muted, UI.colors.surfaceRaised or UI.colors.surface, g.innerWidth)
else
for _, tile in ipairs(g.tiles) do
local active = tile.index == state.launcherSelection
local background = active and (UI.colors.surfaceSelected or UI.colors.accentSoft) or (UI.colors.surface or UI.colors.surfaceBase)
local foreground = active and UI.colors.textInverse or UI.colors.textPrimary or UI.colors.text
UI.fill(native, tile.x, tile.y, tile.w, tile.h, background)
local available = APP_PATHS[tile.name] and fs.exists(APP_PATHS[tile.name])
local icon = tostring(APP_META[tile.name].icon or "?")
local iconColor = active and UI.colors.textInverse or UI.colors.accent
if not available then iconColor = UI.colors.danger end
local iconX = tile.x + math.max(0, math.floor((tile.w - #icon) / 2))
UI.text(native, iconX, tile.y, icon, iconColor, background, tile.w)
local title = UI.clampText(tostring(APP_META[tile.name].title or tile.name), tile.w)
local titleX = tile.x + math.max(0, math.floor((tile.w - #title) / 2))
UI.text(native, titleX, tile.y + 1, title, foreground, background, tile.w)
end
end
if g.showRecent then
UI.text(native, g.innerX, g.recentLabelY, "Recent", UI.colors.textSecondary or UI.colors.textMuted or UI.colors.muted, UI.colors.surfaceRaised or UI.colors.surface, g.innerWidth)
for _, r in ipairs(g.recentRects) do
UI.fill(native, r.x, r.y, r.w, 1, UI.colors.surfaceInset)
local icon = tostring(APP_META[r.name].icon or "?")
local ix = r.x + math.max(0, math.floor((r.w - #icon) / 2))
UI.text(native, ix, r.y, icon, UI.colors.accent, UI.colors.surfaceInset, r.w)
end
end
UI.fill(native, g.innerX, g.footerY, g.innerWidth, 1, UI.colors.surfaceRaised or UI.colors.surface)
UI.text(native, g.userRect.x, g.footerY, "@ " .. tostring(state.user or "-"), UI.colors.textPrimary or UI.colors.text, UI.colors.surfaceRaised or UI.colors.surface, g.userRect.w)
local powerBg = state.powerMenu and UI.colors.surfaceSelected or (UI.colors.surfaceRaised or UI.colors.surface)
local powerFg = state.powerMenu and UI.colors.textInverse or UI.colors.textPrimary or UI.colors.text
UI.fill(native, g.powerRect.x, g.powerRect.y, g.powerRect.w, 1, powerBg)
local powerLabel = UI.clampText(g.powerLabel, g.powerRect.w)
local powerLabelX = g.powerRect.x + math.max(0, math.floor((g.powerRect.w - #powerLabel) / 2))
UI.text(native, powerLabelX, g.powerRect.y, powerLabel, powerFg, powerBg, g.powerRect.w)
if state.powerMenu then
local rects, mx, my, mw, count = powerMenuRects(g)
UI.shadow(native, mx, my, mw, count, 1, UI.colors.shadow)
UI.fill(native, mx, my, mw, count, UI.colors.surfaceInset)
for _, r in ipairs(rects) do
local active = r.index == state.powerSelection
local bg = active and UI.colors.surfaceSelected or UI.colors.surfaceInset
local fg = active and UI.colors.textInverse or UI.colors.text
UI.fill(native, r.x, r.y, r.w, 1, bg)
UI.text(native, r.x + 1, r.y, r.action.label, fg, bg, r.w - 2)
end
end
end
local function drawTaskbar()
local barY = taskbarY()
UI.taskbar(native, width, barY, state.tasks, state.focused, state.launcher, 15, state.mouseX, state.mouseY)
end
local function openLauncher()
state.launcher = true
state.launcherSelection = 1
state.launcherSearch = ""
state.launcherSearchFocused = true
state.powerMenu = false
state.powerSelection = 1
drawLauncher()
state.notificationsDirty = false
state.taskbarDirty = true
end
local function closeLauncher()
if not state.launcher then return end
local rect = state.launcherRect
state.launcher = false
state.launcherSearch = ""
state.launcherSearchFocused = true
state.powerMenu = false
state.taskbarDirty = true
if rect then
restoreRegion(rect.x, rect.y, rect.w, rect.h)
state.notificationsDirty = true
end
end
local function drawDesktop()
width, height = native.getSize()
native.setBackgroundColor(UI.colors.desktop)
native.setTextColor(UI.colors.textPrimary or UI.colors.text)
native.clear()
UI.desktopBackground(native, width, height, config.wallpaper, taskbarHeight())
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
state.notificationRects = {}
drawNotifications()
if state.launcher then drawLauncher() end
drawTaskbar()
if state.contextMenu then drawContextMenu() end
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
for _, name in ipairs(LAUNCHER_APPS) do add(name) end
return items
end
launcherGeometry = function()
local items = launcherItems()
local barY = taskbarY()
local metrics = shellMetrics()
local commandWidth = metrics.tier == "command" and 72 or (metrics.tier == "wide" and 60 or 50)
local panelWidth = math.max(24, math.min(commandWidth, width - math.max(2, metrics.outerPadding * 2)))
local panelHeight = math.max(9, math.min(barY - 2, height - 3))
local panelX = math.max(1, math.floor((width - panelWidth) / 2) + 1)
local panelY = math.max(1, barY - panelHeight - 1)
local innerX = panelX + 2
local innerWidth = math.max(1, panelWidth - 4)
local searchY = panelY + 1
local headingY = panelY + 2
local gridTop = panelY + 3
local footerY = panelY + panelHeight - 2
local recents = recentLauncherItems()
local showRecent = state.launcherSearch == "" and #recents > 0 and panelHeight >= 12
local recentY, recentLabelY, gridBottom
if showRecent then
recentY = footerY - 1
recentLabelY = footerY - 2
gridBottom = recentLabelY - 2
else
gridBottom = footerY - 2
end
if gridBottom < gridTop then gridBottom = gridTop end
local cols = innerWidth >= 62 and 4 or (innerWidth >= 42 and 3 or (innerWidth >= 26 and 2 or 1))
local tileGap = 1
local tileWidth = math.max(6, math.floor((innerWidth - (cols - 1) * tileGap) / cols))
local tileHeight = 2
local rowStride = tileHeight + 1
local gridRows = math.max(1, math.floor((gridBottom - gridTop + 2) / rowStride))
local perPage = math.max(1, cols * gridRows)
local count = #items
if count > 0 then
state.launcherSelection = math.max(1, math.min(state.launcherSelection, count))
else
state.launcherSelection = 1
end
local start = math.floor((state.launcherSelection - 1) / perPage) * perPage + 1
local tiles = {}
for slot = 0, perPage - 1 do
local index = start + slot
local name = items[index]
if name then
local col = slot % cols
local row = math.floor(slot / cols)
tiles[#tiles + 1] = {
x = innerX + col * (tileWidth + tileGap),
y = gridTop + row * rowStride,
w = tileWidth,
h = tileHeight,
index = index,
name = name,
}
end
end
local recentRects = {}
if showRecent then
local cursor = innerX
for _, name in ipairs(recents) do
if cursor + 3 - 1 > innerX + innerWidth - 1 then break end
recentRects[#recentRects + 1] = { x = cursor, y = recentY, w = 3, name = name }
cursor = cursor + 4
end
end
local powerLabel = innerWidth >= 18 and "Power" or "Pwr"
local powerWidth = math.min(innerWidth, #powerLabel + 2)
local powerRect = { x = panelX + panelWidth - 2 - powerWidth + 1, y = footerY, w = powerWidth }
local userRect = { x = innerX, y = footerY, w = math.max(1, powerRect.x - innerX - 1) }
return {
panelX = panelX, panelY = panelY, panelWidth = panelWidth, panelHeight = panelHeight,
innerX = innerX, innerWidth = innerWidth,
searchY = searchY, headingY = headingY, gridTop = gridTop, gridBottom = gridBottom,
cols = cols, gridRows = gridRows, perPage = perPage, tileWidth = tileWidth,
items = items, start = start, tiles = tiles,
showRecent = showRecent, recentY = recentY, recentLabelY = recentLabelY, recentRects = recentRects,
footerY = footerY, powerRect = powerRect, userRect = userRect, powerLabel = powerLabel,
}
end
local function handleLauncherClick(x, y)
local g = launcherGeometry()
if state.powerMenu then
local rects = powerMenuRects(g)
for _, r in ipairs(rects) do
if y == r.y and x >= r.x and x < r.x + r.w then
triggerPowerAction(r.action.id)
return true
end
end
state.powerMenu = false
state.dirty = true
return true
end
if x < g.panelX or x >= g.panelX + g.panelWidth or y < g.panelY or y >= g.panelY + g.panelHeight then
return false
end
if y == g.searchY then
state.launcherSearchFocused = true
state.dirty = true
return true
end
if y == g.powerRect.y and x >= g.powerRect.x and x < g.powerRect.x + g.powerRect.w then
state.powerMenu = true
state.powerSelection = 1
state.dirty = true
return true
end
for _, r in ipairs(g.recentRects) do
if y == r.y and x >= r.x and x < r.x + r.w then
state.launcher = false
state.launcherSearch = ""
state.powerMenu = false
spawn(r.name, { fromLauncher = true })
return true
end
end
for _, tile in ipairs(g.tiles) do
if x >= tile.x and x < tile.x + tile.w and y >= tile.y and y < tile.y + tile.h then
state.launcherSelection = tile.index
state.launcher = false
state.launcherSearch = ""
state.powerMenu = false
spawn(tile.name, { fromLauncher = true })
return true
end
end
return true
end
local function handleMouse(button, x, y)
if state.launcher then
if handleLauncherClick(x, y) then
state.dirty = true
return
end
closeLauncher()
end
if button == 2 then
local modal = activeModal()
if modal then
send(modal, { "mouse_click", button, x - modal.x, y - modal.y })
else
local target = hitTask(x, y)
if target then focusTask(target) end
openContextMenu(x, y, target)
end
return
end
if y >= taskbarY() then
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
task.minimized = false
task.window.setVisible(true)
focusTask(task)
if notificationsOverlap(task.x, task.y, task.width, task.height) then
state.notificationsDirty = true
end
elseif task == state.focused then
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
if y == task.y then
local caps = UI.captionButtons(task.x, task.y, task.width)
if caps and caps.close and x == caps.close.x then
removeTask(task)
return
end
if caps and caps.minimize and x == caps.minimize.x then
minimizeTask(task)
return
end
if caps and caps.maximize and x == caps.maximize.x then
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
newWidth, newHeight = math.max(20, width - 2), math.max(8, height - taskbarHeight() - 1)
task.maximized = true
end
moveWindow(task, newX, newY, newWidth, newHeight)
return
end
state.drag = { task = task, offsetX = x - task.x, offsetY = y - task.y }
return
end
if y > task.y and y <= task.y + task.height - 2 then
send(task, { "mouse_click", button, x - task.x, y - task.y })
end
end
local function dispatch(event)
local name = event[1]
if state.contextMenu then
if name == "mouse_click" then
state.mouseX, state.mouseY = event[3], event[4]
handleContextMenuClick(event[3], event[4])
return
elseif name == "mouse_move" then
state.mouseX, state.mouseY = event[2], event[3]
contextMenuHover(event[2], event[3])
return
elseif name == "key" then
handleContextMenuKey(event[2])
return
elseif name == "mouse_scroll" then
handleContextMenuKey(event[2] < 0 and keys.up or keys.down)
return
elseif name == "char" or name == "paste" or name == "key_up" then
return
elseif name == "term_resize" then
state.dirty = true
return
end
state.dirty = true
end
if name == "mouse_click" then
state.mouseX, state.mouseY = event[3], event[4]
handleMouse(event[2], event[3], event[4])
elseif name == "mouse_move" then
state.mouseX, state.mouseY = event[2], event[3]
local inTaskbar = state.mouseY >= taskbarY()
if inTaskbar or state.mouseInTaskbar then state.taskbarDirty = true end
state.mouseInTaskbar = inTaskbar
local newCaptionHover = captionHoverFor(state.focused)
if newCaptionHover ~= state.captionHover then
state.captionHover = newCaptionHover
if state.focused then redrawTitlebar(state.focused) end
end
if state.focused then
local task = state.focused
send(task, { name, nil, event[2] - task.x, event[3] - task.y })
end
elseif name == "mouse_drag" then
state.mouseX, state.mouseY = event[3], event[4]
if state.drag then
local task = state.drag.task
local newX = math.max(2, math.min(width - task.width, event[3] - state.drag.offsetX))
local newY = math.max(2, math.min(height - task.height - taskbarHeight() + 1, event[4] - state.drag.offsetY))
if newX ~= task.x or newY ~= task.y then
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
if state.powerMenu then
if name == "key" then
if event[2] == keys.up then
state.powerSelection = math.max(1, state.powerSelection - 1)
state.dirty = true
elseif event[2] == keys.down then
state.powerSelection = math.min(#POWER_ACTIONS, state.powerSelection + 1)
state.dirty = true
elseif event[2] == keys.enter then
triggerPowerAction(POWER_ACTIONS[state.powerSelection].id)
elseif event[2] == keys.escape then
state.powerMenu = false
state.dirty = true
end
end
return
end
if name == "char" or name == "paste" then
state.launcherSearch = state.launcherSearch .. tostring(event[2] or "")
state.launcherSearchFocused = true
state.launcherSelection = 1
state.dirty = true
return
elseif name == "key" then
local g = launcherGeometry()
local items = g.items
local cols = g.cols
local count = #items
if event[2] == keys.backspace then
state.launcherSearch = state.launcherSearch:sub(1, math.max(0, #state.launcherSearch - 1))
state.launcherSearchFocused = true
state.launcherSelection = 1
state.dirty = true
return
elseif event[2] == keys.up then
if state.launcherSearchFocused then
return
elseif state.launcherSelection <= cols then
state.launcherSearchFocused = true
else
state.launcherSelection = math.max(1, state.launcherSelection - cols)
end
state.dirty = true
return
elseif event[2] == keys.down then
state.launcherSearchFocused = false
if count > 0 then state.launcherSelection = math.min(count, state.launcherSelection + cols) end
state.dirty = true
return
elseif event[2] == keys.left then
state.launcherSearchFocused = false
state.launcherSelection = math.max(1, state.launcherSelection - 1)
state.dirty = true
return
elseif event[2] == keys.right then
state.launcherSearchFocused = false
if count > 0 then state.launcherSelection = math.min(count, state.launcherSelection + 1) end
state.dirty = true
return
elseif event[2] == keys.enter then
local selected = items[state.launcherSelection]
if selected then
state.launcher = false
state.launcherSearch = ""
state.powerMenu = false
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
broadcast(event)
elseif name == "qalcom_network_reload" then
broadcast(event)
elseif name == "qalcom_config_changed" then
config = Config.load()
Config.apply(UI, config)
for _, task in ipairs(state.tasks) do
if task.context and task.context.refreshCapabilities then task.context:refreshCapabilities() end
end
LAUNCHER_APPS = config.safeMode and SAFE_LAUNCHER_APPS or NORMAL_LAUNCHER_APPS
if config.safeMode then
for _, task in ipairs(state.tasks) do
if task.name ~= "recovery" and task.name ~= "logs" and task.name ~= "terminal" and task.name ~= "settings" and task.name ~= "peripherals" and task.name ~= "telemetry" and task.name ~= "cannon" and task.name ~= "network" and task.name ~= "network_service" then
task.closeRequested = true
end
end
end
state.dirty = true
for _, task in ipairs(state.tasks) do send(task, event) end
elseif name == "qalcom_tick" then
broadcast(event)
end
end
recordBootStage("kernel loaded")
log("boot Qalcom OS " .. VERSION)
local function showSplash()
local w, h = native.getSize()
native.setBackgroundColor(UI.colors.desktop)
native.setTextColor(UI.colors.text)
native.clear()
UI.desktopBackground(native, w, h, config.wallpaper, UI.taskbarHeight(w, h))
local cy = math.max(2, math.floor(h / 2))
local brand = "Qalcom OS"
local bx = math.max(1, math.floor((w - #brand) / 2) + 1)
UI.text(native, bx, cy, "Q", UI.colors.accent, UI.colors.desktop, 1)
UI.text(native, bx + 1, cy, "alcom OS", UI.colors.text, UI.colors.desktop, #brand - 1)
UI.center(native, cy + 2, "version " .. VERSION, UI.colors.textMuted or UI.colors.muted, UI.colors.desktop, w)
UI.center(native, math.max(cy + 3, h - 2), "Starting Qalcom", UI.colors.textMuted or UI.colors.muted, UI.colors.desktop, w)
pcall(os.sleep, 0.5)
end
showSplash()
local authenticated = Auth.login(native, UI, VERSION)
if not authenticated then
Palette.restore(nativePalette)
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
if state.notificationsDirty and not state.launcher and not state.contextMenu then
drawNotifications()
state.notificationsDirty = false
end
end
local event = { os.pullEventRaw() }
if event[1] == "timer" and event[2] == state.clockTimer then
state.clockTimer = os.startTimer(1)
dispatch({ "qalcom_tick" })
state.taskbarDirty = true
if state.nextNotificationExpiry and os.clock() >= state.nextNotificationExpiry then
state.notificationsDirty = true
end
elseif event[1] == "timer" and event[2] == state.uiTimer then
state.uiTimer = os.startTimer(0.1)
if UI.tick() then state.notificationsDirty = true end
elseif event[1] == "terminate" then
state.modifiers.alt = false
state.modifiers.ctrl = false
state.modifiers.shift = false
notify("Ctrl+T is handled by Qalcom; close apps from their title bars.", UI.colors.warning)
elseif event[1] == "qalcom_power_confirmed" then
closeAllTasks()
recordBootStage("power " .. tostring(event[2]))
Palette.restore(nativePalette)
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
if not authenticated then Palette.restore(nativePalette); return end
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
local minimumWidth = math.max(20, width - 2 * math.max(1, shellMetrics().outerPadding or 1))
local minimumHeight = math.max(8, height - taskbarHeight() - 1)
local newWidth = math.min(task.width, minimumWidth)
local newHeight = math.min(task.height, minimumHeight)
local newX = math.max(2, math.min(task.x, width - newWidth))
local newY = math.max(2, math.min(task.y, height - newHeight - taskbarHeight() + 1))
if task.restoreGeometry then
task.restoreGeometry.width = math.min(task.restoreGeometry.width, minimumWidth)
task.restoreGeometry.height = math.min(task.restoreGeometry.height, minimumHeight)
task.restoreGeometry.x = math.max(2, math.min(task.restoreGeometry.x, width - task.restoreGeometry.width))
task.restoreGeometry.y = math.max(2, math.min(task.restoreGeometry.y, height - task.restoreGeometry.height - taskbarHeight() + 1))
end
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