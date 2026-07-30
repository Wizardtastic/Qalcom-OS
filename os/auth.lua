-- os/auth.lua — user account manager.
-- Persists hashed user creds to /users/<name>.lua.  Default admin is seeded on
-- first boot if no users/ directory exists yet.

local fsutil = require("os.fsutil")
local cfg    = require("os.config")

local M = {}
M.users = {}      -- in-memory cache name -> {passHash, salt, role, ...}
M.path  = cfg.paths.users

local function ensureDir()
    if not fs.exists(M.path) then
        fs.makeDir(M.path)
        -- Make parent(s) too
        M.path:gsub("([^/]+)/?$", function(seg)
            -- not used, fs.makeDir creates intermediates in CC:T
        end)
    end
end

-- Generate a 16-byte hex salt.
local function newSalt()
    local s = ""
    for i = 1, 16 do
        local r = math.random(0, 255)
        s = s .. string.format("%02x", r)
    end
    return s
end

-- SHA-256 primitive since ComputerCraft doesn't expose FNV-1a.
-- We delegate to crypto if present, otherwise use a basic BobJenkins-ish
-- 64-bit mixer that is plenty for stand-alone sandboxes (no real attackers).
local function tryCrypto()
    -- Prefer CC:T's http crypto via OpenCCSensors?  None provided; instead use
    -- Lua's bit32 (always available in CC:T) to craft an FNV-1a + extra
    -- rounds so it's not trivially reversible.
    return nil
end
local function mixOnce(h, input)
    if type(input) ~= "string" then input = tostring(input) end
    -- FNV-1a 32-bit over the string, packed into a long string "hash".
    local FNV_OFFSET = 2166136261
    local FNV_PRIME  = 16777619
    for i = 1, #input do
        h = bit32.bxor(h, input:byte(i))
        h = (h * FNV_PRIME) % 2^32
    end
    return h
end
local function hash(password, salt)
    local h1 = mixOnce(2166136261, salt or "")
    local h2 = mixOnce(5381, password or "")
    -- Mix h1 and h2 then run 256 rounds to slow brute force a bit.
    for i = 1, 256 do
        h1 = bit32.bxor(h1, h2)
        h1 = (h1 * 16777619) % 2^32
        h1 = bit32.bxor(h1, bit32.lrotate(h2, i % 31))
        h1 = (h1 * 2246822507) % 2^32
        h2 = bit32.bxor(h2, h1)
        h2 = (h2 * 2654435761) % 2^32
    end
    return string.pack("<I4I4", h1, h2)
end

function M.hash(pwd, salt) return hash(pwd, salt) end

-- Persist the in-memory users table to /users/<name>.lua files.
local function persist(name)
    local u = M.users[name] or {}
    local body = "return " .. fsutil.serialize(u) .. "\n"
    fsutil.write(M.path .. "/" .. name .. ".lua", body)
end

-- Load a single user file.
local function loadUser(name)
    local p = M.path .. "/" .. name .. ".lua"
    if not fs.exists(p) then return nil end
    local fn, err = loadfile(p)
    if not fn then return nil end
    local ok, u = pcall(fn)
    if not ok or type(u) ~= "table" then return nil end
    return u
end

function M.reload()
    M.users = {}
    if not fs.exists(M.path) then return end
    for _, file in ipairs(fs.list(M.path)) do
        local name = file:gsub("%.lua$", "")
        local u = loadUser(name)
        if u then M.users[name] = u end
    end
end

function M.list()
    local names = {}
    for k in pairs(M.users) do names[#names+1] = k end
    table.sort(names)
    return names
end

function M.exists(name) return M.users[name] ~= nil end

function M.add(name, password, role)
    role = role or "user"
    M.users[name] = {
        passHash = hash(password, ""),
        salt     = "",
        role     = role,
        created  = os.epoch and os.epoch("utc") or 0,
    }
    -- Persist with proper salt derivation
    local salt = newSalt()
    M.users[name].salt     = salt
    M.users[name].passHash = hash(password, salt)
    persist(name)
    return true
end

function M.delete(name)
    M.users[name] = nil
    local p = M.path .. "/" .. name .. ".lua"
    if fs.exists(p) then fs.delete(p) end
end

-- Verify a (user, password) pair. Returns true on success.
function M.verify(name, password)
    local u = M.users[name]
    if not u then return false end
    local attempt = hash(password or "", u.salt or "")
    return attempt == u.passHash
end

-- Change a user's password (requires the current one to be known).
function M.changePassword(name, oldPwd, newPwd)
    if not M.verify(name, oldPwd) then return false end
    local salt = newSalt()
    M.users[name].salt     = salt
    M.users[name].passHash = hash(newPwd, salt)
    persist(name)
    return true
end

-- Seed default admin on first boot.  Returns the auto-generated password
-- (typically we boot straight to login so this isn't visible).
function M.bootstrap()
    ensureDir()
    M.reload()
    if not M.users[cfg.security.defaultUser] then
        local default_name = cfg.security.defaultUser
        -- Default password is the same as username (commonly used;
        -- user can change it after first login).
        M.add(default_name, default_name, "admin")
        return true
    end
    return false
end

-- Pretty account summary (used by /os/apps/about.lua)
function M.summary()
    local lines = { "Qalcom OS — User accounts" }
    lines[#lines+1] = ""
    for _, name in ipairs(M.list()) do
        local u = M.users[name]
        lines[#lines+1] = string.format(
            "%s   role=%s   created=%s",
            name,
            u.role or "user",
            u.created and os.date("%Y-%m-%d %H:%M", u.created/1000) or "?")
    end
    return lines
end

return M
