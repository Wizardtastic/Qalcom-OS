local Cannon = {}

Cannon.schemaVersion = 1
Cannon.maxCannons = 16
Cannon.maxTargetDistance = 1000000
Cannon.maxCoordinate = 30000000
Cannon.defaultTolerance = 2
Cannon.defaultPulse = 0.2
Cannon.defaultYawOffset = 0
Cannon.defaultPitchSign = 1

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function number(value)
    local result = tonumber(value)
    return finite(result) and result or nil
end

local function clamp(value, minimum, maximum, fallback)
    local result = number(value) or fallback
    if result < minimum then return minimum end
    if result > maximum then return maximum end
    return result
end

local function normalizeYaw(value)
    local yaw = number(value) or 0
    yaw = yaw % 360
    if yaw >= 180 then yaw = yaw - 360 end
    return yaw
end

local function angleDifference(left, right)
    return math.abs(normalizeYaw(left - right))
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function cleanCoordinate(value)
    local result = number(value)
    if not result or math.abs(result) > Cannon.maxCoordinate then return nil end
    return result
end

function Cannon.target(x, y, z)
    x, y, z = cleanCoordinate(x), cleanCoordinate(y), cleanCoordinate(z)
    if not x or not y or not z then return nil, "Target coordinates must be finite and within world bounds" end
    return { x = x, y = y, z = z }
end

function Cannon.targetFromContact(contact)
    if type(contact) ~= "table" or type(contact.position) ~= "table" then
        return nil, "Radar contact has no position"
    end
    -- A radar contact is an observation, not an identity assertion. An
    -- unverified contact may still be used when it has a fresh position, but
    -- ambiguous contacts are rejected and the UI always requires confirmation.
    if contact.identityStatus == "ambiguous" then
        return nil, "Radar contact identity is ambiguous"
    end
    if contact.age and (not number(contact.age) or contact.age > 10) then
        return nil, "Radar contact is stale"
    end
    return Cannon.target(contact.position.x, contact.position.y, contact.position.z)
end

function Cannon.anglesFromPosition(position, target, options)
    options = options or {}
    if type(position) ~= "table" or type(target) ~= "table" then return nil, "Cannon and target positions are required" end
    local x, y, z = number(position.x), number(position.y), number(position.z)
    if not x or not y or not z then return nil, "Cannon position is unavailable" end
    local dx, dy, dz = target.x - x, target.y - y, target.z - z
    local horizontal = math.sqrt(dx * dx + dz * dz)
    local distance = math.sqrt(horizontal * horizontal + dy * dy)
    if not finite(distance) or distance <= 0 or distance > Cannon.maxTargetDistance then return nil, "Target is too close or too far away" end
    local yawOffset = number(options.yawOffset) or Cannon.defaultYawOffset
    local pitchSign = number(options.pitchSign) or Cannon.defaultPitchSign
    pitchSign = pitchSign < 0 and -1 or 1
    local yaw = math.deg(atan2(dx, dz)) + yawOffset
    -- This is geometric line-of-sight aiming, not a ballistic solution. CBC
    -- projectile velocity, gravity, drag, propellant, and elevation limits are
    -- mod/ammunition-specific and are intentionally not guessed here.
    local pitch = math.deg(atan2(dy, horizontal)) * pitchSign
    if not finite(yaw) or not finite(pitch) or pitch < -90 or pitch > 90 then return nil, "Target angle is invalid" end
    return { yaw = normalizeYaw(yaw), pitch = pitch, distance = distance }
end

function Cannon.plan(cannons, target, options)
    local result = { target = target, entries = {}, rejected = {} }
    for _, cannon in ipairs(cannons or {}) do
        if #result.entries + #result.rejected >= Cannon.maxCannons then break end
        local info = cannon.cbcInfo or cannon.info or cannon
        local position = info.position or info
        local angles, reason = Cannon.anglesFromPosition(position, target, options)
        if angles then result.entries[#result.entries + 1] = { cannon = cannon, angles = angles }
        else result.rejected[#result.rejected + 1] = { cannon = cannon, reason = reason } end
    end
    return result
end

function Cannon.aligned(info, targetAngles, tolerance)
    if type(info) ~= "table" or type(targetAngles) ~= "table" then return false end
    tolerance = clamp(tolerance, 0.1, 20, Cannon.defaultTolerance)
    local yaw, pitch = number(info.yaw), number(info.pitch)
    local targetYaw, targetPitch = number(targetAngles.yaw), number(targetAngles.pitch)
    return yaw and pitch and targetYaw and targetPitch
        and angleDifference(yaw, targetYaw) <= tolerance
        and math.abs(pitch - targetPitch) <= tolerance
end

function Cannon.toggleSelection(selected, id)
    selected = selected or {}
    selected[id] = not selected[id]
    return selected
end

function Cannon.selectedDevices(devices, selected)
    local result = {}
    for _, device in ipairs(devices or {}) do
        if selected and selected[device.name] then result[#result + 1] = device end
    end
    return result
end

function Cannon.settings(options)
    options = options or {}
    return {
        yawOffset = clamp(options.yawOffset, -180, 180, Cannon.defaultYawOffset),
        pitchSign = (number(options.pitchSign) or Cannon.defaultPitchSign) < 0 and -1 or 1,
        tolerance = clamp(options.tolerance, 0.1, 20, Cannon.defaultTolerance),
        pulse = clamp(options.pulse, 0.05, 1, Cannon.defaultPulse),
    }
end

return Cannon
