--[[
  QalcomOS.System.profile - per-user profile reader + auth helper (v0.6)

  The Login app authenticates against /QalcomOS/Users/<name>/.profile.
  The file is a plain key=value document:

      # Comments allowed.
      passwd=<sha1-or-plaintext>   -- 40 hex chars if sha1, else plaintext
      theme_idx=N                  -- 1..3 (Default / Dark / Retro)
      avatar=smiley|hat|wizard|cube

  Both Login and any future System v2 / Desktop read/write fields via
  this module so the file format and the auth primitive live in one
  place. Unit-testable without driving the Login event loop end-to-end.
]]

local M = {}

M.PATH            = function(name)
  return "/QalcomOS/Users/" .. name .. "/.profile"
end
M.CURRENT_USER_PATH = "/QalcomOS/.current_user"

-- Names must be 1..16 chars, alphanumeric/underscore/dash. Mirrors
-- the safety check Login previously inlined for avatar lookup.
local function isSafeUsername(name)
  return type(name) == "string" and #name > 0 and #name <= 16
     and name:match("^[%w_%-]+$") ~= nil
end
M.isSafeUsername = isSafeUsername

-- Parse a profile body string into a key-value table. Lines may have
-- leading/trailing whitespace and a `# comment` tail; both are
-- stripped before parsing. Empty lines and lines without `=` are
-- silently skipped.
local function parse(content)
  local out = {}
  if type(content) ~= "string" then return out end
  for raw in content:gmatch("[^\r\n]+") do
    local line = raw:gsub("#.*$", "")
    local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
    if k and v and #k > 0 then out[k] = v end
  end
  return out
end
M.parse = parse

-- Read /QalcomOS/Users/<name>/.profile. Returns nil if the name is
-- unsafe, the file is missing, or fs.* is unavailable (e.g. the
-- offline harness with no writeable disk).
function M.read(name)
  if not isSafeUsername(name) then return nil end
  if not fs or not fs.exists then return nil end
  local path = M.PATH(name)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local lines = {}
  for raw in f.readLine do lines[#lines + 1] = raw end
  f.close()
  return parse(table.concat(lines, "\n"))
end

-- Persist the active username to /QalcomOS/.current_user so future
-- System/Desktop revisions can consult it without prompting again.
-- Silent on read-only hosts (return value intentionally unused).
function M.writeCurrentUser(name)
  if not isSafeUsername(name) then return end
  if not fs or not fs.open then return end
  local f = fs.open(M.CURRENT_USER_PATH, "w")
  if not f then return end
  f.write(name .. "\n")
  f.close()
end

-- Compute SHA-1 hex of `s` if the host has the bundled sha1 module.
-- Returns nil otherwise so the caller can fail-closed on hashes it
-- can't verify.
local function sha1Hex(s)
  local ok, lib = pcall(require, "sha1")
  if ok and lib and lib.hash then return lib.hash(s) end
  return nil
end

-- Compare a supplied password against the stored value. Stored can
-- be 40 hex chars (compare against SHA-1 of supplied, if available)
-- or anything else (plaintext equality). Returns false on empty
-- supplied or stored, on missing sha1 module when a hash is required,
-- or on any mismatch.
function M.authenticate(supplied, stored)
  if not supplied or not stored or stored == "" then return false end
  if #stored == 40 and stored:match("^%x+$") then
    local hash = sha1Hex(supplied)
    if not hash then return false end
    return hash:lower() == stored:lower()
  end
  return supplied == stored
end

-- Resolve the integer theme_idx from a profile, clamped to {1, 2, 3}.
-- Returns `fallback` when the profile is missing, has no theme_idx,
-- or has an unparseable / out-of-range value.
function M.themeIdx(profile, fallback)
  fallback = fallback or 1
  if type(profile) ~= "table" then return fallback end
  local n = tonumber(profile.theme_idx)
  if not n or n < 1 or n > 3 then return fallback end
  return math.floor(n)
end

-- Avatar names -> 1-based index into Login's AVATARS table.
M.AVATAR_INDEX = {
  smiley = 1,
  hat    = 2,
  wizard = 3,
  cube   = 4,
}

return M
