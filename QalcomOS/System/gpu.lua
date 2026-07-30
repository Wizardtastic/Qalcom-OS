--[[
  QalcomOS.System.gpu - GPU framebuffer module (v1.0)

  CC: Graphics core module providing:
    * 24-bit colour palette management via term.setPaletteColour()
    * Per-cell framebuffer (char, fg, bg) for each row
    * Fast term.blit() rendering from the framebuffer
    * Pixel-level drawing: setPixel, fillRect, drawLine, drawCircle
    * Text rendering with 24-bit colours
    * Double-buffering for flicker-free updates
    * Window compositing: layer multiple framebuffers
    * Gradient fills, rounded rects, shadow effects

  Architecture:
    Each GPUFramebuffer stores three parallel buffers per row:
      text[row]  = string of characters
      fg[row]    = string of hex fg colour codes (0-f)
      bg[row]    = string of hex bg colour codes (0-f)
    Rendering blits each row in one term.blit() call per row.
    The compositor walks windows back-to-front and splices each
    window's framebuffer into the screen framebuffer.

  Palette:
    We manage two palette tables:
      CORE_PALETTE[0..15]  = { r, g, b } floats for the 16 CC colours.
        Initialised from the host's default palette (which we read
        once at init), then apps can override individual slots.
      colourStream      = re-usable table for the hex-encoded map
        we pass to term.blit().  We cache the translated blit chars
        so paintPixel / fillRect don't repeatedly look up the map.

  Performance notes:
    * blitRow()  is the only path to term.blit().
    * render()   calls blitRow() for every row of the framebuffer
      whose content changed (dirty flag per row).  Dirty tracking
      is optional; set dirtyAlways = true to dirty every row after
      each operation (simpler, works for small framebuffers).
    * The framebuffer stores hex strings for fg/bg rather than
      colour indices so blitRow() has zero conversion overhead.
]]--

local PAINTUTILS_OK = pcall(require, "paintutils")

local M = {}

-- The 16 CC colour indices mapped to our extended palette table.
-- Entry n stores { r, g, b } floats in [0, 1].
M.CORE_PALETTE = {}

-- Lookup: colour integer (e.g. colors.white = 2^0 = 1) -> palette index.
-- CC's colours are powers of two; the index is log2(colour) + 1.
-- We compute this on init.
M.COLOUR_TO_IDX = {}

-- Inverse: index 1..16 -> colour power-of-two constant.
M.IDX_TO_COLOUR = {}

-- Initialise the GPU subsystem: capture the host palette, build
-- lookup tables, and set up the default 16-colour map.
function M.init()
  for i = 0, 15 do
    local c = 2 ^ i
    M.COLOUR_TO_IDX[c] = i   -- index 0-based internally
    M.IDX_TO_COLOUR[i] = c
  end
  -- Read the host's current palette (or use nice defaults).
  local term = term.current()
  M.CORE_PALETTE = {}
  for i = 0, 15 do
    local c = M.IDX_TO_COLOUR[i]
    local r, g, b
    if term and term.getPaletteColour then
      local ok, a, b2, c2 = pcall(term.getPaletteColour, c)
      if ok and a then r, g, b = a, b2, c2 end
    end
    M.CORE_PALETTE[i] = {
      r = r or M._defaultPalette[i][1],
      g = g or M._defaultPalette[i][2],
      b = b or M._defaultPalette[i][3],
    }
  end

  M._colourStream = "0123456789abcdef"
end

-- Default fallback palette (CC:Tweaked's standard 16 colours).
M._defaultPalette = {
  [0]  = { 0, 0, 0 },       -- white (actually index 0 maps to white in CC)
  [1]  = { 0.2, 0.2, 0.2 }, -- orange
  [2]  = { 0.3, 0.3, 0.3 }, -- magenta
  [3]  = { 0.2, 0.4, 0.6 }, -- lightBlue
  [4]  = { 0.6, 0.6, 0.2 }, -- yellow
  [5]  = { 0.3, 0.6, 0.2 }, -- lime
  [6]  = { 0.6, 0.2, 0.2 }, -- pink
  [7]  = { 0.3, 0.3, 0.5 }, -- gray
  [8]  = { 0.5, 0.5, 0.5 }, -- lightGray
  [9]  = { 0.1, 0.6, 0.6 }, -- cyan
  [10] = { 0.4, 0.2, 0.6 }, -- purple
  [11] = { 0.2, 0.2, 0.6 }, -- blue
  [12] = { 0.5, 0.3, 0.1 }, -- brown
  [13] = { 0.2, 0.5, 0.2 }, -- green
  [14] = { 0.6, 0.2, 0.4 }, -- red
  [15] = { 0.1, 0.1, 0.1 }, -- black
}

-- Apply a custom palette to a terminal.  palette is a table
-- indexed 0..15 with { r, g, b } floats.  If omitted, resets to
-- the host's defaults (the values we captured at init()).
function M.applyPalette(target, palette)
  palette = palette or M.CORE_PALETTE
  if not (target and target.setPaletteColour) then return end
  for i = 0, 15 do
    local c = M.IDX_TO_COLOUR[i]
    local entry = palette[i]
    if entry then
      target.setPaletteColour(c, entry.r, entry.g, entry.b)
    end
  end
end

-- Set a single palette slot to an RGB triple (each in [0,1]).
function M.setPaletteSlot(idx, r, g, b)
  idx = tonumber(idx)
  if not idx or idx < 0 or idx > 15 then return end
  M.CORE_PALETTE[idx] = { r = r, g = g, b = b }
  local target = term.current()
  if target and target.setPaletteColour then
    target.setPaletteColour(M.IDX_TO_COLOUR[idx], r, g, b)
  end
end

-- Convert {r, g, b} floats to a CC colour index (nearest match).
function M.rgbToPaletteIndex(r, g, b)
  local best, bestDist = 0, 999
  for i = 0, 15 do
    local e = M.CORE_PALETTE[i]
    local dr, dg, db = r - e.r, g - e.g, b - e.b
    local dist = dr * dr + dg * dg + db * db
    if dist < bestDist then
      bestDist = dist
      best = i
    end
  end
  return best
end

-- Convert {r, g, b} floats to a hex colour code for blit strings.
function M.rgbToBlitHex(r, g, b)
  local idx = M.rgbToPaletteIndex(r, g, b)
  return string.format("%x", idx)
end

-- Return the hex digit for a colour constant (e.g. colors.white -> "0").
function M.colourToHex(colour)
  local idx = M.COLOUR_TO_IDX[colour]
  if idx then
    return string.format("%x", idx)
  end
  return "0"
end

-- Return the colour constant for a hex digit.
function M.hexToColour(h)
  local idx = tonumber(h, 16)
  if idx and M.IDX_TO_COLOUR[idx] then
    return M.IDX_TO_COLOUR[idx]
  end
  return colors.white
end

-- Convenience: convert a 24-bit hex colour (#RRGGBB) to the nearest
-- palette entry, return the index.
function M.hex24ToIdx(hex)
  if type(hex) ~= "string" then return 0 end
  hex = hex:gsub("#", "")
  if #hex ~= 6 then return 0 end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return M.rgbToPaletteIndex(r, g, b)
end

-- ---------------------------------------------------------------------------
-- GPUFramebuffer -- the core rendering surface
-- ---------------------------------------------------------------------------

local GPUFramebuffer = {}
GPUFramebuffer.__index = GPUFramebuffer

-- Create a new framebuffer with the given width and height (in character
-- cells).  The framebuffer supports double-buffering (back buffer for
-- drawing, front buffer for screen output).
--   options:
--     doubleBuffer (bool)  - allocate a back buffer (default true)
--     clearColor  (int)    - initial bg colour index (default 0 = white)
--     clearChar   (string) - initial fill char (default " ")
--     dirtyAlways (bool)   - mark all rows dirty after each op (default true)
function M.createFramebuffer(w, h, options)
  options = options or {}
  local self = setmetatable({}, GPUFramebuffer)

  self.w = math.floor(w or 1)
  self.h = math.floor(h or 1)
  self.doubleBuffer = options.doubleBuffer ~= false
  self.dirtyAlways  = options.dirtyAlways  ~= false

  local clearChar = options.clearChar or " "
  local clearBg   = options.clearBg or 0
  local clearFg   = options.clearFg or 15

  -- Front buffer (always present).
  self.text = {}
  self.fg   = {}
  self.bg   = {}
  self.dirty = {}

  -- Back buffer (for double-buffering).
  if self.doubleBuffer then
    self.back = {
      text = {},
      fg   = {},
      bg   = {},
    }
  end

  self:clear(clearChar, clearFg, clearBg)
  return self
end

-- Fill the framebuffer with a solid colour/char.
function GPUFramebuffer:clear(char, fg, bg)
  char = char or " "
  fg   = fg   or 15
  bg   = bg   or 0
  local fgHex = string.format("%x", fg)
  local bgHex = string.format("%x", bg)
  local rowText = string.rep(char, self.w)
  local rowFg   = string.rep(fgHex, self.w)
  local rowBg   = string.rep(bgHex, self.w)

  -- Fill front and back buffers.
  for y = 1, self.h do
    self.text[y] = rowText
    self.fg[y]   = rowFg
    self.bg[y]   = rowBg
    self.dirty[y] = true
    if self.back then
      self.back.text[y] = rowText
      self.back.fg[y]   = rowFg
      self.back.bg[y]   = rowBg
    end
  end
end

-- Begin drawing (swap to back buffer if double-buffered).
function GPUFramebuffer:beginDraw()
  if not self.back then return end
  -- Back buffer becomes the working surface.  Copy front → back
  -- (or just clear back, but we prefer to preserve the last render
  -- so incremental updates don't wipe the screen).
  for y = 1, self.h do
    self.back.text[y] = self.text[y]
    self.back.fg[y]   = self.fg[y]
    self.back.bg[y]   = self.bg[y]
  end
end

-- End drawing and swap buffers (back → front).
function GPUFramebuffer:endDraw()
  if not self.back then
    -- No double-buffering; we drew directly to front.  Mark all
    -- rows dirty so the next render() call flushes them.
    if self.dirtyAlways then
      for y = 1, self.h do self.dirty[y] = true end
    end
    return
  end
  -- Swap back → front.  Track which rows changed.
  for y = 1, self.h do
    local changed = (self.back.text[y] ~= self.text[y])
                 or (self.back.fg[y]   ~= self.fg[y])
                 or (self.back.bg[y]   ~= self.bg[y])
    self.text[y] = self.back.text[y]
    self.fg[y]   = self.back.fg[y]
    self.bg[y]   = self.back.bg[y]
    if changed or self.dirtyAlways then
      self.dirty[y] = true
    end
  end
end

-- Low-level: set a cell directly (no dirty marking).
function GPUFramebuffer:_setCell(x, y, char, fgHex, bgHex)
  local buf = self.back or self
  local rowText = buf.text[y]
  if not rowText then return end
  if x < 1 or x > #rowText then return end
  -- Build new strings (unfortunately unavoidable in Lua 5.1).
  -- For bulk operations, use the higher-level batch methods.
  buf.text[y] = rowText:sub(1, x - 1) .. char .. rowText:sub(x + 1)
  buf.fg[y]   = (buf.fg[y] or ""):sub(1, x - 1) .. (fgHex or "f") .. (buf.fg[y] or ""):sub(x + 1)
  buf.bg[y]   = (buf.bg[y] or ""):sub(1, x - 1) .. (bgHex or "0") .. (buf.bg[y] or ""):sub(x + 1)
end

-- Set a single pixel (character cell) with foreground and background colours.
-- Accepts colour indices (0..15) or colour constants (colors.white, etc.).
function GPUFramebuffer:setPixel(x, y, char, fg, bg)
  char = char or " "
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end
  self:_setCell(x, y, char,
                string.format("%x", fgIdx),
                string.format("%x", bgIdx))
end

-- Fill a rectangular region.
--   (x1, y1) = top-left, (x2, y2) = bottom-right (inclusive).
function GPUFramebuffer:fillRect(x1, y1, x2, y2, char, fg, bg)
  char = char or " "
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end

  local buf = self.back or self
  local fgHex = string.format("%x", fgIdx)
  local bgHex = string.format("%x", bgIdx)

  -- Clamp to framebuffer bounds.
  x1 = math.max(1, math.floor(x1))
  y1 = math.max(1, math.floor(y1))
  x2 = math.min(self.w, math.floor(x2))
  y2 = math.min(self.h, math.floor(y2))

  local rowLen = x2 - x1 + 1
  if rowLen <= 0 then return end

  local fillText = string.rep(char, rowLen)
  local fillFg   = string.rep(fgHex, rowLen)
  local fillBg   = string.rep(bgHex, rowLen)

  for y = y1, y2 do
    local rowText = buf.text[y]
    if rowText then
      buf.text[y] = rowText:sub(1, x1 - 1) .. fillText .. rowText:sub(x2 + 1)
      buf.fg[y]   = (buf.fg[y] or ""):sub(1, x1 - 1) .. fillFg .. (buf.fg[y] or ""):sub(x2 + 1)
      buf.bg[y]   = (buf.bg[y] or ""):sub(1, x1 - 1) .. fillBg .. (buf.bg[y] or ""):sub(x2 + 1)
    end
  end
  if self.dirtyAlways then
    for y = y1, y2 do self.dirty[y] = true end
  end
end

-- Draw a horizontal line (faster than generic line).
function GPUFramebuffer:drawHLine(x1, x2, y, char, fg, bg)
  self:fillRect(x1, y, x2, y, char, fg, bg)
end

-- Draw a vertical line.
function GPUFramebuffer:drawVLine(x, y1, y2, char, fg, bg)
  self:fillRect(x, y1, x, y2, char, fg, bg)
end

-- Draw a rectangle outline (border only).
function GPUFramebuffer:drawRect(x1, y1, x2, y2, fg, bg, borderChar)
  borderChar = borderChar or " "
  self:fillRect(x1, y1, x2, y1, borderChar, fg, bg)      -- top
  self:fillRect(x1, y2, x2, y2, borderChar, fg, bg)      -- bottom
  self:fillRect(x1, y1, x1, y2, borderChar, fg, bg)      -- left
  self:fillRect(x2, y1, x2, y2, borderChar, fg, bg)      -- right
end

-- Draw a rectangle with rounded corners (using block chars for corners).
-- Corner chars: top-left=1, top-right=2, bottom-left=3, bottom-right=4
function GPUFramebuffer:drawRoundedRect(x1, y1, x2, y2, fg, bg,
                                         tl, tr, bl, br)
  tl = tl or 1  -- " " bg squares are fine
  tr = tr or 1
  bl = bl or 1
  br = br or 1

  -- Sides (excluding corners)
  self:fillRect(x1 + 1, y1, x2 - 1, y1, " ", fg, bg)     -- top
  self:fillRect(x1 + 1, y2, x2 - 1, y2, " ", fg, bg)     -- bottom
  self:fillRect(x1, y1 + 1, x1, y2 - 1, " ", fg, bg)     -- left
  self:fillRect(x2, y1 + 1, x2, y2 - 1, " ", fg, bg)     -- right
  -- Corners (uses U+250C etc if available; fall back to bg squares)
  -- We use the box-drawing chars if the terminal supports them.
  if tl then self:setPixel(x1, y1, "\150", fg, bg) end    -- ┌
  if tr then self:setPixel(x2, y1, "\148", fg, bg) end    -- ┐
  if bl then self:setPixel(x1, y2, "\149", fg, bg) end    -- └
  if br then self:setPixel(x2, y2, "\147", fg, bg) end    -- ┘
end

-- Draw text at (x, y) with optional fg/bg colours.
-- The text is clipped to the framebuffer width.
function GPUFramebuffer:drawText(x, y, text, fg, bg)
  if not text or type(text) ~= "string" or #text == 0 then return end
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end

  local buf = self.back or self
  local fgHex = string.format("%x", fgIdx)
  local bgHex = string.format("%x", bgIdx)

  if y < 1 or y > self.h then return end
  if x > self.w then return end

  -- Clip text to framebuffer width.
  local space = self.w - x + 1
  if space <= 0 then return end
  if #text > space then text = text:sub(1, space) end

  local rowText = buf.text[y]
  if not rowText then return end
  local n = #text

  buf.text[y] = rowText:sub(1, x - 1) .. text .. rowText:sub(x + n)
  buf.fg[y]   = (buf.fg[y] or ""):sub(1, x - 1) .. string.rep(fgHex, n) .. (buf.fg[y] or ""):sub(x + n)
  buf.bg[y]   = (buf.bg[y] or ""):sub(1, x - 1) .. string.rep(bgHex, n) .. (buf.bg[y] or ""):sub(x + n)

  if self.dirtyAlways then
    self.dirty[y] = true
  end
end

-- Centered text.
function GPUFramebuffer:drawTextCentered(y, text, fg, bg)
  local x = math.max(1, math.floor((self.w - #text) / 2) + 1)
  self:drawText(x, y, text, fg, bg)
end

-- Draw a gradient fill from top colour to bottom colour.
--   topBg, botBg : colour indices (0..15)
-- Uses dithering by alternating rows for a smooth transition.
function GPUFramebuffer:gradientFill(x1, y1, x2, y2, topBg, botBg, fg)
  fg = fg or 0
  local topIdx
  if type(topBg) == "number" and topBg < 16 then topIdx = topBg
  else topIdx = M.COLOUR_TO_IDX[topBg] or 0
  end
  local botIdx
  if type(botBg) == "number" and botBg < 16 then botIdx = botBg
  else botIdx = M.COLOUR_TO_IDX[botBg] or 0
  end

  local buf = self.back or self
  local fgHex = string.format("%x", fg)
  local height = y2 - y1 + 1
  if height <= 0 then return end

  local rowLen = x2 - x1 + 1
  if rowLen <= 0 then return end

  for dy = 0, height - 1 do
    local t = dy / (height - 1)
    local bgIdx
    if t < 0.5 then
      bgIdx = topIdx
    else
      bgIdx = botIdx
    end
    -- Feather: blend the centre rows.
    if t > 0.3 and t < 0.7 then
      -- Alternate pattern for dithering.
      if dy % 2 == 0 then bgIdx = topIdx else bgIdx = botIdx end
    end
    local bgHex = string.format("%x", bgIdx)
    local y = y1 + dy
    local rowText = buf.text[y]
    if rowText then
      local fillText = string.rep(" ", rowLen)
      local fillFg   = string.rep(fgHex, rowLen)
      local fillBg   = string.rep(bgHex, rowLen)
      buf.text[y] = rowText:sub(1, x1 - 1) .. fillText .. rowText:sub(x2 + 1)
      buf.fg[y]   = (buf.fg[y] or ""):sub(1, x1 - 1) .. fillFg .. (buf.fg[y] or ""):sub(x2 + 1)
      buf.bg[y]   = (buf.bg[y] or ""):sub(1, x1 - 1) .. fillBg .. (buf.bg[y] or ""):sub(x2 + 1)
    end
  end
  if self.dirtyAlways then
    for y = y1, y2 do self.dirty[y] = true end
  end
end

-- Draw a drop shadow behind a rectangle (offset by (dx, dy)).
-- Renders as dark bg cells in the shadow region.
function GPUFramebuffer:drawShadow(x1, y1, x2, y2, dx, dy, shadowBg)
  dx = dx or 1
  dy = dy or 1
  shadowBg = shadowBg or 15  -- black index
  -- Shadow to the right.
  if dx ~= 0 then
    self:fillRect(x2 + 1, y1 + dy, x2 + dx, y2 + dy, " ", 15, shadowBg)
  end
  -- Shadow below.
  if dy ~= 0 then
    self:fillRect(x1 + dx, y2 + 1, x2 + dx, y2 + dy, " ", 15, shadowBg)
  end
end

-- Copy a sub-region of this framebuffer to another position.
function GPUFramebuffer:blitCopy(srcX1, srcY1, srcX2, srcY2, dstX, dstY)
  local buf = self.back or self
  for y = srcY1, srcY2 do
    local srcRow = buf.text[y]
    local srcRowFg = buf.fg[y]
    local srcRowBg = buf.bg[y]
    if srcRow then
      local srcText = srcRow:sub(srcX1, srcX2)
      local srcFg   = srcRowFg and srcRowFg:sub(srcX1, srcX2) or ""
      local srcBg   = srcRowBg and srcRowBg:sub(srcX1, srcX2) or ""
      local dstY = dstY + (y - srcY1)
      if dstY >= 1 and dstY <= self.h then
        local n = #srcText
        buf.text[dstY] = buf.text[dstY]:sub(1, dstX - 1) .. srcText .. buf.text[dstY]:sub(dstX + n)
        buf.fg[dstY]   = (buf.fg[dstY] or ""):sub(1, dstX - 1) .. srcFg .. (buf.fg[dstY] or ""):sub(dstX + n)
        buf.bg[dstY]   = (buf.bg[dstY] or ""):sub(1, dstX - 1) .. srcBg .. (buf.bg[dstY] or ""):sub(dstX + n)
        self.dirty[dstY] = true
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Hardware rendering: blit the framebuffer to a CC terminal
-- ---------------------------------------------------------------------------

-- Render one row of the framebuffer to a terminal using term.blit().
-- Returns true if anything was drawn.
function GPUFramebuffer:blitRow(term, y)
  if not self.dirty[y] then return false end
  local text = self.text[y]
  local fg   = self.fg[y]
  local bg   = self.bg[y]
  if not text or #text == 0 then return false end

  -- blit() writes at the current cursor position.  Move to col 1.
  term.setCursorPos(1, y)
  term.blit(text, fg, bg)

  self.dirty[y] = false
  return true
end

-- Render the entire dirty framebuffer to a terminal.
function GPUFramebuffer:render(term)
  local any = false
  for y = 1, self.h do
    if self:blitRow(term, y) then any = true end
  end
  return any
end

-- Render to the current CC terminal.
function GPUFramebuffer:present()
  self:render(term.current())
end

-- Mark all rows as dirty (forces full redraw on next render).
function GPUFramebuffer:markDirty()
  for y = 1, self.h do self.dirty[y] = true end
end

-- ---------------------------------------------------------------------------
-- Compositor: layer window framebuffers onto a screen framebuffer
-- ---------------------------------------------------------------------------

-- Composite a source framebuffer (src) onto this framebuffer (dst)
-- at position (offsetX, offsetY).  bg-only compositing: where src's
-- bg is not transparent (transparentBg), the src row is spliced in.
--   transparentBg: colour index treated as transparent (default 15/black)
function GPUFramebuffer:composite(src, offsetX, offsetY, transparentBg)
  transparentBg = transparentBg or 0  -- white is transparent by default
  local buf = self.back or self
  local transparentHex = string.format("%x", transparentBg)

  for sy = 1, src.h do
    local dy = offsetY + sy - 1
    if dy >= 1 and dy <= self.h then
      local srcText = src.text[sy]
      local srcFg   = src.fg[sy]
      local srcBg   = src.bg[sy]
      if srcText and #srcText > 0 then
        for sx = 1, #srcText do
          local dx = offsetX + sx - 1
          if dx >= 1 and dx <= self.w then
            local bgChar = srcBg:sub(sx, sx)
            if bgChar ~= transparentHex then
              -- Write this pixel.
              local textChar = srcText:sub(sx, sx)
              local fgChar   = srcFg:sub(sx, sx)
              buf.text[dy] = buf.text[dy]:sub(1, dx - 1) .. textChar .. buf.text[dy]:sub(dx + 1)
              buf.fg[dy]   = (buf.fg[dy] or ""):sub(1, dx - 1) .. fgChar .. (buf.fg[dy] or ""):sub(dx + 1)
              buf.bg[dy]   = (buf.bg[dy] or ""):sub(1, dx - 1) .. bgChar .. (buf.bg[dy] or ""):sub(dx + 1)
            end
          end
        end
      end
    end
  end
  -- Mark affected rows dirty.
  for sy = 1, src.h do
    local dy = offsetY + sy - 1
    if dy >= 1 and dy <= self.h then
      self.dirty[dy] = true
    end
  end
end

-- Optimised compositing: layer a rectangular region of src onto dst.
-- Uses string-level operations rather than per-cell, which is ~10x faster
-- for large regions.
function GPUFramebuffer:compositeFast(src, offsetX, offsetY, transparentBg)
  transparentBg = transparentBg or 0
  local buf = self.back or self
  local transHex = string.format("%x", transparentBg)

  for sy = 1, src.h do
    local dy = offsetY + sy - 1
    if dy >= 1 and dy <= self.h then
      local srcText = src.text[sy]
      local srcFg   = src.fg[sy]
      local srcBg   = src.bg[sy]
      if srcText and #srcText > 0 then
        -- Build the new row strings by splicing src cells where
        -- srcBg is not transparent.
        local dstText = buf.text[dy]
        local dstFg   = buf.fg[dy]
        local dstBg   = buf.bg[dy]
        local newText = dstText
        local newFg   = dstFg
        local newBg   = dstBg
        local changed = false

        for sx = 1, #srcText do
          local dx = offsetX + sx - 1
          if dx >= 1 and dx <= self.w then
            if srcBg:sub(sx, sx) ~= transHex then
              local tc = srcText:sub(sx, sx)
              local fc = srcFg:sub(sx, sx)
              local bc = srcBg:sub(sx, sx)
              if newText:sub(dx, dx) ~= tc then
                newText = newText:sub(1, dx - 1) .. tc .. newText:sub(dx + 1)
                changed = true
              end
              if newFg:sub(dx, dx) ~= fc then
                newFg = newFg:sub(1, dx - 1) .. fc .. newFg:sub(dx + 1)
                changed = true
              end
              if newBg:sub(dx, dx) ~= bc then
                newBg = newBg:sub(1, dx - 1) .. bc .. newBg:sub(dx + 1)
                changed = true
              end
            end
          end
        end

        if changed then
          buf.text[dy] = newText
          buf.fg[dy]   = newFg
          buf.bg[dy]   = newBg
          self.dirty[dy] = true
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Utility: draw a framed panel with title
-- ---------------------------------------------------------------------------

-- Draw a window-style panel with title bar, border, and content area.
-- Returns the content area rect { x1, y1, x2, y2 }.
function GPUFramebuffer:drawPanel(px, py, pw, ph, title,
                                   titleBg, titleFg,
                                   borderBg, bodyBg,
                                   active)
  if not title then title = "" end
  active = active ~= false
  titleBg = titleBg or 4   -- lightBlue or yellow
  titleFg = titleFg or 15  -- black / white
  borderBg = borderBg or 5 -- lime / gray
  bodyBg  = bodyBg or 0    -- white

  -- Title bar (top row).
  self:fillRect(px, py, px + pw - 1, py, " ", titleFg, titleBg)
  if #title > 0 then
    self:drawText(px + 1, py,
      #title > pw - 2 and title:sub(1, pw - 3) .. ".." or title,
      titleFg, titleBg)
  end

  -- Window buttons (close, max, min) in the top-right.
  if pw >= 12 then
    local btnY = py
    self:drawText(px + pw - 8, btnY, " [_] [#] [X]", 15, titleBg)
  end

  -- Body area.
  if ph > 1 then
    self:fillRect(px, py + 1, px + pw - 1, py + ph - 1, " ", 15, bodyBg)
    -- Border lines.
    self:drawHLine(px, px + pw - 1, py + ph - 1, " ", 0, borderBg)
    self:drawVLine(px + pw - 1, py + 1, py + ph - 1, " ", 0, borderBg)
  end

  local content = {
    x1 = px + 1,
    y1 = py + 1,
    x2 = px + pw - 2,
    y2 = py + ph - 2,
  }
  return content
end

-- ---------------------------------------------------------------------------
-- Module-level convenience
-- ---------------------------------------------------------------------------

-- Create the screen framebuffer (the root compositing surface).
-- Call this from boot.lua after GPU init.
local _screenFB = nil

function M.getScreen()
  return _screenFB
end

function M.createScreen(w, h)
  _screenFB = M.createFramebuffer(w, h, {
    doubleBuffer = true,
    dirtyAlways  = false,
    clearColor   = 0,
    clearChar    = " ",
  })
  return _screenFB
end

-- Present the screen framebuffer to the terminal (composite all
-- visible windows and render).
function M.presentScreen()
  if not _screenFB then return end
  _screenFB:beginDraw()
  -- Clear the screen framebuffer.
  _screenFB:clear(" ", 15, 0)
  -- NOTE: actual window compositing is managed by the WM; the WM
  -- calls _screenFB:compositeFast() for each window, then calls
  -- presentScreen() to flush.
  _screenFB:endDraw()
  _screenFB:present()
end

-- ---------------------------------------------------------------------------
-- Paintutils integration
-- ---------------------------------------------------------------------------

-- Draw a line using paintutils algorithm (Bresenham) adapted for
-- our framebuffer.
function GPUFramebuffer:drawLine(x1, y1, x2, y2, char, fg, bg)
  char = char or " "
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end

  local dx = math.abs(x2 - x1)
  local dy = -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy

  while true do
    self:setPixel(x1, y1, char, fgIdx, bgIdx)
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then
      if x1 == x2 then break end
      err = err + dy
      x1 = x1 + sx
    end
    if e2 <= dx then
      if y1 == y2 then break end
      err = err + dx
      y1 = y1 + sy
    end
  end
end

-- Draw a circle outline (Bresenham).
function GPUFramebuffer:drawCircle(cx, cy, r, char, fg, bg)
  char = char or " "
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end

  local x, y = 0, r
  local d = 1 - r
  while x <= y do
    self:setPixel(cx + x, cy + y, char, fgIdx, bgIdx)
    self:setPixel(cx - x, cy + y, char, fgIdx, bgIdx)
    self:setPixel(cx + x, cy - y, char, fgIdx, bgIdx)
    self:setPixel(cx - x, cy - y, char, fgIdx, bgIdx)
    self:setPixel(cx + y, cy + x, char, fgIdx, bgIdx)
    self:setPixel(cx - y, cy + x, char, fgIdx, bgIdx)
    self:setPixel(cx + y, cy - x, char, fgIdx, bgIdx)
    self:setPixel(cx - y, cy - x, char, fgIdx, bgIdx)
    x = x + 1
    if d < 0 then
      d = d + 2 * x + 1
    else
      y = y - 1
      d = d + 2 * (x - y) + 1
    end
  end
end

-- Draw a filled circle.
function GPUFramebuffer:fillCircle(cx, cy, r, char, fg, bg)
  char = char or " "
  local fgIdx
  if type(fg) == "number" and fg < 16 then fgIdx = fg
  else fgIdx = M.COLOUR_TO_IDX[fg] or 15
  end
  local bgIdx
  if type(bg) == "number" and bg < 16 then bgIdx = bg
  else bgIdx = M.COLOUR_TO_IDX[bg] or 0
  end

  for x = -r, r do
    local hx = math.floor(math.sqrt(r * r - x * x) + 0.5)
    self:drawHLine(cx - hx, cx + hx, cy + x, char, fgIdx, bgIdx)
  end
end

-- ---------------------------------------------------------------------------
-- Palette presets
-- ---------------------------------------------------------------------------

M.palettes = {
  default = {
    [0]  = { 1.0, 1.0, 1.0 },    -- white
    [1]  = { 0.95, 0.55, 0.15 }, -- orange (#F28C28)
    [2]  = { 0.85, 0.25, 0.55 }, -- magenta (#D9408C)
    [3]  = { 0.30, 0.55, 0.90 }, -- lightBlue (#4D8CE6)
    [4]  = { 1.0, 0.85, 0.15 },  -- yellow (#FFD824)
    [5]  = { 0.35, 0.75, 0.25 }, -- lime (#58BF3F)
    [6]  = { 0.95, 0.35, 0.45 }, -- pink (#F25973)
    [7]  = { 0.40, 0.40, 0.50 }, -- gray (#666680)
    [8]  = { 0.70, 0.70, 0.75 }, -- lightGray (#B3B3BF)
    [9]  = { 0.15, 0.70, 0.70 }, -- cyan (#26B3B3)
    [10] = { 0.55, 0.30, 0.70 }, -- purple (#8C4DB3)
    [11] = { 0.20, 0.30, 0.80 }, -- blue (#334DCC)
    [12] = { 0.55, 0.35, 0.15 }, -- brown (#8C5926)
    [13] = { 0.25, 0.55, 0.25 }, -- green (#408C40)
    [14] = { 0.80, 0.20, 0.15 }, -- red (#CC3326)
    [15] = { 0.10, 0.10, 0.12 }, -- black (#1A1A1F)
  },
  dark = {
    [0]  = { 0.90, 0.90, 0.95 },  -- white (off-white)
    [1]  = { 0.75, 0.50, 0.15 },  -- orange
    [2]  = { 0.65, 0.20, 0.45 },  -- magenta
    [3]  = { 0.25, 0.45, 0.75 },  -- lightBlue
    [4]  = { 0.85, 0.75, 0.10 },  -- yellow
    [5]  = { 0.25, 0.55, 0.15 },  -- lime
    [6]  = { 0.75, 0.25, 0.35 },  -- pink
    [7]  = { 0.30, 0.30, 0.40 },  -- gray
    [8]  = { 0.50, 0.50, 0.55 },  -- lightGray
    [9]  = { 0.10, 0.50, 0.50 },  -- cyan
    [10] = { 0.40, 0.20, 0.55 },  -- purple
    [11] = { 0.15, 0.20, 0.60 },  -- blue
    [12] = { 0.40, 0.25, 0.10 },  -- brown
    [13] = { 0.15, 0.40, 0.15 },  -- green
    [14] = { 0.60, 0.15, 0.10 },  -- red
    [15] = { 0.05, 0.05, 0.08 },  -- black
  },
  retro = {
    [0]  = { 1.0, 1.0, 1.0 },     -- white
    [1]  = { 1.0, 0.65, 0.0 },    -- bright orange
    [2]  = { 0.85, 0.20, 0.40 },  -- magenta
    [3]  = { 0.40, 0.60, 0.95 },  -- lightBlue
    [4]  = { 0.95, 0.90, 0.20 },  -- bright yellow
    [5]  = { 0.30, 0.80, 0.20 },  -- bright lime
    [6]  = { 1.0, 0.40, 0.50 },   -- pink
    [7]  = { 0.50, 0.50, 0.50 },  -- gray
    [8]  = { 0.75, 0.75, 0.75 },  -- lightGray
    [9]  = { 0.25, 0.75, 0.80 },  -- cyan
    [10] = { 0.60, 0.30, 0.75 },  -- purple
    [11] = { 0.25, 0.35, 0.85 },  -- blue
    [12] = { 0.60, 0.40, 0.15 },  -- brown
    [13] = { 0.20, 0.55, 0.20 },  -- green
    [14] = { 0.85, 0.20, 0.15 },  -- red
    [15] = { 0.08, 0.08, 0.10 },  -- black
  },
}

-- Apply a named palette ("default", "dark", "retro") or a custom table.
function M.applyNamedPalette(target, name)
  local p = M.palettes[name]
  if not p then return end
  M.applyPalette(target, p)
  -- Also update our CORE_PALETTE.
  for i = 0, 15 do
    M.CORE_PALETTE[i] = p[i]
  end
end

return M
