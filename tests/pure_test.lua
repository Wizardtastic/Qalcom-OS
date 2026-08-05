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
