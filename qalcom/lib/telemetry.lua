local Telemetry = {}

Telemetry.schemaVersion = 1
Telemetry.maxRecords = 64
Telemetry.maxHistory = 16
Telemetry.maxText = 80

local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n]", " "):sub(1, maximum or Telemetry.maxText)
end

local function lower(value)
    return string.lower(clean(value, 160))
end

local function has(list, wanted)
    for _, value in ipairs(list or {}) do if value == wanted then return true end end
    return false
end

local function number(value)
    local result = tonumber(value)
    return result
end

local function boundValue(value, depth)
    depth = depth or 0
    if depth > 3 then return "<depth>" end
    if type(value) == "string" then return clean(value, Telemetry.maxText) end
    if type(value) == "number" or type(value) == "boolean" or value == nil then return value end
    if type(value) ~= "table" then return "<unsupported>" end
    local result, count = {}, 0
    for key, item in pairs(value) do
        if (type(key) == "string" or type(key) == "number") and count < 8 then
            result[clean(key, 32)] = boundValue(item, depth + 1)
            count = count + 1
        end
    end
    return result
end

local function copyPosition(value)
    if type(value) ~= "table" then return nil end
    return {
        x = number(value.x or value[1]),
        y = number(value.y or value[2]),
        z = number(value.z or value[3]),
    }
end

local function adapterKind(device)
    for _, adapter in ipairs(device.adapters or {}) do
        if adapter.available and not adapter.stale and adapter.apiCompatible == true then return adapter.name end
    end
    for _, adapter in ipairs(device.adapters or {}) do
        if adapter.name ~= "generic" then return adapter.name end
    end
    return device.type or "unknown"
end

local function candidateStatus(device)
    if device.blocked then return "blocked", "Device is blocklisted" end
    if not device.status and device.statusFailure then return "degraded", device.statusFailure end
    local candidate = false
    local compatible = false
    for _, adapter in ipairs(device.adapters or {}) do
        if adapter.name ~= "generic" then candidate = true end
        if adapter.apiCompatible == true and adapter.available and not adapter.stale then compatible = true end
        if adapter.stale then return "stale", adapter.failure or "Adapter has no current data" end
        if not adapter.available then return "unavailable", adapter.failure or "Adapter unavailable" end
    end
    if candidate and not compatible then return "unknown", "Candidate integration needs an in-game API probe" end
    if not device.status then return "unknown", "No safe status method reported" end
    return "online", nil
end

local function read(ctx, name, methods, methodList, ...)
    for _, method in ipairs(methods) do
        if has(methodList, method) then
            local value, reason = ctx:peripheralRead(name, method, ...)
            if value ~= nil then return value, method end
            if reason then return nil, reason end
        end
    end
    return nil, "No supported read method"
end

function Telemetry.adapterForDevice(device)
    local kind = adapterKind(device)
    local title = "Peripheral telemetry"
    if kind == "aeronautics" then title = "Aeronautics telemetry"
    elseif kind == "cbc" then title = "CBC artillery telemetry"
    elseif kind == "create_propulsion" then title = "Create: Propulsion telemetry"
    elseif kind == "create_radar" or kind == "create_aero_radar" then title = "Radar telemetry" end
    return {
        name = kind,
        title = title,
        contractVersion = Telemetry.schemaVersion,
        readOnly = true,
        supported = kind ~= "unknown" and kind ~= "generic",
    }
end

function Telemetry.snapshot(ctx, devices, now)
    local records = {}
    now = tonumber(now) or 0
    for _, device in ipairs(devices or {}) do
        if #records >= Telemetry.maxRecords then break end
        local health, failure = candidateStatus(device)
        local record = {
            id = clean(device.name, 48),
            alias = clean(device.alias or device.name, 48),
            source = clean(device.name, 48),
            adapter = Telemetry.adapterForDevice(device),
            kind = adapterKind(device),
            health = health,
            failure = clean(failure, Telemetry.maxText),
            timestamp = now,
            age = 0,
            trusted = device.trusted == true,
            blocked = device.blocked == true,
            contacts = {},
            data = {},
        }
        if device.contacts and #device.contacts > 0 then
            record.contacts = boundValue(device.contacts)
            record.data.contactCount = #record.contacts
        end
        if device.status then record.data.status = clean(device.status) end

        local typeText = lower(device.type)
        local methods = device.methods or {}
        if health == "online" and device.name and ctx then
            if kind == "aeronautics" then
                local position = read(ctx, device.name, { "getPosition", "getLocation" }, methods)
                local heading = read(ctx, device.name, { "getHeading", "getYaw" }, methods)
                local velocity = read(ctx, device.name, { "getVelocity", "getSpeed" }, methods)
                record.data.position = copyPosition(position)
                record.data.heading = number(heading)
                record.data.velocity = number(velocity)
            elseif kind == "cbc" then
                record.data.readiness = read(ctx, device.name, { "getReadiness", "isReady", "getState" }, methods)
                record.data.ammo = boundValue(read(ctx, device.name, { "getAmmo", "getAmmunition", "getInventory" }, methods))
                record.data.position = copyPosition(read(ctx, device.name, { "getPosition" }, methods))
            elseif kind == "create_propulsion" then
                record.data.energy = boundValue(read(ctx, device.name, { "getEnergy", "getPower" }, methods))
                record.data.fuel = boundValue(read(ctx, device.name, { "getFuel" }, methods))
                record.data.readiness = boundValue(read(ctx, device.name, { "getReadiness", "getState" }, methods))
            elseif kind == "create_radar" or kind == "create_aero_radar" then
                record.data.range = read(ctx, device.name, { "getRange" }, methods)
                record.data.signal = read(ctx, device.name, { "getSignalStrength" }, methods)
            elseif typeText ~= "" and #methods > 0 then
                record.data.methodCount = #methods
            end
        end
        records[#records + 1] = record
    end
    return records
end

function Telemetry.mergeContacts(records, now, limit)
    now = tonumber(now) or 0
    limit = math.max(1, math.min(Telemetry.maxRecords, tonumber(limit) or Telemetry.maxRecords))
    local merged, seen = {}, {}
    for _, record in ipairs(records or {}) do
        for _, contact in ipairs(record.contacts or {}) do
            if #merged >= limit then break end
            local position = contact.position or {}
            local key = clean(contact.identity, 48) .. ":" .. tostring(position.x or "?") .. ":" .. tostring(position.z or "?")
            if not seen[key] then
                seen[key] = true
                local copy = {}
                for field, value in pairs(contact) do copy[field] = value end
                copy.sources = { record.source }
                copy.age = math.max(0, now - (tonumber(copy.timestamp) or now))
                merged[#merged + 1] = copy
            end
        end
    end
    return merged
end

function Telemetry.summary(records, contacts)
    local result = {
        total = 0, online = 0, stale = 0, degraded = 0, unavailable = 0, blocked = 0, unknown = 0,
        radar = 0, aeronautics = 0, cbc = 0, propulsion = 0, contacts = #(contacts or {}),
    }
    for _, record in ipairs(records or {}) do
        result.total = result.total + 1
        local state = record.health or "unavailable"
        if result[state] ~= nil then result[state] = result[state] + 1 end
        if record.kind == "create_radar" or record.kind == "create_aero_radar" then result.radar = result.radar + 1 end
        if record.kind == "aeronautics" then result.aeronautics = result.aeronautics + 1 end
        if record.kind == "cbc" then result.cbc = result.cbc + 1 end
        if record.kind == "create_propulsion" then result.propulsion = result.propulsion + 1 end
    end
    return result
end

return Telemetry
