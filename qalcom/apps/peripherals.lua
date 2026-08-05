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
        local _, _, contentStart = Screen.begin(ctx.win, "Peripheral Manager", nil, { ui = UI })
        UI.text(ctx.win, 2, contentStart, editingAlias and ("Alias: " .. aliasInput .. "_") or status, UI.colors.muted, UI.colors.surface, width - 3)
        local bodyStart = contentStart + 1
        local footer = height + 1
        local split = math.max(15, math.floor(width * 0.42))
        local device = selectedDevice()

        UI.sectionHeader(ctx.win, 2, bodyStart, split - 3, "Attached devices", { background = colors.yellow, foreground = colors.black })
        UI.sectionHeader(ctx.win, split, bodyStart, width - split - 1, "Inspection", { background = colors.yellow, foreground = colors.black })
        local row = bodyStart + 1
        local visible = math.max(0, footer - row)
        local start = math.max(1, math.min(selected - visible + 1, #devices - visible + 1))
        for index = start, math.min(#devices, start + visible - 1) do
            local y = row + index - start
            local item = devices[index]
            local active = index == selected
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            local marker = item.blocked and "B " or (item.trusted and "T " or "  ")
            UI.listRow(ctx.win, 2, y, split - 3, marker .. tostring(item.alias or item.name), nil, active, {
                activeBackground = UI.colors.accentLight,
                activeForeground = colors.white,
                foreground = foreground,
                background = UI.colors.surface,
            })
        end

        if device and row < footer then
            local detailRow = row
            local function detail(label, value, color)
                if detailRow >= footer then return end
                UI.text(ctx.win, split, detailRow, label, UI.colors.muted, UI.colors.surface, 13)
                UI.text(ctx.win, split + 14, detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, width - split - 15)
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
                UI.text(ctx.win, split, detailRow, "Adapters", UI.colors.accent, UI.colors.surface, width - split - 1)
                detailRow = detailRow + 1
                for _, adapter in ipairs(device.adapters or {}) do
                    if detailRow >= footer then break end
                    local health = adapter.stale and "stale" or (adapter.available and "available" or "failed")
                    local color = adapter.stale and UI.colors.warning or (adapter.available and UI.colors.success or UI.colors.danger)
                    UI.badge(ctx.win, split, detailRow, health, color, 10)
                    UI.text(ctx.win, split + 12, detailRow, adapter.title .. " / v" .. tostring(adapter.contractVersion), UI.colors.text, UI.colors.surface, width - split - 13)
                    detailRow = detailRow + 1
                end
            end
            if #device.contacts > 0 and detailRow < footer then
                UI.text(ctx.win, split, detailRow, "Radar contacts: " .. tostring(#device.contacts), UI.colors.accent, UI.colors.surface, width - split - 1)
                detailRow = detailRow + 1
                local contact = device.contacts[1]
                if contact and detailRow < footer then
                    UI.text(ctx.win, split, detailRow, tostring(contact.identityStatus) .. " / " .. tostring(contact.identity), UI.colors.muted, UI.colors.surface, width - split - 1)
                end
            end
        elseif row < footer then
            UI.text(ctx.win, split, row, "No device selected", UI.colors.muted, UI.colors.surface, width - split - 1)
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
