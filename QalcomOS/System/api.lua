--[[
  QalcomOS.System.api
  Shared low-level utilities used by the boot, kernel, and window manager.

  This module provides:
    * M.version        - the OS version string
    * M.paths          - canonical paths used across the system
    * M.applyPalette   - apply the QalcomOS color theme to a terminal
    * M.drawWallpaper  - fill a terminal with the OS wallpaper pattern
    * lineData         - robust getLine() reader (handles both 1.120.x
                         multi-return API and the legacy table shape)
    * M.presentMaster  - blit a back-buffer (the master window) onto the
                        underlying screen terminal
    * M.blitWindow     - blit a child window onto a parent terminal
]]

local M = {}

M.version  = "0.4.0"
M.codename = "Genesis II"

M.paths = {
  root       = "/QalcomOS",
  system     = "/QalcomOS/System",
  apps       = "/QalcomOS/Apps",
  resources  = "/QalcomOS/Resources",
  wallpaper  = "/QalcomOS/Resources/Wallpapers",
  fonts      = "/QalcomOS/Resources/Fonts",
}

-- Theme colors. We DO NOT mutate the global CraftOS palette in v0.1; we
-- rely on the 16 default colors and use color names a lot so higher-level
-- code stays readable. A future version will setPaletteColour().
M.theme = {
  bg       = colors.cyan,        -- desktop background
  panel    = colors.lightBlue,   -- focused window title
  panelX   = colors.gray,        -- unfocused window title
  text     = colors.white,
  textDim  = colors.lightGray,
  accent   = colors.yellow,
  error    = colors.red,
  border   = colors.black,
}

-- Apply a (minor) theme. Currently a no-op; here for forward-compat so
-- later versions can change the 16 palette entries without touching callers.
function M.applyPalette(t)
  -- Kept intentionally simple for v0.1.
  return t
end

-- Robust getLine() reader that normalises both wire shapes CC uses:
--
--   Legacy (older Forge with Lua 5.1): returns a TABLE
--       { text_string, fg_string, bg_string }
--       so pulled[1] is the text.
--
--   Modern (CC:Tweaked 1.109+ on Cobalt Lua 5.2/5.3): returns three
--       POSITIONAL strings -- "string, string, string" -- so
--       (a, b, c) = term.getLine() gives text=a, fg=b, bg=c.
--
-- Tolerant helper for both. Returns (text, fg, bg) all of equal length
-- or (nil) if the line has no drawable content.
local function lineData(t, line)
  local a, b, c = t.getLine(line)
  if a == nil then return nil end

  -- Legacy table form: a is a table indexed [1]/[2]/[3].
  if type(a) == "table" then
    local tx, fg, bg = a[1], a[2], a[3]
    if type(tx) ~= "string" or #tx == 0 then return nil end
    if type(fg) ~= "string" then fg = nil end
    if type(bg) ~= "string" then bg = nil end
    return tx, fg, bg
  end

  -- Modern positional form: a, b, c are strings already.
  if type(a) ~= "string" then return nil end
  return a, b, c
end

-- Pad fg/bg strings so they're the same length as text. CC's blit
-- rejects mismatched-length strings with a hard error.
local function padColors(text, fg, bg)
  local n = #text
  fg = fg or ""
  bg = bg or ""
  if #fg < n then fg = fg .. string.rep("f", n - #fg) end  -- default fg = white
  if #bg < n then bg = bg .. string.rep("0", n - #bg) end  -- default bg = black
  if #fg > n then fg = fg:sub(1, n) end
  if #bg > n then bg = bg:sub(1, n) end
  return text, fg, bg
end

-- Composed reader used by blitters: returns (text, fg, bg) ready for
-- oTerm.blit(), or nil if the line should be skipped.
local function readLine(t, line)
  local text, fg, bg = lineData(t, line)
  if not text or #text == 0 then return nil end
  return padColors(text, fg, bg)
end

-- Public export of the line reader so callers (e.g. WM title bars) can
-- use the same defensive path.
M.readLine = readLine

-- Paint the wallpaper on a given terminal / window. v0.1 is intentionally
-- minimal: a flat colour field with a centered brand caption. A future
-- version can layer NFT/NFP art here.
function M.drawWallpaper(t)
  local w, h = t.getSize()
  t.setBackgroundColor(M.theme.bg)
  t.setTextColor(M.theme.textDim)
  t.clear()
  -- Centered branding text.
  local label = "Qalcom OS " .. M.version .. " \"" .. M.codename .. "\""
  if #label < w then
    t.setCursorPos(math.floor((w - #label) / 2) + 1, math.floor(h / 2))
    t.setTextColor(M.theme.accent)
    t.write(label)
  end
  -- Subtle band along the bottom so the user's eye learns to expect the
  -- taskbar there once we ship one.
  if h >= 3 then
    t.setCursorPos(1, h)
    t.setBackgroundColor(M.theme.panelX)
    t.setTextColor(M.theme.text)
    t.write(string.rep(" ", w))
  end
  -- Restore both colours to the wallpaper defaults so any later draw on
  -- this terminal sees predictable state.
  t.setBackgroundColor(M.theme.bg)
  -- Choose an fg that contrasts with bg to avoid invisible subsequent
  -- writes on the wallpaper.
  if M.theme.bg == colors.black then
    t.setTextColor(M.theme.text)
  else
    t.setTextColor(colors.white)
  end
  t.setCursorPos(1, 1)
end

-- Blit a back-buffer (the master window) onto the real screen terminal.
-- Preserves the real terminal's cursor position and blink state so the
-- compositor doesn't flicker or jump. Tolerates empty/uninitialised
-- lines by writing a fallback solid colour.
function M.presentMaster(master, oTerm)
  local cur_x, cur_y = oTerm.getCursorPos()
  local curBlink     = oTerm.getCursorBlink()
  oTerm.setCursorBlink(false)
  local w, h         = oTerm.getSize()
  oTerm.setBackgroundColor(colors.black)
  oTerm.setTextColor(colors.white)

  for line = 1, h do
    local text, fg, bg = readLine(master, line)
    if text then
      oTerm.setCursorPos(1, line)
      oTerm.blit(text, fg, bg)
    else
      -- Uninitialised line: paint a black 'space' fallback so the
      -- compositor never leaves a hole on the screen.
      oTerm.setCursorPos(1, line)
      oTerm.setBackgroundColor(colors.black)
      oTerm.write(string.rep(" ", w))
    end
  end

  oTerm.setCursorPos(cur_x, cur_y)
  oTerm.setCursorBlink(curBlink)
end

-- Blit a child window onto a parent terminal / window at (x, y). Used by
-- the window manager during the composite pass. Tolerates empty lines.
function M.blitWindow(src, dst, x, y)
  local w, h = src.getSize()
  local cx, cy = dst.getCursorPos()
  local blink = dst.getCursorBlink()
  dst.setCursorBlink(false)

  for line = 1, h do
    local text, fg, bg = readLine(src, line)
    if text then
      dst.setCursorPos(x, y + line - 1)
      dst.blit(text, fg, bg)
    end
  end

  dst.setCursorBlink(blink)
  dst.setCursorPos(cx, cy)
end

return M
