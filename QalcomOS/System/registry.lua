--[[
  QalcomOS.System.registry - Launcher manifest scanner (v0.2)

  Reads .qalcom files from /QalcomOS/Apps/ (top-level) and returns a
  list of app descriptors used by the desktop's icon picker and Start
  menu.

  Manifest format -- plain key=value text, # comments allowed:
    # Hello.qalcom
    name=Hello
    title=Hello
    icon=Hi
    path=/QalcomOS/Apps/Hello/main.lua
    window_w=28
    window_h=12

  Required fields: name, path
  Optional fields: title (= name if missing), icon (= "?" if missing),
                   window_w (= 28), window_h (= 12)
]]

local M = {}

local APPS_DIR = "/QalcomOS/Apps"

-- Trim leading/trailing whitespace from a string.
local function trim(s)
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Parse one .qalcom file. Returns a descriptor table or nil on error.
function M.parse(filepath)
  if not fs.exists(filepath) then return nil end
  local f, ferr = fs.open(filepath, "r")
  if not f then return nil, ferr end

  local desc = {
    name      = nil,
    title     = nil,
    icon      = nil,
    path      = nil,
    window_w  = 28,
    window_h  = 12,
    trusted   = false,
  }

  for line in f.readLine do
    local stripped = trim(line or "")
    if stripped == "" or stripped:sub(1, 1) == "#" then
      -- skip blank / comment
    else
      local eq = stripped:find("=", 1, true)
      if eq then
        local key   = trim(stripped:sub(1, eq - 1))
        local value = trim(stripped:sub(eq + 1))
        if key == "window_w" or key == "window_h" then
          desc[key] = tonumber(value) or desc[key]
        elseif key == "trusted" then
          -- Case-insensitive: "true", "True", "TRUE", "1" all opt in.
          -- Keeps hand-edited .qalcom files forgiving.
          local lower = (type(value) == "string") and value:lower() or ""
          desc[key] = (lower == "true" or value == "1")
        else
          desc[key] = value
        end
      end
    end
  end
  f.close()

  -- Defaults.
  if not desc.name or not desc.path then return nil end
  desc.title = desc.title or desc.name
  desc.icon  = desc.icon  or "?"

  return desc
end

-- Scan APPS_DIR for *.qalcom files and return all valid descriptors.
function M.scan()
  local out = {}
  if not fs.exists(APPS_DIR) then return out end
  if not fs.isDir(APPS_DIR) then return out end

  for _, name in ipairs(fs.list(APPS_DIR)) do
    -- Only top-level .qalcom files. Subdirectories containing apps are
    -- discovered via the path= field, not directly.
    if name:sub(-7) == ".qalcom" then
      local filepath = APPS_DIR .. "/" .. name
      local desc, err = M.parse(filepath)
      if desc then
        out[#out + 1] = desc
      end
      -- Errors are non-fatal; we just skip unreadable manifests.
    end
  end

  -- Stable sort by name so the Start menu / icons render in alpha order.
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Directly fetch one descriptor by name, or nil.
function M.byName(name)
  for _, d in ipairs(M.scan()) do
    if d.name == name then return d end
  end
  return nil
end

return M
