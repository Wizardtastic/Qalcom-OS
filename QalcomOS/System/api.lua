--[[
  QalcomOS.System.api - Shared low-level utilities (v1.0 CC: Graphics)

  This module provides:
    * M.version / M.codename
    * M.paths          - canonical system paths
    * M.theme          - 24-bit colour-rich theme table
    * M.gpu            - reference to the GPU module
    * M.fb             - the screen framebuffer (set by boot)
    * Drawing helpers  - wallpapers, blit compositing
    * Colour utilities - hex24 conversion, palette helpers

  This revision integrates the GPU framebuffer module (gpu.lua)
  and provides a richer colour model: each theme entry can be a
  palette index (0..15) or a 24-bit hex string like "#4D8CE6"
  that gets resolved to the nearest palette entry at init time.
]]--

local M = {}

M.version  = "1.0.0"
M.codename = "Graphics"

M.paths = {
  root       = "/QalcomOS",
  system     = "/QalcomOS/System",
  apps       = "/QalcomOS/Apps",
  resources  = "/QalcomOS/Resources",
  wallpaper  = "/QalcomOS/Resources/Wallpapers",
  fonts      = "/QalcomOS/Resources/Fonts",
}

-- GPU module reference (lazy-loaded; set by boot via M.initGPU()).
M.gpu = nil
M.fb  = nil
M.isGPUReady = false

function M.initGPU()
  M.gpu = dofile("/QalcomOS/System/gpu.lua")
  M.gpu.init()
  M.isGPUReady = true
  -- Re-resolve theme colours now that the GPU palette is available.
  -- Without this call, themeResolved would have been computed at module
  -- load time (before GPU init) and would default all colours to index 0.
  M.refreshTheme()
end

-- Resolve a colour value to a palette index (0..15).
-- Accepts: palette index (number), colour constant (colors.*),
--          24-bit hex string ("#RRGGBB"), or nil (defaults to 0/white).
function M.resolveColour(c, default)
  default = default or 0
  if c == nil then return default end
  if type(c) == "number" then
    if c < 16 then return math.floor(c) end  -- already an index
    -- colour constant (power of 2) -> convert via GPU
    if M.gpu and M.gpu.COLOUR_TO_IDX then
      local idx = M.gpu.COLOUR_TO_IDX[c]
      if idx then return idx end
    end
    -- Fallback: log2(colour) + 1
    local idx = 0
    local cc = c
    while cc > 1 do cc = cc / 2; idx = idx + 1 end
    return math.min(15, idx)
  end
  if type(c) == "string" and #c > 0 then
    if M.gpu then return M.gpu.hex24ToIdx(c) end
    return default
  end
  return default
end

-- Convert a colour value to a hex digit for blit strings.
function M.colourToHex(c)
  local idx = M.resolveColour(c, 0)
  return string.format("%x", idx)
end

-- Parse a 24-bit hex colour (#RRGGBB) to an RGB table {r, g, b}.
function M.parseHex24(hex)
  if type(hex) ~= "string" then return { r = 0, g = 0, b = 0 } end
  local s = hex:gsub("#", "")
  if #s ~= 6 then return { r = 0, g = 0, b = 0 } end
  return {
    r = tonumber(s:sub(1, 2), 16) / 255,
    g = tonumber(s:sub(3, 4), 16) / 255,
    b = tonumber(s:sub(5, 6), 16) / 255,
  }
end

-- Format an RGB table or three floats as a hex string.
function M.formatHex24(r, g, b)
  if type(r) == "table" then
    r, g, b = r.r, r.g, r.b
  end
  r = math.floor((r or 0) * 255 + 0.5)
  g = math.floor((g or 0) * 255 + 0.5)
  b = math.floor((b or 0) * 255 + 0.5)
  return string.format("#%02X%02X%02X", r, g, b)
end

-- Theme colours. Each value can be:
--   * A palette index (0..15) for direct CC colours
--   * A 24-bit hex string "#RRGGBB" for extended colours
--     (resolved to nearest palette entry at init time)
--   * A colour constant (colors.white, etc.)
M.theme = {
  name      = "Qalcom Graphics",

  -- Desktop
  bg        = 9,                -- cyan
  bgAlt     = "#1A3A5C",       -- deep blue for wallpaper gradient
  accent    = 4,                -- yellow
  accent2   = "#FF6B35",       -- warm orange accent

  -- Text
  text      = 0,                -- white
  textDim   = 7,                -- gray
  textDark  = 15,               -- black

  -- Panels / Windows
  panel     = 3,                -- lightBlue (focused title)
  panelX    = 7,                -- gray (unfocused title)
  panelBg   = "#F0F4FF",       -- very light blue for window body

  -- Controls
  buttonBg  = "#4D8CE6",       -- blue button
  buttonFg  = 0,                -- white text
  buttonHov = "#6BA3F0",       -- hover blue
  field     = 0,                -- white field
  fieldText = 15,               -- black text

  -- Status
  okText    = 5,                -- lime
  error     = 14,               -- red
  warning   = "#FFA500",       -- orange

  -- Shadow
  shadow    = "#1A1A2E",       -- dark shadow for depth

  -- Borders
  border    = "#2D3748",       -- dark border
  borderDim = "#CBD5E0",       -- light border

  -- Taskbar
  taskbarBg = "#1A202C",       -- dark taskbar
  taskbarFg = 0,                -- white
  trayBg    = "#2D3748",       -- slightly lighter
  trayHovBg = "#4A5568",

  -- Start Menu
  menuBg    = "#2B6CB0",       -- blue
  menuFg    = 0,
  menuHovBg = "#3182CE",

  -- Notifications
  notifBg   = "#1A202C",
  notifTitle = "#4D8CE6",
}

-- Resolve all theme colour values to palette indices (0..15) and
-- store both the index and the 24-bit hex form.
function M.resolveTheme(t)
  t = t or M.theme
  local resolved = {}
  for k, v in pairs(t) do
    if type(v) == "string" and v:sub(1, 1) == "#" then
      -- Store the index and hex.
      local idx = M.resolveColour(v, 0)
      resolved[k] = idx
      resolved[k .. "_hex"] = v
    elseif type(v) == "number" or type(v) == "string" then
      resolved[k] = M.resolveColour(v, 0)
    else
      resolved[k] = v
    end
  end
  return resolved
end

-- Resolve the theme in-place.
M.themeResolved = nil
function M.refreshTheme()
  M.themeResolved = M.resolveTheme(M.theme)
end

-- Initialise the theme resolution.
M.refreshTheme()

-- Apply the resolved theme colours to the terminal via GPU palette.
function M.applyThemePalette(target, themeName)
  local gpu = M.gpu
  if not gpu then return end
  themeName = themeName or "default"
  gpu.applyNamedPalette(target, themeName)
end

-- ---------------------------------------------------------------------------
-- Drawing helpers using the GPU framebuffer
-- ---------------------------------------------------------------------------

-- Paint the wallpaper onto the given framebuffer.
function M.drawWallpaperFB(fb, w, h)
  local T = M.themeResolved or M.theme

  -- Gradient background: top = accent, bottom = bg.
  fb:gradientFill(1, 1, w, h, T.bgAlt or T.bg, T.bg, 0)
  fb:markDirty()
end

-- Draw a branded wallpaper layer on framebuffer.
function M.drawBrandedWallpaper(fb, w, h)
  local T = M.themeResolved or M.theme

  -- Base gradient.
  M.drawWallpaperFB(fb, w, h)

  -- Centered brand text.
  local label = "Qalcom OS " .. M.version .. " \"" .. M.codename .. "\""
  local labelX = math.floor((w - #label) / 2) + 1
  local labelY = math.floor(h / 2)

  fb:drawText(labelX, labelY, label, T.accent, T.bg)
  fb:drawText(labelX, labelY + 1,
    string.rep("-", #label), T.textDim, T.bg)
end

-- ---------------------------------------------------------------------------
-- Legacy wrappers (for backward compat with boot/recovery)
-- ---------------------------------------------------------------------------

-- Apply palette to a terminal (delegates to GPU).
function M.applyPalette(target)
  if not M.gpu then return target end
  M.gpu.applyPalette(target)
  return target
end

-- Blit a child window onto a parent terminal (legacy; used by WM for
-- non-GPU rendering).  With GPU mode we use framebuffer compositing
-- instead.
function M.blitWindow(src, dst, x, y)
  local w, h = src.getSize()
  for line = 1, h do
    local text, fg, bg = M.readLine(src, line)
    if text then
      dst.setCursorPos(x, y + line - 1)
      dst.blit(text, fg, bg)
    end
  end
end

-- Robust getLine() reader (kept for backward compat).
local function lineData(t, line)
  local a, b, c = t.getLine(line)
  if a == nil then return nil end
  if type(a) == "table" then
    local tx, fg, bg = a[1], a[2], a[3]
    if type(tx) ~= "string" or #tx == 0 then return nil end
    return tx, fg, bg
  end
  if type(a) ~= "string" then return nil end
  return a, b, c
end

local function padColors(text, fg, bg)
  local n = #text
  fg = fg or ""
  bg = bg or ""
  if #fg < n then fg = fg .. string.rep("f", n - #fg) end
  if #bg < n then bg = bg .. string.rep("0", n - #bg) end
  if #fg > n then fg = fg:sub(1, n) end
  if #bg > n then bg = bg:sub(1, n) end
  return text, fg, bg
end

function M.readLine(t, line)
  local text, fg, bg = lineData(t, line)
  if not text or #text == 0 then return nil end
  return padColors(text, fg, bg)
end

-- Present master to screen (legacy).
function M.presentMaster(master, oTerm)
  local cur_x, cur_y = oTerm.getCursorPos()
  local curBlink     = oTerm.getCursorBlink()
  oTerm.setCursorBlink(false)
  local w, h         = oTerm.getSize()
  oTerm.setBackgroundColor(colors.black)
  oTerm.setTextColor(colors.white)

  for line = 1, h do
    local text, fg, bg = M.readLine(master, line)
    if text then
      oTerm.setCursorPos(1, line)
      oTerm.blit(text, fg, bg)
    else
      oTerm.setCursorPos(1, line)
      oTerm.setBackgroundColor(colors.black)
      oTerm.write(string.rep(" ", w))
    end
  end

  oTerm.setCursorPos(cur_x, cur_y)
  oTerm.setCursorBlink(curBlink)
end

-- Draw a decorative brand corner piece (for splash screens).
function M.drawBrandCorner(fb, w, h, fg, bg)
  fg = fg or 4   -- yellow
  bg = bg or 9   -- cyan
  -- Top-left corner accent bar.
  fb:fillRect(1, 1, math.min(8, w), 1, " ", fg, bg)
  fb:fillRect(1, 1, 1, math.min(4, h), " ", fg, bg)
  -- Bottom-right.
  fb:fillRect(w - math.min(8, w) + 1, h, w, h, " ", fg, bg)
  fb:fillRect(w, h - math.min(4, h) + 1, w, h, " ", fg, bg)
end

-- Draw a modal dialog box with title, shadow, and close button.
-- Returns content area rect { x, y, w, h } for the caller to draw into.
function M.drawDialog(fb, dialogW, dialogH, title, screenW, screenH)
  local T = M.themeResolved or M.theme
  local x = math.max(1, math.floor((screenW - dialogW) / 2) + 1)
  local y = math.max(1, math.floor((screenH - dialogH) / 2))

  -- Shadow.
  fb:drawShadow(x, y, x + dialogW - 1, y + dialogH - 1, 2, 1, T.shadow)

  -- Panel.
  fb:fillRect(x, y, x + dialogW - 1, y + dialogH - 1, " ", 15, T.panelBg or 0)

  -- Title bar.
  fb:fillRect(x, y, x + dialogW - 1, y, " ", 15, T.panel)
  fb:drawText(x + 1, y,
    #title > (dialogW - 6) and title:sub(1, dialogW - 8) .. ".." or title,
    T.text, T.panel)

  -- Close button in title bar.
  if dialogW >= 8 then
    local btnX = x + dialogW - 4
    fb:drawText(btnX, y, "[X]", T.error, T.panel)
  end

  -- Border.
  fb:drawRect(x, y, x + dialogW - 1, y + dialogH - 1, T.border, T.border)

  return {
    x = x + 1,
    y = y + 1,
    w = dialogW - 2,
    h = dialogH - 2,
  }
end

return M
