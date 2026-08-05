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

return Jobs
