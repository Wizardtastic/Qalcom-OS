local Jobs = dofile("/qalcom/lib/jobs.lua")
local Infrastructure = dofile("/qalcom/lib/infrastructure.lua")

return function(ctx)
    local history = {}
    local lastRun = {}
    local nextTimer = {}
    local previousInputs = {}

    local function load()
        local text = ctx:readFile("/qalcom/data/jobs.meta")
        local data = Jobs.parse(text or "")
        local historyText = ctx:readFile("/qalcom/data/jobs.history")
        history = Jobs.parseHistory(historyText or "")
        for _, job in ipairs(data.jobs) do
            if job.trigger == "timer" and job.enabled and not job.paused and not nextTimer[job.id] then
                local interval = Jobs.timerInterval(job)
                if interval then nextTimer[job.id] = os.startTimer(interval) end
            end
        end
        return data
    end

    local function persistHistory()
        ctx:writeFile("/qalcom/data/jobs.history", Jobs.serializeHistory(history))
    end

    local function record(job, outcome, detail)
        history = Jobs.addHistory(history, { id = job.id, outcome = outcome, detail = detail, at = os.clock() })
        persistHistory()
        if ctx.audit then ctx:audit("job-run", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. job.id .. " outcome=" .. outcome .. " " .. tostring(detail or "")) end
    end

    local function findProfile(id, profiles)
        for _, profile in ipairs(profiles.profiles or {}) do if profile.id == id then return profile end end
    end

    local function execute(job, profiles, source)
        if not ctx:hasCapability("jobs.manage") then record(job, "denied", "jobs.manage denied"); return end
        local allowed, reason = Jobs.canRun(job, os.clock(), lastRun[job.id])
        if not allowed then record(job, "skipped", reason); return end
        local valid, validationReason = Jobs.actionValid(job)
        if not valid then record(job, "rejected", validationReason); return end
        local attempts, ok, failure = 0, false, nil
        repeat
            attempts = attempts + 1
            if job.action == "infrastructure_safe_state" then
                if not ctx:hasCapability("infrastructure.emergency") then
                    failure = "Emergency capability denied"
                else
                    local failures = 0
                    for _, profile in ipairs(profiles.profiles or {}) do
                        if profile.kind == "output" and profile.enabled ~= false and not profile.blocked and Infrastructure.zoneAllowed(profile) then
                            local changed, detail = ctx:redstoneWrite(profile.side, Infrastructure.safeState(profile))
                            if not changed then failures = failures + 1; failure = detail end
                        end
                    end
                    ok = failures == 0
                    if not ok then failure = tostring(failures) .. " target(s) failed" end
                end
            elseif job.action == "infrastructure_toggle" then
                local profile = findProfile(job.target, profiles)
                local state = profile and ctx:infrastructureState(profile)
                if not profile or profile.kind ~= "output" or profile.blocked or profile.enabled == false or not Infrastructure.zoneAllowed(profile) then
                    failure = "Target profile unavailable"
                elseif not ctx:hasCapability("redstone.control") or not ctx:hasCapability("infrastructure.control") then
                    failure = "Infrastructure control denied"
                else
                    local target = job.value == "toggle" and not (state and state.value == true) or job.value == true
                    ok, failure = ctx:redstoneWrite(profile.side, target)
                end
            end
        until ok or attempts > job.maxRetries
        lastRun[job.id] = os.clock()
        record(job, ok and "success" or "failed", source .. (failure and (" " .. tostring(failure)) or ""))
    end

    local data = load()
    while true do
        local event, value = ctx:pullEvent()
        if event == "timer" then
            if ctx:isSafeMode() then data = load() else
            for _, job in ipairs(data.jobs) do
                if nextTimer[job.id] == value then
                    execute(job, ctx:jobInfrastructureProfiles() or Infrastructure.empty(), "timer")
                    local interval = Jobs.timerInterval(job) or 10
                    nextTimer[job.id] = os.startTimer(interval)
                end
            end
            end
        elseif event == "redstone" then
            if ctx:isSafeMode() then data = load() else
            for _, job in ipairs(data.jobs) do
                if job.trigger == "redstone" and job.enabled and not job.paused then
                    local side, expected = Jobs.redstoneTrigger(job)
                    local actual = side and ctx:redstoneInput(side) or nil
                    if side and actual ~= previousInputs[side] and actual == expected then execute(job, ctx:jobInfrastructureProfiles() or Infrastructure.empty(), "redstone:" .. side) end
                    if side then previousInputs[side] = actual end
                end
            end
            end
        elseif event == "qalcom_tick" then
            data = load()
        elseif event == "qalcom_job_reload" then
            data = load()
        end
    end
end
