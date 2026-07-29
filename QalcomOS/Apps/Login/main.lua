--[[
  /QalcomOS/Apps/Login/main.lua - Centered login dialog (v0.4 polish)

  v0.4 features:
    * Three theme palettes cycled by clicking the swatches at the
      bottom of the dialog (Default / Dark / Retro).
    * Real password input echoed as '*' so observers can't shoulder-surf.
    * Avatar glyph: a small 5-row ASCII portrait next to the username
      field, picked deterministically from the username's first letter
      so your face stays the same when you re-type.
    * Two-line Login button widget: a top "----" border row and a
      "[ LOGIN ]" centred label below. The button is rendered in grey
      and click-suppressed while the username is empty (disabled state).
    * Tab key navigates between Username and Password fields.
    * Roller-shade transition: after a successful submit, Login shrinks
      its own window from the BOTTOM upward over ~10 frames. Each
      frame, the master window redraws the diminished Login rect over
      the Desktop's first paint, so users perceive the curtain rising
      and the desktop chrome being exposed rather than a one-frame
      swap to desktop.

  Authentication is still mock for v0.4 -- any non-empty username is
  accepted. A follow-up version will validate against
  /QalcomOS/Users/<name>/.profile.
]]

local qos       = _QOS
local kernel    = qos.kernel
local wm        = qos.wm
local DESKTOP   = "/QalcomOS/Apps/Desktop/main.lua"

-- ----------------------------------------------------------------------------
-- Theme palettes
-- ----------------------------------------------------------------------------

local THEMES = {
  {  -- 1: Default (light-on-dark, blue accents)
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
  {  -- 2: Dark (subdued purple-magenta)
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
  {  -- 3: Retro (orange / amber CRT-ish)
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

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

local state = {
  username    = "",
  password    = "",
  themeIdx    = 1,
  activeField = "user",   -- "user" | "pass"
}

-- 5-line avatars deterministically picked by first letter of username.
-- Each is a small "~portrait" rendered to the left of the username row.
local AVATARS = {
  { "  o  ", " o.o ", "  T  ", " / \\ ", "/___\\" },     -- smiley
  { "/---\\", "| o |", " o.o ", "  T  ", " \\-/ " },     -- with a hat
  { "  *  ", " /\\  ", "|o.o|", " \\-/ ", "/___\\" },     -- wizard / wizard
  { " ___ ", "/   \\", "|o o|", "| ^ |", "|___|" },     -- cube
}

local function isSafeUsername(name)
  return type(name) == "string" and #name > 0 and #name <= 16
     and name:match("^[%w_%-]+$") ~= nil
end

local function loadAvatar(name)
  if isSafeUsername(name) then
    local path = "/QalcomOS/Users/" .. name .. "/avatar"
    if fs.exists(path) then
      local f = fs.open(path, "r")
      if f then
        local lines = {}
        for line in f.readLine do
          if #lines >= 5 then break end
          lines[#lines + 1] = line
        end
        f.close()
        if #lines == 5 then return lines end
      end
    end
  end
  -- Deterministic synthetic fallback so the OS still works without
  -- per-user avatar files.
  if not name or name == "" then return nil end
  local h = 0
  for i = 1, #name do h = h + string.byte(name, i) end
  return AVATARS[(h % #AVATARS) + 1]
end

local function getTheme()    return THEMES[state.themeIdx] end
local function getName()     return (getTheme()).name end

-- ----------------------------------------------------------------------------
-- Layout
-- ----------------------------------------------------------------------------
-- Dialog is 36 columns x 13 rows, centred. All coords in this layout
-- helper are body-relative (a body of 51 wide x 18 tall on an Advanced
-- Computer gives us room). When the body is smaller we clamp to row 1+
-- or col 2+ and let the bottom of the dialog crop.

local function layout()
  local w, h = term.getSize()
  local boxW, boxH = 36, 13
  local boxX = math.max(2, math.floor((w - boxW) / 2) + 1)
  local boxY = math.max(2, math.floor((h - boxH) / 2))
  return {
    w = w, h = h,
    boxX = boxX, boxY = boxY,
    boxW = boxW, boxH = boxH,

    -- Avatar rendered along the left edge of the dialog
    avatarX = boxX + 2, avatarY = boxY + 2,

    -- Username / password fields
    userX   = boxX + 13, userY = boxY + 3,
    passX   = boxX + 13, passY = boxY + 5,

    -- Two-line Login button (2 rows tall)
    btnX1   = boxX + 12, btnX2 = boxX + 23,
    btnY1   = boxY + 8, btnY2 = boxY + 9,

    -- Theme swatches in the bottom row of the dialog
    sw1X    = boxX + 4,  sw2X = boxX + 15, sw3X = boxX + 26,
    swY     = boxY + 11,
  }
end

-- ----------------------------------------------------------------------------
-- Hit-tests
-- ----------------------------------------------------------------------------

local function buttonHit(mx, my, L)
  return (mx >= L.btnX1 and mx <= L.btnX2)
     and (my == L.btnY1 or my == L.btnY2)
end

local function fieldAt(mx, my, L)
  if my == L.userY and mx >= L.userX and mx < L.boxX + L.boxW - 1 then
    return "user"
  elseif my == L.passY and mx >= L.passX and mx < L.boxX + L.boxW - 1 then
    return "pass"
  end
  return nil
end

local function swatchHit(mx, my, L)
  if my ~= L.swY then return nil end
  for i = 1, 3 do
    local sx = (i == 1) and L.sw1X or ((i == 2) and L.sw2X or L.sw3X)
    if mx >= sx and mx < sx + 8 then return i end
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Draw
-- ----------------------------------------------------------------------------

local function draw()
  local L = layout()
  local T = getTheme()

  -- Backdrop.
  term.setBackgroundColor(T.bg)
  term.setTextColor(T.text)
  term.clear()

  -- Brand above the dialog.
  local brand         = "QALCOM OS"
  local brandY        = math.max(2, L.boxY - 3)
  local sub           = "Genesis II -- sign in"
  local subY          = math.max(3, L.boxY - 1)
  if brandY > 0 then
    term.setTextColor(T.accent)
    term.setCursorPos(math.floor((L.w - #brand) / 2) + 1, brandY)
    term.write(brand)
    if subY > 0 then
      term.setTextColor(T.textDim)
      term.setCursorPos(math.floor((L.w - #sub) / 2) + 1, subY)
      term.write(sub)
    end
  end

  -- Dialog backdrop (entire rectangle).
  for row = L.boxY, L.boxY + L.boxH - 1 do
    term.setCursorPos(L.boxX, row)
    term.setBackgroundColor(T.panelX)
    term.setTextColor(T.text)
    term.write(string.rep(" ", L.boxW))
  end

  -- Dialog title strip.
  term.setCursorPos(L.boxX, L.boxY)
  term.setBackgroundColor(T.panel)
  term.setTextColor(T.accent)
  term.write(string.rep(" ", L.boxW))
  local title = " Login to Qalcom OS "
  term.setCursorPos(L.boxX + math.max(1, math.floor((L.boxW - #title) / 2)), L.boxY)
  term.write(title)

  -- Avatar to the left of the username field.
  local avatar = loadAvatar(state.username)
  if avatar then
    term.setBackgroundColor(T.panelX)
    term.setTextColor(T.accent)
    for i, line in ipairs(avatar) do
      local row = L.avatarY + i - 1
      if row >= L.boxY and row < L.boxY + L.boxH then
        term.setCursorPos(L.avatarX, row)
        term.write(line)
      end
    end
  end

  -- Username row.
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.text)
  term.setCursorPos(L.boxX + 9, L.boxY + 3)
  term.write("Username:")
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
  term.setCursorPos(L.userX, L.userY)
  term.write(string.rep(" ", L.boxW - 14))
  term.setCursorPos(L.userX, L.userY)
  if #state.username > 0 then term.write(state.username) end

  -- Password row (masked with '*').
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.text)
  term.setCursorPos(L.boxX + 9, L.boxY + 5)
  term.write("Password:")
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
  term.setCursorPos(L.passX, L.passY)
  term.write(string.rep(" ", L.boxW - 14))
  term.setCursorPos(L.passX, L.passY)
  if #state.password > 0 then
    term.write(string.rep("*", #state.password))
  end

  -- Theme swatches + caption (theme name).
  for i, sw in ipairs(THEMES) do
    local sx = (i == 1) and L.sw1X or ((i == 2) and L.sw2X or L.sw3X)
    term.setBackgroundColor(sw.panel)
    term.setTextColor(sw.swatch_fg)
    term.setCursorPos(sx, L.swY)
    term.write(string.rep(" ", 8))
    -- Mini caption inside the swatch (theme initial letter).
    term.setCursorPos(sx + 3, L.swY)
    term.write(sw.name:sub(1, 1))
  end
  -- Theme name in the empty row above the swatches, shows current.
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.textDim)
  local themeName = ("Theme: %s  (click a swatch)"):format(getName())
  local nameY = L.boxY + 10
  if nameY < L.boxY + L.boxH then
    term.setCursorPos(L.boxX + 4, nameY)
    term.write(themeName)
  end

  -- Two-line Login button widget with disabled-state styling.
  local canSubmit = (#state.username > 0)
  local btnBg     = canSubmit and T.button_ok_bg  or T.button_dis_bg
  local btnFg     = canSubmit and T.button_ok_fg  or T.button_dis_fg

  -- Top row: a fill bar (acts as the button border).
  term.setBackgroundColor(btnBg)
  term.setTextColor(btnFg)
  term.setCursorPos(L.btnX1, L.btnY1)
  term.write(string.rep("-", L.btnX2 - L.btnX1 + 1))

  -- Bottom row: "[ LOGIN ]" centred + a thin underline outline.
  local labelW = L.btnX2 - L.btnX1 + 1
  local label  = "[ LOGIN ]"
  if not canSubmit then label = "[ ---- ]" end
  local pad    = math.max(0, math.floor((labelW - #label) / 2))
  term.setCursorPos(L.btnX1, L.btnY2)
  term.write(string.rep(" ", pad))
  term.write(label)
  local tail = math.max(0, labelW - pad - #label)
  term.write(string.rep(" ", tail))

  -- Hint line below the dialog.
  local hintY = L.boxY + L.boxH + 1
  if hintY > L.h then hintY = L.h end
  if hintY >= L.boxY + L.boxH then
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.textDim)
    term.setCursorPos(L.boxX, hintY)
    term.write("Tab=switch field | Enter=submit | Backspace=delete | Esc=cancel")
  end

  -- Drop the caret in the active input field (no blink so the signal
  -- stays steady even during the printer-drawn frames).
  term.setCursorBlink(false)
  if state.activeField == "pass" then
    term.setCursorPos(L.passX + #state.password, L.passY)
  else
    term.setCursorPos(L.userX + #state.username, L.userY)
  end
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
end

-- ----------------------------------------------------------------------------
-- Submit + curtain transition
-- ----------------------------------------------------------------------------

-- Animates Login's window shrinking from the BOTTOM upward so that the
-- desktop window underneath is progressively exposed. Each tick shrinks
-- the outer height by 1 row, keeping the title row anchored; the master
-- is repainted by the kernel's timer-event handler each tick (which
-- calls reapAndRefocus -> wm.render).
--
-- Uses the narrow qos.resizeSelf helper instead of the full WM table
-- so the trusted app can't accidentally destroy other windows.
local function curtainUp()
  local sw, sh = term.getSize()
  -- Read the current outer height (body height + 1-row title).
  local cur_h = math.max(2, (qos.child and qos.child.getSize
                            and qos.child.getSize()) and (qos.child.getSize() + 1) or sh)
  if cur_h <= 2 then return end
  for tick = 1, cur_h - 2 do
    local new_h = math.max(2, cur_h - tick)
    qos.resizeSelf(new_h)
    os.sleep(0.04)
  end
end

local function submit()
  -- Spawn Desktop as the system process. SYSTEM_PID slot is empty
  -- because Login is a regular process. Desktop renders its first
  -- frame beneath Login -> unseen yet.
  local L = layout()
  kernel.spawn(DESKTOP, {
    title    = "Desktop",
    isSystem = true,
    w        = L.w,
    h        = L.h,
  })
  os.sleep(0.10)  -- let Desktop's first paint complete

  -- Roller-shade in.
  curtainUp()

  -- Returning lets the kernel reap Login and run wm.render(), which
  -- finally exposes the Desktop's chrome without the curtain overlap.
end

-- ----------------------------------------------------------------------------
-- Main event loop
-- ----------------------------------------------------------------------------

draw()
local loginHover = false

while true do
  local ev, a, b, c = os.pullEvent()

  if ev == "char" then
    if type(a) == "string" and #a == 1 then
      if state.activeField == "pass" then
        state.password = state.password .. a
      else
        state.username = state.username .. a
      end
      draw()
    end

  elseif ev == "key" then
    if a == keys.enter then
      if #state.username > 0 then submit(); return end
    elseif a == keys.backspace then
      if state.activeField == "pass" then
        if #state.password > 0 then
          state.password = state.password:sub(1, #state.password - 1)
          draw()
        end
      else
        if #state.username > 0 then
          state.username = state.username:sub(1, #state.username - 1)
          draw()
        end
      end
    elseif a == keys.tab then
      state.activeField = (state.activeField == "user") and "pass" or "user"
      draw()
    elseif a == keys.escape then
      -- Cancel: red and exit; no desktop spawn.
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.red)
      term.clear()
      term.setCursorPos(1, 1)
      print("Login cancelled.")
      return
    end

  elseif ev == "mouse_click" then
    local L = layout()
    if buttonHit(b, c, L) then
      if #state.username > 0 then submit(); return end
    else
      local f = fieldAt(b, c, L)
      if f then
        state.activeField = f
        draw()
      else
        local sw = swatchHit(b, c, L)
        if sw then state.themeIdx = sw; draw() end
      end
    end

  elseif ev == "mouse_move" then
    local L = layout()
    local h = buttonHit(b, c, L)
    if h ~= loginHover then loginHover = h; draw() end

  elseif ev == "terminate" then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("Login terminated.")
    return
  end
end
