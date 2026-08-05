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

print("All " .. tostring(passed) .. " pure helper tests passed.")
