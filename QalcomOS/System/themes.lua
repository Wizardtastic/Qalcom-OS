--[[
  QalcomOS.System.themes - shared theme palette table (v0.6)

  Both Login and the System app dofile this module so the three
  palettes (Default / Dark / Retro) live in exactly one place. A future
  4th theme would change only this file.

  The module also owns the .theme file IO:
      /QalcomOS/.theme:    one line, "theme_idx=N" with N in {1, 2, 3}.

  Both Login (on spawn) and the System app (on SAVE) speak this format.
  fs.* calls tolerate the offline test harness where fs.open returns
  nil -- in that case load() falls back to 1 (Default) and save()
  is a silent no-op, which is the right behaviour for hosts that have
  no writable fs under /QalcomOS/.

  A future commit moves the file to /QalcomOS/Users/<name>/.theme
  once the OS has a "current user" concept; until then, the global
  /QalcomOS/.theme stands in as the boot-time default that's also
  shared across users.
]]

local M = {}

M.FILE = "/QalcomOS/.theme"

-- Each entry has both the rendering fields Login uses and `swatch_fg`
-- which only System uses; both readers pick what they need.
M.themes = {
  {  -- 1: Default
    name              = "Default",
    bg                = colors.black,
    panel             = colors.lightBlue,
    panelX            = colors.gray,
    text              = colors.white,
    textDim           = colors.lightGray,
    accent            = colors.yellow,
    field             = colors.white,
    fieldText         = colors.black,
    button_ok_bg      = colors.lime,
    button_ok_fg      = colors.black,
    button_dis_bg     = colors.gray,
    button_dis_fg     = colors.white,
    swatch_fg         = colors.white,
  },
  {  -- 2: Dark
    name              = "Dark",
    bg                = colors.black,
    panel             = colors.purple,
    panelX            = colors.black,
    text              = colors.lightGray,
    textDim           = colors.gray,
    accent            = colors.magenta,
    field             = colors.gray,
    fieldText         = colors.white,
    button_ok_bg      = colors.magenta,
    button_ok_fg      = colors.white,
    button_dis_bg     = colors.gray,
    button_dis_fg     = colors.lightGray,
    swatch_fg         = colors.lightGray,
  },
  {  -- 3: Retro
    name              = "Retro",
    bg                = colors.black,
    panel             = colors.orange,
    panelX            = colors.brown,
    text              = colors.yellow,
    textDim           = colors.brown,
    accent            = colors.white,
    field             = colors.brown,
    fieldText         = colors.yellow,
    button_ok_bg      = colors.yellow,
    button_ok_fg      = colors.black,
    button_dis_bg     = colors.brown,
    button_dis_fg     = colors.white,
    swatch_fg         = colors.white,
  },
}

-- Clamp a candidate to the validated palette index range.
function M.normalize(idx)
  idx = tonumber(idx)
  if idx and idx >= 1 and idx <= #M.themes then return math.floor(idx) end
  return 1
end

-- Write the chosen theme index. Silent no-op if the host can't open
-- the file (e.g. read-only disk or the offline harness).
function M.save(idx)
  idx = M.normalize(idx)
  if not fs or not fs.open then return false end
  local f = fs.open(M.FILE, "w")
  if not f then return false end
  f.write(string.format("theme_idx=%d\n", idx))
  f.close()
  return true
end

-- Read the persisted theme index. Returns 1 if anything is missing
-- or unparseable so the OS still boots with a sensible default.
--
-- Lines may carry a `# comment` tail; strip those first so a hand
-- edit like `theme_idx=2 # picked dark` still parses as 2. Lines
-- that don't match the theme_idx= form are skipped; if no theme_idx
-- entry is found at all, default to 1.
function M.load()
  if not fs or not fs.open or not fs.exists then return 1 end
  if not fs.exists(M.FILE) then return 1 end
  local f = fs.open(M.FILE, "r")
  if not f then return 1 end
  for raw in f.readLine do
    local line = raw:gsub("#.*$", "")
    local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
    if k == "theme_idx" then
      f.close()
      return M.normalize(v)
    end
  end
  f.close()
  return 1
end

return M
