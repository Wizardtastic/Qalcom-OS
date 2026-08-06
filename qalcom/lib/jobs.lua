local Jobs = {}

Jobs.schemaVersion = 1
Jobs.maxJobs = 32
Jobs.maxLabelLength = 48
Jobs.maxIdLength = 24
Jobs.maxTriggerValueLength = 48
Jobs.maxTargetLength = 32
Jobs.maxCooldown = 3600
Jobs.maxRetries = 3
Jobs.maxTimeout = 30
Jobs.maxHistory = 40
Jobs.maxStatus = 32
Jobs.maxRetryDelay = 30
Jobs.maxMetadataBytes = 24000
Jobs.validSides = { top = true, bottom = true, left = true, right = true, front = true, back = true }
Jobs.validTriggers = { manual = true, timer = true, redstone = true }
Jobs.validActions = { infrastructure_toggle = true, infrastructure_safe_state = true }

local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n]", " "):sub(1, maximum or 120)
end

local function escape(value)
    return clean(value, 120):gsub("\\", "\\\\"):gsub("|", "\\p")
end

local function unescape(value)
    local result, index = {}, 1
    value = tostring(value or "")
    while index <= #value do
        local character = value:sub(index, index)
        if character == "\\" and index < #value then
            local nextCharacter = value:sub(index + 1, index + 1)
            result[#result + 1] = nextCharacter == "p" and "|" or nextCharacter
            index = index + 2
        else
            result[#result + 1] = character
            index = index + 1
        end
    end
    return table.concat(result)
end

local function split(line)
    local fields, current, escaped = {}, {}, false
    for index = 1, #line do
        local character = line:sub(index, index)
        if escaped then
            current[#current + 1] = "\\" .. character
            escaped = false
        elseif character == "\\" then
            escaped = true
        elseif character == "|" then
            fields[#fields + 1] = unescape(table.concat(current))
            current = {}
        else
            current[#current + 1] = character
        end
    end
    if escaped then current[#current + 1] = "\\" end
    fields[#fields + 1] = unescape(table.concat(current))
    return fields
end

local function bool(value, fallback)
    if value == true or value == "true" or value == "1" then return true end
    if value == false or value == "false" or value == "0" then return false end
    return fallback == true
end

local function integer(value, minimum, maximum, fallback)
    local result = math.floor(tonumber(value) or fallback or minimum)
    return math.max(minimum, math.min(maximum, result))
end

local function validTrigger(trigger)
    return Jobs.validTriggers[trigger] == true
end

local function validAction(action)
    return Jobs.validActions[action] == true
end

function Jobs.normalize(job, fallbackId)
    job = job or {}
    local trigger = validTrigger(job.trigger) and job.trigger or "manual"
    local action = validAction(job.action) and job.action or "infrastructure_safe_state"
    local id = clean(job.id or fallbackId or "job", Jobs.maxIdLength):gsub("|", "")
    if id == "" then id = fallbackId or "job" end
    local capability = action == "infrastructure_safe_state" and "infrastructure.emergency" or "infrastructure.control"
    return {
        id = id,
        label = clean(job.label or id, Jobs.maxLabelLength),
        enabled = job.enabled ~= false,
        trigger = trigger,
        triggerValue = clean(job.triggerValue or (trigger == "timer" and "10" or ""), Jobs.maxTriggerValueLength),
        action = action,
        target = clean(job.target or "", Jobs.maxTargetLength),
        value = job.value == true and true or (job.value == false and false or "toggle"),
        cooldown = integer(job.cooldown, 1, Jobs.maxCooldown, 5),
        maxRetries = integer(job.maxRetries, 0, Jobs.maxRetries, 0),
        timeout = integer(job.timeout, 1, Jobs.maxTimeout, 5),
        capability = capability,
        paused = job.paused == true,
    }
end

function Jobs.empty()
    return { schemaVersion = Jobs.schemaVersion, jobs = {} }
end

function Jobs.parse(text)
    text = tostring(text or "")
    local result, seen, lines = Jobs.empty(), {}, 0
    if #text > Jobs.maxMetadataBytes then
        result.error = "Job metadata exceeds safety limit"
        text = text:sub(1, Jobs.maxMetadataBytes)
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if lines > 256 then break end
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "schema" then
                local schema = tonumber(fields[2])
                if schema and schema ~= Jobs.schemaVersion then result.error = "Unsupported job schema" end
            elseif fields[1] == "job" and #result.jobs < Jobs.maxJobs then
                local job = Jobs.normalize({
                    id = fields[2], label = fields[3], enabled = bool(fields[4], true),
                    trigger = fields[5], triggerValue = fields[6], action = fields[7],
                    target = fields[8], value = fields[9] == "true" and true or (fields[9] == "false" and false or "toggle"),
                    cooldown = fields[10], maxRetries = fields[11], timeout = fields[12], paused = bool(fields[13], false),
                }, "job-" .. tostring(#result.jobs + 1))
                if not seen[job.id] then
                    seen[job.id] = true
                    result.jobs[#result.jobs + 1] = job
                end
            end
        end
    end
    if result.error then result.jobs = {} end
    return result
end

function Jobs.parseHistory(text)
    text = tostring(text or "")
    local history = {}
    if #text > Jobs.maxMetadataBytes then text = text:sub(-Jobs.maxMetadataBytes) end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local fields = split(line)
        if fields[1] == "history" then
            history = Jobs.addHistory(history, { id = fields[2], outcome = fields[3], detail = fields[4], at = fields[5] })
        end
    end
    return history
end

function Jobs.serializeHistory(history)
    local lines = { "# Qalcom bounded job history schema " .. tostring(Jobs.schemaVersion) }
    for _, entry in ipairs(history or {}) do
        lines[#lines + 1] = table.concat({ "history", escape(entry.id), escape(entry.outcome), escape(entry.detail), tostring(entry.at or 0) }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Jobs.serialize(data)
    data = data or Jobs.empty()
    local lines = {
        "# Qalcom structured jobs schema " .. tostring(Jobs.schemaVersion),
        "schema|" .. tostring(Jobs.schemaVersion),
    }
    local jobs = {}
    for index, job in ipairs(data.jobs or {}) do
        if index <= Jobs.maxJobs then jobs[#jobs + 1] = Jobs.normalize(job, "job-" .. tostring(index)) end
    end
    table.sort(jobs, function(left, right) return left.id < right.id end)
    for _, job in ipairs(jobs) do
        lines[#lines + 1] = table.concat({
            "job", escape(job.id), escape(job.label), tostring(job.enabled ~= false),
            job.trigger, escape(job.triggerValue), job.action, escape(job.target),
            tostring(job.value), tostring(job.cooldown), tostring(job.maxRetries),
            tostring(job.timeout), tostring(job.paused == true),
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Jobs.timerInterval(job)
    if not job or job.trigger ~= "timer" then return nil, "Not a timer job" end
    local seconds = tonumber(job.triggerValue)
    if not seconds or seconds < 1 or seconds > Jobs.maxCooldown then return nil, "Timer interval must be 1-3600 seconds" end
    return math.floor(seconds)
end

function Jobs.redstoneTrigger(job)
    if not job or job.trigger ~= "redstone" then return nil, "Not a redstone job" end
    local side, value = tostring(job.triggerValue or ""):match("^(%a+):(on|off)$")
    if not side or not Jobs.validSides[side] then return nil, "Redstone trigger must use a valid side:on or side:off" end
    return side, value == "on"
end

function Jobs.canRun(job, now, lastRun)
    if not job or job.enabled == false or job.paused == true then return false, "Job disabled or paused" end
    local elapsed = tonumber(now or 0) - tonumber(lastRun or -math.huge)
    if elapsed < job.cooldown then return false, "Job cooldown active" end
    return true
end

function Jobs.actionValid(job)
    if not job or not validAction(job.action) then return false, "Unsupported structured action" end
    if job.action == "infrastructure_toggle" and job.target == "" then return false, "Infrastructure target required" end
    return true
end

function Jobs.definitionValid(job)
    local normalized = Jobs.normalize(job, job and job.id or "job")
    if not validTrigger(job and job.trigger) then return false, "Unsupported trigger" end
    if not validAction(job and job.action) then return false, "Unsupported structured action" end
    if normalized.trigger == "timer" then
        local _, reason = Jobs.timerInterval(normalized)
        if not _ then return false, reason end
    elseif normalized.trigger == "redstone" then
        local side, reason = Jobs.redstoneTrigger(normalized)
        if not side then return false, reason end
    end
    return Jobs.actionValid(normalized)
end

function Jobs.dataValid(data)
    for _, job in ipairs((data and data.jobs) or {}) do
        local ok, reason = Jobs.definitionValid(job)
        if not ok then return false, tostring(job.id or "job") .. ": " .. tostring(reason) end
    end
    return true
end

function Jobs.parseStrict(text)
    text = tostring(text or "")
    if #text > Jobs.maxMetadataBytes then return { error = "Job metadata exceeds safety limit", jobs = {} } end
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if lines > 256 then break end
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "schema" then
                local schema = tonumber(fields[2])
                if schema ~= Jobs.schemaVersion then return { error = "Unsupported job schema", jobs = {} } end
            elseif fields[1] == "job" then
                local trigger, action = fields[5], fields[7]
                if not validTrigger(trigger) then return { error = "Unsupported trigger: " .. tostring(trigger), jobs = {} } end
                if not validAction(action) then return { error = "Unsupported action: " .. tostring(action), jobs = {} } end
                local candidate = Jobs.normalize({
                    id = fields[2], label = fields[3], enabled = bool(fields[4], true),
                    trigger = trigger, triggerValue = fields[6], action = action,
                    target = fields[8], value = fields[9] == "true" and true or (fields[9] == "false" and false or "toggle"),
                    cooldown = fields[10], maxRetries = fields[11], timeout = fields[12], paused = bool(fields[13], false),
                }, "job-" .. tostring(lines))
                local valid, reason = Jobs.definitionValid(candidate)
                if not valid then return { error = tostring(candidate.id) .. ": " .. tostring(reason), jobs = {} } end
            end
        end
    end
    local result = Jobs.parse(text)
    local valid, reason = Jobs.dataValid(result)
    if not valid then return { error = reason, jobs = {} } end
    return result
end

function Jobs.addHistory(history, entry)
    history = history or {}
    history[#history + 1] = {
        id = clean(entry and entry.id, Jobs.maxIdLength),
        outcome = clean(entry and entry.outcome, 24),
        detail = clean(entry and entry.detail, 120),
        at = tonumber(entry and entry.at) or 0,
    }
    while #history > Jobs.maxHistory do table.remove(history, 1) end
    return history
end

function Jobs.retryDelay(attempt)
    attempt = math.max(1, math.floor(tonumber(attempt) or 1))
    return math.min(Jobs.maxRetryDelay, 2 ^ math.min(attempt - 1, 5))
end

function Jobs.normalizeStatus(status, fallbackId)
    status = status or {}
    local state = clean(status.state or "idle", 16)
    if state ~= "idle" and state ~= "running" and state ~= "retrying" and state ~= "success" and state ~= "failed" and state ~= "disabled" and state ~= "blocked" then
        state = "idle"
    end
    return {
        id = clean(status.id or fallbackId or "job", Jobs.maxIdLength),
        state = state,
        source = clean(status.source or "", 24),
        attempts = integer(status.attempts, 0, Jobs.maxRetries + 1, 0),
        nextAt = tonumber(status.nextAt) or 0,
        lastOutcome = clean(status.lastOutcome or "", 24),
        lastDetail = clean(status.lastDetail or "", 120),
        updated = tonumber(status.updated) or 0,
    }
end

function Jobs.parseStatus(text)
    text = tostring(text or "")
    local statuses, seen, lines = {}, {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if lines > 256 then break end
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "status" then
                local status = Jobs.normalizeStatus({
                    id = fields[2], state = fields[3], source = fields[4],
                    attempts = fields[5], nextAt = fields[6], lastOutcome = fields[7],
                    lastDetail = fields[8], updated = fields[9],
                }, "job-" .. tostring(#statuses + 1))
                if not seen[status.id] and #statuses < Jobs.maxStatus then
                    seen[status.id] = true
                    statuses[#statuses + 1] = status
                end
            end
        end
    end
    return statuses
end

function Jobs.serializeStatus(statuses)
    local lines = { "# Qalcom structured job status schema " .. tostring(Jobs.schemaVersion) }
    local values = {}
    local count = 0
    for key, status in pairs(statuses or {}) do
        count = count + 1
        if count <= Jobs.maxStatus then values[#values + 1] = Jobs.normalizeStatus(status, type(key) == "string" and key or "job-" .. tostring(count)) end
    end
    table.sort(values, function(left, right) return left.id < right.id end)
    for _, status in ipairs(values) do
        lines[#lines + 1] = table.concat({
            "status", escape(status.id), status.state, escape(status.source),
            tostring(status.attempts), tostring(status.nextAt), escape(status.lastOutcome),
            escape(status.lastDetail), tostring(status.updated),
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Jobs.statusSummary(statuses)
    local summary = { total = 0, active = 0, retrying = 0, failed = 0, success = 0, disabled = 0, blocked = 0, lastFailure = "" }
    for _, status in ipairs(statuses or {}) do
        local normalized = Jobs.normalizeStatus(status)
        summary.total = summary.total + 1
        if normalized.state == "running" then summary.active = summary.active + 1 end
        if normalized.state == "retrying" then summary.retrying = summary.retrying + 1; summary.active = summary.active + 1 end
        if normalized.state == "failed" then
            summary.failed = summary.failed + 1
            if summary.lastFailure == "" then summary.lastFailure = normalized.lastDetail end
        end
        if normalized.state == "success" then summary.success = summary.success + 1 end
        if normalized.state == "disabled" then summary.disabled = summary.disabled + 1 end
        if normalized.state == "blocked" then summary.blocked = summary.blocked + 1 end
    end
    return summary
end

return Jobs
