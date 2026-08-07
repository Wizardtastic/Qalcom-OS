local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Peripherals = dofile("/qalcom/lib/peripherals.lua")
local Cannon = dofile("/qalcom/lib/cannon.lua")

return function(ctx)
    local devices = {}
    local selected = {}
    local cursor = 1
    local contacts = {}
    -- Keep coordinates unset until each axis has been entered explicitly. A
    -- missing axis must never silently become world origin (0, 0, 0).
    local target = { x = nil, y = nil, z = nil }
    local targetMode = "coordinates"
    local selectedContact = 1
    local plan = nil
    local status = "Select CBC mounts, enter coordinates, or choose a radar contact"
    local editing = nil
    local input = ""
    local settings = Cannon.settings({})
    local phase = "idle"
    local fireArmed = false
    local fireTimer = nil
    local lastFireAt = -math.huge

    local function now()
        if os.epoch then
            local ok, value = pcall(os.epoch, "utc")
            if ok and value then return math.floor(value / 1000) end
        end
        return math.floor(os.clock())
    end

    local function refresh()
        if not ctx:hasCapability("cannon.control") then
            devices = {}
            status = "Cannon control denied for this role"
            return
        end
        local metadata = Peripherals.parseMetadata(ctx:peripheralMetadataFile() or "")
        local all = Peripherals.inspect(ctx, metadata, now())
        devices = {}
        for _, device in ipairs(all) do
            for _, adapter in ipairs(device.adapters or {}) do
                if adapter.name == "cbc" and adapter.apiCompatible and not device.blocked then
                    devices[#devices + 1] = device
                    break
                end
            end
        end
        local metadataText = ctx:peripheralMetadataFile() or ""
        local radarMetadata = Peripherals.parseMetadata(metadataText)
        local radarDevices = Peripherals.inspect(ctx, radarMetadata, now())
        contacts = {}
        for _, device in ipairs(radarDevices) do
            if device.contacts then
                for _, contact in ipairs(device.contacts) do
                    if #contacts >= 32 then break end
                    contacts[#contacts + 1] = contact
                end
            end
            if #contacts >= 32 then break end
        end
        selectedContact = math.max(1, math.min(selectedContact, math.max(1, #contacts)))
        cursor = math.max(1, math.min(cursor, math.max(1, #devices)))
        status = #devices == 0 and "No verified CBC cannon mounts available" or (tostring(#devices) .. " verified mount(s) available")
    end

    local function selectedCannons()
        return Cannon.selectedDevices(devices, selected)
    end

    local function currentTarget()
        if targetMode == "radar" then
            local contact = contacts[selectedContact]
            if not contact or contact.identityStatus == "ambiguous" then
                return nil, "Radar contact is ambiguous; choose a fresh contact or coordinates"
            end
            if contact.age and contact.age > 10 then return nil, "Radar contact is stale" end
            return Cannon.targetFromContact(contact)
        end
        if target.x == nil or target.y == nil or target.z == nil then
            return nil, "Enter all X, Y, and Z coordinates"
        end
        return Cannon.target(target.x, target.y, target.z)
    end

    local function buildPlan()
        local targetValue, reason = currentTarget()
        if not targetValue then
            status = reason or "Target coordinates are incomplete"
            plan = nil
            return false
        end
        local cannons = selectedCannons()
        if #cannons == 0 then
            status = "Select at least one cannon"
            plan = nil
            return false
        end
        plan = Cannon.plan(cannons, targetValue, settings)
        plan.target = targetValue
        if #plan.entries == 0 then
            status = "No selected cannon has a usable position"
            return false
        end
        status = "Plan ready: " .. tostring(#plan.entries) .. " cannon(s), " .. tostring(#plan.rejected) .. " rejected"
        return true
    end

    local function audit(action, detail)
        if ctx.audit then ctx:audit(action, "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " " .. tostring(detail or "")) end
    end

    local function control(device, method, ...)
        if not device or not device.name then return false, "Cannon identity unavailable" end
        local current = {}
        for _, candidate in ipairs(ctx:peripheralNames() or {}) do current[candidate] = true end
        if not current[device.name] then return false, "Cannon peripheral detached" end
        local kind = ctx:peripheralType(device.name)
        if kind ~= "cannon_mount" and kind ~= "compact_cannon_mount" then return false, "Peripheral is not a verified CBC mount" end
        local verified = false
        for _, adapter in ipairs(device.adapters or {}) do
            if adapter.name == "cbc" and adapter.apiCompatible then verified = true; break end
        end
        if not verified then return false, "CBC telemetry is not currently verified" end
        return ctx:cannonControl(device.name, method, ...)
    end

    local function aimAll(entries)
        local failures, controlled = {}, {}
        if not ctx:hasCapability("cannon.control") then return false, "Cannon control denied" end
        for _, entry in ipairs(entries) do
            local device = entry.cannon
            local ok, reason = control(device, "setComputerControl", true)
            if not ok then
                failures[#failures + 1] = device.name .. ": " .. tostring(reason)
            else
                controlled[#controlled + 1] = device
                ok, reason = control(device, "setTargetAngles", entry.angles.yaw, entry.angles.pitch)
                if not ok then failures[#failures + 1] = device.name .. ": " .. tostring(reason) end
            end
        end
        if #failures > 0 then
            for _, device in ipairs(controlled) do control(device, "setComputerControl", false) end
        end
        audit("cbc-aim", "count=" .. tostring(#entries) .. " target=" .. tostring(plan.target.x) .. "," .. tostring(plan.target.y) .. "," .. tostring(plan.target.z))
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local function fireAll(entries)
        local failures, fired = {}, {}
        local refreshed = Peripherals.inspect(ctx, Peripherals.parseMetadata(ctx:peripheralMetadataFile() or ""), now())
        local currentDevices = {}
        for _, device in ipairs(refreshed) do currentDevices[device.name] = device end
        local fireNow = os.clock()
        if fireNow - (lastFireAt or -math.huge) < 2 then return false, "Fire cooldown active" end
        lastFireAt = fireNow
        if not ctx:hasCapability("cannon.control") then return false, "Cannon control denied" end
        for _, entry in ipairs(entries) do
            local selectedName = entry.cannon and entry.cannon.name or "unknown"
            entry.cannon = currentDevices[selectedName]
            if not entry.cannon then
                failures[#failures + 1] = "selected cannon detached: " .. tostring(selectedName)
            else
                local info = entry.cannon.cbcInfo or {}
                if not Cannon.aligned(info, entry.angles, settings.tolerance) then
                    failures[#failures + 1] = entry.cannon.name .. ": not aligned"
                elseif info.assembled ~= true then
                    failures[#failures + 1] = entry.cannon.name .. ": not assembled"
                elseif info.computerControl ~= true then
                    failures[#failures + 1] = entry.cannon.name .. ": computer control is not enabled; aim first"
                else
                    local ok, reason = control(entry.cannon, "fire", true)
                    if not ok then failures[#failures + 1] = entry.cannon.name .. ": " .. tostring(reason)
                    else fired[#fired + 1] = entry end
                end
            end
        end
        if #failures > 0 and #fired > 0 then
            local cleanupFailures = {}
            for _, entry in ipairs(fired) do
                local stopped, stopReason = control(entry.cannon, "fire", false)
                if not stopped then cleanupFailures[#cleanupFailures + 1] = entry.cannon.name .. ": " .. tostring(stopReason) end
            end
            for _, reason in ipairs(cleanupFailures) do failures[#failures + 1] = "fire cleanup: " .. reason end
            if #cleanupFailures > 0 then
                -- Keep a bounded cleanup timer armed if a failed mount may
                -- still be level-triggered. The task cleanup callback is a
                -- second path when the app closes or crashes.
                fireArmed = true
                fireTimer = os.startTimer(settings.pulse)
            end
        end
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local function stopAll(entries)
        local failures = {}
        for _, entry in ipairs(entries or {}) do
            local name = entry.cannon and entry.cannon.name or "unknown"
            local ok, reason = control(entry.cannon, "fire", false)
            if not ok then failures[#failures + 1] = name .. ": " .. tostring(reason) end
        end
        audit("cbc-fire-stop", "count=" .. tostring(#(entries or {})) .. " failures=" .. tostring(#failures))
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local render

    local function beginEdit(field)
        editing = field
        input = ""
        status = "Enter " .. field .. "; Enter accepts, Esc cancels"
        render()
    end

    local function acceptEdit()
        local value = tonumber(input)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            status = "Enter a finite number"
            render()
            return
        end
        if editing == "x" or editing == "y" or editing == "z" then
            target[editing] = value
        elseif editing == "yaw offset" then settings.yawOffset = math.max(-180, math.min(180, value))
        elseif editing == "tolerance" then settings.tolerance = math.max(0.1, math.min(20, value))
        elseif editing == "pitch sign" then settings.pitchSign = value < 0 and -1 or 1
        end
        editing = nil
        input = ""
        plan = nil
        status = "Target/settings updated; press P to build a plan"
        render()
    end

    render = function()
        local width, height = ctx.win.getSize()
        local _, _, start = Screen.begin(ctx.win, "CBC Fire Control", nil, { ui = UI })
        UI.text(ctx.win, 2, start, editing and ("Edit " .. editing .. ": " .. input .. "_") or status, UI.colors.muted, UI.colors.surface, width - 3)
        local row, footer = start + 1, height + 1
        local split = math.max(25, math.floor(width * 0.46))
        UI.sectionHeader(ctx.win, 2, row, split - 3, "Verified cannon mounts", { background = colors.yellow, foreground = colors.black })
        UI.sectionHeader(ctx.win, split, row, width - split - 1, "Target / firing state", { background = colors.yellow, foreground = colors.black })
        row = row + 1
        local leftRow = row
        for index, device in ipairs(devices) do
            if leftRow >= footer then break end
            local active = selected[device.name] == true
            local focused = index == cursor
            UI.listRow(ctx.win, 2, leftRow, split - 3, (focused and "> " or "  ") .. (active and "[x] " or "[ ] ") .. (device.alias or device.name), device.cbcInfo and (device.cbcInfo.assembled and "assembled" or "open") or "unknown", focused, { activeBackground = UI.colors.accentLight, activeForeground = colors.white, background = UI.colors.surface })
            leftRow = leftRow + 1
        end
        local right = row
        local function line(label, value, color)
            if right >= footer then return end
            UI.listRow(ctx.win, split, right, width - split - 1, label, tostring(value or "-"), false, { split = 15, valueColor = color or UI.colors.text, background = UI.colors.surface })
            right = right + 1
        end
        line("Mode", targetMode)
        local coordinateText = target.x ~= nil and target.y ~= nil and target.z ~= nil
            and (tostring(target.x) .. ", " .. tostring(target.y) .. ", " .. tostring(target.z)) or "incomplete"
        line("Coordinates", coordinateText)
        line("Radar contacts", #contacts)
        line("Selected", #selectedCannons())
        line("Plan", plan and (#plan.entries .. " ready / " .. #plan.rejected .. " rejected") or "none")
        line("Phase", phase)
        line("Safety", "manual confirmation; no auto-fire", UI.colors.warning)
        if targetMode == "radar" and contacts[selectedContact] then
            line("Contact", contacts[selectedContact].identity .. " / " .. contacts[selectedContact].identityStatus)
        end
        if right < footer then right = right + 1 end
        UI.text(ctx.win, 2, footer, "Up/Down move  Space select  C coords  R radar  X/Y/Z edit  P plan  A aim  F confirm fire  S stop  Esc close", UI.colors.muted, UI.colors.surface, width - 3)
    end

    ctx:registerCleanup(function()
        if fireArmed then
            stopAll(plan and plan.entries or {})
            fireArmed = false
        end
    end)
    refresh()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if editing then
            if event == "char" then input = input .. tostring(value or ""):sub(1, 1); render()
            elseif event == "paste" then input = input .. tostring(value or ""):sub(1, 24); render()
            elseif event == "key" and value == keys.backspace then input = input:sub(1, -2); render()
            elseif event == "key" and value == keys.enter then acceptEdit()
            elseif event == "key" and value == keys.escape then editing = nil; input = ""; render() end
        elseif event == "key" then
            if value == keys.up or value == keys.down then
                cursor = value == keys.up and math.max(1, cursor - 1) or math.min(math.max(1, #devices), cursor + 1)
                render()
            elseif value == keys.space then
                if devices[cursor] then
                    selected = Cannon.toggleSelection(selected, devices[cursor].name)
                    plan = nil
                end
                render()
            elseif value == keys.c then targetMode = "coordinates"; plan = nil; render()
            elseif value == keys.r then targetMode = "radar"; plan = nil; render()
            elseif value == keys.left and targetMode == "radar" then selectedContact = math.max(1, selectedContact - 1); plan = nil; render()
            elseif value == keys.right and targetMode == "radar" then selectedContact = math.min(math.max(1, #contacts), selectedContact + 1); plan = nil; render()
            elseif value == keys.x then beginEdit("x")
            elseif value == keys.y then beginEdit("y")
            elseif value == keys.z then beginEdit("z")
            elseif value == keys.p then buildPlan(); render()
            elseif value == keys.a then
                if buildPlan() and plan then
                    local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Confirm cannon aim", dialogMessage = "Aim " .. tostring(#plan.entries) .. " cannon(s) at the selected target?" })
                    if dialog then
                        dialog.context.dialogCallback = function()
                            local ok, reason = aimAll(plan.entries)
                            phase = ok and "aiming" or "aim failed"
                            status = ok and "Aim command sent; refresh to observe movement" or tostring(reason)
                            render()
                            return ok, reason
                        end
                        dialog.context.dialogCancelCallback = function() status = "Aim cancelled"; audit("cbc-aim-cancelled", "count=" .. tostring(#plan.entries)); render() end
                    end
                end
            elseif value == keys.f then
                if not plan and not buildPlan() then render()
                elseif plan then
                    local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Confirm CBC fire", dialogMessage = "Fire " .. tostring(#plan.entries) .. " cannon(s) at the selected target?" })
                    if dialog then
                        dialog.context.dialogCallback = function()
                            -- Radar data and the selected target may have changed
                            -- while the confirmation dialog was open. Refresh
                            -- and rebuild immediately before any fire call.
                            refresh()
                            local fresh, freshReason = buildPlan()
                            if not fresh or not plan then
                                status = freshReason or "Fire plan is no longer valid"
                                phase = "fire rejected"
                                render()
                                return false, status
                            end
                            local ok, reason = fireAll(plan.entries)
                            phase = ok and "fire pulse active" or "fire partial/failed"
                            status = ok and "Fire signal sent; pulse will clear automatically" or tostring(reason)
                            if ok then
                                fireArmed = true
                                fireTimer = os.startTimer(settings.pulse)
                            end
                            render()
                            return ok, reason
                        end
                        dialog.context.dialogCancelCallback = function() status = "Fire cancelled"; audit("cbc-fire-cancelled", "count=" .. tostring(#plan.entries)); render() end
                    end
                end
            elseif value == keys.s then
                local ok, reason = stopAll(plan and plan.entries or {})
                phase = "stopped"
                status = ok and "Fire signal cleared" or tostring(reason)
                render()
            elseif value == keys.escape then
                if fireArmed then
                    fireArmed = false
                    fireTimer = nil
                    stopAll(plan and plan.entries or {})
                end
                ctx:close()
            end
        elseif event == "timer" and fireTimer and value == fireTimer then
            fireTimer = nil
            fireArmed = false
            local ok, reason = stopAll(plan and plan.entries or {})
            phase = "stopped"
            status = ok and "Fire pulse cleared" or tostring(reason)
            render()
        elseif event == "peripheral" or event == "peripheral_detach" or event == "qalcom_tick" then
            if event == "peripheral_detach" and fireArmed then
                stopAll(plan and plan.entries or {})
                fireArmed = false
                fireTimer = nil
                phase = "stopped after peripheral detach"
            end
            refresh()
            if plan and target then buildPlan() end
            render()
        end
    end
end
