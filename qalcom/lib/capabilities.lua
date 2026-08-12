local Capabilities = {}
local function loadRoles()
    local candidates = { "qalcom/lib/roles.lua", "../qalcom/lib/roles.lua", "/qalcom/lib/roles.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    error("Unable to load Qalcom roles")
end
local Roles = loadRoles()

Capabilities.schemaVersion = 1
Capabilities.policySchemaVersion = Roles.schemaVersion
Capabilities.names = {
    "fs.read",
    "fs.write",
    "account.manage",
    "peripheral.read",
    "peripheral.control",
    "redstone.read",
    "redstone.control",
    "infrastructure.control",
    "infrastructure.emergency",
    "jobs.manage",
    "network.send",
    "network.receive",
    "network.configure",
    "telemetry.read",
    "network.pair",
    "network.control",
    "incident.manage",
    "cannon.control",
    "system.label",
    "system.reboot",
    "system.shutdown",
}

Capabilities.descriptions = {
    ["fs.read"] = "Read files and directories",
    ["fs.write"] = "Create, modify, copy, or delete files",
    ["account.manage"] = "Assign roles to local accounts",
    ["peripheral.read"] = "Inspect attached peripherals",
    ["peripheral.control"] = "Invoke allowlisted peripheral controls",
    ["redstone.read"] = "Read redstone state",
    ["redstone.control"] = "Change managed redstone outputs",
    ["infrastructure.control"] = "Control named local infrastructure profiles",
    ["infrastructure.emergency"] = "Set named infrastructure outputs to safe state",
    ["jobs.manage"] = "Create, pause, and stop structured local jobs",
    ["network.send"] = "Send approved network messages",
    ["network.receive"] = "Receive approved network messages",
    ["network.configure"] = "Configure the local modem foundation",
    ["telemetry.read"] = "Inspect normalized mod telemetry",
    ["network.pair"] = "Enroll and revoke Qalcom nodes",
    ["network.control"] = "Issue approved authenticated network controls",
    ["incident.manage"] = "Manage structured war-server incidents",
    ["cannon.control"] = "Aim and fire approved CBC cannon mounts",
    ["system.label"] = "Change the computer label",
    ["system.reboot"] = "Request a computer reboot",
    ["system.shutdown"] = "Request a computer shutdown",
}

-- 0.2.0 describes policy; it does not sandbox trusted Lua globals. Requested
-- entries are declarations only; approval decisions arrive in a later milestone.
local manifests = {
    terminal = {
        title = "Terminal", trusted = true,
        requested = { "fs.read", "fs.write", "system.label", "system.reboot", "system.shutdown" },
        unmanaged = { "term", "os.pullEvent" },
    },
    explorer = {
        title = "File Explorer", trusted = true,
        requested = { "fs.read", "fs.write" },
        unmanaged = { "term", "os.pullEvent" },
    },
    settings = {
        title = "Settings", trusted = true,
        requested = { "fs.read", "fs.write", "system.label" },
        unmanaged = { "settings", "os.pullEvent" },
    },
    account = {
        title = "Account", trusted = true,
        requested = { "account.manage" },
        unmanaged = { "os.queueEvent", "os.pullEvent" },
    },
    editor = {
        title = "Text Viewer", trusted = true,
        requested = { "fs.read", "fs.write" },
        unmanaged = { "term", "os.pullEvent" },
    },
    dialog = {
        title = "Confirm", trusted = true,
        requested = {},
        unmanaged = { "os.queueEvent", "os.pullEvent" },
    },
    control = {
        title = "Control Center", trusted = true,
        requested = { "fs.read", "peripheral.read" },
        unmanaged = { "os.pullEvent" },
    },
    logs = {
        title = "System Log", trusted = true,
        requested = { "fs.read" },
        unmanaged = { "os.pullEvent" },
    },
    recovery = {
        title = "Recovery", trusted = true,
        requested = { "fs.read", "fs.write" },
        unmanaged = { "settings", "os.pullEvent" },
    },
    diagnostics = {
        title = "Diagnostics", trusted = true,
        requested = {},
        unmanaged = { "os.pullEvent" },
    },
    capabilities = {
        title = "Capabilities", trusted = true,
        requested = { "fs.read" },
        unmanaged = { "os.pullEvent" },
    },
    peripherals = {
        title = "Peripheral Manager", trusted = true,
        requested = { "fs.read", "fs.write", "peripheral.read", "telemetry.read" },
        unmanaged = { "os.pullEvent" },
    },
    calculator = {
        title = "Calculator", trusted = true,
        requested = {},
        unmanaged = { "os.pullEvent" },
    },
    fluent = {
        title = "Fluent Desktop", trusted = true,
        requested = {},
        unmanaged = { "term", "os.pullEvent" },
    },
    network = {
        title = "Network Manager", trusted = true,
        requested = { "fs.read", "fs.write", "peripheral.read", "network.configure", "network.receive", "network.pair", "network.control" },
        unmanaged = { "os.pullEvent" },
    },
    network_service = {
        title = "Encrypted Network Service", trusted = true,
        requested = { "fs.read", "fs.write", "peripheral.read", "network.send", "network.receive", "telemetry.read" },
        unmanaged = { "os.pullEvent" },
    },
    telemetry = {
        title = "Operations Telemetry", trusted = true,
        requested = { "peripheral.read", "telemetry.read", "incident.manage" },
        unmanaged = { "os.pullEvent" },
    },
    cannon = {
        title = "CBC Fire Control", trusted = true,
        requested = { "fs.read", "peripheral.read", "cannon.control", "telemetry.read", "incident.manage" },
        unmanaged = { "os.pullEvent" },
    },
}

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function copyList(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[index] = value end
    return result
end

local function cleanDetail(detail)
    return tostring(detail or "unknown"):gsub("[\r\n]", " "):sub(1, 120)
end

function Capabilities.manifest(name)
    local source = manifests[name]
    if not source then return nil end
    return {
        name = name,
        title = source.title,
        trusted = source.trusted == true,
        requested = copyList(source.requested),
        unmanaged = copyList(source.unmanaged),
    }
end

function Capabilities.namesFor(name)
    local manifest = Capabilities.manifest(name)
    return manifest and manifest.requested or {}
end

function Capabilities.has(name, capability)
    return contains(Capabilities.namesFor(name), capability)
end

function Capabilities.roleAllows(role, capability)
    return Roles.allows(role, capability)
end

local function safeModeBlocks(capability)
    return capability == "fs.write" or capability == "peripheral.control"
        or capability == "redstone.control" or capability == "infrastructure.control"
        or capability == "infrastructure.emergency" or capability == "jobs.manage" or capability == "network.send" or capability == "network.receive" or capability == "network.configure" or capability == "network.pair" or capability == "network.control" or capability == "system.label"
        or capability == "cannon.control"
        or capability == "system.reboot" or capability == "system.shutdown"
end

function Capabilities.effective(role, appName, capability, safeMode)
    return not (safeMode == true and safeModeBlocks(capability))
        and Capabilities.roleAllows(role, capability) and Capabilities.has(appName, capability)
end

function Capabilities.policy(role, appName, capability, safeMode)
    local appKnown = Capabilities.manifest(appName) ~= nil
    local roleKnown = Roles.exists(role)
    local declared = appKnown and Capabilities.has(appName, capability) or false
    local safeModeDenied = safeMode == true and safeModeBlocks(capability)
    local allowed = roleKnown and declared and Roles.allows(role, capability) and not safeModeDenied or false
    return {
        role = Roles.normalize(role),
        app = appName,
        capability = capability,
        declared = declared,
        allowed = allowed,
        safeMode = safeMode == true,
        reason = not appKnown and "unknown application"
            or not roleKnown and "unknown role"
            or not declared and "application did not declare capability"
            or safeModeDenied and "Safe Mode blocks sensitive actions"
            or not Roles.allows(role, capability) and "role policy denied"
            or "allowed",
    }
end

function Capabilities.all()
    local result = {}
    for name, _ in pairs(manifests) do result[#result + 1] = name end
    table.sort(result)
    return result
end

function Capabilities.catalog()
    local result = { schemaVersion = Capabilities.schemaVersion, apps = {}, capabilities = {} }
    for _, capability in ipairs(Capabilities.names) do
        result.capabilities[#result.capabilities + 1] = {
            name = capability,
            description = Capabilities.descriptions[capability],
        }
    end
    for _, name in ipairs(Capabilities.all()) do
        result.apps[#result.apps + 1] = Capabilities.manifest(name)
    end
    return result
end

function Capabilities.auditDecision(decision, actor, detail, outcome)
    local allowed = decision and decision.allowed == true
    local action = outcome or (allowed and "approval" or "denial")
    local suffix = tostring(actor or "unknown") .. " " .. tostring(decision and decision.role or "unknown")
        .. " " .. tostring(decision and decision.capability or "unknown")
    if detail then suffix = suffix .. " " .. tostring(detail) end
    return Capabilities.audit(action, suffix)
end

function Capabilities.auditRoleChange(actor, actorRole, target, previousRole, requestedRole, outcome, detail)
    local suffix = tostring(actor or "unknown") .. " " .. tostring(actorRole or "unknown")
        .. " target=" .. tostring(target or "unknown")
        .. " from=" .. tostring(previousRole or "unknown")
        .. " to=" .. tostring(requestedRole or "unknown")
    if detail then suffix = suffix .. " " .. tostring(detail) end
    return Capabilities.audit(outcome or "role-change", suffix)
end

function Capabilities.audit(action, detail)
    -- Auditing must never prevent boot or crash an application when storage is
    -- unavailable, read-only, or occupied by an invalid path.
    local wrote = false
    local ok = pcall(function()
        if not fs.exists("/qalcom/logs") then fs.makeDir("/qalcom/logs") end
        local path = "/qalcom/logs/audit.log"
        local file = fs.open(path, "a")
        if file then
            file.writeLine(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " capability " .. cleanDetail(action) .. " " .. cleanDetail(detail))
            file.close()
            wrote = true
        end
        if fs.getSize and fs.getSize(path) > 120000 then
            local input = fs.open(path, "r")
            local lines = {}
            if input then
                local text = input.readAll() or ""
                input.close()
                for line in (text .. "\n"):gmatch("(.-)\n") do
                    if line ~= "" then lines[#lines + 1] = line end
                end
            end
            while #lines > 500 do table.remove(lines, 1) end
            local output = fs.open(path, "w")
            if output then output.write(table.concat(lines, "\n") .. "\n"); output.close() end
        end
    end)
    return ok and wrote
end

return Capabilities
