local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Peripherals = dofile("/qalcom/lib/peripherals.lua")
local Telemetry = dofile("/qalcom/lib/telemetry.lua")

return function(ctx)
    local records = {}
    local contacts = {}
    local summary = {}
    local selected = 1
    local status = "Read-only mod telemetry; unknown data stays unknown"

    local function refresh()
        local metadata = Peripherals.emptyMetadata()
        local text = ctx:peripheralMetadataFile()
        metadata = Peripherals.parseMetadata(text or "")
        local devices = Peripherals.inspect(ctx, metadata, os.clock())
        records = Telemetry.snapshot(ctx, devices, os.clock())
        contacts = Telemetry.mergeContacts(records, os.clock(), 32)
        summary = Telemetry.summary(records, contacts)
        selected = math.max(1, math.min(selected, math.max(1, #records)))
    end

    local function render()
        local width, height = ctx.win.getSize()
        local shell = Screen.app(ctx.win, "Operations Telemetry", {
            ui = UI,
            status = status,
            statusColor = UI.colors.textSecondary or UI.colors.muted,
        })
        local start = shell.body.y
        local row = start + 1
        local footer = height + 1
        local overview = tostring(summary.online or 0) .. " online  " .. tostring(summary.stale or 0) .. " stale  " .. tostring(summary.degraded or 0) .. " degraded  " .. tostring(summary.contacts or 0) .. " contacts"
        local bodyX, bodyWidth = shell.body.x, shell.body.width
        UI.text(ctx.win, bodyX, row, overview, UI.colors.accent, UI.colors.surface, bodyWidth)
        row = row + 2
        local compact = shell.metrics.tier == "compact"
        local compactRecord = records[selected]
        if compact then
            UI.sectionHeader(ctx.win, bodyX, row, bodyWidth, "ASSETS / SENSORS", {
                background = UI.colors.surfaceInset,
                foreground = UI.colors.accent,
            })
            local listStart = row + 1
            local contentBottom = math.max(listStart - 1, height - 1)
            local detailCount = 0
            if compactRecord then
                local available = math.max(0, contentBottom - listStart + 1)
                if available >= 4 then detailCount = math.min(4, available - 2) end
            end
            local detailStart = contentBottom - detailCount
            local visible = math.max(1, detailCount > 0 and detailStart - listStart or contentBottom - listStart + 1)
            local listEnd = math.max(1, #records - visible + 1)
            local start = math.max(1, math.min(selected - visible + 1, listEnd))
            for index = start, math.min(#records, start + visible - 1) do
                local record = records[index]
                local active = index == selected
                UI.listRow(ctx.win, bodyX, listStart + index - start, bodyWidth,
                    (active and "> " or "  ") .. record.alias, record.health, active, {
                        activeBackground = UI.colors.surfaceSelected,
                        activeForeground = UI.colors.text,
                        background = UI.colors.surface,
                        valueColor = active and UI.colors.text or (record.health == "online" and UI.colors.success or UI.colors.warning),
                    })
            end
            if #records == 0 then
                UI.text(ctx.win, bodyX + 1, listStart, "No supported telemetry found", UI.colors.muted, UI.colors.surface, math.max(1, bodyWidth - 1))
            elseif detailCount > 0 then
                UI.sectionHeader(ctx.win, bodyX, detailStart, bodyWidth,
                    "SELECTED: " .. UI.clampText(compactRecord.alias, math.max(1, bodyWidth - 12)), {
                        background = UI.colors.surfaceInset,
                        foreground = UI.colors.accent,
                    })
                local detailValues = {
                    { "Kind", compactRecord.kind },
                    { "Health", compactRecord.health },
                    { "Source", compactRecord.source },
                    { "Contacts", compactRecord.data.contactCount or 0 },
                }
                if compactRecord.failure ~= "" then detailValues[4] = { "Reason", compactRecord.failure } end
                for index = 1, detailCount do
                    local item = detailValues[index]
                    if item then
                        UI.listRow(ctx.win, bodyX, detailStart + index, bodyWidth, item[1], item[2], false, {
                            split = math.max(1, math.floor(bodyWidth * 0.42)),
                            background = UI.colors.surface,
                            valueColor = item[1] == "Health" and (compactRecord.health == "online" and UI.colors.success or UI.colors.warning) or UI.colors.text,
                        })
                    end
                end
            end
            UI.text(ctx.win, bodyX, height, "Up/Down select  R refresh  Esc close  Read-only", UI.colors.muted, UI.colors.surface, bodyWidth)
            return
        end
        local panes = Screen.splitRect(shell, 0.48)
        local listPane, detailPane = panes.left, panes.right
        UI.sectionHeader(ctx.win, listPane.x, row, listPane.width, "ASSETS / SENSORS", { background = UI.colors.surfaceInset, foreground = UI.colors.accent })
        UI.sectionHeader(ctx.win, detailPane.x, row, detailPane.width, "READ-ONLY DETAIL", { background = UI.colors.surfaceInset, foreground = UI.colors.accent })
        row = row + 1
        local listStart = row
        local visible = math.max(0, footer - row)
        for index = 1, math.min(#records, visible) do
            local record = records[index]
            local active = index == selected
            UI.listRow(ctx.win, listPane.x, row + index - 1, listPane.width, (active and "> " or "  ") .. record.alias, record.health, active, {
                activeBackground = UI.colors.surfaceSelected, activeForeground = UI.colors.text, background = UI.colors.surface,
                valueColor = active and UI.colors.text or (record.health == "online" and UI.colors.success or UI.colors.warning),
            })
        end
        local record = records[selected]
        local detailRow = listStart
        local function detail(label, value, color)
            if detailRow >= footer then return end
            UI.text(ctx.win, detailPane.x, detailRow, label, UI.colors.muted, UI.colors.surface, math.min(13, detailPane.width))
            UI.text(ctx.win, detailPane.x + math.min(14, detailPane.width), detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, math.max(1, detailPane.width - 15))
            detailRow = detailRow + 1
        end
        if record then
            detail("Kind", record.kind)
            detail("Adapter", record.adapter.title)
            detail("Health", record.health, record.health == "online" and UI.colors.success or UI.colors.warning)
            detail("Source", record.source)
            detail("Contacts", record.data.contactCount or 0)
            detail("Trust", record.trusted and "operator marked" or "untrusted/unknown")
            if record.failure ~= "" then detail("Reason", record.failure, UI.colors.warning) end
            if record.kind == "cbc" then
                detail("Assembled", record.data.assembled == nil and "unknown" or tostring(record.data.assembled))
                detail("Yaw / pitch", tostring(record.data.yaw or "?") .. " / " .. tostring(record.data.pitch or "?"))
                detail("Target", tostring(record.data.targetYaw or "?") .. " / " .. tostring(record.data.targetPitch or "?"))
                detail("Ammunition", "unknown / API does not expose it", UI.colors.warning)
                detail("Firing readiness", "unknown / API does not expose it", UI.colors.warning)
            end
            if record.kind == "aeronautics" then detail("Heading", record.data.heading) end
            if record.kind == "create_propulsion" then detail("Energy", record.data.energy) end
            if record.kind == "create_radar" or record.kind == "create_aero_radar" then detail("Range", record.data.range) end
        elseif detailRow < footer then
            UI.text(ctx.win, detailPane.x, detailRow, "No supported telemetry found", UI.colors.muted, UI.colors.surface, detailPane.width)
        end
        if footer >= 1 then UI.text(ctx.win, bodyX, footer, "Up/Down select  R refresh  Esc close  Read-only; CBC fire/aim disabled", UI.colors.muted, UI.colors.surface, bodyWidth) end
    end

    refresh()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(math.max(1, #records), selected + 1); render()
            elseif value == keys.r then refresh(); status = "Telemetry refreshed"; render()
            elseif value == keys.escape then ctx:close() end
        elseif event == "peripheral" or event == "peripheral_detach" or event == "term_resize" or event == "qalcom_tick" then
            refresh(); render()
        end
    end
end
