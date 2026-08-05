local Roles = {}

Roles.schemaVersion = 1
Roles.default = "Observer"
Roles.legacyAdministrator = "Administrator"

local definitions = {
    Administrator = {
        label = "Administrator",
        description = "Full local administrative access",
        capabilities = {
            "fs.read", "fs.write", "peripheral.read", "peripheral.control", "account.manage",
            "redstone.read", "redstone.control", "network.send", "network.receive",
            "system.reboot", "system.shutdown",
        },
    },
    Commander = {
        label = "Commander",
        description = "Strategic operations and emergency oversight",
        capabilities = {
            "fs.read", "peripheral.read", "redstone.read", "redstone.control",
            "network.send", "network.receive", "system.reboot",
        },
    },
    ["Operations officer"] = {
        label = "Operations officer",
        description = "Base operations and approved infrastructure response",
        capabilities = {
            "fs.read", "peripheral.read", "redstone.read", "redstone.control",
            "network.send", "network.receive",
        },
    },
    ["Artillery officer"] = {
        label = "Artillery officer",
        description = "Artillery telemetry and future server-approved actions",
        capabilities = {
            "fs.read", "peripheral.read", "network.receive",
        },
    },
    Engineer = {
        label = "Engineer",
        description = "Vehicle, propulsion, and infrastructure telemetry",
        capabilities = {
            "fs.read", "peripheral.read", "peripheral.control", "redstone.read",
            "redstone.control", "network.receive",
        },
    },
    ["Logistics officer"] = {
        label = "Logistics officer",
        description = "Supply, storage, and transport telemetry",
        capabilities = {
            "fs.read", "peripheral.read", "redstone.read", "network.receive",
        },
    },
    Observer = {
        label = "Observer",
        description = "Read-only status and incident visibility",
        capabilities = {
            "fs.read", "peripheral.read", "redstone.read", "network.receive",
        },
    },
    ["Automation service"] = {
        label = "Automation service",
        description = "Bounded service identity for future structured jobs",
        capabilities = {
            "fs.read", "peripheral.read", "redstone.read", "redstone.control",
            "network.send", "network.receive",
        },
    },
    ["Restricted guest"] = {
        label = "Restricted guest",
        description = "Identity with no managed operational permissions",
        capabilities = {},
    },
}

local order = {
    "Administrator", "Commander", "Operations officer", "Artillery officer",
    "Engineer", "Logistics officer", "Observer", "Automation service", "Restricted guest",
}

local function copyList(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[index] = value end
    return result
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

function Roles.exists(role)
    return type(role) == "string" and definitions[role] ~= nil
end

function Roles.normalize(role, legacyFirstAccount)
    if Roles.exists(role) then return role end
    if role == nil and legacyFirstAccount then return Roles.legacyAdministrator end
    return Roles.default
end

function Roles.names()
    return copyList(order)
end

function Roles.definition(role)
    local source = definitions[Roles.normalize(role)]
    if not source then return nil end
    return {
        name = Roles.normalize(role),
        label = source.label,
        description = source.description,
        capabilities = copyList(source.capabilities),
    }
end

function Roles.capabilitiesFor(role)
    local definition = Roles.definition(role)
    return definition and definition.capabilities or {}
end

function Roles.allows(role, capability)
    return contains(Roles.capabilitiesFor(role), capability)
end

return Roles
