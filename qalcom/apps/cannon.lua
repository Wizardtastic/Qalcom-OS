local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Peripherals = dofile("/qalcom/lib/peripherals.lua")
local Cannon = dofile("/qalcom/lib/cannon.lua")

return function(ctx)
    local devices = {}
    local selected = {}
    local contacts = {}
    local cursor = 1
    local selectedContact = 1
    local targetMode = "coordinates"
    local fields = { x = "", y = "", z = "" }
    local editingField = nil
    local plan = nil
    local status = "Select mounts and enter a target"
    local phase = "idle"
    local settings = Cannon.settings({})
    local fireArmed = false
    local fireTimer = nil
    local cleanupAttempts = 0
    local maxCleanupAttempts = 3
    local lastFireAt = -math.huge
    local hitTargets = {}
    local hovered = nil

    local function isHovered(action, field, name)
        return hovered and hovered.action == action
            and (not field or hovered.field == field)
            and (not name or hovered.name == name)
    end

    local function now()
        if os.epoch then
            local ok, value = pcall(os.epoch, "utc")
            if ok and value then return math.floor(value / 1000) end
        end
        return math.floor(os.clock())
    end

    local function audit(action, detail)
        if ctx.audit then
            ctx:audit(action, "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " " .. tostring(detail or ""))
        end
    end

    local function refresh()
        if not ctx:hasCapability("cannon.control") then
            devices = {}
            contacts = {}
            status = "Cannon control denied for this role"
            return
        end
        local metadataText = ctx:peripheralMetadataFile() or ""
        local metadata = Peripherals.parseMetadata(metadataText)
        local all = Peripherals.inspect(ctx, metadata, now())
        devices = {}
        contacts = {}
        for _, device in ipairs(all) do
            for _, adapter in ipairs(device.adapters or {}) do
                if adapter.name == "cbc" and adapter.apiCompatible and not device.blocked then
                    devices[#devices + 1] = device
                    break
                end
            end
            for _, contact in ipairs(device.contacts or {}) do
                if #contacts < 32 then contacts[#contacts + 1] = contact end
            end
        end
        cursor = math.max(1, math.min(cursor, math.max(1, #devices)))
        selectedContact = math.max(1, math.min(selectedContact, math.max(1, #contacts)))
        status = #devices == 0 and "No verified CBC mounts available"
            or (tostring(#devices) .. " verified mount(s) available")
    end

    local function selectedCannons()
        return Cannon.selectedDevices(devices, selected)
    end

    local function currentTarget()
        if targetMode == "radar" then
            local contact = contacts[selectedContact]
            if not contact or contact.identityStatus == "ambiguous" then
                return nil, "Choose a non-ambiguous radar contact"
            end
            return Cannon.targetFromContact(contact)
        end
        if fields.x == "" or fields.y == "" or fields.z == "" then
            return nil, "Enter X, Y, and Z coordinates"
        end
        return Cannon.target(fields.x, fields.y, fields.z)
    end

    local function buildPlan()
        local target, reason = currentTarget()
        if not target then
            plan = nil
            status = reason or "Target is invalid"
            return false
        end
        local cannons = selectedCannons()
        if #cannons == 0 then
            plan = nil
            status = "Select at least one cannon"
            return false
        end
        plan = Cannon.plan(cannons, target, settings)
        plan.target = target
        if #plan.entries == 0 then
            status = "No selected mount has a usable position"
            return false
        end
        status = "Plan ready: " .. tostring(#plan.entries) .. " mount(s), " .. tostring(#plan.rejected) .. " rejected"
        return true
    end

    local function control(device, method, ...)
        if not device or not device.name then return false, "Cannon identity unavailable" end
        local present = false
        for _, name in ipairs(ctx:peripheralNames() or {}) do
            if name == device.name then present = true; break end
        end
        if not present then return false, "Cannon peripheral detached" end
        local kind = ctx:peripheralType(device.name)
        if kind ~= "cannon_mount" and kind ~= "compact_cannon_mount" then
            return false, "Peripheral is not a verified CBC mount"
        end
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
        audit("cbc-aim", "count=" .. tostring(#entries))
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local function fireAll(entries)
        local failures, fired = {}, {}
        local refreshed = Peripherals.inspect(ctx, Peripherals.parseMetadata(ctx:peripheralMetadataFile() or ""), now())
        local current = {}
        for _, device in ipairs(refreshed) do current[device.name] = device end
        local fireNow = os.clock()
        if fireNow - lastFireAt < 2 then return false, "Fire cooldown active" end
        lastFireAt = fireNow
        if not ctx:hasCapability("cannon.control") then return false, "Cannon control denied" end
        for _, entry in ipairs(entries) do
            local name = entry.cannon and entry.cannon.name or "unknown"
            entry.cannon = current[name]
            if not entry.cannon then
                failures[#failures + 1] = "selected cannon detached: " .. name
            else
                local info = entry.cannon.cbcInfo or {}
                if not Cannon.aligned(info, entry.angles, settings.tolerance) then
                    failures[#failures + 1] = name .. ": not aligned"
                elseif info.assembled ~= true then
                    failures[#failures + 1] = name .. ": not assembled"
                elseif info.computerControl ~= true then
                    failures[#failures + 1] = name .. ": aim first to enable computer control"
                else
                    local ok, reason = control(entry.cannon, "fire", true)
                    if not ok then failures[#failures + 1] = name .. ": " .. tostring(reason)
                    else fired[#fired + 1] = entry end
                end
            end
        end
        if #failures > 0 and #fired > 0 then
            local stopFailures = {}
            for _, entry in ipairs(fired) do
                local stopped, stopReason = control(entry.cannon, "fire", false)
                if not stopped then stopFailures[#stopFailures + 1] = entry.cannon.name .. ": " .. tostring(stopReason) end
            end
            for _, reason in ipairs(stopFailures) do failures[#failures + 1] = "fire cleanup: " .. reason end
            if #stopFailures > 0 then
                fireArmed = true
                if not fireTimer then fireTimer = os.startTimer(settings.pulse) end
            end
        end
        audit("cbc-fire", "count=" .. tostring(entries and #entries or 0) .. " failures=" .. tostring(#failures))
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local function stopAll(entries)
        local failures = {}
        for _, entry in ipairs(entries or {}) do
            local name = entry.cannon and entry.cannon.name or "unknown"
            local ok, reason = control(entry.cannon, "fire", false)
            if not ok then failures[#failures + 1] = name .. ": " .. tostring(reason) end
        end
        -- Keep the cleanup path armed when a mount could not be disarmed; the
        -- kernel cleanup callback must get another chance during task close.
        if #failures == 0 then
            fireArmed = false
            fireTimer = nil
            cleanupAttempts = 0
        else
            fireArmed = true
            cleanupAttempts = cleanupAttempts + 1
            if cleanupAttempts < maxCleanupAttempts and not fireTimer then fireTimer = os.startTimer(settings.pulse) end
        end
        audit("cbc-fire-stop", "count=" .. tostring(entries and #entries or 0) .. " failures=" .. tostring(#failures))
        return #failures == 0, #failures > 0 and table.concat(failures, "; ") or nil
    end

    local function entriesForStop()
        if plan and plan.entries then return plan.entries end
        local entries = {}
        for _, device in ipairs(selectedCannons()) do entries[#entries + 1] = { cannon = device } end
        return entries
    end

    local render

    local function sanitizeInput(value)
        value = tostring(value or "")
        local result = {}
        local hasDot = false
        for index = 1, #value do
            local character = value:sub(index, index)
            if character >= "0" and character <= "9" then
                result[#result + 1] = character
            elseif character == "." and not hasDot then
                hasDot = true
                result[#result + 1] = character
            elseif character == "-" and #result == 0 and index == 1 then
                result[#result + 1] = character
            end
        end
        return table.concat(result):sub(1, 16)
    end

    local function commitField()
        if not editingField then return true end
        if fields[editingField] == "" or fields[editingField] == "-" or fields[editingField] == "." or fields[editingField] == "-." then
            status = "Enter a valid " .. string.upper(editingField) .. " coordinate"
            return false
        end
        if not tonumber(fields[editingField]) then
            status = "Enter a finite " .. string.upper(editingField) .. " coordinate"
            return false
        end
        editingField = nil
        return true
    end

    local function beginField(field)
        if editingField and editingField ~= field and not commitField() then return end
        editingField = field
        status = "Editing " .. string.upper(field) .. "; type a value"
        render()
    end

    local function press(action)
        if action == "coordinates" or action == "radar" then
            if not commitField() then render(); return end
            targetMode = action
            plan = nil
            status = action == "radar" and "Choose a fresh radar contact" or "Enter all three coordinates"
        elseif action == "refresh" then
            if fireArmed then stopAll(entriesForStop()) end
            refresh()
            plan = nil
            status = "Peripheral and radar data refreshed"
        elseif action == "prev-contact" then
            selectedContact = math.max(1, selectedContact - 1)
            plan = nil
        elseif action == "next-contact" then
            selectedContact = math.min(math.max(1, #contacts), selectedContact + 1)
            plan = nil
        elseif action == "select-cannon" or action == "toggle-current" then
            local device = devices[cursor]
            if device then selected[device.name] = not selected[device.name]; plan = nil end
        elseif action == "up-cannon" then
            cursor = math.max(1, cursor - 1)
        elseif action == "down-cannon" then
            cursor = math.min(math.max(1, #devices), cursor + 1)
        elseif action == "plan" then
            if commitField() then buildPlan() end
        elseif action == "aim" then
            if commitField() and buildPlan() then
                local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Confirm cannon aim", dialogMessage = "Aim " .. tostring(#plan.entries) .. " mount(s) at this target?" })
                if dialog then
                    dialog.context.dialogCallback = function()
                        refresh()
                        if not commitField() or not buildPlan() then return false, status end
                        local ok, reason = aimAll(plan.entries)
                        phase = ok and "aiming" or "aim failed"
                        status = ok and "Aim command sent" or tostring(reason)
                        render()
                        return ok, reason
                    end
                    dialog.context.dialogCancelCallback = function()
                        status = "Aim cancelled"
                        audit("cbc-aim-cancelled", "")
                        render()
                    end
                end
            end
        elseif action == "fire" then
            if commitField() and buildPlan() then
                local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Confirm CBC fire", dialogMessage = "Fire " .. tostring(#plan.entries) .. " mount(s) at this target?" })
                if dialog then
                    dialog.context.dialogCallback = function()
                        refresh()
                        if not commitField() or not buildPlan() then return false, status end
                        local ok, reason = fireAll(plan.entries)
                        phase = ok and "fire pulse active" or "fire failed"
                        status = ok and "Fire signal sent; it will clear automatically" or tostring(reason)
                        if ok then
                            fireArmed = true
                            fireTimer = os.startTimer(settings.pulse)
                        end
                        render()
                        return ok, reason
                    end
                    dialog.context.dialogCancelCallback = function()
                        status = "Fire cancelled"
                        audit("cbc-fire-cancelled", "")
                        render()
                    end
                end
            end
        elseif action == "stop" then
            local ok, reason = stopAll(entriesForStop())
            phase = "stopped"
            status = ok and "Fire signal cleared" or tostring(reason)
        end
        render()
    end

    local function addButton(x, y, width, label, action, active, options)
        local button = UI.button(ctx.win, x, y, width, label, active or isHovered(action), options)
        button.action = action
        hitTargets[#hitTargets + 1] = button
    end

    render = function()
        local width, height = ctx.win.getSize()
        local _, _, body = Screen.begin(ctx.win, "CBC Fire Control", nil, { ui = UI })
        hitTargets = {}
        UI.text(ctx.win, 2, body, status, UI.colors.muted, UI.colors.surface, width - 3)
        local top = body + 1
        local compact = width < 50
        if height < 16 then
            UI.text(ctx.win, 2, body + 1, "CBC Fire Control needs a terminal height of 16+", UI.colors.warning, UI.colors.surface, width - 3)
            return
        end
        local leftWidth = compact and math.max(1, width - 2) or math.min(24, math.max(16, math.floor(width * 0.42)))
        local rightX = compact and 2 or leftWidth + 3
        local rightWidth = compact and math.max(1, width - 2) or math.max(1, width - rightX)
        local targetTop = compact and math.max(top + 3, math.min(height - 10, top + 5)) or top
        UI.sectionHeader(ctx.win, 2, top, leftWidth, "CANNON BATTERY", { background = colors.yellow, foreground = colors.black })
        UI.sectionHeader(ctx.win, rightX, targetTop, rightWidth, "TARGETING", { background = colors.yellow, foreground = colors.black })

        local row = top + 1
        local maxMountRows = compact and 2 or math.huge
        for index, device in ipairs(devices) do
            if index > maxMountRows or row >= (compact and targetTop - 1 or height - 3) then break end
            local active = selected[device.name] == true
            local focused = index == cursor
            local button = UI.button(ctx.win, 2, row, leftWidth, (focused and "> " or "  ") .. (active and "[x] " or "[ ] ") .. (device.alias or device.name), focused or isHovered("select-cannon", nil, device.name), {
                background = active and colors.green or colors.gray,
                activeBackground = UI.colors.accentLight,
                foreground = active and colors.white or colors.black,
                activeForeground = colors.white,
            })
            button.action = "select-cannon"
            button.name = device.name
            hitTargets[#hitTargets + 1] = button
            row = row + 1
        end
        if #devices == 0 then
            UI.text(ctx.win, 3, row, "No verified mounts", UI.colors.muted, UI.colors.surface, leftWidth - 2)
        end
        local navY = math.min(targetTop - 2, row + 1)
        addButton(2, navY, math.max(3, math.floor(leftWidth / 4)), "UP", "up-cannon", false, { background = colors.gray })
        addButton(2 + math.max(3, math.floor(leftWidth / 4)) + 1, navY, math.max(3, math.floor(leftWidth / 4)), "DOWN", "down-cannon", false, { background = colors.gray })
        addButton(2 + (math.max(3, math.floor(leftWidth / 4)) + 1) * 2, navY, math.max(3, leftWidth - (math.max(3, math.floor(leftWidth / 4)) + 1) * 2), "TOGGLE CURRENT", "toggle-current", isHovered("toggle-current"), { background = colors.gray })

        local modeWidth = math.max(4, math.floor((rightWidth - 1) / 2))
        addButton(rightX, targetTop + 1, modeWidth, "COORDS", "coordinates", targetMode == "coordinates", { background = colors.gray })
        addButton(rightX + modeWidth + 1, targetTop + 1, math.max(1, rightWidth - modeWidth - 1), "RADAR", "radar", targetMode == "radar", { background = colors.gray })
        addButton(rightX, targetTop + 2, rightWidth, "REFRESH", "refresh", false, { background = colors.gray })

        local controlsY = targetTop + 4
        if targetMode == "coordinates" then
            local fieldWidth = math.max(4, math.floor((rightWidth - 2) / 3))
            local fieldGap = fieldWidth >= 7 and 1 or 0
            fieldWidth = math.max(4, math.floor((rightWidth - fieldGap * 2) / 3))
            local fieldsX = { rightX, rightX + fieldWidth + fieldGap, rightX + (fieldWidth + fieldGap) * 2 }
            local names = { "x", "y", "z" }
            for index, name in ipairs(names) do
                UI.input(ctx.win, fieldsX[index], controlsY + 1, fieldWidth, string.upper(name), fields[name], editingField == name or isHovered("edit-field", name))
                local hit = { x = fieldsX[index], y = controlsY + 1, width = fieldWidth, height = 1, action = "edit-field", field = name }
                hitTargets[#hitTargets + 1] = hit
            end
            UI.text(ctx.win, rightX, controlsY + 3, "Geometric line-of-sight aim; not ballistic", UI.colors.muted, UI.colors.surface, rightWidth)
        else
            local contact = contacts[selectedContact]
            addButton(rightX, controlsY + 1, 5, "<", "prev-contact", false, { background = colors.gray })
            addButton(rightX + 6, controlsY + 1, 5, ">", "next-contact", false, { background = colors.gray })
            local contactText = contact and (contact.identity .. " / " .. contact.identityStatus) or "No radar contact"
            UI.text(ctx.win, rightX + 12, controlsY + 1, contactText, contact and UI.colors.text or UI.colors.muted, UI.colors.surface, rightWidth - 12)
            local position = contact and contact.position
            UI.text(ctx.win, rightX, controlsY + 3, position and ("Position " .. tostring(position.x) .. ", " .. tostring(position.y) .. ", " .. tostring(position.z)) or "Position unavailable", UI.colors.muted, UI.colors.surface, rightWidth)
            UI.text(ctx.win, rightX, controlsY + 4, contact and ("Age " .. tostring(contact.age or "?") .. "s / confidence " .. tostring(contact.confidence or "?")) or "", UI.colors.muted, UI.colors.surface, rightWidth)
        end

        local actionY = height - 3
        local actions = {
            { label = "PLAN", name = "plan", background = colors.gray, foreground = colors.black },
            { label = "AIM", name = "aim", background = colors.blue, foreground = colors.white },
            { label = "FIRE", name = "fire", background = colors.red, foreground = colors.white },
            { label = "STOP", name = "stop", background = colors.red, foreground = colors.white },
        }
        local actionGap = 1
        if rightWidth >= 23 then
            local actionWidth = math.max(5, math.floor((rightWidth - actionGap * 3) / 4))
            for index, action in ipairs(actions) do
                local buttonWidth = index == 4 and math.max(1, rightWidth - (actionWidth + actionGap) * 3) or actionWidth
                addButton(rightX + (index - 1) * (actionWidth + actionGap), actionY, buttonWidth, action.label, action.name, false, { background = action.background, foreground = action.foreground })
            end
        else
            -- At compact terminal sizes, use two rows instead of drawing
            -- controls beyond the right edge of the window.
            local compactWidth = math.max(3, math.floor((rightWidth - actionGap) / 2))
            for index = 1, 2 do
                local action = actions[index]
                addButton(rightX + (index - 1) * (compactWidth + actionGap), actionY - 1, compactWidth, action.label, action.name, false, { background = action.background, foreground = action.foreground })
            end
            for index = 3, 4 do
                local action = actions[index]
                addButton(rightX + (index - 3) * (compactWidth + actionGap), actionY, compactWidth, action.label, action.name, false, { background = action.background, foreground = action.foreground })
            end
        end
        UI.text(ctx.win, rightX, actionY - 2, "Phase: " .. phase .. "  Selected: " .. tostring(#selectedCannons()) .. "  Plan: " .. (plan and tostring(#plan.entries) or "none"), UI.colors.muted, UI.colors.surface, rightWidth)
        UI.text(ctx.win, 2, height, "Click a mount, field, mode, contact, or action. Fire always requires confirmation.", UI.colors.muted, UI.colors.surface, width - 3)
    end

    ctx:registerCleanup(function()
        if fireArmed then
            for _ = 1, maxCleanupAttempts do
                local ok = stopAll(plan and plan.entries or {})
                if ok then break end
            end
        end
    end)
    refresh()
    render()
    while true do
        local event, value, x, y = ctx:pullEvent()
        if event == "mouse_move" then
            hovered = UI.hitButton(hitTargets, x, y)
            render()
        elseif event == "mouse_click" then
            local target = UI.hitButton(hitTargets, x, y)
            if target then
                if target.action == "edit-field" then
                    beginField(target.field)
                elseif target.action == "select-cannon" then
                    for index, device in ipairs(devices) do if device.name == target.name then cursor = index; break end end
                    press("select-cannon")
                else
                    press(target.action)
                end
            end
        elseif editingField then
            if event == "char" then
                fields[editingField] = sanitizeInput(fields[editingField] .. tostring(value or ""))
                render()
            elseif event == "paste" then
                fields[editingField] = sanitizeInput(fields[editingField] .. tostring(value or ""))
                render()
            elseif event == "key" and value == keys.backspace then
                fields[editingField] = fields[editingField]:sub(1, -2)
                render()
            elseif event == "key" and value == keys.enter then
                if commitField() then status = "Coordinate updated; press PLAN" end
                render()
            elseif event == "key" and value == keys.escape then
                editingField = nil
                render()
            end
        elseif event == "key" and value == keys.escape then
            ctx:close()
        elseif event == "timer" and fireTimer and value == fireTimer then
            fireTimer = nil
            local ok, reason = stopAll(plan and plan.entries or {})
            phase = "stopped"
            status = ok and "Fire pulse cleared" or tostring(reason)
            render()
        elseif event == "peripheral_detach" then
            local wasArmed = fireArmed
            if wasArmed then stopAll(plan and plan.entries or {}) end
            refresh()
            plan = nil
            phase = wasArmed and "stopped after detach" or phase
            render()
        elseif event == "peripheral" or event == "qalcom_tick" or event == "term_resize" then
            refresh()
            render()
        end
    end
end
