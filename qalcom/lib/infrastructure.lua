local Infrastructure = {}

Infrastructure.schemaVersion = 1
Infrastructure.maxProfiles = 32
Infrastructure.maxLabelLength = 48
Infrastructure.maxZoneLength = 32
Infrastructure.maxPulseSeconds = 30
Infrastructure.maxMetadataBytes = 24000
Infrastructure.maxMetadataLines = 256
Infrastructure.validSides = { "top", "bottom", "left", "right", "front", "back" }

local function clean(value, maximum)
    local text = tostring(value or "")
    text = text:gsub("[\r\n]", " ")
    return text:sub(1, maximum or 120)
end

local function escape(value)
    return clean(value, 120):gsub("\\", "\\\\"):gsub("|", "\\p")
end

local function unescape(value)
    value = tostring(value or "")
    local result = {}
    local index = 1
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
    local fields, current = {}, {}
    local escaped = false
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

local function number(value, minimum, maximum, fallback)
    local result = tonumber(value)
    if not result then result = fallback end
    result = math.floor(result or minimum)
    if result < minimum then return minimum end
    if result > maximum then return maximum end
    return result
end

local function validSide(side)
    for _, candidate in ipairs(Infrastructure.validSides) do
        if side == candidate then return true end
    end
    return false
end

function Infrastructure.normalizeProfile(profile, fallbackId)
    profile = profile or {}
    local kind = profile.kind == "input" and "input" or "output"
    local side = validSide(profile.side) and profile.side or "back"
    local id = clean(profile.id or fallbackId or "point", 24):gsub("|", "")
    if id == "" then id = fallbackId or "point" end
    return {
        id = id,
        label = clean(profile.label or id, Infrastructure.maxLabelLength),
        kind = kind,
        side = side,
        safe = profile.safe == true,
        confirm = profile.confirm ~= false,
        zone = clean(profile.zone or "local", Infrastructure.maxZoneLength),
        maxPulse = number(profile.maxPulse, 0, Infrastructure.maxPulseSeconds, kind == "output" and 5 or 0),
        enabled = profile.enabled ~= false,
        blocked = profile.blocked == true,
    }
end

function Infrastructure.empty()
    return { schemaVersion = Infrastructure.schemaVersion, profiles = {} }
end

function Infrastructure.parse(text)
    text = tostring(text or "")
    if #text > Infrastructure.maxMetadataBytes then text = text:sub(1, Infrastructure.maxMetadataBytes) end
    local result = Infrastructure.empty()
    local lineCount = 0
    local seen = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lineCount = lineCount + 1
        if lineCount > Infrastructure.maxMetadataLines then break end
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "schema" then
                result.schemaVersion = tonumber(fields[2]) or Infrastructure.schemaVersion
            elseif fields[1] == "profile" and #result.profiles < Infrastructure.maxProfiles then
                local profile = Infrastructure.normalizeProfile({
                    id = fields[2], label = fields[3], kind = fields[4], side = fields[5],
                    safe = bool(fields[6], false), confirm = bool(fields[7], true), zone = fields[8],
                    maxPulse = fields[9], enabled = bool(fields[10], true), blocked = bool(fields[11], false),
                }, "point-" .. tostring(#result.profiles + 1))
                if not seen[profile.id] then
                    seen[profile.id] = true
                    result.profiles[#result.profiles + 1] = profile
                end
            end
        end
    end
    result.schemaVersion = Infrastructure.schemaVersion
    return result
end

function Infrastructure.serialize(data)
    data = data or Infrastructure.empty()
    local lines = {
        "# Qalcom infrastructure profile schema " .. tostring(Infrastructure.schemaVersion),
        "schema|" .. tostring(Infrastructure.schemaVersion),
    }
    local profiles = {}
    for index, profile in ipairs(data.profiles or {}) do
        if index <= Infrastructure.maxProfiles then profiles[#profiles + 1] = Infrastructure.normalizeProfile(profile, "point-" .. tostring(index)) end
    end
    table.sort(profiles, function(left, right) return left.id < right.id end)
    for _, profile in ipairs(profiles) do
        lines[#lines + 1] = table.concat({
            "profile", escape(profile.id), escape(profile.label), profile.kind, profile.side,
            tostring(profile.safe == true), tostring(profile.confirm == true), escape(profile.zone),
            tostring(profile.maxPulse), tostring(profile.enabled ~= false), tostring(profile.blocked == true),
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Infrastructure.profileName(profile)
    return clean(profile and (profile.label or profile.id) or "Unknown", Infrastructure.maxLabelLength)
end

function Infrastructure.isOutput(profile)
    return profile and profile.kind == "output"
end

function Infrastructure.canPulse(profile, seconds)
    if not Infrastructure.isOutput(profile) then return false, "Only outputs can pulse" end
    local duration = tonumber(seconds)
    if not duration or duration <= 0 then return false, "Pulse duration must be positive" end
    if duration > Infrastructure.maxPulseSeconds then return false, "Pulse exceeds global safety limit" end
    if profile.maxPulse <= 0 or duration > profile.maxPulse then return false, "Pulse exceeds profile limit" end
    return true
end

function Infrastructure.safeState(profile)
    return profile and profile.safe == true or false
end

function Infrastructure.zoneAllowed(profile)
    return profile and (profile.zone == "local" or profile.zone == "base")
end

function Infrastructure.state(ctx, profile)
    if not profile or not profile.enabled then return { online = false, value = nil, reason = "Profile disabled" } end
    local value, reason
    if Infrastructure.isOutput(profile) and ctx.redstoneState then
        value, reason = ctx:redstoneState(profile.side)
    else
        value, reason = ctx:redstoneInput(profile.side)
    end
    if value == nil then return { online = false, value = nil, reason = reason or "Input unavailable" } end
    return { online = true, value = value == true }
end

return Infrastructure
