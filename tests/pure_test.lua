local function fail(message)
    error(message, 0)
end

local function equal(actual, expected, label)
    if actual ~= expected then
        fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function truthy(value, label)
    if not value then fail(label .. ": expected true") end
end

local function loadPure()
    local candidates = { "qalcom/lib/pure.lua", "../qalcom/lib/pure.lua", "/qalcom/lib/pure.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/pure.lua")
end

local Pure = loadPure()
local function loadRoles()
    local candidates = { "qalcom/lib/roles.lua", "../qalcom/lib/roles.lua", "/qalcom/lib/roles.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/roles.lua")
end

local Roles = loadRoles()
local function loadCapabilities()
    local candidates = { "qalcom/lib/capabilities.lua", "../qalcom/lib/capabilities.lua", "/qalcom/lib/capabilities.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/capabilities.lua")
end

local Capabilities = loadCapabilities()
local function loadAnimation()
    local candidates = { "qalcom/lib/ui/animation.lua", "../qalcom/lib/ui/animation.lua", "/qalcom/lib/ui/animation.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/ui/animation.lua")
end

local Animation = loadAnimation()
local function loadPeripherals()
    local candidates = { "qalcom/lib/peripherals.lua", "../qalcom/lib/peripherals.lua", "/qalcom/lib/peripherals.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/peripherals.lua")
end

local Peripherals = loadPeripherals()
local function loadInfrastructure()
    local candidates = { "qalcom/lib/infrastructure.lua", "../qalcom/lib/infrastructure.lua", "/qalcom/lib/infrastructure.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/infrastructure.lua")
end

local Infrastructure = loadInfrastructure()
local function loadJobs()
    local candidates = { "qalcom/lib/jobs.lua", "../qalcom/lib/jobs.lua", "/qalcom/lib/jobs.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/jobs.lua")
end

local Jobs = loadJobs()
local function loadCalculator()
    local candidates = { "qalcom/lib/calculator.lua", "../qalcom/lib/calculator.lua", "/qalcom/lib/calculator.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/calculator.lua")
end

local Calculator = loadCalculator()
local function loadHit()
    local candidates = { "qalcom/lib/ui/hit.lua", "../qalcom/lib/ui/hit.lua", "/qalcom/lib/ui/hit.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/ui/hit.lua")
end

local Hit = loadHit()
local passed = 0

local function test(label, callback)
    callback()
    passed = passed + 1
    print("PASS " .. label)
end

test("normalizes paths", function()
    equal(Pure.normalizePath("/qalcom/./apps/../lib"), "/qalcom/lib", "normalize")
    equal(Pure.absolutePath("/qalcom/apps", "../lib/ui.lua"), "/qalcom/lib/ui.lua", "absolute")
end)

test("validates usernames", function()
    truthy(Pure.validateUsername("Walker"), "valid username")
    equal(Pure.validateUsername("bad name"), false, "spaces rejected")
    equal(Pure.validateUsername("x"), false, "short username rejected")
end)

test("validates account records", function()
    truthy(Pure.validateAccountRecord({ username = "Walker", salt = "1", digest = "2" }), "valid account")
    equal(Pure.validateAccountRecord({ username = "Walker" }), false, "incomplete account")
end)

test("validates roles and policies", function()
    truthy(Roles.exists("Administrator"), "administrator role")
    equal(Roles.exists("Unknown"), false, "unknown role")
    equal(Roles.normalize(nil, true), "Administrator", "first legacy role")
    equal(Roles.normalize("invalid", true), "Observer", "invalid role fallback")
    truthy(Roles.allows("Administrator", "system.shutdown"), "administrator shutdown")
    truthy(Roles.allows("Administrator", "account.manage"), "administrator account management")
    truthy(Roles.allows("Administrator", "infrastructure.control"), "administrator infrastructure control")
    truthy(Capabilities.policy("Operations officer", "infrastructure", "infrastructure.control", false).allowed, "operations infrastructure policy")
    equal(Roles.allows("Observer", "system.shutdown"), false, "observer shutdown")
    truthy(Pure.validateRole("Observer", Roles.names()), "valid role")
    equal(Pure.validateRole("Unknown", Roles.names()), false, "invalid role")
    truthy(Pure.validatePolicyDecision({ role = "Observer", capability = "fs.read", allowed = true }), "valid decision")
    local allowed = Capabilities.policy("Administrator", "terminal", "fs.write", false)
    truthy(allowed.allowed, "administrator filesystem policy")
    local safe = Capabilities.policy("Administrator", "terminal", "fs.write", true)
    equal(safe.allowed, false, "Safe Mode blocks filesystem writes")
    equal(safe.reason, "Safe Mode blocks sensitive actions", "Safe Mode reason")
    local readOnly = Capabilities.policy("Observer", "monitor", "peripheral.read", true)
    truthy(readOnly.allowed, "Safe Mode preserves read-only inspection")
end)

test("normalizes peripheral metadata and radar contacts", function()
    local metadata = Peripherals.parseMetadata("schema|1\nalias|left|Main Radar\nblocked|right\ntrusted|left\n")
    truthy(metadata.aliases.left == "Main Radar", "alias parsed")
    local safeName = Peripherals.parseMetadata("alias|front|North\n").aliases.front
    truthy(safeName == "North", "metadata name preserves letters")
    truthy(metadata.blocked.right, "block marker parsed")
    truthy(metadata.trusted.left, "trusted marker parsed")
    local serialized = Peripherals.serializeMetadata(metadata)
    truthy(serialized:find("alias|left|Main Radar", 1, true) ~= nil, "alias serialized")
    local contacts = Peripherals.normalizeContacts({
        { id = "contact-1", timestamp = 8, position = { x = 1, y = 2, z = 3 }, confidence = 0.75 },
        { ambiguous = true },
    }, "radar-left", 10, 2)
    equal(#contacts, 2, "contact limit")
    equal(contacts[1].age, 2, "contact age")
    equal(contacts[1].identityStatus, "unverified", "unknown identity status")
    equal(contacts[2].identityStatus, "ambiguous", "ambiguous identity status")
    local adapters = Peripherals.adapterFor("create radar", { "getContacts" })
    equal(adapters[1].name, "create_radar", "radar adapter discovery")
    equal(adapters[1].contractVersion, 1, "adapter contract version")
    local contactsMany = {}
    for index = 1, 200 do contactsMany[index] = { id = tostring(index) } end
    equal(#Peripherals.normalizeContacts(contactsMany, "radar", 1, 32), 32, "contact output bound")
end)

test("normalizes infrastructure profiles and pulse limits", function()
    local data = Infrastructure.parse("schema|1\nprofile|alarm|Base Alarm|output|front|false|true|base|3|true|false\nprofile|input|Door Sensor|input|left|false|true|base|0|true|false\n")
    equal(#data.profiles, 2, "profile count")
    equal(data.profiles[1].id, "alarm", "profile id")
    equal(data.profiles[1].maxPulse, 3, "profile pulse limit")
    equal(data.profiles[1].blocked, false, "profile block marker")
    truthy(Infrastructure.zoneAllowed(data.profiles[1]), "local zone allowed")
    truthy(Infrastructure.canPulse(data.profiles[1], 2), "valid pulse")
    equal(Infrastructure.canPulse(data.profiles[1], 4), false, "profile pulse cap")
    equal(Infrastructure.canPulse(data.profiles[2], 1), false, "input cannot pulse")
    local serialized = Infrastructure.serialize(data)
    truthy(serialized:find("profile|alarm|Base Alarm", 1, true) ~= nil, "profile serialized")
end)

test("validates structured jobs and bounds execution helpers", function()
    local data = Jobs.parse("schema|1\njob|door|Door Watch|true|timer|10|infrastructure_toggle|door-a|toggle|5|1|3|false\njob|bad|Bad|true|lua|x|shell|x|toggle|0|99|99|false\n")
    equal(#data.jobs, 2, "job count")
    equal(data.jobs[1].trigger, "timer", "timer trigger")
    equal(data.jobs[2].trigger, "manual", "invalid trigger fallback")
    equal(data.jobs[2].action, "infrastructure_safe_state", "invalid action fallback")
    equal(Jobs.timerInterval(data.jobs[1]), 10, "timer interval")
    local side, value = Jobs.redstoneTrigger(Jobs.normalize({ trigger = "redstone", triggerValue = "front:on" }))
    equal(side, "front", "redstone side")
    equal(value, true, "redstone value")
    local allowed = Jobs.canRun(Jobs.normalize({ cooldown = 5 }), 10, 4)
    equal(allowed, true, "cooldown elapsed")
    local blocked = Jobs.canRun(Jobs.normalize({ cooldown = 5 }), 10, 8)
    equal(blocked, false, "cooldown active")
    local history = {}
    for index = 1, 60 do history = Jobs.addHistory(history, { id = "job", outcome = "success", at = index }) end
    equal(#history, Jobs.maxHistory, "history bound")
    local serialized = Jobs.serialize(data)
    truthy(serialized:find("job|door|Door Watch", 1, true) ~= nil, "job serialized")
end)

test("hit-tests shared button geometry", function()
    local buttons = {
        { x = 2, y = 3, width = 4, height = 1, label = "A" },
        { x = 8, y = 3, width = 4, height = 1, label = "B" },
    }
    truthy(Hit.inBounds(2, 3, 2, 3, 4, 1), "button origin")
    equal(Hit.inBounds(6, 3, 2, 3, 4, 1), false, "button right edge")
    local button = Hit.button(buttons, 9, 3)
    equal(button.label, "B", "shared button lookup")
end)

test("performs bounded calculator arithmetic", function()
    local state = Calculator.new()
    Calculator.inputDigit(state, "1")
    Calculator.inputDigit(state, "2")
    Calculator.operator(state, "+")
    Calculator.inputDigit(state, "3")
    Calculator.equals(state)
    equal(Calculator.display(state), "15", "addition")
    Calculator.operator(state, "/")
    Calculator.inputDigit(state, "0")
    Calculator.equals(state)
    equal(Calculator.display(state), "Error", "division by zero")
    Calculator.clear(state)
    Calculator.inputDigit(state, "9")
    Calculator.percent(state)
    equal(Calculator.display(state), "0.09", "percent")
    for index = 1, 20 do Calculator.inputDigit(state, "8") end
    truthy(#Calculator.display(state) <= 13, "display digit bound")
end)

test("retains newest log lines", function()
    local lines = Pure.retainLines({ "one", "two", "three" }, 2)
    equal(#lines, 2, "line count")
    equal(lines[1], "two", "first retained line")
    equal(lines[2], "three", "last retained line")
end)

test("clamps integer settings", function()
    equal(Pure.clampInteger("999", 50, 1000, 200), 1000, "upper clamp")
    equal(Pure.clampInteger("invalid", 50, 1000, 200), 200, "fallback")
end)

test("fits windows inside a terminal", function()
    local x, y, width, height = Pure.fitWindow(80, 24, 50, 18, 20, 8, 1)
    equal(width, 50, "window width")
    equal(height, 18, "window height")
    truthy(x >= 1 and y >= 1, "window origin")
end)

test("animates and completes numeric properties", function()
    local now = 0
    local manager = Animation.new(function() return now end)
    local target = { x = 0 }
    local completed = false
    manager:to(target, { x = 10 }, 1, "linear", nil, function() completed = true end)
    now = 0.5
    manager:update()
    equal(target.x, 5, "halfway animation")
    now = 1
    manager:update()
    equal(target.x, 10, "completed animation")
    truthy(completed, "completion callback")
end)

test("cancels animations for a target", function()
    local manager = Animation.new(function() return 0 end)
    local target = { x = 0 }
    manager:to(target, { x = 10 }, 1)
    manager:cancel(target)
    equal(manager:hasActive(), false, "animation cancellation")
end)

print("All " .. tostring(passed) .. " pure helper tests passed.")
