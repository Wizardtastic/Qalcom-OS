local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Peripherals = dofile("/qalcom/lib/peripherals.lua")
return function(ctx)
local selected = 1
local devices = {}
local metadata = Peripherals.emptyMetadata()
local status = "Read-only inspection"
local metadataDirty = false
local editingAlias = false
local aliasInput = ""
local function loadMetadata()
local text = ctx:peripheralMetadataFile()
metadata = Peripherals.parseMetadata(text or "")
end
local function refresh()
loadMetadata()
devices = Peripherals.inspect(ctx, metadata, os.clock())
selected = math.max(1, math.min(selected, math.max(1, #devices)))
status = #devices == 0 and "No attached peripherals" or (tostring(#devices) .. " device(s) discovered")
end
local function selectedDevice()
return devices[selected]
end
local function saveMetadata()
if not metadataDirty then return true end
local ok, reason = ctx:writePeripheralMetadata(Peripherals.serializeMetadata(metadata))
if ok then
metadataDirty = false
status = "Peripheral metadata saved"
refresh()
else
status = reason or "Metadata save denied"
ctx:notify(status, UI.colors.danger)
end
return ok
end
local function toggleMarker(kind)
local device = selectedDevice()
if not device then return end
local values = metadata[kind]
values[device.name] = not values[device.name]
metadataDirty = true
status = (values[device.name] and "Marked " or "Cleared ") .. kind .. ": " .. device.name .. " (press S to save)"
end
local function render()
local width, height = ctx.win.getSize()
local shell = Screen.app(ctx.win, "Peripheral Manager", {
ui = UI,
status = editingAlias and ("Alias: " .. aliasInput .. "_") or status,
statusColor = UI.colors.textSecondary or UI.colors.muted,
})
local contentStart = shell.body.y
local bodyStart = contentStart + 1
local footer = height + 1
local device = selectedDevice()
local bodyX, bodyWidth = shell.body.x, shell.body.width
if shell.metrics.tier == "compact" then
UI.sectionHeader(ctx.win, bodyX, bodyStart, bodyWidth, "ATTACHED DEVICES", {
background = UI.colors.surfaceInset,
foreground = UI.colors.accent,
})
local listStart = bodyStart + 1
local contentBottom = math.max(listStart - 1, height - 1)
local detailCount = 0
if device then
local available = math.max(0, contentBottom - listStart + 1)
if available >= 4 then detailCount = math.min(4, available - 2) end
end
local detailStart = contentBottom - detailCount
local visible = math.max(1, detailCount > 0 and detailStart - listStart or contentBottom - listStart + 1)
local listEnd = math.max(1, #devices - visible + 1)
local start = math.max(1, math.min(selected - visible + 1, listEnd))
for index = start, math.min(#devices, start + visible - 1) do
local item = devices[index]
local active = index == selected
local marker = item.blocked and "B " or (item.trusted and "T " or "  ")
UI.listRow(ctx.win, bodyX, listStart + index - start, bodyWidth,
marker .. tostring(item.alias or item.name), nil, active, {
activeBackground = UI.colors.surfaceSelected,
activeForeground = UI.colors.text,
foreground = UI.colors.text,
background = UI.colors.surface,
})
end
if #devices == 0 then
UI.text(ctx.win, bodyX + 1, listStart, "No attached peripherals", UI.colors.muted, UI.colors.surface, math.max(1, bodyWidth - 1))
elseif detailCount > 0 then
UI.sectionHeader(ctx.win, bodyX, detailStart,
bodyWidth, "SELECTED: " .. UI.clampText(device.alias or device.name, math.max(1, bodyWidth - 12)), {
background = UI.colors.surfaceInset,
foreground = UI.colors.accent,
})
local detailValues = {
{ "Name", device.name },
{ "Type", device.type },
{ "Status", device.status or device.statusFailure or "not reported" },
{ "Markers", (device.blocked and "blocked " or "") .. (device.trusted and "trusted" or "none") },
}
if editingAlias then detailValues[4] = { "Alias", aliasInput .. "_" } end
for index = 1, detailCount do
local item = detailValues[index]
if item then
UI.listRow(ctx.win, bodyX, detailStart + index, bodyWidth, item[1], item[2], false, {
split = math.max(1, math.floor(bodyWidth * 0.42)),
background = UI.colors.surface,
valueColor = item[1] == "Status" and (device.status and UI.colors.success or UI.colors.warning) or UI.colors.text,
})
end
end
end
UI.text(ctx.win, bodyX, height, "Up/Down select  A alias  B block  T trust  S save", UI.colors.muted, UI.colors.surface, bodyWidth)
return
end
local panes = Screen.splitRect(shell, 0.42)
local listPane, detailPane = panes.left, panes.right
UI.sectionHeader(ctx.win, listPane.x, bodyStart, listPane.width, "ATTACHED DEVICES", { background = UI.colors.surfaceInset, foreground = UI.colors.accent })
UI.sectionHeader(ctx.win, detailPane.x, bodyStart, detailPane.width, "INSPECTION", { background = UI.colors.surfaceInset, foreground = UI.colors.accent })
local row = bodyStart + 1
local visible = math.max(0, footer - row)
local start = math.max(1, math.min(selected - visible + 1, #devices - visible + 1))
for index = start, math.min(#devices, start + visible - 1) do
local y = row + index - start
local item = devices[index]
local active = index == selected
local marker = item.blocked and "B " or (item.trusted and "T " or "  ")
UI.listRow(ctx.win, listPane.x, y, listPane.width, marker .. tostring(item.alias or item.name), nil, active, {
activeBackground = UI.colors.surfaceSelected,
activeForeground = UI.colors.text,
foreground = UI.colors.text,
background = UI.colors.surface,
})
end
if device and row < footer then
local detailRow = row
local function detail(label, value, color)
if detailRow >= footer then return end
local labelWidth = math.min(13, detailPane.width)
UI.text(ctx.win, detailPane.x, detailRow, label, UI.colors.muted, UI.colors.surface, labelWidth)
UI.text(ctx.win, detailPane.x + math.min(14, detailPane.width), detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, math.max(1, detailPane.width - 15))
detailRow = detailRow + 1
end
detail("Name", device.name)
detail("Side", device.side)
detail("Type", device.type)
detail("Methods", tostring(device.methodCount))
detail("Status", device.status or device.statusFailure or "not reported", device.status and UI.colors.success or UI.colors.warning)
detail("Alias", editingAlias and (aliasInput .. "_") or device.alias or "(none)")
detail("Markers", (device.blocked and "blocked " or "") .. (device.trusted and "trusted" or "none"))
if detailRow < footer then detailRow = detailRow + 1 end
if detailRow < footer then
UI.text(ctx.win, detailPane.x, detailRow, "Adapters", UI.colors.accent, UI.colors.surface, detailPane.width)
detailRow = detailRow + 1
for _, adapter in ipairs(device.adapters or {}) do
if detailRow >= footer then break end
local health = adapter.stale and "stale" or (adapter.available and "available" or "failed")
local color = adapter.stale and UI.colors.warning or (adapter.available and UI.colors.success or UI.colors.danger)
local badgeWidth = math.min(10, detailPane.width)
UI.badge(ctx.win, detailPane.x, detailRow, health, color, badgeWidth)
UI.text(ctx.win, detailPane.x + math.min(12, detailPane.width), detailRow, adapter.title .. " / v" .. tostring(adapter.contractVersion), UI.colors.text, UI.colors.surface, math.max(1, detailPane.width - 13))
detailRow = detailRow + 1
end
end
if #device.contacts > 0 and detailRow < footer then
UI.text(ctx.win, detailPane.x, detailRow, "Radar contacts: " .. tostring(#device.contacts), UI.colors.accent, UI.colors.surface, detailPane.width)
detailRow = detailRow + 1
local contact = device.contacts[1]
if contact and detailRow < footer then
UI.text(ctx.win, detailPane.x, detailRow, tostring(contact.identityStatus) .. " / " .. tostring(contact.identity), UI.colors.muted, UI.colors.surface, detailPane.width)
end
end
elseif row < footer then
UI.text(ctx.win, detailPane.x, row, "No device selected", UI.colors.muted, UI.colors.surface, detailPane.width)
end
end
refresh()
render()
while true do
local event, value = ctx:pullEvent()
if editingAlias then
if event == "char" then
if #aliasInput < 48 then aliasInput = aliasInput .. tostring(value) end
render()
elseif event == "paste" then
aliasInput = aliasInput .. tostring(value):sub(1, 48 - #aliasInput)
render()
elseif event == "key" then
if value == keys.backspace then
aliasInput = aliasInput:sub(1, math.max(0, #aliasInput - 1))
render()
elseif value == keys.enter then
local device = selectedDevice()
if device then
if aliasInput == "" then metadata.aliases[device.name] = nil
else metadata.aliases[device.name] = aliasInput end
metadataDirty = true
editingAlias = false
status = "Alias staged for " .. device.name .. " (press S to save)"
end
render()
elseif value == keys.escape then
editingAlias = false
render()
end
elseif event == "term_resize" then
render()
end
elseif event == "key" then
if value == keys.up then
selected = math.max(1, selected - 1)
render()
elseif value == keys.down then
selected = math.min(math.max(1, #devices), selected + 1)
render()
elseif value == keys.a then
local device = selectedDevice()
if device then
aliasInput = device.alias or ""
editingAlias = true
render()
end
elseif value == keys.r then
refresh()
render()
elseif value == keys.b then
toggleMarker("blocked")
render()
elseif value == keys.t then
toggleMarker("trusted")
render()
elseif value == keys.s then
saveMetadata()
render()
elseif value == keys.escape then
if metadataDirty then saveMetadata() end
ctx:close()
end
elseif event == "mouse_scroll" then
selected = value < 0 and math.max(1, selected - 1) or math.min(math.max(1, #devices), selected + 1)
render()
elseif event == "peripheral" or event == "peripheral_detach" or event == "term_resize" or event == "qalcom_tick" then
refresh()
render()
end
end
end