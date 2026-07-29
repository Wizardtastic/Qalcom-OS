--[[
  /QalcomOS/Apps/System/main.lua - System Settings app (v0.6)

  Two-tab dialog in a 40x14 window:
    * Theme tab: three palette swatches (Default / Dark / Retro).
      Click a swatch to switch the preview in-app. Clicking SAVE
      writes the chosen index to /QalcomOS/.theme (via the shared
      themes.save helper) and shows a "Saved." overlay for 0.6s
      before returning.  Login reads the same file on its next
      spawn so the choice persists across sessions.
    * About tab: version, codename, app / path metadata.

  No _QOS.kernel calls -- this is a regular-tier app. The chunk returns
  on SAVE / CLOSE / Esc / terminate; the kernel reaps it via reapAndRefocus
  the next time the event pump runs. Killing via the title-bar [X] also
  works (the close-button path routes through killProcess).
]]

local qos    = _QOS
local themes = dofile("/QalcomOS/System/themes.lua")
local w, h   = term.getSize()

term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.clear()

-- Inject any qos.options.preset_theme_idx as the initial pick so a
-- caller (e.g. boot.lua) can pre-select a theme to preview without
-- the user clicking a swatch.
local state = {
  tab      = "theme",      -- "theme" | "about"
  themeIdx = themes.normalize(
    (qos.options and qos.options.preset_theme_idx) or themes.load()
  ),
}

-- Layout in app coords (after the WM's title-bar reservation).
local LAYOUT = {
  tabsY        = 1,
  tabsThemeX1  = 2, tabsThemeX2 = 9,
  tabsAboutX1  = 12, tabsAboutX2 = 19,

  themeNameY   = 3,
  swatchY      = 5,
  swW          = 10,
  sw1X         = 2,  sw2X = 15, sw3X = 28,

  hintY        = math.max(2, h - 1),
  btnY         = h,

  saveX1       = 2,  saveX2 = 9,
  closeX1      = 14, closeX2 = 22,
}

-- ----------------------------------------------------------------------------
-- Hit-tests
-- ----------------------------------------------------------------------------

local function hitTab(mx, my)
  if my ~= LAYOUT.tabsY then return nil end
  if mx >= LAYOUT.tabsThemeX1 and mx <= LAYOUT.tabsThemeX2 then return "theme" end
  if mx >= LAYOUT.tabsAboutX1 and mx <= LAYOUT.tabsAboutX2 then return "about" end
  return nil
end

local function hitSwatch(mx, my)
  if state.tab ~= "theme" then return nil end
  if my ~= LAYOUT.swatchY then return nil end
  for i = 1, #themes.themes do
    local sx = (i == 1) and LAYOUT.sw1X
            or (i == 2) and LAYOUT.sw2X
            or              LAYOUT.sw3X
    if mx >= sx and mx < sx + LAYOUT.swW then return i end
  end
  return nil
end

local function hitButton(mx, my)
  if my ~= LAYOUT.btnY then return nil end
  if mx >= LAYOUT.saveX1  and mx <= LAYOUT.saveX2  then return "save" end
  if mx >= LAYOUT.closeX1 and mx <= LAYOUT.closeX2 then return "close" end
  return nil
end

-- ----------------------------------------------------------------------------
-- Drawing
-- ----------------------------------------------------------------------------

local function drawTabs()
  for _, name in ipairs({ "theme", "about" }) do
    local x1 = (name == "theme") and LAYOUT.tabsThemeX1 or LAYOUT.tabsAboutX1
    local x2 = (name == "theme") and LAYOUT.tabsThemeX2 or LAYOUT.tabsAboutX2
    local active = (state.tab == name)
    term.setBackgroundColor(active and colors.white or colors.lightBlue)
    term.setTextColor(active and colors.black or colors.white)
    term.setCursorPos(x1, LAYOUT.tabsY)
    term.write(" " .. name:sub(1, 1):upper() .. name:sub(2) .. " ")
  end
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
end

local function drawThemeTab()
  local t = themes.themes[state.themeIdx]
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)

  term.setCursorPos(2, LAYOUT.themeNameY)
  term.write("Theme: " .. t.name)

  term.setCursorPos(2, LAYOUT.themeNameY + 1)
  term.setTextColor(colors.gray)
  term.write("(click a swatch to switch; SAVE to persist)")

  for i, sw in ipairs(themes.themes) do
    local sx = (i == 1) and LAYOUT.sw1X
            or (i == 2) and LAYOUT.sw2X
            or              LAYOUT.sw3X
    term.setCursorPos(sx, LAYOUT.swatchY)
    term.setBackgroundColor(sw.panel)
    term.setTextColor(sw.swatch_fg)
    term.write(string.rep(" ", LAYOUT.swW))
    term.setCursorPos(sx + 4, LAYOUT.swatchY)
    term.write(sw.name:sub(1, 1))
    term.setCursorPos(sx, LAYOUT.swatchY + 1)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.write(sw.name)
  end

  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(2, LAYOUT.hintY)
  term.write("Read by Login on the next session.")
end

local function drawAboutTab()
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)

  term.setCursorPos(2, 3)
  term.setTextColor(colors.yellow)
  term.write("Qalcom OS " .. tostring(_QOS_VERSION or "?"))

  term.setCursorPos(2, 4)
  term.setTextColor(colors.white)
  term.write('"' .. tostring(_QOS_CODENAME or "?") .. '"')

  term.setCursorPos(2, 6)
  term.setTextColor(colors.gray)
  term.write("A Windows-like operating system")
  term.setCursorPos(2, 7)
  term.write("for ComputerCraft: Tweaked on 1.21.1.")

  term.setCursorPos(2, 9)
  term.setTextColor(colors.lightGray)
  term.write("App: " .. tostring(_QOS_TITLE or "?"))
  term.setCursorPos(2, 10)
  term.write("Path: " .. tostring(_QOS_PATH or "?"))

  term.setCursorPos(2, LAYOUT.hintY)
  term.write("System v0.6: theme picker migrated here.")
end

local function drawButtons()
  term.setCursorPos(LAYOUT.saveX1, LAYOUT.btnY)
  term.setBackgroundColor(colors.lime)
  term.setTextColor(colors.black)
  term.write(" SAVE ")

  term.setCursorPos(LAYOUT.closeX1, LAYOUT.btnY)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.write(" CLOSE ")

  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
end

-- "Saved." overlay sits on row 12 centred between the buttons. The
-- written string is 8 chars long (" Saved. "), so the centering math
-- subtracts 8 rather than a stale 7 -- for w=40 they happen to land
-- on the same column, but for narrower windows a `(w - 7)` formula
-- drifts the overlay one column right of centre.
local function drawSavedOverlay()
  local cx = math.floor((w - 8) / 2) + 1
  term.setCursorPos(math.max(1, cx), LAYOUT.btnY - 1)
  term.setBackgroundColor(colors.lime)
  term.setTextColor(colors.black)
  term.write(" Saved. ")
  term.setBackgroundColor(colors.lightGray)
end

local function draw()
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  term.clear()
  drawTabs()
  if state.tab == "theme" then
    drawThemeTab()
  else
    drawAboutTab()
  end
  drawButtons()
end

-- ----------------------------------------------------------------------------
-- Main loop
-- ----------------------------------------------------------------------------

draw()

while true do
  local ev, a, b, c = os.pullEvent()

  if ev == "mouse_click" then
    local mx, my = b, c
    local hit = hitTab(mx, my) or hitSwatch(mx, my) or hitButton(mx, my)
    if hit == "theme" or hit == "about" then
      state.tab = hit
      draw()
    elseif type(hit) == "number" then
      state.themeIdx = hit
      draw()
    elseif hit == "save" then
      local ok = themes.save(state.themeIdx)
      draw()
      if ok then
        -- Visual feedback: 0.6s "Saved." pill so the user knows the
        -- write landed before we tear the chunk down.
        drawSavedOverlay()
        os.sleep(0.6)
      end
      return
    elseif hit == "close" then
      return
    end
  elseif ev == "key" then
    if a == keys.escape then return end
  elseif ev == "terminate" then
    return
  end
end
