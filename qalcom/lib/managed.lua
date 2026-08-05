local Managed = {}

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

function Managed.redstoneInput(ctx, side)
    local ok, reason = allowed(ctx, "redstone.read", side)
    if not ok then return nil, reason end
    local value = call("redstone.getInput", function() return redstone.getInput(side) end)
    return value
end

function Managed.redstoneOutput(ctx, side, value)
    local ok, reason = allowed(ctx, "redstone.control", side)
    if not ok then return false, reason end
    local success, failure = pcall(redstone.setOutput, side, value == true)
    return success, success and nil or tostring(failure or "Unable to set redstone output")
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
