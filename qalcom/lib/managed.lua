local Managed = {}
local unpack = table.unpack or unpack

local READ_ONLY_METHODS = {
    getStatus = true,
    getState = true,
    getInfo = true,
    getHealth = true,
    getSignalStrength = true,
    getRange = true,
    isConnected = true,
    getContacts = true,
    getScan = true,
    getPosition = true,
    getHeading = true,
    getVersion = true,
    getName = true,
    getType = true,
    getFuel = true,
    getEnergy = true,
    getPower = true,
    getTemperature = true,
    getReadiness = true,
    getAmmo = true,
    getInventory = true,
}

local function hasMethod(methods, wanted)
    for _, method in ipairs(methods or {}) do
        if method == wanted then return true end
    end
    return false
end

local function clean(value)
    return tostring(value or "unknown"):gsub("[\r\n]", " "):sub(1, 120)
end

local function denied(ctx, capability, detail)
    local policy = ctx and ctx.policy and ctx:policy(capability) or nil
    local reason = "Capability denied: " .. tostring(capability)
    local auditDetail = capability .. " operation=" .. clean(detail)
    if policy then auditDetail = auditDetail .. " role=" .. clean(policy.role) .. " reason=" .. clean(policy.reason) end
    if ctx and ctx.audit then ctx:audit("denied", auditDetail) end
    if ctx and ctx.notify then ctx:notify(reason, colors.red) end
    return false, reason
end

local function allowed(ctx, capability, detail)
    if not ctx or not ctx.hasCapability or not ctx:hasCapability(capability) then
        return denied(ctx, capability, detail)
    end
    return true
end

local function call(functionName, callback, fallback)
    local ok, value = pcall(callback)
    if not ok then return nil, tostring(value or fallback or (functionName .. " failed")) end
    return value
end

function Managed.pathInfo(ctx, path)
    local ok, reason = allowed(ctx, "fs.read", path)
    if not ok then return nil, reason end
    local exists, existsReason = call("fs.exists", function() return fs.exists(path) end)
    if exists == nil then return nil, existsReason end
    if not exists then return { exists = false, directory = false, readOnly = false } end
    local directory, directoryReason = call("fs.isDir", function() return fs.isDir(path) end, "Unable to inspect path")
    if directory == nil then return nil, directoryReason end
    local readOnly, readOnlyReason = call("fs.isReadOnly", function() return fs.isReadOnly(path) end, "Unable to inspect path")
    if readOnly == nil then return nil, readOnlyReason end
    return { exists = true, directory = directory == true, readOnly = readOnly == true }
end

function Managed.listDirectory(ctx, path)
    local ok, reason = allowed(ctx, "fs.read", path)
    if not ok then return {}, reason end
    local names, listReason = call("fs.list", function() return fs.list(path) end, "Unable to list directory")
    if type(names) ~= "table" then return {}, listReason or "Unable to list directory" end
    local entries = {}
    for _, name in ipairs(names) do
        local child = fs.combine(path, name)
        local directory = call("fs.isDir", function() return fs.isDir(child) end, false)
        entries[#entries + 1] = { name = name, path = child, dir = directory == true }
    end
    return entries
end

function Managed.readFile(ctx, path)
    local ok, reason = allowed(ctx, "fs.read", path)
    if not ok then return nil, reason end
    local info, infoReason = Managed.pathInfo(ctx, path)
    if not info or not info.exists or info.directory then return nil, infoReason or "File not found" end
    local okOpen, file = pcall(fs.open, path, "r")
    if not okOpen or not file then return nil, "Unable to read file" end
    local okRead, text = pcall(file.readAll)
    pcall(file.close)
    if not okRead then return nil, tostring(text or "Unable to read file") end
    return text or ""
end

function Managed.writeFile(ctx, path, text)
    local ok, reason = allowed(ctx, "fs.write", path)
    if not ok then return false, reason end
    local okOpen, file = pcall(fs.open, path, "w")
    if not okOpen or not file then return false, "Unable to write file" end
    local okWrite, failure = pcall(file.write, tostring(text or ""))
    pcall(file.close)
    return okWrite, okWrite and nil or tostring(failure or "Unable to write file")
end

function Managed.touch(ctx, path)
    local ok, reason = allowed(ctx, "fs.write", path)
    if not ok then return false, reason end
    local okOpen, file = pcall(fs.open, path, "a")
    if not okOpen or not file then return false, "Unable to create file" end
    local okClose, failure = pcall(file.close)
    return okClose, okClose and nil or tostring(failure or "Unable to create file")
end

function Managed.makeDir(ctx, path)
    local ok, reason = allowed(ctx, "fs.write", path)
    if not ok then return false, reason end
    local success, value = pcall(fs.makeDir, path)
    return success and value ~= false, success and nil or tostring(value)
end

function Managed.delete(ctx, path)
    local ok, reason = allowed(ctx, "fs.write", path)
    if not ok then return false, reason end
    local readOnly = call("fs.isReadOnly", function() return fs.isReadOnly(path) end, false)
    if readOnly then return false, "Read-only path" end
    local success, value = pcall(fs.delete, path)
    return success and value ~= false, success and nil or tostring(value)
end

function Managed.copy(ctx, source, destination)
    local ok, reason = allowed(ctx, "fs.read", source)
    if not ok then return false, reason end
    ok, reason = allowed(ctx, "fs.write", destination)
    if not ok then return false, reason end
    local success, value = pcall(fs.copy, source, destination)
    return success and value ~= false, success and nil or tostring(value)
end

function Managed.move(ctx, source, destination)
    local ok, reason = allowed(ctx, "fs.read", source)
    if not ok then return false, reason end
    ok, reason = allowed(ctx, "fs.write", destination)
    if not ok then return false, reason end
    local success, value = pcall(fs.move, source, destination)
    return success and value ~= false, success and nil or tostring(value)
end

function Managed.peripheralNames(ctx)
    local ok, reason = allowed(ctx, "peripheral.read", "inventory")
    if not ok then return {}, reason end
    local names = call("peripheral.getNames", function() return peripheral.getNames() end)
    if type(names) ~= "table" then return {}, "Peripheral inventory unavailable" end
    return names
end

function Managed.peripheralType(ctx, name)
    local ok, reason = allowed(ctx, "peripheral.read", name)
    if not ok then return nil, reason end
    return call("peripheral.getType", function() return peripheral.getType(name) end, "Peripheral type unavailable")
end

function Managed.peripheralMethods(ctx, name)
    local ok, reason = allowed(ctx, "peripheral.read", name)
    if not ok then return {}, reason end
    local methods = call("peripheral.getMethods", function() return peripheral.getMethods(name) end)
    if type(methods) ~= "table" then return {}, "Peripheral methods unavailable" end
    return methods
end

function Managed.peripheralRead(ctx, name, method, ...)
    local ok, reason = allowed(ctx, "peripheral.read", name .. ":" .. tostring(method))
    if not ok then return nil, reason end
    if type(method) ~= "string" or not READ_ONLY_METHODS[method] then
        return nil, "Method is not allowlisted for read-only inspection"
    end
    local methods = Managed.peripheralMethods(ctx, name)
    if not hasMethod(methods, method) then return nil, "Peripheral method unavailable" end
    local args = { ... }
    local value
    local failure
    local success = pcall(function()
        local wrapped = peripheral.wrap(name)
        if not wrapped or type(wrapped[method]) ~= "function" then
            failure = "Peripheral method unavailable"
            return
        end
        value = wrapped[method](unpack(args))
    end)
    if not success then return nil, "Peripheral read failed" end
    if failure then return nil, failure end
    return value
end

function Managed.peripheralMetadata(ctx, name)
    local methods, reason = Managed.peripheralMethods(ctx, name)
    if not methods then return nil, reason end
    return { name = name, type = Managed.peripheralType(ctx, name), methods = methods }
end

function Managed.peripheralInventory(ctx)
    local names, reason = Managed.peripheralNames(ctx)
    if not names then return {}, reason end
    local inventory = {}
    for _, name in ipairs(names) do
        local metadata = Managed.peripheralMetadata(ctx, name)
        if metadata then inventory[#inventory + 1] = metadata end
    end
    return inventory
end

function Managed.peripheralMetadataFile(ctx)
    local ok, reason = allowed(ctx, "fs.read", "/qalcom/data/peripherals.meta")
    if not ok then return nil, reason end
    if not fs.exists("/qalcom/data/peripherals.meta") then return nil end
    local file = fs.open("/qalcom/data/peripherals.meta", "r")
    if not file then return nil, "Peripheral metadata unavailable" end
    local success, text = pcall(file.readAll)
    pcall(file.close)
    if not success then return nil, "Peripheral metadata unavailable" end
    return text or ""
end

function Managed.writePeripheralMetadata(ctx, text)
    local ok, reason = allowed(ctx, "fs.write", "/qalcom/data/peripherals.meta")
    if not ok then return false, reason end
    if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
    local file = fs.open("/qalcom/data/peripherals.meta", "w")
    if not file then return false, "Unable to save peripheral metadata" end
    local success, failure = pcall(file.write, tostring(text or ""))
    pcall(file.close)
    return success, success and nil or tostring(failure or "Unable to save peripheral metadata")
end

function Managed.redstoneInput(ctx, side)
    local ok, reason = allowed(ctx, "redstone.read", side)
    if not ok then return nil, reason end
    local value = call("redstone.getInput", function() return redstone.getInput(side) end)
    return value
end

function Managed.redstoneOutput(ctx, side, value)
    return Managed.redstoneWrite(ctx, side, value)
end

function Managed.redstoneState(ctx, side)
    local ok, reason = allowed(ctx, "redstone.read", side)
    if not ok then return nil, reason end
    local value = call("redstone.getOutput", function() return redstone.getOutput(side) end)
    if value == nil then return nil, "Redstone output state unavailable" end
    return value == true
end

function Managed.redstoneWrite(ctx, side, value)
    local ok, reason = allowed(ctx, "redstone.control", side)
    if not ok then return false, reason end
    local success, failure = pcall(redstone.setOutput, side, value == true)
    if not success then return false, tostring(failure or "Unable to set redstone output") end
    return true
end

function Managed.setLabel(ctx, label)
    local ok, reason = allowed(ctx, "system.label", "computer label")
    if not ok then return false, reason end
    local success, failure = pcall(os.setComputerLabel, label)
    return success, success and nil or tostring(failure or "Unable to set computer label")
end

function Managed.power(ctx, action)
    local capability = action == "reboot" and "system.reboot" or action == "shutdown" and "system.shutdown"
    if not capability then return false, "Unsupported power action" end
    local ok, reason = allowed(ctx, capability, action)
    if not ok then return false, reason end
    return ctx:requestPower(action)
end

return Managed
