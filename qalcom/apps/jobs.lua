local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Jobs = dofile("/qalcom/lib/jobs.lua")
local Infrastructure = dofile("/qalcom/lib/infrastructure.lua")

return function(ctx)
    local data = Jobs.empty()
    local selected = 1
    local history = {}
    local lastRun = {}
    local nextTimer = {}
    local status = "Structured jobs are disabled until explicitly enabled"
    local editing = false
    local input = ""
    local editingField = nil
    local profiles = Infrastructure.empty()
    local profileStates = {}

    local function audit(action, detail)
        if ctx.audit then ctx:audit(action, detail) end
    end

    local function load()
        data = ctx:jobDefinitions() or Jobs.empty()
        if data.error then status = data.error end
        local historyText = ctx:readFile("/qalcom/data/jobs.history")
        history = Jobs.parseHistory(historyText or "")
        profiles = ctx:jobInfrastructureProfiles() or Infrastructure.empty()
        profileStates = {}
        for _, profile in ipairs(profiles.profiles or {}) do
            profileStates[profile.id] = ctx:jobInfrastructureState(profile)
        end
        selected = math.max(1, math.min(selected, math.max(1, #data.jobs)))
        for _, job in ipairs(data.jobs) do
            if job.trigger == "timer" and job.enabled and not job.paused then
                local interval = Jobs.timerInterval(job)
                if interval and not nextTimer[job.id] then nextTimer[job.id] = os.clock() + interval end
            end
        end
    end

    local function save()
        local ok, reason = ctx:writeJobDefinitions(data)
        if ok then
            local historyOk, historyReason = ctx:writeFile("/qalcom/data/jobs.history", Jobs.serializeHistory(history))
            status = historyOk and "Job definitions saved" or (historyReason or "Job definitions saved; history could not be saved")
            return historyOk
        end
        status = reason or "Unable to save jobs"
        return false, reason
    end

    local function current()
        return data.jobs[selected]
    end

    local function profileFor(job)
        for _, profile in ipairs(profiles.profiles or {}) do
            if profile.id == job.target then return profile end
        end
        return nil
    end

    local function record(job, outcome, detail)
        history = Jobs.addHistory(history, { id = job.id, outcome = outcome, detail = detail, at = os.clock() })
        audit("job-run", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. job.id .. " outcome=" .. outcome .. " " .. tostring(detail or ""))
    end

    local function writeProfile(profile, value)
        if not profile or profile.kind ~= "output" then return false, "Output profile required" end
        if profile.blocked or profile.enabled == false or not Infrastructure.zoneAllowed(profile) then return false, "Target profile unavailable" end
        if not ctx:hasCapability("redstone.control") or not ctx:hasCapability("infrastructure.control") then return false, "Infrastructure control denied" end
        local ok, failure = ctx:redstoneWrite(profile.side, value)
        if not ok then return false, failure or "Output unavailable" end
        profileStates[profile.id] = ctx:jobInfrastructureState(profile)
        return true
    end

    local function run(job, source)
        local now = os.clock()
        local allowed, reason = Jobs.canRun(job, now, lastRun[job.id])
        if not allowed then record(job, "skipped", reason); return false, reason end
        local valid, actionReason = Jobs.actionValid(job)
        if not valid then record(job, "rejected", actionReason); return false, actionReason end
        if not ctx:hasCapability("jobs.manage") then
            record(job, "denied", "jobs.manage denied")
            return false, "Job management denied"
        end
        local ok, failure
        if job.action == "infrastructure_safe_state" then
            if not ctx:hasCapability("infrastructure.emergency") then
                ok, failure = false, "Emergency capability denied"
            else
                local failures = 0
                for _, profile in ipairs(profiles.profiles or {}) do
                    if profile.kind == "output" and profile.enabled ~= false then
                        local changed, detail = writeProfile(profile, Infrastructure.safeState(profile))
                        if not changed then failures = failures + 1; failure = detail end
                    end
                end
                ok = failures == 0
                if not ok then failure = tostring(failures) .. " target(s) failed" end
            end
        else
            local profile = profileFor(job)
            local state = profile and profileStates[profile.id]
            local targetValue = job.value == "toggle" and not (state and state.value == true) or job.value == true
            ok, failure = writeProfile(profile, targetValue)
        end
        lastRun[job.id] = now
        record(job, ok and "success" or "failed", source .. (failure and (" " .. tostring(failure)) or ""))
        status = ok and (job.label .. " completed") or (job.label .. " failed: " .. tostring(failure))
        return ok, failure
    end

    local function addJob()
        if #data.jobs >= Jobs.maxJobs then status = "Job limit reached"; return end
        local index = #data.jobs + 1
        data.jobs[#data.jobs + 1] = Jobs.normalize({ id = "job-" .. index, label = "New Job " .. index, trigger = "manual", action = "infrastructure_safe_state", cooldown = 5 })
        selected = #data.jobs
        status = "Added job; press S to save"
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, start = Screen.begin(ctx.win, "Automation Jobs", status, { ui = UI })
        local footer = math.max(start, height - 3)
        local split = math.max(20, math.floor(width * 0.46))
        UI.text(ctx.win, 2, start, "Jobs", UI.colors.accent, UI.colors.surface, split - 3)
        UI.text(ctx.win, split, start, "Definition / history", UI.colors.accent, UI.colors.surface, width - split - 1)
        local row = start + 1
        local visible = math.max(0, footer - row)
        local first = math.max(1, math.min(selected - visible + 1, math.max(1, #data.jobs - visible + 1)))
        for index = first, math.min(#data.jobs, first + visible - 1) do
            local job = data.jobs[index]
            local active = index == selected
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            UI.fill(ctx.win, 2, row + index - first, split - 3, 1, background)
            local marker = job.paused and "|| " or (job.enabled and "> " or "- ")
            UI.text(ctx.win, 3, row + index - first, marker .. job.label, foreground, background, split - 5)
            UI.text(ctx.win, split - 13, row + index - first, job.trigger, UI.colors.muted, background, 11)
        end
        local job = current()
        local detailRow = row
        local function detail(label, value, color)
            if detailRow >= footer then return end
            UI.text(ctx.win, split, detailRow, label, UI.colors.muted, UI.colors.surface, 12)
            UI.text(ctx.win, split + 13, detailRow, tostring(value or "-"), color or UI.colors.text, UI.colors.surface, width - split - 14)
            detailRow = detailRow + 1
        end
        if job then
            detail("ID", job.id)
            detail("Trigger", job.trigger .. (job.triggerValue ~= "" and (":" .. job.triggerValue) or ""))
            detail("Action", job.action)
            detail("Target", job.target ~= "" and job.target or "all enabled outputs")
            detail("Cooldown", job.cooldown .. "s / retries " .. job.maxRetries)
            detail("State", job.paused and "PAUSED" or (job.enabled and "ENABLED" or "DISABLED"), job.paused and UI.colors.warning or UI.colors.success)
            if detailRow < footer then detailRow = detailRow + 1 end
            UI.text(ctx.win, split, detailRow, "Last runs", UI.colors.accent, UI.colors.surface, width - split - 1)
            detailRow = detailRow + 1
            local shown = 0
            for index = #history, 1, -1 do
                if history[index].id == job.id and detailRow < footer and shown < 4 then
                    local entry = history[index]
                    UI.text(ctx.win, split, detailRow, entry.outcome .. " " .. string.format("%.0fs", entry.at), entry.outcome == "success" and UI.colors.success or UI.colors.warning, UI.colors.surface, width - split - 1)
                    detailRow = detailRow + 1
                    shown = shown + 1
                end
            end
        else
            UI.text(ctx.win, split, row, "No structured jobs configured", UI.colors.muted, UI.colors.surface, width - split - 1)
        end
        UI.fill(ctx.win, 1, height - 2, width, 3, UI.colors.surfaceAlt)
        if editing then
            UI.text(ctx.win, 2, height - 2, "New value for " .. tostring(editingField) .. ":", colors.white, UI.colors.accentLight, width - 3)
            UI.text(ctx.win, 2, height - 1, input .. "_", colors.white, UI.colors.accentLight, width - 3)
            UI.text(ctx.win, 2, height, "Enter apply   Esc cancel", colors.white, UI.colors.accentLight, width - 3)
        else
            UI.text(ctx.win, 2, height - 2, "Up/Down select   N new   Enter run   C trigger", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
            UI.text(ctx.win, 2, height - 1, "A action   L label   T target   V trigger value", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
            UI.text(ctx.win, 2, height, "Space pause   D disable   S save   E stop all", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        end
    end

    load()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if editing then
            if event == "char" then input = input .. tostring(value or ""):sub(1, 32 - #input); render()
            elseif event == "paste" then input = input .. tostring(value or ""):sub(1, 32 - #input); render()
            elseif event == "key" then
                if value == keys.backspace then input = input:sub(1, math.max(0, #input - 1)); render()
                elseif value == keys.escape then editing = false; input = ""; render()
                elseif value == keys.enter then
                    local job = current()
                    if job and editingField == "label" then job.label = tostring(input):sub(1, Jobs.maxLabelLength)
                    elseif job and editingField == "target" then job.target = tostring(input):sub(1, Jobs.maxTargetLength)
                    elseif job and editingField == "trigger" then job.triggerValue = tostring(input):sub(1, Jobs.maxTriggerValueLength) end
                    editing = false; input = ""; status = "Definition updated; press S to save"; render()
                end
            end
        elseif event == "key" then
            local job = current()
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(math.max(1, #data.jobs), selected + 1); render()
            elseif value == keys.n then addJob(); render()
            elseif value == keys.enter then if job then run(job, "manual") end; render()
            elseif value == keys.space then if job then job.paused = not job.paused; status = job.paused and "Job paused" or "Job resumed"; render() end
            elseif value == keys.d then if job then job.enabled = not job.enabled; status = job.enabled and "Job enabled" or "Job disabled"; render() end
            elseif value == keys.s then save(); render()
            elseif value == keys.r then load(); status = "Jobs refreshed"; render()
            elseif value == keys.e then
                for _, item in ipairs(data.jobs) do item.paused = true end
                local saved = save()
                status = saved and "All jobs paused (emergency stop)" or "Emergency stop applied; persistence failed"
                audit("jobs-emergency-stop", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role))
                render()
            elseif value == keys.a then
                if job then
                    job.action = job.action == "infrastructure_toggle" and "infrastructure_safe_state" or "infrastructure_toggle"
                    if job.action == "infrastructure_toggle" and job.target == "" then status = "Action set to toggle; press T to choose a target" end
                    status = "Action changed; press S to save"
                    render()
                end
            elseif value == keys.c then
                if job then
                    local triggers = { "manual", "timer", "redstone" }
                    local currentIndex = 1
                    for index, trigger in ipairs(triggers) do if trigger == job.trigger then currentIndex = index end end
                    job.trigger = triggers[(currentIndex % #triggers) + 1]
                    job.triggerValue = job.trigger == "timer" and "10" or (job.trigger == "redstone" and "front:on" or "")
                    status = "Trigger changed; press S to save"
                    render()
                end
            elseif value == keys.l then if job then editing = true; editingField = "label"; input = job.label; render() end
            elseif value == keys.t then if job then editing = true; editingField = "target"; input = job.target; render() end
            elseif value == keys.v then if job then editing = true; editingField = "trigger"; input = job.triggerValue; render() end
            elseif value == keys.escape then
                if ctx:isSafeMode() then ctx:close()
                elseif save() then ctx:close() end
            end
        elseif event == "timer" then
            for _, job in ipairs(data.jobs) do
                if job.trigger == "timer" and job.enabled and not job.paused and nextTimer[job.id] and os.clock() >= nextTimer[job.id] then
                    run(job, "timer")
                    local interval = Jobs.timerInterval(job) or 10
                    nextTimer[job.id] = os.clock() + interval
                end
            end
            render()
        elseif event == "redstone" then
            for _, job in ipairs(data.jobs) do
                if job.trigger == "redstone" and job.enabled and not job.paused then
                    local side, expected = Jobs.redstoneTrigger(job)
                    local actual = side and ctx:redstoneInput(side) or nil
                    if side and actual == expected then run(job, "redstone:" .. side) end
                end
            end
            render()
        elseif event == "qalcom_tick" or event == "term_resize" then
            render()
        end
    end
end
