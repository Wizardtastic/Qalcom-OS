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
        local _, _, start = Screen.begin(ctx.win, "Operations Telemetry", nil, { ui = UI })
        UI.text(ctx.win, 2, start, status, UI.colors.muted, UI.colors.surface, width - 3)
        local row = start + 1
        local footer = height + 1
        local overview = tostring(summary.online or 0) .. " online  " .. tostring(summary.stale or 0) .. " stale  " .. tostring(summary.degraded or 0) .. " degraded  " .. tostring(summary.contacts or 0) .. " contacts"
        UI.text(ctx.win, 2, row, overview, UI.colors.accent, UI.colors.surface, width - 3)
        row = row + 2
        local split = math.max(20, math.floor(width * 0.48))
        UI.sectionHeader(ctx.win, 2, row, split - 3, "Assets / sensors", { background = colors.yellow, foreground = colors.black })
        UI.sectionHeader(ctx.win, split, row, width - split - 1, "Read-only detail", { background = colors.yellow, foreground = colors.black })
        row = row + 1
        local listStart = row
        local visible = math.max(0, footer - row)
        for index = 1, math.min(#records, visible) do
            local record = records[index]
            local active = index == selected
            UI.listRow(ctx.win, 2, row + index - 1, split - 3, (active and "> " or "  ") .. record.alias, record.health, active, {
                activeBackground = UI.colors.accentLight, activeForeground = colors.white, background = UI.colors.surface,
                valueColor = record.health == "online" and UI.colors.success or UI.colors.warning,
            })
        end
        local record = records[selected]
        local detailRow = listStart
        local function detail(label, value, color)
            if detailRow >= footer then return end
            UI.text(ctx.win, split, detailRow, label, UI.colors.muted, UI.colors.surface, 13)
            UI.text(ctx.win, split + 14, detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, width - split - 15)
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
            if record.kind == "cbc" then detail("Readiness", record.data.readiness) end
            if record.kind == "aeronautics" then detail("Heading", record.data.heading) end
            if record.kind == "create_propulsion" then detail("Energy", record.data.energy) end
            if record.kind == "create_radar" or record.kind == "create_aero_radar" then detail("Range", record.data.range) end
        elseif detailRow < footer then
            UI.text(ctx.win, split, detailRow, "No supported telemetry found", UI.colors.muted, UI.colors.surface, width - split - 1)
        end
        if footer >= 1 then UI.text(ctx.win, 2, footer, "Up/Down select  R refresh  Esc close  No control actions", UI.colors.muted, UI.colors.surface, width - 3) end
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
