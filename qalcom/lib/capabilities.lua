local Capabilities = {}

Capabilities.schemaVersion = 1
Capabilities.names = {
    "fs.read",
    "fs.write",
    "peripheral.read",
    "peripheral.control",
    "redstone.read",
    "redstone.control",
    "network.send",
    "network.receive",
    "system.reboot",
    "system.shutdown",
}

Capabilities.descriptions = {
    ["fs.read"] = "Read files and directories",
    ["fs.write"] = "Create, modify, copy, or delete files",
    ["peripheral.read"] = "Inspect attached peripherals",
    ["peripheral.control"] = "Invoke allowlisted peripheral controls",
    ["redstone.read"] = "Read redstone state",
    ["redstone.control"] = "Change managed redstone outputs",
    ["network.send"] = "Send approved network messages",
    ["network.receive"] = "Receive approved network messages",
    ["system.reboot"] = "Request a computer reboot",
    ["system.shutdown"] = "Request a computer shutdown",
}

-- 0.2.0 describes policy; it does not sandbox trusted Lua globals. Requested
-- entries are declarations only; approval decisions arrive in a later milestone.
local manifests = {
    terminal = {
        title = "Terminal", trusted = true,
        requested = { "fs.read", "fs.write", "system.reboot", "system.shutdown" },
        unmanaged = { "term", "os.pullEvent" },
    },
    explorer = {
        title = "File Explorer", trusted = true,
        requested = { "fs.read", "fs.write" },
        unmanaged = { "term", "os.pullEvent" },
    },
    monitor = {
        title = "System Monitor", trusted = true,
        requested = { "peripheral.read" },
        unmanaged = { "term", "os.pullEvent" },
    },
    settings = {
        title = "Settings", trusted = true,
        requested = { "fs.read", "fs.write" },
        unmanaged = { "settings", "os.setComputerLabel", "os.pullEvent" },
    },
    account = {
        title = "Account", trusted = true,
        requested = {},
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
        requested = {},
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
