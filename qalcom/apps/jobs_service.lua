local Jobs = dofile("/qalcom/lib/jobs.lua")
local Infrastructure = dofile("/qalcom/lib/infrastructure.lua")

return function(ctx)
    local history = {}
    local statuses = {}
    local lastRun = {}
    local nextTimer = {}
    local retryTimers = {}
    local retryPending = {}
    local previousInputs = {}

    local function cancelTimer(timer)
        if timer then pcall(os.cancelTimer, timer) end
    end

    local function cancelScheduled()
        for _, timer in pairs(nextTimer) do cancelTimer(timer) end
        for timer, _ in pairs(retryTimers) do cancelTimer(timer) end
        nextTimer = {}
        retryTimers = {}
        retryPending = {}
    end

    local function persistHistory()
        if ctx.writeJobServiceFile then ctx:writeJobServiceFile("/qalcom/data/jobs.history", Jobs.serializeHistory(history)) else ctx:writeFile("/qalcom/data/jobs.history", Jobs.serializeHistory(history)) end
    end

    local function persistStatus()
        if ctx.writeJobServiceFile then ctx:writeJobServiceFile("/qalcom/data/jobs.status", Jobs.serializeStatus(statuses)) else ctx:writeFile("/qalcom/data/jobs.status", Jobs.serializeStatus(statuses)) end
    end

    local function setStatus(job, state, source, attempts, nextAt, outcome, detail)
        local nextStatus = Jobs.normalizeStatus({
            id = job.id,
            state = state,
            source = source,
            attempts = attempts,
            nextAt = nextAt,
            lastOutcome = outcome,
            lastDetail = detail,
            updated = os.clock(),
        }, job.id)
        local previous = statuses[job.id]
        local changed = not previous
            or previous.state ~= nextStatus.state
            or previous.source ~= nextStatus.source
            or previous.attempts ~= nextStatus.attempts
            or previous.nextAt ~= nextStatus.nextAt
            or previous.lastOutcome ~= nextStatus.lastOutcome
            or previous.lastDetail ~= nextStatus.lastDetail
        statuses[job.id] = nextStatus
        if changed then persistStatus() end
    end

    local function load(resetTimers)
        if resetTimers then cancelScheduled() end
        local text = ctx:readFile("/qalcom/data/jobs.meta")
        local data = Jobs.parseStrict(text or "")
        if data.error then
            if ctx.log then ctx:log("jobs metadata rejected: " .. tostring(data.error)) end
            if ctx.audit then ctx:audit("jobs-metadata-rejected", tostring(data.error)) end
        end
        local historyText = ctx:readFile("/qalcom/data/jobs.history")
        history = Jobs.parseHistory(historyText or "")
        local statusText = ctx:readFile("/qalcom/data/jobs.status")
        statuses = {}
        for _, status in ipairs(Jobs.parseStatus(statusText or "")) do statuses[status.id] = status end
        local active = {}
        for _, job in ipairs(data.jobs) do
            active[job.id] = true
            if job.enabled and not job.paused and job.trigger == "timer" and not nextTimer[job.id] then
                local interval = Jobs.timerInterval(job)
                if interval then nextTimer[job.id] = os.startTimer(interval) end
            elseif (not job.enabled or job.paused or job.trigger ~= "timer") and nextTimer[job.id] then
                cancelTimer(nextTimer[job.id])
                nextTimer[job.id] = nil
            end
            if not job.enabled or job.paused then
                setStatus(job, "disabled", "configuration", 0, 0, "disabled", "Job is disabled or paused")
            elseif not statuses[job.id] then
                setStatus(job, "idle", "configuration", 0, 0, "", "Waiting for trigger")
            end
        end
        for id, timer in pairs(nextTimer) do
            if not active[id] then cancelTimer(timer); nextTimer[id] = nil end
        end
        return data
    end

    local function record(job, outcome, detail)
        history = Jobs.addHistory(history, { id = job.id, outcome = outcome, detail = detail, at = os.clock() })
        if ctx.writeJobServiceFile then ctx:writeJobServiceFile("/qalcom/data/jobs.history", Jobs.serializeHistory(history)) else persistHistory() end
        if ctx.audit then ctx:audit("job-run", "actor=" .. tostring(ctx.user) .. " role=" .. tostring(ctx.role) .. " id=" .. job.id .. " outcome=" .. outcome .. " " .. tostring(detail or "")) end
    end

    local function findProfile(id, profiles)
        for _, profile in ipairs(profiles.profiles or {}) do if profile.id == id then return profile end end
    end

    local function attempt(job, profiles)
        local ok, failure = false, nil
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
        return ok, failure
    end

    local function execute(job, profiles, source, attemptNumber)
        if not ctx:hasCapability("jobs.manage") then
            retryPending[job.id] = nil
            setStatus(job, "blocked", source, 0, 0, "denied", "jobs.manage denied")
            record(job, "denied", "jobs.manage denied")
            return
        end
        local allowed, reason = Jobs.canRun(job, os.clock(), lastRun[job.id])
        if not allowed then
            retryPending[job.id] = nil
            setStatus(job, "disabled", source, 0, 0, "skipped", reason)
            record(job, "skipped", reason)
            return
        end
        local valid, validationReason = Jobs.actionValid(job)
        if not valid then
            retryPending[job.id] = nil
            setStatus(job, "blocked", source, 0, 0, "rejected", validationReason)
            record(job, "rejected", validationReason)
            return
        end
        attemptNumber = math.max(1, tonumber(attemptNumber) or 1)
        setStatus(job, "running", source, attemptNumber, 0, "", "Attempt " .. tostring(attemptNumber))
        local ok, failure = attempt(job, profiles)
        if ok then
            retryPending[job.id] = nil
            lastRun[job.id] = os.clock()
            setStatus(job, "success", source, attemptNumber, 0, "success", "Completed on attempt " .. tostring(attemptNumber))
            record(job, "success", source .. " attempts=" .. tostring(attemptNumber))
            return
        end
        local detail = source .. " attempt=" .. tostring(attemptNumber) .. " " .. tostring(failure or "action failed")
        if failure == "Target profile unavailable" then
            retryPending[job.id] = nil
            setStatus(job, "blocked", source, attemptNumber, 0, "blocked", "Target unavailable; no output change attempted")
            record(job, "blocked", detail)
        elseif attemptNumber <= job.maxRetries then
            local delay = Jobs.retryDelay(attemptNumber)
            local timer = os.startTimer(delay)
            retryPending[job.id] = true
            retryTimers[timer] = { job = job, source = source, attempt = attemptNumber + 1 }
            setStatus(job, "retrying", source, attemptNumber, os.clock() + delay, "retrying", detail .. "; retry in " .. tostring(delay) .. "s")
            record(job, "retrying", detail .. " retry_in=" .. tostring(delay))
        else
            retryPending[job.id] = nil
            lastRun[job.id] = os.clock()
            setStatus(job, "failed", source, attemptNumber, 0, "failed", detail)
            record(job, "failed", detail)
        end
    end

    local data = load(true)
    while true do
        local event, value = ctx:pullEvent()
        if event == "timer" then
            local retry = retryTimers[value]
            if retry then
                retryTimers[value] = nil
                local current = nil
                for _, candidate in ipairs(data.jobs) do if candidate.id == retry.job.id then current = candidate; break end end
                if not ctx:isSafeMode() and current and current.enabled and not current.paused then
                    execute(current, ctx:jobInfrastructureProfiles() or Infrastructure.empty(), retry.source, retry.attempt)
                    if not retryPending[current.id] then
                        if current.trigger == "timer" and current.enabled and not current.paused and not nextTimer[current.id] then
                            nextTimer[current.id] = os.startTimer(Jobs.timerInterval(current) or 10)
                        end
                    end
                elseif current then
                    retryPending[current.id] = nil
                    setStatus(current, "disabled", retry.source, retry.attempt, 0, "paused", "Retry cancelled while automation is disabled")
                end
            elseif not ctx:isSafeMode() then
                for _, job in ipairs(data.jobs) do
                    if nextTimer[job.id] == value then
                        nextTimer[job.id] = nil
                        execute(job, ctx:jobInfrastructureProfiles() or Infrastructure.empty(), "timer", 1)
                        if job.enabled and not job.paused and not retryPending[job.id] then
                            local interval = Jobs.timerInterval(job) or 10
                            nextTimer[job.id] = os.startTimer(interval)
                        end
                    end
                end
            else
                data = load()
            end
        elseif event == "redstone" then
            if ctx:isSafeMode() then data = load() else
            for _, job in ipairs(data.jobs) do
                if job.trigger == "redstone" and job.enabled and not job.paused then
                    local side, expected = Jobs.redstoneTrigger(job)
                    local actual = side and ctx:redstoneInput(side) or nil
                    if side and actual ~= previousInputs[side] and actual == expected and not retryPending[job.id] then execute(job, ctx:jobInfrastructureProfiles() or Infrastructure.empty(), "redstone:" .. side, 1) end
                    if side then previousInputs[side] = actual end
                end
            end
            end
        elseif event == "qalcom_tick" then
            data = load()
        elseif event == "qalcom_job_reload" then
            data = load(true)
        end
    end
end
