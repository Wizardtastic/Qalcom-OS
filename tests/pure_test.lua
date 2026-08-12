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
local function loadNetwork()
    local candidates = { "qalcom/lib/network.lua", "../qalcom/lib/network.lua", "/qalcom/lib/network.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/network.lua")
end

local Network = loadNetwork()
local function loadCrypto()
    local candidates = { "qalcom/lib/crypto.lua", "../qalcom/lib/crypto.lua", "/qalcom/lib/crypto.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/crypto.lua")
end

local Crypto = loadCrypto()
local function loadPeripherals()
    local candidates = { "qalcom/lib/peripherals.lua", "../qalcom/lib/peripherals.lua", "/qalcom/lib/peripherals.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/peripherals.lua")
end

local Peripherals = loadPeripherals()
local function loadTelemetry()
    local candidates = { "qalcom/lib/telemetry.lua", "../qalcom/lib/telemetry.lua", "/qalcom/lib/telemetry.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/telemetry.lua")
end

local Telemetry = loadTelemetry()
local function loadCannon()
    local candidates = { "qalcom/lib/cannon.lua", "../qalcom/lib/cannon.lua", "/qalcom/lib/cannon.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    fail("Unable to load qalcom/lib/cannon.lua")
end

local Cannon = loadCannon()
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
    equal(Roles.allows("Observer", "system.shutdown"), false, "observer shutdown")
    truthy(Pure.validateRole("Observer", Roles.names()), "valid role")
    equal(Pure.validateRole("Unknown", Roles.names()), false, "invalid role")
    truthy(Pure.validatePolicyDecision({ role = "Observer", capability = "fs.read", allowed = true }), "valid decision")
    local allowed = Capabilities.policy("Administrator", "terminal", "fs.write", false)
    truthy(allowed.allowed, "administrator filesystem policy")
    local safe = Capabilities.policy("Administrator", "terminal", "fs.write", true)
    equal(safe.allowed, false, "Safe Mode blocks filesystem writes")
    equal(safe.reason, "Safe Mode blocks sensitive actions", "Safe Mode reason")
    local readOnly = Capabilities.policy("Observer", "peripherals", "peripheral.read", true)
    truthy(readOnly.allowed, "Safe Mode preserves read-only inspection")
end)

test("validates bounded network envelopes and replay protection", function()
    local envelope = { protocol = "qalcom.v1", version = 1, source = "node-a", kind = "status_request", nonce = "n1", timestamp = 100, auth = "x" }
    truthy(Pure.validateNetworkEnvelope(envelope, 100, 30, 10), "valid envelope")
    equal(Pure.validateNetworkEnvelope(envelope, 140, 30, 10), false, "expired envelope")
    local replay = {}
    local first = Pure.replayAccept(replay, "node-a:n1", 100, 2, 30)
    truthy(first, "first replay token")
    equal(Pure.replayAccept(replay, "node-a:n1", 100, 2, 30), false, "duplicate replay token")
    truthy(Network.validateRequest({ request = "telemetry.snapshot" }, "status_request"), "read request allowlist")
    equal(Network.validateRequest({ request = "shell.run" }, "status_request"), false, "arbitrary request rejected")
    local config = Network.emptyConfig("node-a")
    local envelope = Network.createSecureEnvelope(config, "node-b", "status_request", { request = "telemetry.snapshot", requestId = "r1" }, "shared secret", 1, 100)
    local node = Network.normalizeNode({ id = "node-a", secret = "shared secret", state = "paired" })
    local replay = {}
    local payload = Network.openSecureEnvelope(envelope, "shared secret", config.protocol, 100, node, replay, "node-b")
    truthy(payload and payload.requestId == "r1", "secure envelope opens")
    equal(Network.openSecureEnvelope(envelope, "shared secret", config.protocol, 100, node, replay, "node-b"), nil, "secure replay rejected")
    envelope.tag = string.rep("00", 16)
    local altered = Network.openSecureEnvelope(envelope, "shared secret", config.protocol, 100, node, {}, "node-b")
    equal(altered, nil, "altered tag rejected")
    local state = { txCounter = 4, rxCounters = { ["node-a"] = { highWater = 7, seen = { [6] = true, [7] = true } } } }
    local restored = Network.parseState(Network.serializeState(state))
    equal(restored.rxCounters["node-a"].highWater, 7, "receive counter persists")
    truthy(restored.rxCounters["node-a"].seen[6], "receive window persists")
end)

test("hashes and authenticates with standard vectors", function()
    equal(Crypto.hex(Crypto.sha256("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty")
    equal(Crypto.hex(Crypto.sha256("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
    equal(Crypto.hex(Crypto.hmac("key", "The quick brown fox jumps over the lazy dog")), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", "hmac-sha256 vector")
    equal(#Crypto.hkdf("secret", "salt", "info", 48), 48, "hkdf length")
end)

test("seals, opens, and rejects tampered payloads", function()
    local function flipFirst(value)
        local first = string.byte(value, 1) or 0
        local changed = first == 0 and 1 or (first == 255 and 254 or first + 1)
        return string.char(changed) .. tostring(value):sub(2)
    end
    local ciphertext, tag = Crypto.seal("secret", "nonce-1", "attack at dawn", "context")
    equal(Crypto.open("secret", "nonce-1", ciphertext, tag, "context"), "attack at dawn", "seal/open round trip")
    equal(Crypto.open("secret", "nonce-1", ciphertext, tag, "other"), nil, "associated data mismatch rejected")
    equal(Crypto.open("secret", "nonce-2", ciphertext, tag, "context"), nil, "nonce mismatch rejected")
    equal(Crypto.open("other", "nonce-1", ciphertext, tag, "context"), nil, "key mismatch rejected")
    equal(Crypto.open("secret", "nonce-1", flipFirst(ciphertext), tag, "context"), nil, "ciphertext tamper rejected")
    equal(Crypto.open("secret", "nonce-1", ciphertext, flipFirst(tag), "context"), nil, "tag tamper rejected")
    local emptyCiphertext, emptyTag = Crypto.seal("secret", "nonce-3", "", "context")
    equal(Crypto.open("secret", "nonce-3", emptyCiphertext, emptyTag, "context"), "", "empty payload round trip")
    -- Larger payload exercises the streaming keystream and chunked XOR path.
    local big = string.rep("Qalcom optimization test ", 200)
    local bigCipher, bigTag = Crypto.seal("secret", "nonce-4", big, "context")
    equal(Crypto.open("secret", "nonce-4", bigCipher, bigTag, "context"), big, "large payload round trip")
    equal(Crypto.unhex(Crypto.hex(big)), big, "hex round trip")
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
    local cannonAdapters = Peripherals.adapterFor("cannon_mount", { "getInfo", "fire", "assemble", "setTargetAngles" })
    equal(cannonAdapters[1].name, "cbc", "CC:CBC adapter discovery")
    truthy(cannonAdapters[1].supportedReadOperations[1] == "cannon telemetry", "CC:CBC read contract")
    local contactsMany = {}
    for index = 1, 200 do contactsMany[index] = { id = tostring(index) } end
    equal(#Peripherals.normalizeContacts(contactsMany, "radar", 1, 32), 32, "contact output bound")

    local info = { computerControl = false, assembled = true, yaw = 90, pitch = 12, targetYaw = 95, targetPitch = 15, yawShaftSpeed = 8, pitchShaftSpeed = 4, x = 10, y = 64, z = -3 }
    local fake = {}
    function fake:peripheralNames() return { "front" } end
    function fake:peripheralType() return "cannon_mount" end
    function fake:peripheralMethods() return { "getInfo", "fire", "assemble", "setTargetAngles" } end
    local calls = {}
    function fake:peripheralRead(_, method)
        calls[#calls + 1] = method
        if method == "getInfo" then return info end
        return nil, "unexpected method"
    end
    local devices = Peripherals.inspect(fake, Peripherals.emptyMetadata(), 20)
    equal(#calls, 1, "CC:CBC only probes getInfo")
    equal(calls[1], "getInfo", "CC:CBC control methods are not called")
    equal(#devices, 1, "CC:CBC device inspected")
    truthy(devices[1].cbcInfo and devices[1].cbcInfo.assembled, "CC:CBC info bounded")
    local records = Telemetry.snapshot(fake, devices, 20)
    equal(records[1].kind, "cbc", "CC:CBC telemetry kind")
    equal(records[1].data.yaw, 90, "CC:CBC yaw")
    truthy(records[1].data.ammunition:find("unknown", 1, true) ~= nil, "CC:CBC ammunition remains unknown")
    truthy(records[1].data.firingReadiness:find("unknown", 1, true) ~= nil, "CC:CBC readiness remains unknown")
end)

test("plans bounded CBC cannon targets", function()
    local target = Cannon.target(10, 70, 10)
    truthy(target, "coordinate target")
    local angles = Cannon.anglesFromPosition({ x = 0, y = 64, z = 0 }, target, {})
    equal(math.floor(angles.yaw + 0.5), 45, "coordinate yaw")
    truthy(angles.pitch > 0, "coordinate pitch")
    local contactTarget = Cannon.targetFromContact({ position = { x = 10, y = 70, z = 10 }, identityStatus = "claimed", age = 1 })
    equal(contactTarget.z, 10, "radar target")
    truthy(Cannon.targetFromContact({ position = { x = 1, y = 2, z = 3 }, identityStatus = "unverified", age = 1 }), "fresh unverified radar position accepted")
    equal(Cannon.targetFromContact({ position = { x = 1, y = 2, z = 3 }, identityStatus = "ambiguous", age = 1 }), nil, "ambiguous radar target rejected")
    equal(Cannon.targetFromContact({ position = { x = 1, y = 2, z = 3 }, identityStatus = "claimed", age = 11 }), nil, "stale radar target rejected")
    local plan = Cannon.plan({ { name = "front", cbcInfo = { x = 0, y = 64, z = 0 } } }, target, {})
    equal(#plan.entries, 1, "cannon plan")
    truthy(Cannon.aligned({ yaw = angles.yaw, pitch = angles.pitch }, angles, 1), "alignment")
    equal(Cannon.target("bad", 1, 1), nil, "invalid coordinates rejected")
    equal(Cannon.target(1, nil, 3), nil, "incomplete coordinates rejected")
    local invalid = Cannon.settings({ pulse = 99, tolerance = -1 })
    equal(invalid.pulse, 1, "pulse upper bound")
    equal(invalid.tolerance, 0.1, "tolerance lower bound")
end)

test("validates CBC control argument contracts", function()
    local Managed = nil
    local candidates = { "qalcom/lib/managed.lua", "../qalcom/lib/managed.lua", "/qalcom/lib/managed.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then Managed = module; break end
    end
    truthy(Managed, "managed helper loaded")
    local calls = {}
    local fake = {
        hasCapability = function() return true end,
        peripheralType = function() return "cannon_mount" end,
        peripheralMethods = function() return { "fire", "setTargetAngles" } end,
        audit = function() end,
    }
    local oldPeripheral = peripheral
    peripheral = {
        getType = function() return "cannon_mount" end,
        getMethods = function() return { "fire", "setTargetAngles" } end,
        wrap = function()
            return {
                fire = function(value) calls[#calls + 1] = { "fire", value } end,
                setTargetAngles = function(yaw, pitch) calls[#calls + 1] = { "setTargetAngles", yaw, pitch } end,
            }
        end,
    }
    truthy(Managed.cannonControl(fake, "front", "fire", true), "valid fire control")
    equal(Managed.cannonControl(fake, "front", "fire", "true"), false, "boolean contract")
    equal(Managed.cannonControl(fake, "front", "setTargetAngles", 1), false, "angle count contract")
    equal(Managed.cannonControl(fake, "front", "setTargetAngles", 1, 2, 3), false, "extra angle rejected")
    equal(Managed.cannonControl(fake, "front", "setTargetAngles", 999, 0), false, "angle range contract")
    equal(#calls, 1, "invalid controls are not invoked")
    peripheral = oldPeripheral
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

test("converts palette hex to color channels", function()
    local function approx(actual, expected, label)
        if math.abs(actual - expected) > 0.0001 then
            fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        end
    end
    local r, g, b = Pure.colorChannels(0xFFFFFF)
    approx(r, 1, "white r"); approx(g, 1, "white g"); approx(b, 1, "white b")
    r, g, b = Pure.colorChannels(0x000000)
    approx(r, 0, "black r"); approx(g, 0, "black g"); approx(b, 0, "black b")
    r, g, b = Pure.colorChannels(0x4CC2FF)
    approx(r, 76 / 255, "accent r"); approx(g, 194 / 255, "accent g"); approx(b, 1, "accent b")
    r = Pure.colorChannels(nil)
    approx(r, 0, "nil defaults to zero")
    r, g, b = Pure.colorChannels(0x1FF0000)
    approx(r, 1, "overflow wraps to 24-bit")
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
