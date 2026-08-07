local Peripherals = {}

Peripherals.schemaVersion = 1
Peripherals.contractVersion = 1
Peripherals.maxContacts = 32
Peripherals.maxMethods = 48
Peripherals.maxStatusLength = 80

local function clean(value, maximum)
    local text = tostring(value or "")
    text = text:gsub("[\r\n]", " ")
    return text:sub(1, maximum or Peripherals.maxStatusLength)
end

local function lower(value)
    return string.lower(clean(value, 160))
end

local function listContains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function copyList(list, maximum)
    local result = {}
    for index, value in ipairs(list or {}) do
        if not maximum or index <= maximum then result[#result + 1] = value end
    end
    return result
end

local function clamp(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number then number = fallback end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function escape(value)
    return clean(value, 160):gsub("\\", "\\\\"):gsub("|", "\\p")
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
    local fields = {}
    local current = {}
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

local function cleanMetadataName(value)
    return clean(value, 120):gsub("|", "")
end

function Peripherals.emptyMetadata()
    return { schemaVersion = Peripherals.schemaVersion, aliases = {}, blocked = {}, trusted = {} }
end

function Peripherals.parseMetadata(text)
    local metadata = Peripherals.emptyMetadata()
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            local kind = fields[1]
            local name = fields[2]
            if kind == "schema" then
                metadata.schemaVersion = tonumber(name) or Peripherals.schemaVersion
            elseif name and name ~= "" and kind == "alias" and fields[3] and fields[3] ~= "" then
                metadata.aliases[cleanMetadataName(name)] = clean(fields[3], 48)
            elseif name and name ~= "" and kind == "blocked" then
                metadata.blocked[cleanMetadataName(name)] = true
            elseif name and name ~= "" and kind == "trusted" then
                metadata.trusted[cleanMetadataName(name)] = true
            end
        end
    end
    metadata.schemaVersion = Peripherals.schemaVersion
    return metadata
end

function Peripherals.serializeMetadata(metadata)
    metadata = metadata or Peripherals.emptyMetadata()
    local lines = { "# Qalcom peripheral metadata schema " .. tostring(Peripherals.schemaVersion), "schema|" .. tostring(Peripherals.schemaVersion) }
    local aliases = {}
    for name, alias in pairs(metadata.aliases or {}) do aliases[#aliases + 1] = { name = name, value = alias } end
    table.sort(aliases, function(left, right) return left.name < right.name end)
    for _, item in ipairs(aliases) do
        if item.name ~= "" and tostring(item.value or "") ~= "" then
            lines[#lines + 1] = "alias|" .. escape(cleanMetadataName(item.name)) .. "|" .. escape(item.value)
        end
    end
    local function appendMarkers(kind, values)
        local names = {}
        for name, enabled in pairs(values or {}) do if enabled then names[#names + 1] = name end end
        table.sort(names)
        for _, name in ipairs(names) do lines[#lines + 1] = kind .. "|" .. escape(name) end
    end
    appendMarkers("blocked", metadata.blocked)
    appendMarkers("trusted", metadata.trusted)
    return table.concat(lines, "\n") .. "\n"
end

function Peripherals.adapterFor(peripheralType, methods)
    local typeText = lower(peripheralType)
    local methodText = lower(table.concat(methods or {}, " "))
    local combined = typeText .. " " .. methodText
    -- Lower the combined evidence string once; each contains() call below
    -- would otherwise re-clean and re-lower the same text repeatedly.
    local function has(needle)
        return combined:find(needle, 1, true) ~= nil
    end
    local adapters = {}
    local function add(name, title, operations, apiVersion)
        adapters[#adapters + 1] = {
            name = name,
            title = title,
            contractVersion = Peripherals.contractVersion,
            apiVersion = apiVersion or "unknown",
            available = true,
            stale = false,
            failure = nil,
            compatibility = "unknown",
            apiCompatible = false,
            supportedReadOperations = copyList(operations),
        }
    end
    if has("aeronautics") or has("aeroworks") or has("airship") or has("vehicle") then
        add("aeronautics", "Aeronautics", { "status", "vehicle telemetry" })
    end
    if has("cbc") or has("cannon") or has("big_cannon") then
        -- CC:CBC exposes standard mounts as cannon_mount and the compact-mount
        -- addon as compact_cannon_mount. Both share the read-only getInfo()
        -- telemetry contract; control methods are deliberately not allowlisted.
        add("cbc", "Create: Big Cannons", { "cannon telemetry", "mount readiness", "aim state", "mount position" })
    end
    if has("propulsion") or (has("create") and (has("engine") or has("assembly"))) then
        add("create_propulsion", "Create: Propulsion", { "status", "propulsion telemetry" })
    end
    if has("aero radar") or has("aeroradar") then
        add("create_aero_radar", "Create Aero Radar", { "status", "radar contacts", "scan metadata" })
    elseif has("radar") then
        add("create_radar", "Create Radar", { "status", "radar contacts", "scan metadata" })
    end
    if #adapters == 0 then
        add("generic", "Generic peripheral", { "safe status" })
    end
    return adapters
end

local function safeStatus(ctx, name, methods)
    -- getInfo is adapter-specific (not a generic status probe); CC:CBC
    -- handles it below so it is called once and normalized consistently.
    local candidates = { "getStatus", "getState", "getHealth", "getSignalStrength", "getRange", "isConnected" }
    local allowed = {}
    for _, method in ipairs(candidates) do
        if listContains(methods, method) then allowed[#allowed + 1] = method end
    end
    for _, method in ipairs(allowed) do
        local value, reason = ctx:peripheralRead(name, method)
        if value ~= nil then
            if type(value) == "table" then
                local summary = {}
                for key, item in pairs(value) do
                    if #summary >= 4 then break end
                    if type(item) ~= "table" and type(item) ~= "function" then
                        summary[#summary + 1] = clean(key, 24) .. "=" .. clean(item, 32)
                    end
                end
                local summaryText = table.concat(summary, ", ")
                return summaryText ~= "" and summaryText or "reported"
            end
            return clean(value)
        end
        if reason and method == allowed[#allowed] then return nil, reason end
    end
    return nil
end

local function normalizePosition(value)
    if type(value) ~= "table" then return nil end
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if not x and not y and not z then return nil end
    return { x = x, y = y, z = z }
end

local function normalizeCbcInfo(value)
    if type(value) ~= "table" then return nil end
    -- Keep only the documented CC:CBC getInfo() scalar fields. This prevents
    -- an addon from injecting an unbounded or opaque table into the desktop.
    local result, count = {}, 0
    local fields = {
        "computerControl", "assembled", "yaw", "pitch", "targetYaw", "targetPitch",
        "yawShaftSpeed", "pitchShaftSpeed", "x", "y", "z",
    }
    for _, field in ipairs(fields) do
        local item = value[field]
        if type(item) == "boolean" then result[field] = item; count = count + 1
        elseif type(item) == "number" then result[field] = item; count = count + 1 end
    end
    -- Require the mount-state field plus at least one position/angle field;
    -- this avoids confirming arbitrary cannon-like peripherals on a single
    -- coincidental key.
    local hasMountState = type(result.assembled) == "boolean"
    local hasTelemetry = result.yaw ~= nil or result.pitch ~= nil or result.x ~= nil or result.y ~= nil or result.z ~= nil
    return hasMountState and hasTelemetry and result or nil
end

function Peripherals.normalizeContacts(raw, source, now, limit)
    local contacts = {}
    now = tonumber(now) or 0
    limit = math.max(1, math.min(Peripherals.maxContacts, tonumber(limit) or Peripherals.maxContacts))
    if type(raw) ~= "table" then return contacts end
    local function append(item)
        if #contacts >= limit or type(item) ~= "table" then return end
        local identity = item.identity or item.name or item.id or item.target
        local identityStatus = item.identityStatus
        if identityStatus ~= "friendly" and identityStatus ~= "claimed" and identityStatus ~= "unverified" and identityStatus ~= "ambiguous" then
            identityStatus = identity and (item.ambiguous and "ambiguous" or "unverified") or "ambiguous"
        end
        local timestamp = tonumber(item.timestamp or item.time or item.seenAt) or now
        contacts[#contacts + 1] = {
            source = clean(source, 80),
            timestamp = timestamp,
            age = math.max(0, now - timestamp),
            position = normalizePosition(item.position or item.pos or item.location),
            heading = tonumber(item.heading or item.yaw),
            confidence = clamp(item.confidence, 0, 1, 0),
            identity = clean(identity or "unknown", 64),
            identityStatus = identityStatus,
        }
    end
    local scanned = 0
    local scanLimit = math.min(Peripherals.maxContacts * 4, 128)
    if #raw > 0 then
        for _, item in ipairs(raw) do
            scanned = scanned + 1
            if scanned > scanLimit then break end
            append(item)
        end
    else
        for _, item in pairs(raw) do
            scanned = scanned + 1
            if scanned > scanLimit then break end
            append(item)
        end
    end
    return contacts
end

function Peripherals.inspect(ctx, metadata, now)
    metadata = metadata or Peripherals.emptyMetadata()
    local names, inventoryReason = ctx:peripheralNames()
    names = names or {}
    local devices = {}
    for _, name in ipairs(names) do
        name = tostring(name)
        local peripheralType, typeReason = ctx:peripheralType(name)
        peripheralType = peripheralType or "unknown"
        local rawMethods, methodsReason = ctx:peripheralMethods(name)
        local methods = {}
        for _, method in ipairs(rawMethods or {}) do methods[#methods + 1] = tostring(method) end
        while #methods > Peripherals.maxMethods do table.remove(methods) end
        table.sort(methods)
        local adapters = Peripherals.adapterFor(peripheralType, methods)
        local device = {
            name = name,
            side = (name == "top" or name == "bottom" or name == "left" or name == "right" or name == "front" or name == "back") and name or "attached",
            type = clean(peripheralType, 80),
            methods = methods,
            methodCount = #methods,
            alias = metadata.aliases[name],
            blocked = metadata.blocked[name] == true,
            trusted = metadata.trusted[name] == true,
            adapters = adapters,
            status = nil,
            statusFailure = nil,
            inventoryFailure = inventoryReason,
            typeFailure = typeReason,
            methodsFailure = methodsReason,
            contacts = {},
        }
        device.status, device.statusFailure = safeStatus(ctx, name, methods)
        if device.statusFailure or device.typeFailure or device.methodsFailure then
            for _, adapter in ipairs(device.adapters) do
                adapter.available = false
                adapter.stale = true
                adapter.failure = device.typeFailure or device.methodsFailure
            end
        end
        for _, adapter in ipairs(device.adapters) do
            if adapter.name == "create_radar" or adapter.name == "create_aero_radar" then
                local raw, method
                if listContains(methods, "getContacts") then raw, method = ctx:peripheralRead(name, "getContacts"), "getContacts"
                elseif listContains(methods, "getScan") then raw, method = ctx:peripheralRead(name, "getScan"), "getScan" end
                device.contacts = Peripherals.normalizeContacts(raw, name, now, Peripherals.maxContacts)
                if method and raw ~= nil then
                    adapter.apiCompatible = true
                    adapter.compatibility = "confirmed-read"
                else
                    adapter.stale = true
                    adapter.failure = "No confirmed contact read method"
                end
            elseif adapter.name == "aeronautics" then
                local probe
                if listContains(methods, "getPosition") then probe = ctx:peripheralRead(name, "getPosition")
                elseif listContains(methods, "getLocation") then probe = ctx:peripheralRead(name, "getLocation") end
                if probe ~= nil then adapter.apiCompatible = true; adapter.compatibility = "confirmed-read" end
            elseif adapter.name == "cbc" then
                -- Verified CC:CBC API: cannon_mount and compact_cannon_mount
                -- provide getInfo(). Do not probe assemble/fire or any aiming
                -- setter; those are world-changing controls.
                local info
                if listContains(methods, "getInfo") then info = ctx:peripheralRead(name, "getInfo") end
                device.cbcInfo = normalizeCbcInfo(info)
                if device.cbcInfo then
                    device.status = "CC:CBC getInfo available"
                    adapter.apiCompatible = true
                    adapter.compatibility = "confirmed-read"
                    adapter.apiVersion = "cc-cbc-getInfo-v1"
                else
                    adapter.stale = true
                    adapter.failure = "CC:CBC getInfo() did not return telemetry"
                end
            elseif adapter.name == "create_propulsion" then
                local probe
                if listContains(methods, "getEnergy") then probe = ctx:peripheralRead(name, "getEnergy")
                elseif listContains(methods, "getFuel") then probe = ctx:peripheralRead(name, "getFuel") end
                if probe ~= nil then adapter.apiCompatible = true; adapter.compatibility = "confirmed-read" end
            end
        end
        devices[#devices + 1] = device
    end
    table.sort(devices, function(left, right) return (left.alias or left.name) < (right.alias or right.name) end)
    return devices
end

return Peripherals
