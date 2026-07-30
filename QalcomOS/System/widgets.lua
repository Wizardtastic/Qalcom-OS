--[[
  QalcomOS.System.widgets - Reusable pixel-art widget library (v1.0)

  Builds on top of the GPUFramebuffer and api.themeResolved to provide
  a complete set of pixel-art UI widgets for Qalcom OS apps.

  Widget architecture:
    Each widget is a table with standard fields (x, y, w, h, type, id,
    visible, enabled) plus type-specific fields. Widgets render
    themselves to a GPUFramebuffer passed in via render(fb).

    All widgets accept an `opts` table on construction that sets
    position, size, colours, callbacks, and other properties.

  Widgets provided:
    Button      - Clickable button with hover/press/disabled states
    TextInput   - Single-line text field with cursor, focus, validation
    Toggle      - On/off switch with animated indicator
    Checkbox    - Check/uncheck with pixel-art box
    ProgressBar - Horizontal progress bar with label
    Slider      - Horizontal value slider with drag
    Label       - Static text label
    ScrollPanel - Scrollable container with scrollbar
    Dropdown    - Select dropdown with popup options
    List        - Vertical item list with keyboard nav
    TabPanel    - Tabbed container

  Key design choices:
    * No global state — each widget is self-contained.
    * Widgets don't handle events directly; callers dispatch events
      through the widget's handleEvent() method and call render().
    * All colours are resolved via api.resolveColour() at draw time.
    * Pixel-art decorations use Unicode box-drawing chars.
]]--

local M = {}

-- Colour resolution shorthand.
-- Callers should pass an API module reference via M.setApi(apiModule)
-- so the widget library shares the same initialised module (with GPU).
-- If no API is set, we try to load one lazily (may not have GPU).
local _api = nil

function M.setApi(apiModule)
  _api = apiModule
end

local function T()
  if not _api then
    local ok, mod = pcall(dofile, "/QalcomOS/System/api.lua")
    _api = ok and mod or nil
  end
  if _api then
    return _api.themeResolved or _api.theme
  end
  -- Absolute fallback: use default indices.
  return {}
end

local function idx(c, d)
  if not _api then
    local ok, mod = pcall(dofile, "/QalcomOS/System/api.lua")
    _api = ok and mod or nil
  end
  if _api then
    return _api.resolveColour(c, d or 0)
  end
  -- Fallback: if c is a number < 16, return it; otherwise return default.
  if type(c) == "number" and c < 16 then return math.floor(c) end
  return d or 0
end

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------

-- Pixel-art frame: draw a bordered box with Unicode box-drawing chars.
-- Returns the content area { x1, y1, x2, y2 }.
-- Public so apps can use it directly.
function M.drawFrame(fb, x, y, w, h, fg, bg, title)
  local border = idx(T().border or "#2D3748", 15)
  local bodyBg = bg or idx(T().panelBg or "#F0F4FF", 0)

  -- Shadow.
  fb:drawShadow(x, y, x + w - 1, y + h - 1, 1, 1, idx(T().shadow or "#1A1A2E", 15))

  -- Fill body.
  fb:fillRect(x + 1, y + 1, x + w - 2, y + h - 2, " ", 15, bodyBg)

  -- Top border.
  fb:setPixel(x, y, "\150", fg or border, border)     -- ┌
  fb:drawHLine(x + 1, x + w - 2, y, " ", fg or border, border)
  fb:setPixel(x + w - 1, y, "\148", fg or border, border)  -- ┐

  -- Bottom border.
  fb:setPixel(x, y + h - 1, "\149", fg or border, border)  -- └
  fb:drawHLine(x + 1, x + w - 2, y + h - 1, " ", fg or border, border)
  fb:setPixel(x + w - 1, y + h - 1, "\147", fg or border, border)  -- ┘

  -- Side borders.
  fb:drawVLine(x, y + 1, y + h - 2, " ", fg or border, border)
  fb:drawVLine(x + w - 1, y + 1, y + h - 2, " ", fg or border, border)

  -- Title.
  if title and #title > 0 then
    local maxTitle = math.max(1, w - 4)
    local t = #title > maxTitle and title:sub(1, maxTitle - 1) .. "~" or title
    fb:drawText(x + 2, y, t, idx(T().text or 0, 0), border)
  end

  return { x1 = x + 1, y1 = y + 1, x2 = x + w - 2, y2 = y + h - 2 }
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w, h    : position and size
--   label, icon    : text label and optional icon character
--   fg, bg         : colours (default: theme button colours)
--   hoverFg, hoverBg : hover state colours
--   disabledFg, disabledBg : disabled state colours
--   onClick        : function(widget, button, mx, my)
--   enabled        : boolean (default true)
--   style          : "normal" | "pill" | "flat" (default "normal")
function M.Button(opts)
  opts = opts or {}
  local self = {
    type       = "Button",
    id         = opts.id or false,
    x          = opts.x or 1,
    y          = opts.y or 1,
    w          = opts.w or 10,
    h          = opts.h or 3,
    label      = opts.label or "",
    icon       = opts.icon or "",
    fg         = opts.fg or idx(T().buttonFg or 0, 0),
    bg         = opts.bg or idx(T().buttonBg or "#4D8CE6", 3),
    hoverFg    = opts.hoverFg or opts.fg or idx(T().buttonFg or 0, 0),
    hoverBg    = opts.hoverBg or idx(T().buttonHov or "#6BA3F0", 3),
    disabledFg = opts.disabledFg or 7,
    disabledBg = opts.disabledBg or 8,
    onClick    = opts.onClick or nil,
    enabled    = opts.enabled ~= false,
    visible    = opts.visible ~= false,
    style      = opts.style or "normal",
    _hover     = false,
    _pressed   = false,

  }

  function self:render(fb)
    if not self.visible then return end

    local isEnabled = self.enabled
    local bgCol = isEnabled and (self._hover and self.hoverBg or self.bg)
                              or self.disabledBg
    local fgCol = isEnabled and (self._hover and self.hoverFg or self.fg)
                              or self.disabledFg

    -- Different styles.
    if self.style == "flat" then
      fb:fillRect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, " ", fgCol, bgCol)
    elseif self.style == "pill" then
      fb:fillRect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, " ", fgCol, bgCol)
      if self.h >= 2 then
        fb:setPixel(self.x, self.y, "\150", fgCol, bgCol)
        fb:setPixel(self.x + self.w - 1, self.y, "\148", fgCol, bgCol)
        fb:setPixel(self.x, self.y + self.h - 1, "\149", fgCol, bgCol)
        fb:setPixel(self.x + self.w - 1, self.y + self.h - 1, "\147", fgCol, bgCol)
      end
    else
      -- Normal button: pixel-art 3D effect.
      local sh = self._pressed and 0 or 1
      fb:fillRect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, " ", fgCol, bgCol)
      if self.h >= 2 then
        fb:drawHLine(self.x, self.x + self.w - 1, self.y + self.h - 1 - sh, " ", idx(T().text or 0, 0), bgCol)
        fb:drawHLine(self.x, self.x + self.w - 1, self.y + sh, " ", fgCol, bgCol)
        fb:drawVLine(self.x + self.w - 1 - sh, self.y, self.y + self.h - 1, " ", fgCol, bgCol)
      end
    end

    -- Label.
    local labelStr = self.label
    if #self.icon > 0 then
      labelStr = self.icon .. " " .. self.label
    end
    if #labelStr > self.w - 2 then
      labelStr = labelStr:sub(1, self.w - 3) .. "~"
    end
    local lx = self.x + math.floor((self.w - #labelStr) / 2) + 1
    local ly = self.y + math.floor((self.h - 1) / 2) + 1
    fb:drawText(lx, ly, labelStr, fgCol, bgCol)
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1
       and my >= self.y and my <= self.y + self.h - 1
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end

    if ev == "mouse_click" and a == 1 then
      if self:contains(b, c) then
        self._pressed = true
        if self.onClick then self:onClick(self, a, b, c) end
        return true
      end
    elseif ev == "mouse_up" then
      self._pressed = false
    elseif ev == "mouse_move" then
      local oldHover = self._hover
      self._hover = self:contains(b, c)
      return oldHover ~= self._hover  -- signal redraw needed
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- TextInput
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w, h    : position and size (h defaults to 1)
--   label         : prompt label shown to the left
--   value         : initial value
--   maxLen        : maximum characters
--   placeholder   : text shown when empty
--   secret        : boolean (mask with '*')
--   onEnter       : function(self)
--   onChange      : function(self, newValue)
--   onFocus       : function(self)
--   onBlur        : function(self)
--   validator     : function(char) returns boolean
--   fg, bg, fieldFg, fieldBg : colours
--   focusable     : boolean (default true)
function M.TextInput(opts)
  opts = opts or {}
  local self = {
    type        = "TextInput",
    id          = opts.id or false,
    x           = opts.x or 1,
    y           = opts.y or 1,
    w           = opts.w or 20,
    h           = opts.h or 1,
    label       = opts.label or "",
    value       = opts.value or "",
    maxLen      = opts.maxLen or 64,
    placeholder = opts.placeholder or "",
    secret      = opts.secret or false,
    onEnter     = opts.onEnter or nil,
    onChange    = opts.onChange or nil,
    onFocus     = opts.onFocus or nil,
    onBlur      = opts.onBlur or nil,
    validator   = opts.validator or nil,
    fg          = opts.fg or idx(T().text or 0, 0),
    bg          = opts.bg or idx(T().panelBg or "#F0F4FF", 0),
    fieldFg     = opts.fieldFg or idx(T().fieldText or 15, 15),
    fieldBg     = opts.fieldBg or idx(T().field or 0, 0),
    focusable   = opts.focusable ~= false,
    visible     = opts.visible ~= false,
    enabled     = opts.enabled ~= false,
    _focused    = false,
    _tabPressed = false,
  }

  function self:render(fb)
    if not self.visible then return end
    local cx = self.x
    local cy = self.y

    -- Label.
    if #self.label > 0 then
      local labelText = self.label .. " "
      if #labelText > self.w - 2 then labelText = labelText:sub(1, self.w - 3) end
      fb:drawText(cx, cy, labelText, self.fg, self.bg)
      cx = cx + #labelText
    end

    local fieldW = self.x + self.w - cx
    if fieldW <= 0 then return end

    -- Field background.
    fb:fillRect(cx, cy, cx + fieldW - 1, cy, " ", self.fieldFg, self.fieldBg)

    -- Display value.
    local display = self.value
    if #display == 0 and #self.placeholder > 0 and not self._focused then
      display = self.placeholder
      fb:drawText(cx, cy, #display > fieldW and display:sub(#display - fieldW + 1) or display,
                  7, self.fieldBg)
    elseif #self.value > 0 then
      local shown = self.secret and string.rep("*", #self.value) or self.value
      if #shown > fieldW then shown = shown:sub(#shown - fieldW + 1) end
      fb:drawText(cx, cy, shown, self.fieldFg, self.fieldBg)
    end

    -- Cursor (only when focused).
    if self._focused then
      local cursorOffset = math.min(#self.value, fieldW - 1)
      local cursorX = cx + math.min(cursorOffset, fieldW - 1)
      fb:setPixel(cursorX, cy, "_", self.fieldFg, self.fieldBg)
    end
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1
       and my == self.y
  end

  function self:focus()
    self._focused = true
    if self.onFocus then self:onFocus(self) end
  end

  function self:blur()
    self._focused = false
    if self.onBlur then self:onBlur(self) end
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end

    if ev == "mouse_click" and a == 1 then
      if self:contains(b, c) then
        self:focus()
        return true
      elseif self._focused then
        self:blur()
      end
    elseif ev == "char" and self._focused then
      if type(a) == "string" and #a == 1 then
        if #self.value < self.maxLen then
          if not self.validator or self.validator(a) then
            self.value = self.value .. a
            if self.onChange then self:onChange(self, self.value) end
            return true
          end
        end
      end
    elseif ev == "key" and self._focused then
      if a == keys.backspace then
        if #self.value > 0 then
          self.value = self.value:sub(1, #self.value - 1)
          if self.onChange then self:onChange(self, self.value) end
          return true
        end
      elseif a == keys.enter then
        if self.onEnter then self:onEnter(self) end
        return true
      elseif a == keys.tab then
        self._tabPressed = true
        self:blur()
        return true
      elseif a == keys.escape then
        self:blur()
        return true
      end
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------

-- opts:
--   x, y          : position (w=5, h=1 fixed)
--   value         : initial boolean
--   label         : label to the right
--   onChange      : function(self, newValue)
--   onBg, offBg   : colours for on/off states
--   knobFg        : knob colour
function M.Toggle(opts)
  opts = opts or {}
  local self = {
    type    = "Toggle",
    id      = opts.id or false,
    x       = opts.x or 1,
    y       = opts.y or 1,
    w       = 5,
    h       = 1,
    value   = opts.value == true,
    label   = opts.label or "",
    onChange = opts.onChange or nil,
    onBg    = opts.onBg or idx(T().okText or 5, 5),
    offBg   = opts.offBg or 7,
    knobFg  = opts.knobFg or 0,
    visible = opts.visible ~= false,
    enabled = opts.enabled ~= false,
  }

  function self:render(fb)
    if not self.visible then return end
    local bg = self.value and self.onBg or self.offBg
    -- Rail.
    fb:fillRect(self.x, self.y, self.x + 4, self.y, " ", self.knobFg, bg)
    -- Knob.
    local knobX = self.value and self.x + 3 or self.x + 1
    fb:setPixel(knobX, self.y, "\143", self.knobFg, bg)  -- ▘
    -- Label.
    if #self.label > 0 then
      fb:drawText(self.x + 6, self.y, self.label, idx(T().text or 0, 0),
                   idx(T().panelBg or "#F0F4FF", 0))
    end
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + 4 and my == self.y
  end

  function self:toggle()
    if not self.enabled then return end
    self.value = not self.value
    if self.onChange then self:onChange(self, self.value) end
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end
    if ev == "mouse_click" and a == 1 and self:contains(b, c) then
      self:toggle()
      return true
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Checkbox
-- ---------------------------------------------------------------------------

-- opts:
--   x, y          : position (w=3+len(label), h=1)
--   value         : initial boolean
--   label         : label to the right
--   onChange      : function(self, newValue)
--   checkFg       : colour for check mark
function M.Checkbox(opts)
  opts = opts or {}
  local self = {
    type    = "Checkbox",
    id      = opts.id or false,
    x       = opts.x or 1,
    y       = opts.y or 1,
    value   = opts.value == true,
    label   = opts.label or "",
    onChange = opts.onChange or nil,
    checkFg = opts.checkFg or idx(T().okText or 5, 5),
    visible = opts.visible ~= false,
    enabled = opts.enabled ~= false,
  }

  function self:render(fb)
    if not self.visible then return end
    local boxFg = 15
    local boxBg = 0
    -- Box frame.
    fb:setPixel(self.x, self.y, "[", boxFg, boxBg)
    fb:setPixel(self.x + 2, self.y, "]", boxFg, boxBg)
    -- Check mark (X for checked, space for unchecked).
    fb:setPixel(self.x + 1, self.y, self.value and "X" or " ", self.checkFg, boxBg)
    -- Label.
    if #self.label > 0 then
      fb:drawText(self.x + 4, self.y, self.label, idx(T().text or 0, 0),
                   idx(T().panelBg or "#F0F4FF", 0))
    end
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + 2 and my == self.y
  end

  function self:toggle()
    if not self.enabled then return end
    self.value = not self.value
    if self.onChange then self:onChange(self, self.value) end
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end
    if ev == "mouse_click" and a == 1 and self:contains(b, c) then
      self:toggle()
      return true
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- ProgressBar
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w       : position and width (h=1 fixed)
--   value         : float 0..1
--   label         : optional text shown inside/overlaid
--   fg, bg        : bar fill and track colours
--   showPercent   : boolean (draw "XX%" text)
function M.ProgressBar(opts)
  opts = opts or {}
  local self = {
    type        = "ProgressBar",
    id          = opts.id or false,
    x           = opts.x or 1,
    y           = opts.y or 1,
    w           = opts.w or 20,
    h           = 1,
    value       = math.max(0, math.min(1, opts.value or 0)),
    label       = opts.label or "",
    fg          = opts.fg or idx(T().okText or 5, 5),
    bg          = opts.bg or 7,
    showPercent = opts.showPercent ~= false,
    visible     = opts.visible ~= false,
  }

  function self:render(fb)
    if not self.visible then return end
    -- Track.
    fb:fillRect(self.x, self.y, self.x + self.w - 1, self.y, " ", 15, self.bg)
    -- Fill.
    local fillW = math.max(0, math.floor(self.value * self.w))
    if fillW > 0 then
      fb:fillRect(self.x, self.y, self.x + fillW - 1, self.y, " ", 15, self.fg)
    end
    -- Label text.
    local text = self.label
    if self.showPercent then
      text = text .. string.format("%d%%", math.floor(self.value * 100 + 0.5))
    end
    if #text > 0 then
      if #text > self.w - 2 then text = text:sub(1, self.w - 3) .. "~" end
      fb:drawText(self.x + math.floor((self.w - #text) / 2) + 1, self.y, text,
                   idx(T().text or 0, 0), 15)
    end
  end

  function self:setValue(v)
    self.value = math.max(0, math.min(1, v or 0))
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Slider
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w       : position and width (h=1 fixed)
--   value         : float 0..1
--   label         : label to the left
--   onChange      : function(self, newValue)
--   trackBg, knobFg : colours
function M.Slider(opts)
  opts = opts or {}
  local self = {
    type    = "Slider",
    id      = opts.id or false,
    x       = opts.x or 1,
    y       = opts.y or 1,
    w       = opts.w or 20,
    h       = 1,
    value   = math.max(0, math.min(1, opts.value or 0)),
    label   = opts.label or "",
    onChange = opts.onChange or nil,
    trackBg = opts.trackBg or 7,
    knobFg  = opts.knobFg or idx(T().accent or 4, 4),
    visible = opts.visible ~= false,
    enabled = opts.enabled ~= false,
    _dragging = false,
  }

  function self:render(fb)
    if not self.visible then return end
    local cx = self.x
    if #self.label > 0 then
      fb:drawText(cx, self.y, self.label .. " ", idx(T().text or 0, 0),
                   idx(T().panelBg or "#F0F4FF", 0))
      cx = cx + #self.label + 1
    end
    local trackW = self.x + self.w - cx
    if trackW <= 2 then return end

    -- Track.
    fb:fillRect(cx, self.y, cx + trackW - 1, self.y, " ", 15, self.trackBg)
    -- Fill portion.
    local fillW = math.max(1, math.floor(self.value * trackW))
    fb:fillRect(cx, self.y, cx + fillW - 1, self.y, " ", 15, self.knobFg)
    -- Knob marker.
    local knobX = cx + math.floor(self.value * (trackW - 1))
    fb:setPixel(knobX, self.y, "\143", idx(T().text or 0, 0), self.knobFg)  -- █
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1 and my == self.y
  end

  function self:setValueFromPos(mx)
    if not self.enabled then return end
    local cx = self.x
    if #self.label > 0 then cx = cx + #self.label + 1 end
    local trackW = self.x + self.w - cx
    if trackW <= 0 then return end
    local relX = math.max(0, math.min(trackW - 1, mx - cx))
    self.value = relX / (trackW - 1)
    if self.onChange then self:onChange(self, self.value) end
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end
    if ev == "mouse_click" and a == 1 and self:contains(b, c) then
      self:setValueFromPos(b)
      self._dragging = true
      return true
    elseif ev == "mouse_drag" and self._dragging then
      self:setValueFromPos(b)
      return true
    elseif ev == "mouse_up" then
      self._dragging = false
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Label
-- ---------------------------------------------------------------------------

-- opts:
--   x, y          : position
--   text          : string
--   fg, bg        : colours
--   align         : "left" | "center" | "right"
--   w             : optional width (for centering)
function M.Label(opts)
  opts = opts or {}
  local self = {
    type    = "Label",
    id      = opts.id or false,
    x       = opts.x or 1,
    y       = opts.y or 1,
    text    = opts.text or "",
    fg      = opts.fg or idx(T().text or 0, 0),
    bg      = opts.bg or idx(T().panelBg or "#F0F4FF", 0),
    align   = opts.align or "left",
    w       = opts.w or 0,
    h       = 1,
    visible = opts.visible ~= false,
  }

  function self:render(fb)
    if not self.visible or #self.text == 0 then return end
    local x = self.x
    if self.align == "center" and self.w > 0 then
      x = self.x + math.floor((self.w - #self.text) / 2)
    elseif self.align == "right" and self.w > 0 then
      x = self.x + self.w - #self.text
    end
    fb:drawText(math.max(1, x), self.y, self.text, self.fg, self.bg)
  end

  function self:setText(text)
    self.text = text or ""
  end

  return self
end

-- ---------------------------------------------------------------------------
-- ScrollPanel
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w, h    : container area
--   contentH      : virtual content height (> h enables scrolling)
--   scrollPos     : initial scroll offset (0 = top)
--   scrollbarW    : scrollbar width (default 2)
--   fg, bg        : colours
--   renderContent : function(fb, x, y, w, h, scrollY)
--                    called to draw the content area
function M.ScrollPanel(opts)
  opts = opts or {}
  local self = {
    type          = "ScrollPanel",
    id            = opts.id or false,
    x             = opts.x or 1,
    y             = opts.y or 1,
    w             = opts.w or 30,
    h             = opts.h or 10,
    contentH      = opts.contentH or opts.h or 10,
    scrollPos     = opts.scrollPos or 0,
    scrollbarW    = opts.scrollbarW or 2,
    fg            = opts.fg or idx(T().text or 0, 0),
    bg            = opts.bg or idx(T().panelBg or "#F0F4FF", 0),
    renderContent = opts.renderContent or nil,
    visible       = opts.visible ~= false,
    _maxScroll    = 0,
  }

  function self:render(fb)
    if not self.visible then return end
    local sbW = (self.contentH > self.h) and self.scrollbarW or 0
    local contentW = self.w - sbW
    local contentH = self.h

    -- Content area background.
    fb:fillRect(self.x, self.y, self.x + contentW - 1, self.y + contentH - 1, " ",
                15, self.bg)

    -- Scrollbar.
    if sbW > 0 then
      local sbX = self.x + contentW
      local trackH = contentH
      local thumbH = math.max(1, math.floor(contentH / self.contentH * (trackH - 2)))
      local maxS = self.contentH - contentH
      local thumbY = self.y + 1
      if maxS > 0 then
        thumbY = thumbY + math.floor(self.scrollPos / maxS * (trackH - 2 - thumbH))
      end

      -- Track.
      fb:fillRect(sbX, self.y, sbX + sbW - 1, self.y + trackH - 1, " ", 15, 7)
      -- Up arrow.
      fb:setPixel(sbX, self.y, "\136", self.fg, 7)  -- ▲
      -- Down arrow.
      fb:setPixel(sbX, self.y + trackH - 1, "\134", self.fg, 7)  -- ▼
      -- Thumb.
      for ty = 0, thumbH - 1 do
        fb:setPixel(sbX, self.y + thumbY + ty, " ", 15, self.fg)
      end
    end

    -- Call content renderer.
    if self.renderContent then
      self:renderContent(fb, self.x, self.y, contentW, contentH, self.scrollPos)
    end
  end

  function self:scrollTo(pos)
    self.scrollPos = math.max(0, math.min(self.contentH - self.h, math.floor(pos)))
  end

  function self:scrollBy(delta)
    self:scrollTo(self.scrollPos + delta)
  end

  function self:scrollUp()
    self:scrollBy(-1)
  end

  function self:scrollDown()
    self:scrollBy(1)
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1
       and my >= self.y and my <= self.y + self.h - 1
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible then return false end
    if ev == "mouse_click" and a == 1 and self:contains(b, c) then
      local sbW = (self.contentH > self.h) and self.scrollbarW or 0
      local sbX = self.x + self.w - sbW
      -- Clicked on scrollbar?
      if b >= sbX and self.contentH > self.h then
        local relY = c - self.y
        if relY == 0 then
          self:scrollUp()
        elseif relY >= self.h - 1 then
          self:scrollDown()
        else
          -- Click on track: jump to position.
          local target = (relY - 1) / (self.h - 2) * self.contentH
          self:scrollTo(target - self.h / 2)
        end
        return true
      end
      -- Otherwise, let content handle it.
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Dropdown
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w       : position and width (h=1 fixed)
--   options       : array of strings
--   selected      : index (1-based, 0 = none)
--   label         : label to the left
--   onChange      : function(self, selectedIndex, selectedLabel)
--   fg, bg, popupBg, hoverBg : colours
function M.Dropdown(opts)
  opts = opts or {}
  local self = {
    type     = "Dropdown",
    id       = opts.id or false,
    x        = opts.x or 1,
    y        = opts.y or 1,
    w        = opts.w or 20,
    h        = 1,
    options  = opts.options or {},
    selected = opts.selected or 0,
    label    = opts.label or "",
    onChange = opts.onChange or nil,
    fg       = opts.fg or idx(T().text or 0, 0),
    bg       = opts.bg or idx(T().panelBg or "#F0F4FF", 0),
    popupBg  = opts.popupBg or 0,
    hoverBg  = opts.hoverBg or 3,
    visible  = opts.visible ~= false,
    enabled  = opts.enabled ~= false,
    _open    = false,
    _hoverIdx = 0,
  }

  function self:render(fb)
    if not self.visible then return end
    local cx = self.x
    if #self.label > 0 then
      fb:drawText(cx, self.y, self.label .. " ", self.fg, self.bg)
      cx = cx + #self.label + 1
    end

    local fieldW = self.x + self.w - cx
    if fieldW <= 2 then return end

    -- Field.
    local display = (self.selected > 0 and self.options[self.selected]) or ""
    if #display > fieldW - 2 then display = display:sub(1, fieldW - 3) .. "~" end
    fb:fillRect(cx, self.y, cx + fieldW - 1, self.y, " ", 15, 0)
    fb:drawText(cx, self.y, " " .. display .. " " .. string.rep(" ", fieldW - #display - 2), self.fg, 0)

    -- Dropdown indicator.
    local indX = cx + fieldW - 2
    fb:setPixel(indX, self.y, self._open and "\136" or "\134", 4, 0)  -- ▲/▼

    -- Popup when open.
    if self._open and #self.options > 0 then
      local popH = math.min(#self.options, 8)
      local popY = self.y + 1
      fb:fillRect(cx, popY, cx + fieldW - 1, popY + popH - 1, " ", self.fg, self.popupBg)
      -- Border.
      fb:drawRect(cx, popY, cx + fieldW - 1, popY + popH - 1, 15, 15)
      for i, opt in ipairs(self.options) do
        if i <= popH then
          local rowBg = (i == self._hoverIdx) and self.hoverBg or self.popupBg
          local rowFg = (i == self._hoverIdx) and 0 or self.fg
          fb:fillRect(cx + 1, popY + i - 1, cx + fieldW - 2, popY + i - 1, " ", rowFg, rowBg)
          local optLabel = opt
          if #optLabel > fieldW - 4 then optLabel = optLabel:sub(1, fieldW - 5) .. "~" end
          fb:drawText(cx + 2, popY + i - 1, optLabel, rowFg, rowBg)
        end
      end
    end
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1 and my == self.y
  end

  function self:popupContains(mx, my)
    if not self._open then return false end
    local cx = self.x
    if #self.label > 0 then cx = cx + #self.label + 1 end
    local fieldW = self.x + self.w - cx
    local popH = math.min(#self.options, 8)
    return mx >= cx and mx <= cx + fieldW - 1
       and my >= self.y + 1 and my <= self.y + popH
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end

    if ev == "mouse_click" and a == 1 then
      if self._open then
        -- Check popup clicks.
        if self:popupContains(b, c) then
          local cx = self.x
          if #self.label > 0 then cx = cx + #self.label + 1 end
          local relY = c - self.y - 1 + 1
          if relY >= 1 and relY <= #self.options then
            self.selected = relY
            self._open = false
            if self.onChange then self:onChange(self, self.selected, self.options[self.selected]) end
            return true
          end
        else
          self._open = false
          return true
        end
      elseif self:contains(b, c) then
        self._open = true
        return true
      end
    elseif ev == "mouse_move" and self._open then
      if self:popupContains(b, c) then
        local cx = self.x
        if #self.label > 0 then cx = cx + #self.label + 1 end
        local relY = c - self.y - 1 + 1
        self._hoverIdx = math.max(1, math.min(#self.options, relY))
        return true
      end
    elseif ev == "key" then
      if self._open then
        if a == keys.up then
          self._hoverIdx = math.max(1, self._hoverIdx - 1)
          return true
        elseif a == keys.down then
          self._hoverIdx = math.min(#self.options, self._hoverIdx + 1)
          return true
        elseif a == keys.enter then
          if self._hoverIdx >= 1 and self._hoverIdx <= #self.options then
            self.selected = self._hoverIdx
            self._open = false
            if self.onChange then self:onChange(self, self.selected, self.options[self.selected]) end
          end
          return true
        elseif a == keys.escape then
          self._open = false
          return true
        end
      end
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w, h    : position and size
--   items         : array of strings
--   selected      : selected index (1-based, 0 = none)
--   onChange      : function(self, selectedIndex, selectedLabel)
--   onDoubleClick : function(self, selectedIndex, selectedLabel)
--   fg, bg, selBg, selFg : colours
function M.List(opts)
  opts = opts or {}
  local self = {
    type     = "List",
    id       = opts.id or false,
    x        = opts.x or 1,
    y        = opts.y or 1,
    w        = opts.w or 20,
    h        = opts.h or 10,
    items    = opts.items or {},
    selected = opts.selected or 0,
    onChange = opts.onChange or nil,
    onDoubleClick = opts.onDoubleClick or nil,
    fg       = opts.fg or idx(T().text or 0, 0),
    bg       = opts.bg or idx(T().panelBg or "#F0F4FF", 0),
    selBg    = opts.selBg or idx(T().accent or 4, 4),
    selFg    = opts.selFg or 15,
    visible  = opts.visible ~= false,
    enabled  = opts.enabled ~= false,
    scrollPos = opts.scrollPos or 0,
  }

  function self:render(fb)
    if not self.visible then return end
    fb:fillRect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, " ", 15, self.bg)
    fb:drawRect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, 15, 15)

    local visibleRows = self.h - 2
    for i = 1, math.min(#self.items - self.scrollPos, visibleRows) do
      local idx = self.scrollPos + i
      local isSel = (idx == self.selected)
      local rowBg = isSel and self.selBg or self.bg
      local rowFg = isSel and self.selFg or self.fg
      local label = self.items[idx] or ""
      if #label > self.w - 4 then label = label:sub(1, self.w - 5) .. "~" end
      fb:fillRect(self.x + 1, self.y + i, self.x + self.w - 2, self.y + i, " ", rowFg, rowBg)
      fb:drawText(self.x + 2, self.y + i, label, rowFg, rowBg)
    end
  end

  function self:contains(mx, my)
    return mx >= self.x and mx <= self.x + self.w - 1
       and my >= self.y and my <= self.y + self.h - 1
  end

  function self:itemAt(my)
    local idx = my - self.y
    if idx >= 1 and idx <= self.h - 2 then
      local realIdx = self.scrollPos + idx
      if realIdx >= 1 and realIdx <= #self.items then
        return realIdx
      end
    end
    return nil
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible or not self.enabled then return false end
    if ev == "mouse_click" and a == 1 and self:contains(b, c) then
      local idx = self:itemAt(c)
      if idx then
        self.selected = idx
        if self.onChange then self:onChange(self, idx, self.items[idx]) end
        -- Double-click detection (simple: just fire on second click)
        if self._lastClickTime and os.clock() - self._lastClickTime < 0.3 then
          if self.onDoubleClick then self:onDoubleClick(self, idx, self.items[idx]) end
        end
        self._lastClickTime = os.clock()
        return true
      end
    elseif ev == "key" then
      if a == keys.up and self.selected > 1 then
        self.selected = self.selected - 1
        if self.selected <= self.scrollPos then
          self.scrollPos = math.max(0, self.selected - 1)
        end
        if self.onChange then self:onChange(self, self.selected, self.items[self.selected]) end
        return true
      elseif a == keys.down and self.selected < #self.items then
        self.selected = self.selected + 1
        if self.selected >= self.scrollPos + self.h - 2 then
          self.scrollPos = math.min(#self.items - (self.h - 2), self.selected - 1)
        end
        if self.onChange then self:onChange(self, self.selected, self.items[self.selected]) end
        return true
      elseif a == keys.home then
        self.selected = 1; self.scrollPos = 0
        if self.onChange then self:onChange(self, 1, self.items[1]) end
        return true
      elseif a == keys["end"] then
        self.selected = #self.items
        self.scrollPos = math.max(0, #self.items - (self.h - 2))
        if self.onChange then self:onChange(self, self.selected, self.items[self.selected]) end
        return true
      end
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- TabPanel
-- ---------------------------------------------------------------------------

-- opts:
--   x, y, w, h    : position and size (includes tab strip row)
--   tabs          : array of { label = "...", content = function(fb, x, y, w, h) }
--   activeTab     : index (1-based)
--   onChange      : function(self, tabIndex)
--   tabFg, tabBg, activeTabFg, activeTabBg : colours
function M.TabPanel(opts)
  opts = opts or {}
  local self = {
    type     = "TabPanel",
    id       = opts.id or false,
    x        = opts.x or 1,
    y        = opts.y or 1,
    w        = opts.w or 40,
    h        = opts.h or 20,
    tabs     = opts.tabs or {},
    activeTab = opts.activeTab or 1,
    onChange = opts.onChange or nil,
    tabFg    = opts.tabFg or idx(T().text or 0, 0),
    tabBg    = opts.tabBg or idx(T().panelX or 7, 7),
    activeFg = opts.activeFg or idx(T().text or 0, 0),
    activeBg = opts.activeBg or idx(T().panel or 3, 3),
    visible  = opts.visible ~= false,
  }

  function self:render(fb)
    if not self.visible then return end
    local tabH = 1
    local bodyY = self.y + tabH
    local bodyH = self.h - tabH

    -- Draw tabs.
    local tabX = self.x
    for i, tab in ipairs(self.tabs) do
      local active = (i == self.activeTab)
      local tFg = active and self.activeFg or self.tabFg
      local tBg = active and self.activeBg or self.tabBg
      local label = " " .. (tab.label or "Tab " .. i) .. " "
      if #label > 16 then label = label:sub(1, 15) .. "~" end

      fb:fillRect(tabX, self.y, tabX + #label - 1, self.y, " ", tFg, tBg)
      fb:drawText(tabX, self.y, label, tFg, tBg)
      tabX = tabX + #label + 1
      if tabX > self.x + self.w - 4 then break end
    end
    -- Fill remainder of tab row.
    if tabX <= self.x + self.w - 1 then
      fb:fillRect(tabX, self.y, self.x + self.w - 1, self.y, " ", self.tabFg, self.tabBg)
    end

    -- Tab separator.
    fb:drawHLine(self.x, self.x + self.w - 1, bodyY, " ", 15, 7)

    -- Content area.
    fb:fillRect(self.x, bodyY + 1, self.x + self.w - 1, bodyY + bodyH - 1, " ", 15,
                 idx(T().panelBg or "#F0F4FF", 0))

    -- Call active tab content renderer.
    local active = self.tabs[self.activeTab]
    if active and active.content then
      active:content(fb, self.x + 1, bodyY + 1, self.w - 2, bodyH - 2)
    end
  end

  function self:tabAt(mx, my)
    if my ~= self.y then return nil end
    local tabX = self.x
    for i, tab in ipairs(self.tabs) do
      local label = " " .. (tab.label or "Tab " .. i) .. " "
      if #label > 16 then label = label:sub(1, 15) .. "~" end
      if mx >= tabX and mx < tabX + #label then return i end
      tabX = tabX + #label + 1
      if tabX > self.x + self.w - 1 then break end
    end
    return nil
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible then return false end
    if ev == "mouse_click" and a == 1 then
      local tabIdx = self:tabAt(b, c)
      if tabIdx and tabIdx ~= self.activeTab then
        self.activeTab = tabIdx
        if self.onChange then self:onChange(self, tabIdx) end
        return true
      end
    end
    return false
  end

  return self
end

-- ---------------------------------------------------------------------------
-- Container: groups widgets and dispatches events to all children
-- ---------------------------------------------------------------------------

-- A simple container that holds child widgets and renders/dispatches them.
-- Not a widget itself, but useful for composing UIs.
function M.Container(opts)
  opts = opts or {}
  local self = {
    x        = opts.x or 1,
    y        = opts.y or 1,
    w        = opts.w or 50,
    h        = opts.h or 20,
    children = {},
    visible  = opts.visible ~= false,
    _focusIdx = 0,
  }

  function self:add(child)
    self.children[#self.children + 1] = child
  end

  function self:remove(child)
    for i, c in ipairs(self.children) do
      if c == child then table.remove(self.children, i); break end
    end
  end

  function self:clear()
    self.children = {}
  end

  function self:render(fb)
    if not self.visible then return end
    for _, child in ipairs(self.children) do
      if child.render then child:render(fb) end
    end
  end

  function self:handleEvent(ev, a, b, c)
    if not self.visible then return false end
    -- Dispatch to children in reverse (topmost first).
    for i = #self.children, 1, -1 do
      local child = self.children[i]
      if child.handleEvent then
        if child:handleEvent(ev, a, b, c) then return true end
      end
    end
    return false
  end

  function self:findWidget(id)
    for _, child in ipairs(self.children) do
      if child.id == id then return child end
      if child.children then
        local found = self:findWidget(child, id)
        if found then return found end
      end
    end
    return nil
  end

  function self:focusNext()
    local focusable = {}
    for _, child in ipairs(self.children) do
      if child.focusable then focusable[#focusable + 1] = child end
    end
    if #focusable == 0 then return end
    -- Blur the currently focused widget (if any).
    local current = focusable[self._focusIdx]
    if current and current.blur then current:blur() end
    -- Advance to next.
    self._focusIdx = (self._focusIdx % #focusable) + 1
    focusable[self._focusIdx]:focus()
  end

  return self
end

return M
