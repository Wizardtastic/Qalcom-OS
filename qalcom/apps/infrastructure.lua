local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Infrastructure = dofile("/qalcom/lib/infrastructure.lua")
return function(ctx)
    local data = Infrastructure.empty()
    local selected = 1
    local states = {}
    local pulses = {}
    local profilesDirty = false
    local status = "Read-only until an output action is confirmed"
    local editing = false
    local input = ""

    local function audit(action, detail)
        if ctx.audit then ctx:audit(action, detail) end
    end

    local function load()
        data = ctx:infrastructureProfiles() or Infrastructure.empty()
        profilesDirty = false
        states = {}
        for _, profile in ipairs(data.profiles) do
            states[profile.id] = ctx:infrastructureState(profile)
        end
        selected = math.max(1, math.min(selected, math.max(1, #data.profiles)))
    end

    local function save()
        local ok, reason = ctx:writeInfrastructureProfiles(data)
        if ok then profilesDirty = false; status = "Infrastructure profiles saved" else status = reason or "Unable to save profiles" end
        return ok
    end

    local function profile()
        return data.profiles[selected]
    end

    local render

    local function addProfile()
        if #data.profiles >= Infrastructure.maxProfiles then
            status = "Profile limit reached"
            render()
            return
        end
        local index = #data.profiles + 1
        local item = Infrastructure.normalizeProfile({
            id = "output-" .. tostring(index),
            label = "New Output " .. tostring(index),
            kind = "output",
            side = "back",
            safe = false,
            confirm = true,
            zone = "local",
            maxPulse = 5,
        })
        data.profiles[#data.profiles + 1] = item
        profilesDirty = true
        selected = #data.profiles
        status = "Added " .. Infrastructure.profileName(item) .. "; press S to save"
        render()
    end

    local function pulseText(item)
        local pulse = pulses[item.id]
        if not pulse then return "" end
        local remaining = math.max(0, pulse.untilAt - os.clock())
        return string.format("pulse %.1fs", remaining)
    end

    render = function()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "Infrastructure Controls", status, { ui = UI })
        local footer = math.max(contentStart, height - 2)
        local split = math.max(18, math.floor(width * 0.44))
        local active = profile()
        UI.text(ctx.win, 2, contentStart, "Named points", UI.colors.accent, UI.colors.surface, split - 3)
        UI.text(ctx.win, split, contentStart, "State and controls", UI.colors.accent, UI.colors.surface, width - split - 1)
        local row = contentStart + 1
        local visible = math.max(0, footer - row)
        local start = math.max(1, math.min(selected - visible + 1, #data.profiles - visible + 1))
        for index = start, math.min(#data.profiles, start + visible - 1) do
            local item = data.profiles[index]
            local state = states[item.id] or {}
            local activeRow = index == selected
            local background = activeRow and UI.colors.accentLight or UI.colors.surface
            local foreground = activeRow and colors.white or UI.colors.text
            UI.fill(ctx.win, 2, row + index - start, split - 3, 1, background)
            local marker = item.blocked and "X " or (item.kind == "output" and "> " or "< ")
            UI.text(ctx.win, 3, row + index - start, marker .. Infrastructure.profileName(item), foreground, background, split - 5)
            UI.text(ctx.win, split - 12, row + index - start, state.online and (state.value and "ON" or "OFF") or "OFFLINE", state.online and (state.value and UI.colors.success or UI.colors.muted) or UI.colors.warning, background, 10)
        end
        if active and row < footer then
            local detailRow = row
            local function detail(label, value, color)
                if detailRow >= footer then return end
                UI.text(ctx.win, split, detailRow, label, UI.colors.muted, UI.colors.surface, 13)
                UI.text(ctx.win, split + 14, detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, width - split - 15)
                detailRow = detailRow + 1
            end
            local state = states[active.id] or {}
            detail("Name", Infrastructure.profileName(active))
            detail("Kind", active.kind)
            detail("Side", active.side)
            detail("Zone", active.zone)
            detail("Access", active.blocked and "BLOCKED" or (active.confirm and "confirm writes" or "direct writes"), active.blocked and UI.colors.danger or UI.colors.muted)
            detail("State", state.online and (state.value and "ON" or "OFF") or (state.reason or "OFFLINE"), state.online and (state.value and UI.colors.success or UI.colors.muted) or UI.colors.warning)
            detail("Pulse", pulseText(active) ~= "" and pulseText(active) or "none")
            if detailRow < footer then detailRow = detailRow + 1 end
            if detailRow < footer then
                UI.text(ctx.win, split, detailRow, active.kind == "output" and "Enter toggle   P pulse" or "Input is read-only", UI.colors.accent, UI.colors.surface, width - split - 1)
                detailRow = detailRow + 1
            end
            if detailRow < footer then
                UI.text(ctx.win, split, detailRow, "Safe state: " .. (Infrastructure.safeState(active) and "ON" or "OFF"), UI.colors.muted, UI.colors.surface, width - split - 1)
            end
        elseif row < footer then
            UI.text(ctx.win, split, row, "No infrastructure profile configured", UI.colors.muted, UI.colors.surface, width - split - 1)
        end
        UI.fill(ctx.win, 1, height - 2, width, 3, UI.colors.surfaceAlt)
        if editing then
            UI.text(ctx.win, 2, height - 2, "Pulse seconds (1-" .. tostring(Infrastructure.maxPulseSeconds) .. "):", colors.white, UI.colors.accentLight, width - 3)
            UI.text(ctx.win, 2, height - 1, input .. "_", colors.white, UI.colors.accentLight, width - 3)
            UI.text(ctx.win, 2, height, "Enter continue   Esc cancel", colors.white, UI.colors.accentLight, width - 3)
        else
            UI.text(ctx.win, 2, height - 2, "Up/Down select   N new output   Enter toggle", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
            UI.text(ctx.win, 2, height - 1, "P pulse   E safe-state   S save   I refresh", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
            UI.text(ctx.win, 2, height, "Esc close   Profile labels/sides are stored metadata", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        end
    end

    local function performWrite(item, value, reason)
        if not item or item.kind ~= "output" then return false, "Only output profiles can change state" end
        if item.enabled == false then
            audit("infrastructure-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " reason=disabled")
            return false, "Profile disabled"
        end
        if item.blocked then
            audit("infrastructure-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " reason=blocklisted")
            return false, "Profile is blocklisted"
        end
        if not Infrastructure.zoneAllowed(item) then
            audit("infrastructure-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " reason=zone")
            return false, "Profile zone is not locally approved"
        end
        if not ctx:hasCapability("redstone.control") or not ctx:hasCapability("infrastructure.control") then
            audit("infrastructure-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " reason=capability")
            return false, "Infrastructure control denied"
        end
        local ok, failure = ctx:redstoneWrite(item.side, value)
        if not ok then
            audit("infrastructure-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " reason=" .. tostring(failure))
            return false, failure or "Output unavailable"
        end
        states[item.id] = ctx:infrastructureState(item)
        audit("infrastructure-write", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " side=" .. item.side .. " value=" .. tostring(value) .. " reason=" .. tostring(reason or "manual"))
        status = Infrastructure.profileName(item) .. " set " .. (value and "ON" or "OFF")
        return true
    end

    local function confirmWrite(item, value, reason)
        if not item then return end
        if not item.confirm then
            local ok, failure = performWrite(item, value, reason)
            if not ok then ctx:notify(failure, UI.colors.danger) end
            render()
            return
        end
        local dialog = ctx:launch("dialog", {
            modal = true,
            dialogTitle = value and "Confirm output ON" or "Confirm output OFF",
            dialogMessage = Infrastructure.profileName(item) .. " / " .. item.side .. " → " .. (value and "ON" or "OFF") .. "?",
        })
        if not dialog then status = "Unable to open confirmation"; render(); return end
        dialog.context.dialogCallback = function()
            local ok, failure = performWrite(item, value, reason)
            if not ok then return false, failure end
            render()
            return true
        end
        dialog.context.dialogCancelCallback = function()
            audit("infrastructure-cancelled", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " value=" .. tostring(value))
            status = "Output change cancelled"
            render()
        end
    end

    local function startPulse(item, seconds)
        local allowed, reason = Infrastructure.canPulse(item, seconds)
        if not allowed then
            audit("infrastructure-pulse-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. tostring(item and item.id) .. " reason=" .. tostring(reason))
            status = reason
            render()
            return
        end
        local ok, failure = performWrite(item, true, "pulse-start")
        if not ok then ctx:notify(failure, UI.colors.danger); render(); return end
        local timer = os.startTimer(seconds)
        pulses[item.id] = { timer = timer, untilAt = os.clock() + seconds, value = true, profile = Infrastructure.normalizeProfile(item, item.id) }
        audit("infrastructure-pulse-start", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " seconds=" .. tostring(seconds))
        status = "Pulse started: " .. Infrastructure.profileName(item)
        render()
    end

    local function emergencySafeState()
        if not ctx:hasCapability("redstone.control") or not ctx:hasCapability("infrastructure.control") or not ctx:hasCapability("infrastructure.emergency") then
            audit("infrastructure-safe-state-denied", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " reason=capability")
            status = "Emergency safe-state denied"
            render()
            return
        end
        local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Emergency safe-state", dialogMessage = "Set every enabled output to its safe state?" })
        if not dialog then status = "Unable to open confirmation"; render(); return end
        dialog.context.dialogCallback = function()
            local failures = 0
            local attempted = 0
            for _, item in ipairs(data.profiles) do
                if item.kind == "output" and item.enabled ~= false then
                    attempted = attempted + 1
                    local ok, failure = performWrite(item, Infrastructure.safeState(item), "emergency-safe-state")
                    if not ok then failures = failures + 1; audit("infrastructure-safe-state-failed", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " " .. tostring(failure)) end
                end
            end
            audit("infrastructure-safe-state", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " outputs=" .. tostring(attempted) .. " failures=" .. tostring(failures))
            status = failures == 0 and "All outputs set to safe state" or (tostring(failures) .. " output(s) failed safe-state")
            if profilesDirty then profilesDirty = false end
            load()
            render()
            return failures == 0, status
        end
    end

    ctx:registerCleanup(function()
        for id, pulse in pairs(pulses) do
            local item = pulse.profile
            local ok, failure = performWrite(item, Infrastructure.safeState(item), "pulse-cleanup")
            if not ok then audit("infrastructure-pulse-cleanup-failed", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. tostring(id) .. " " .. tostring(failure)) end
            pulses[id] = nil
        end
    end)
    load()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if editing then
            if event == "char" then
                if #input < 3 then input = input .. tostring(value):gsub("[^0-9]", "") end
                render()
            elseif event == "paste" then
                input = input .. tostring(value):gsub("[^0-9]", ""):sub(1, 3 - #input)
                render()
            elseif event == "key" then
                if value == keys.backspace then input = input:sub(1, math.max(0, #input - 1)); render()
                elseif value == keys.escape then editing = false; input = ""; render()
                elseif value == keys.enter then
                    local seconds = tonumber(input)
                    editing = false
                    input = ""
                    local item = profile()
                    local dialog = ctx:launch("dialog", { modal = true, dialogTitle = "Confirm pulse", dialogMessage = Infrastructure.profileName(item) .. " for " .. tostring(seconds or "?") .. " second(s)?" })
                    if dialog then
                        dialog.context.dialogCallback = function() startPulse(item, seconds); return true end
                        dialog.context.dialogCancelCallback = function() audit("infrastructure-cancelled", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. item.id .. " pulse"); status = "Pulse cancelled"; render() end
                    end
                    render()
                end
            elseif event == "term_resize" then render() end
        elseif event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(math.max(1, #data.profiles), selected + 1); render()
            elseif value == keys.enter then
                local item = profile()
                if item and item.kind == "output" then
                    local current = states[item.id] and states[item.id].value == true
                    confirmWrite(item, not current, "manual")
                end
            elseif value == keys.n then addProfile()
            elseif value == keys.p then
                local item = profile()
                if item and item.kind == "output" then editing = true; input = ""; editKind = "pulse"; render() end
            elseif value == keys.e then emergencySafeState()
            elseif value == keys.s then save(); render()
            elseif value == keys.i or value == keys.r then
                if profilesDirty then status = "Unsaved profile changes; press S before refresh" else load(); status = "Inputs refreshed" end
                render()
            elseif value == keys.escape then
                if profilesDirty then status = "Unsaved profile changes; press S before closing"; render() else ctx:close() end
            end
        elseif event == "mouse_scroll" then
            selected = value < 0 and math.max(1, selected - 1) or math.min(math.max(1, #data.profiles), selected + 1)
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then
            if not profilesDirty then load() end
            for id, pulse in pairs(pulses) do
                if os.clock() >= pulse.untilAt then
                    local ok, failure = performWrite(pulse.profile, Infrastructure.safeState(pulse.profile), "pulse-complete")
                    if not ok then audit("infrastructure-pulse-failed", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. tostring(id) .. " " .. tostring(failure)) end
                    pulses[id] = nil
                end
            end
            render()
        elseif event == "timer" then
            for id, pulse in pairs(pulses) do
                if pulse.timer == value then
                    local ok, failure = performWrite(pulse.profile, Infrastructure.safeState(pulse.profile), "pulse-complete")
                    if not ok then ctx:notify(failure, UI.colors.danger); audit("infrastructure-pulse-failed", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. tostring(id) .. " " .. tostring(failure)) end
                    pulses[id] = nil
                    render()
                end
            end
        end
    end
end
