local Pure = {}

function Pure.clampInteger(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number then number = fallback end
    number = math.floor(number or minimum)
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

function Pure.normalizePath(path)
    local result = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        if part == ".." then
            if #result > 0 then table.remove(result) end
        elseif part ~= "." and part ~= "" then
            result[#result + 1] = part
        end
    end
    if #result == 0 then return "/" end
    return "/" .. table.concat(result, "/")
end

function Pure.absolutePath(base, path)
    path = tostring(path or "")
    if path:sub(1, 1) == "/" then return Pure.normalizePath(path) end
    return Pure.normalizePath(tostring(base or "/") .. "/" .. path)
end

function Pure.validateUsername(username, maximum)
    maximum = maximum or 24
    return type(username) == "string"
        and #username >= 2
        and #username <= maximum
        and username:match("^[%w_%-]+$") ~= nil
end

function Pure.validateAccountRecord(account)
    return type(account) == "table"
        and type(account.username) == "string"
        and type(account.salt) == "string"
        and type(account.digest) == "string"
end

function Pure.validateRole(role, allowed)
    if type(role) ~= "string" or type(allowed) ~= "table" then return false end
    for _, candidate in ipairs(allowed) do
        if role == candidate then return true end
    end
    return false
end

function Pure.copyList(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[index] = value end
    return result
end

function Pure.hasValue(list, value)
    for _, candidate in ipairs(list or {}) do
        if candidate == value then return true end
    end
    return false
end

function Pure.validatePolicyDecision(decision)
    return type(decision) == "table"
        and type(decision.capability) == "string"
        and type(decision.role) == "string"
        and (decision.allowed == true or decision.allowed == false)
end

function Pure.validateNetworkEnvelope(envelope, now, maxAge, futureSkew)
    if type(envelope) ~= "table" then return false, "not a table" end
    if type(envelope.protocol) ~= "string" or envelope.protocol == "" then return false, "protocol missing" end
    if tonumber(envelope.version) ~= 1 then return false, "version invalid" end
    if type(envelope.source) ~= "string" or envelope.source == "" then return false, "source missing" end
    if type(envelope.kind) ~= "string" or envelope.kind == "" then return false, "kind missing" end
    if type(envelope.nonce) ~= "string" or envelope.nonce == "" then return false, "nonce missing" end
    local timestamp = tonumber(envelope.timestamp)
    if not timestamp then return false, "timestamp missing" end
    now = tonumber(now) or 0
    if timestamp < now - (tonumber(maxAge) or 30) then return false, "expired" end
    if timestamp > now + (tonumber(futureSkew) or 10) then return false, "future" end
    if type(envelope.auth) ~= "string" or envelope.auth == "" then return false, "auth missing" end
    return true
end

function Pure.replayAccept(replay, key, now, maximum, age)
    replay = replay or {}
    now = tonumber(now) or 0
    maximum = Pure.clampInteger(maximum, 1, 1024, 64)
    age = tonumber(age) or 30
    if replay[key] then return false, replay end
    replay[key] = now
    local count = 0
    for existing, timestamp in pairs(replay) do
        if now - (tonumber(timestamp) or now) > age then replay[existing] = nil else count = count + 1 end
    end
    while count > maximum do
        for existing, _ in pairs(replay) do replay[existing] = nil; count = count - 1; break end
    end
    return true, replay
end

function Pure.retainDecisions(decisions, limit)
    return Pure.retainLines(decisions, limit)
end

function Pure.retainLines(lines, limit)
    local retained = {}
    limit = Pure.clampInteger(limit, 1, math.max(1, #lines), #lines)
    local first = math.max(1, #lines - limit + 1)
    for index = first, #lines do retained[#retained + 1] = lines[index] end
    return retained
end

function Pure.fitWindow(screenWidth, screenHeight, desiredWidth, desiredHeight, minimumWidth, minimumHeight, margin)
    margin = margin or 1
    local availableWidth = math.max(1, screenWidth - margin * 2)
    local availableHeight = math.max(1, screenHeight - margin * 2)
    local width = math.min(desiredWidth, availableWidth)
    local height = math.min(desiredHeight, availableHeight)
    width = math.max(1, width)
    height = math.max(1, height)
    local x = math.max(margin, math.floor((screenWidth - width) / 2) + 1)
    local y = math.max(margin, math.floor((screenHeight - height) / 2) + 1)
    return x, y, width, height
end

return Pure
