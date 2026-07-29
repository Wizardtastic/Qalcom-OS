--[[
  /QalcomOS/Apps/Desktop/main.lua - System desktop process (v0.3)

  The desktop owns the bottom z-order layer. It draws:
    * Wallpaper on a full-bleed system window.
    * Desktop icons (right-side vertical grid).
    * A 1-row taskbar at the bottom with [Start], running-window tray,
      and a clock. The focused window's tray button is highlighted with a
      distinct accent colour. Minimized windows show with a dimmed label.
    * A Start menu overlay (managed by toggling showStartMenu state)
      that lists every .qalcom app.
    * A right-click context menu (managed by showContextMenu state) with
      quick actions: Settings, About, and Reboot. Clicking anywhere else
      or pressing Esc closes it.

  On click, it:
    * Hits an icon -> kernel.spawn the app at its declared geometry.
    * Hits the Start button -> toggles the Start menu.
    * Hits a running-window tray button -> kernel.focusWindow (or
      restore a minimized window; toggle-minimize for the focused one).
    * Hits a menu item -> kernel.spawn + close menu.
    * Esc -> terminate (drops to CraftOS).

  On right-click (button == 2), the context menu opens near the cursor.
]]

local qos      = _QOS
local registry = qos.registry
local kernel   = qos.kernel

local w, h = term.getSize()
term.setBackgroundColor(colors.cyan)
term.setTextColor(colors.lightGray)
term.clear()

-- State.
local apps = registry.scan()     -- app descriptors
local showStartMenu = false
local menuIndex     = 0         -- highlight index, 0 = none
local menuTW        = 26        -- menu width
local menuTH        = #apps + 4 -- menu height: title + items + 2 padding
-- Clamp menu size to the screen.
if menuTH + 4 > h then menuTH = h - 4 end
if menuTW > w - 6 then menuTW = w - 6 end

-- Right-click context menu state.
local showContextMenu = false
local contextX = 0              -- top-left corner of the menu
local contextY = 0
local contextItems = {
  { label = "Settings",  icon = "S", action = "settings"  },
  { label = "About",     icon = "A", action = "about"     },
  { label = "-" },  -- separator
  { label = "Reboot",    icon = "R", action = "reboot"    },
}
local contextW = 18  -- fixed width
local contextMenuIndex = 0  -- hover highlight index, 0 = none

-- ----------------------------------------------------------------------------
-- Drawing helpers
-- ----------------------------------------------------------------------------

local function drawWallpaper()
  term.setBackgroundColor(colors.cyan)
  term.setTextColor(colors.white)
  term.clear()
  local label = "Qalcom OS " .. _QOS_VERSION .. " \"" .. _QOS_CODENAME .. "\""
  term.setCursorPos(math.floor((w - #label) / 2) + 1, 2)
  term.setTextColor(colors.yellow)
  term.write(label)
  term.setBackgroundColor(colors.cyan)
end

-- Right-side icon grid: 5 rows max, each icon = one cell with a 2-char
-- glyph plus a name on the next row.
local ICON_W = 12
local ICON_X = math.max(1, w - ICON_W - 1)
local ICON_PITCH = 4  -- rows per icon slot
local ICON_Y0 = 4

local function drawIcon(x, y, glyph, name)
  -- Stage 1: paint the entire glyph cell with the icon backdrop. We
  -- write the full ICON_W cells once with spaces rather than
  -- computing a per-character backdrop -- simpler and faster.
  term.setCursorPos(x, y)
  term.setBackgroundColor(colors.lightGray)
  term.write(string.rep(" ", ICON_W))

  -- Stage 2: stamp the 2-char glyph in the center.
  local gx = x + math.floor((ICON_W - #glyph) / 2)
  term.setCursorPos(gx, y)
  term.setTextColor(colors.black)
  term.write(glyph)

  -- Stage 3: name label on the row below the glyph.
  local nx = x + math.floor((ICON_W - #name) / 2)
  term.setCursorPos(nx, y + 1)
  term.setBackgroundColor(colors.cyan)
  term.setTextColor(colors.white)
  term.write(name)
end

local function hitIcon(mx, my)
  -- Returns the index (1-based) of the icon under (mx, my), or nil.
  if mx < ICON_X or mx >= ICON_X + ICON_W then return nil end
  local row = my - ICON_Y0
  if row < 0 then return nil end
  local idx = math.floor(row / ICON_PITCH) + 1
  if row % ICON_PITCH >= 2 then return nil end  -- only label+name rows
  if idx < 1 or idx > #apps then return nil end
  return idx
end

local function drawIcons()
  term.setBackgroundColor(colors.cyan)
  for i, desc in ipairs(apps) do
    if i > 5 then break end  -- cap visible icons for v0.2
    drawIcon(ICON_X, ICON_Y0 + (i - 1) * ICON_PITCH, desc.icon, desc.name)
  end
end

-- Format current time as HH:MM. CC's os.time() ALREADY returns the
-- clock-aligned fractional hour (6.0 at dawn, 12.0 at noon, 18.0 at
-- dusk, 24 at midnight). We just split into integer hour + minute and
-- wrap at 24 so the format never prints "24:00".
local function clockText()
  local t          = os.time()
  local totalHours = t % 24         -- wraps MC midnight back to 0
  local h          = math.floor(totalHours)
  local m          = math.floor((totalHours - h) * 60)
  return string.format("%02d:%02d", h, m)
end

-- Constants used by the bottom-row taskbar. The Start label and
-- width never change; the round() helper is also constant. Both
-- are hoisted out of taskbarGeom so per-frame and per-click
-- calls don't pay the allocation cost.
local START_LABEL = "[Start]"
local START_W     = #START_LABEL
local function round(x) return math.floor(x + 0.5) end

-- Compute the columns used by the bottom-row taskbar. Start is
-- centered in the LEFT QUARTER of the bar, Clock in the RIGHT
-- QUARTER, with a 1-char separator drawn next to Start; tray
-- buttons fill the middle. Falls back to edge-aligned when the
-- screen is too narrow to honor the quarter centers without
-- Start and Clock colliding. Both rendering and click hit-tests
-- share this so the visual layout and click targets stay in
-- lock-step.
local function taskbarGeom()
  local clk_w   = #clockText()
  -- Centers: Start at 1/4 width, Clock at 3/4 width.
  local start_x = round(w / 4) - math.floor(START_W / 2)
  local clk_x   = round(3 * w / 4) - math.floor(clk_w / 2)
  start_x = math.max(1, start_x)
  clk_x   = math.min(w - clk_w + 1, math.max(1, clk_x))
  -- If the centered quarters can't keep Start and Clock 2 cols
  -- apart (room for separator + tray), fall back to edge-aligned.
  if clk_x < start_x + START_W + 2 then
    start_x = 1
    clk_x   = w - clk_w + 1
  end
  -- Final clamp: keep Start and Clock strictly adjacent unless
  -- the screen is too narrow to fit START_W + clk_w (in which
  -- case overlap is unavoidable, but we never write past the
  -- right edge). Outer min caps, inner max enforces Start ->
  -- Clock separation when there's room.
  clk_x = math.min(w - clk_w + 1, math.max(start_x + START_W, clk_x))
  return start_x, START_W, start_x + START_W, clk_x, clk_w
end

local function drawTaskbar()
  -- 1 row at the bottom of our system window. Layout:
  --   '[Start]|<tray buttons>      <HH:MM>'
  --   ^Start in left quarter         ^Clock in right quarter
  -- Both flank elements are inset from the edges so the row
  -- feels symmetrically balanced whether tray buttons are
  -- present or not.
  local y = h
  local start_x, start_w, sep_x, clk_x, clk_w = taskbarGeom()

  -- Background.
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.setCursorPos(1, y)
  term.write(string.rep(" ", w))

  -- Start button.
  term.setBackgroundColor(colors.lightBlue)
  term.setTextColor(colors.white)
  term.setCursorPos(start_x, y)
  term.write("[Start]")

  -- Separator after Start button. Only draw it when there's a real
  -- 1-col gap before the clock -- on very narrow screens the
  -- centered quarters collapse into a tight edge-aligned layout
  -- and the separator would visually collide with the clock.
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.lightGray)
  if sep_x + 1 < clk_x then
    term.setCursorPos(sep_x, y)
    term.write("|")
  end

  -- Running-window tray buttons. The transient Login chunk sits
  -- in the tray for one frame between submit() and the reap
  -- pass -- a kernel artifact, not a user-visible concept. Filter
  -- it out so the taskbar stays clean during / right after login.
  local prog = kernel.listRunning()
  local visible = {}
  for _, p in ipairs(prog) do
    if p.title ~= "Login" then visible[#visible + 1] = p end
  end

  if #visible > 0 and sep_x < clk_x then
    local tray_left  = sep_x + 1
    local tray_right = clk_x - 1
    local tray_total = tray_right - tray_left + 1
    local tray_w     = math.max(8, math.floor(tray_total / #visible))
    for i, p in ipairs(visible) do
      local x = tray_left + (i - 1) * tray_w
      if x + tray_w - 1 > tray_right then break end
      local label = " " .. (p.title or "?")
      if #label > tray_w then label = label:sub(1, tray_w - 1) .. "~" end

      -- Highlight the focused window; dim minimized windows.
      local isFocused   = p.focused
      local isMinimized = p.minimized

      term.setCursorPos(x, y)
      if isMinimized then
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.gray)
      elseif isFocused then
        term.setBackgroundColor(colors.lightBlue)
        term.setTextColor(colors.yellow)
      else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
      end
      term.write(label)
    end
  end

  -- Clock on the right.
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.setCursorPos(clk_x, y)
  term.write(clockText())
end

-- ----------------------------------------------------------------------------
-- Context menu drawing & hit-testing
-- ----------------------------------------------------------------------------

local function drawContextMenu()
  if not showContextMenu then return end
  local menuH = #contextItems + 2  -- items + 2 border rows
  local mx = contextX
  local my = contextY
  -- Clamp to screen so the menu never goes off the bottom or right.
  if mx + contextW > w then mx = w - contextW + 1 end
  if my + menuH > h - 1 then my = h - 1 - menuH end  -- above taskbar
  if mx < 1 then mx = 1 end
  if my < 1 then my = 1 end
  contextX, contextY = mx, my  -- store clamped coords for hit-test

  -- Fill background.
  for row = my, my + menuH - 1 do
    term.setCursorPos(mx, row)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.write(string.rep(" ", contextW))
  end

  -- Border.
  term.setCursorPos(mx, my)
  term.setBackgroundColor(colors.white)
  term.write("+" .. string.rep("-", contextW - 2) .. "+")
  term.setCursorPos(mx, my + menuH - 1)
  term.write("+" .. string.rep("-", contextW - 2) .. "+")
  for row = my + 1, my + menuH - 2 do
    term.setCursorPos(mx, row); term.write("|")
    term.setCursorPos(mx + contextW - 1, row); term.write("|")
  end

  -- Items.
  local iy = my + 1
  for i, item in ipairs(contextItems) do
    if iy > my + menuH - 2 then break end
    term.setCursorPos(mx + 2, iy)
    if item.label == "-" then
      -- Separator row.
      term.setBackgroundColor(colors.white)
      term.setTextColor(colors.lightGray)
      term.write(string.rep("-", contextW - 4))
    else
      if i == contextMenuIndex then
        term.setBackgroundColor(colors.yellow)
        term.setTextColor(colors.black)
      else
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
      end
      local row = " " .. (item.icon or "?") .. "  " .. item.label
      if #row > contextW - 4 then row = row:sub(1, contextW - 5) .. "~" end
      term.write(row)
    end
    iy = iy + 1
  end
end

local function contextMenuHit(mx, my)
  if not showContextMenu then return nil end
  local menuH = #contextItems + 2
  local mx1, my1 = contextX, contextY
  if mx < mx1 or mx >= mx1 + contextW then return nil end
  if my < my1 + 1 or my >= my1 + menuH - 1 then return nil end
  local idx = my - my1  -- convert row to item index (skip top border)
  if idx < 1 or idx > #contextItems then return nil end
  if contextItems[idx].label == "-" then return nil end  -- separator
  return idx
end

local function contextMenuHover(mx, my)
  local idx = contextMenuHit(mx, my)
  contextMenuIndex = idx or 0
end

-- Start menu panel: drawn over the wallpaper on the left.
local function menuRect()
  -- Centered horizontally with fixed vertical bounds.
  local mx = math.floor((w - menuTW) / 2) + 1
  local my = math.floor((h - menuTH) / 2)
  if my < ICON_Y0 then my = ICON_Y0 end
  return mx, my, mx + menuTW - 1, my + menuTH
end

local function drawStartMenu()
  local mx1, my1, mx2, my2 = menuRect()
  for row = my1, my2 do
    term.setCursorPos(mx1, row)
    term.setBackgroundColor(colors.lightBlue)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", mx2 - mx1 + 1))
  end
  -- Border.
  term.setCursorPos(mx1, my1)
  term.setBackgroundColor(colors.white)
  term.write("+" .. string.rep("-", menuTW - 2) .. "+")
  term.setCursorPos(mx1, my2)
  term.write("+" .. string.rep("-", menuTW - 2) .. "+")
  for row = my1 + 1, my2 - 1 do
    term.setCursorPos(mx1, row); term.write("|")
    term.setCursorPos(mx2, row); term.write("|")
  end

  -- Title row.
  term.setCursorPos(mx1 + 2, my1 + 1)
  term.setBackgroundColor(colors.lightBlue)
  term.setTextColor(colors.yellow)
  term.write("Qalcom OS -- Apps")
  term.setTextColor(colors.white)

  -- Items.
  local iy = my1 + 2
  for i, desc in ipairs(apps) do
    if iy > my2 - 2 then break end
    term.setCursorPos(mx1 + 2, iy)
    if i == menuIndex then
      term.setBackgroundColor(colors.yellow)
      term.setTextColor(colors.black)
    else
      term.setBackgroundColor(colors.lightBlue)
      term.setTextColor(colors.white)
    end
    local row = "  " .. (desc.icon or "?") .. "  " .. desc.name
    if #row > menuTW - 4 then row = row:sub(1, menuTW - 5) .. "~" end
    term.write(row)
    iy = iy + 1
  end

  -- Footer.
  if my2 - 1 >= my1 + 1 then
    term.setCursorPos(mx1 + 2, my2 - 1)
    term.setBackgroundColor(colors.lightBlue)
    term.setTextColor(colors.lightGray)
    term.write("Esc closes Menu. Click outside to quit.")
  end
end

-- ----------------------------------------------------------------------------
-- Click dispatch
-- ----------------------------------------------------------------------------

local function launch(desc)
  local opts = {
    title = desc.title or desc.name,
    x     = nil, y = nil,
    w     = desc.window_w or 28,
    h     = desc.window_h or 12,
  }
  local pid = kernel.spawn(desc.path, opts)
  return pid
end

local function startButtonHit(mx, my)
  if my ~= h then return false end
  local start_x, _, sep_x = taskbarGeom()
  -- The Start button AND the separator glyph both toggle the menu,
  -- so the hit-test extends to sep_x.
  return mx >= start_x and mx <= sep_x
end

local function trayButtonHit(mx, my)
  if my ~= h then return nil end
  local _, _, sep_x, clk_x = taskbarGeom()
  local tray_left  = sep_x + 1
  local tray_right = clk_x - 1
  if mx < tray_left or mx > tray_right then return nil end

  -- Same Login filter as drawTaskbar so phantom hit-test slots
  -- don't sneak through to a vanishing process.
  local prog = kernel.listRunning()
  local visible = {}
  for _, p in ipairs(prog) do
    if p.title ~= "Login" then visible[#visible + 1] = p end
  end
  if #visible == 0 then return nil end

  local tray_total = tray_right - tray_left + 1
  local tray_w     = math.max(8, math.floor(tray_total / #visible))
  local idx        = math.floor((mx - tray_left) / tray_w) + 1
  if idx < 1 or idx > #visible then return nil end
  return visible[idx]
end

local function menusContains(mx, my)
  local mx1, my1, mx2, my2 = menuRect()
  return mx >= mx1 and mx <= mx2 and my >= my1 and my <= my2
end

local function handleClick(button, mx, my)
  -- 1. Context menu takes top priority when open.
  if showContextMenu then
    local ci = contextMenuHit(mx, my)
    if ci then
      local action = contextItems[ci].action
      showContextMenu = false
      if action == "settings" then
        kernel.spawn("/QalcomOS/Apps/System/main.lua", {
          title = "System", w = 40, h = 14,
        })
      elseif action == "about" then
        kernel.spawn("/QalcomOS/Apps/About/main.lua", {
          title = "About", w = 32, h = 12,
        })
      elseif action == "reboot" then
        os.reboot()
      end
      return
    else
      -- Click outside: close the context menu.
      showContextMenu = false
      return
    end
  end

  -- 2. Start menu: if open, handle clicks inside or outside.
  if showStartMenu then
    if menusContains(mx, my) then
      local mx1, my1, _, my2 = menuRect()
      local idx = my - my1 - 2 + 1  -- convert from y row to item index
      if idx >= 1 and idx <= #apps then
        menuIndex = idx
        launch(apps[idx])
        showStartMenu = false
        menuIndex = 0
      end
      return
    else
      -- Click outside: close the menu.
      showStartMenu = false
      menuIndex = 0
      return
    end
  end

  -- 3. Right-click on the desktop background opens the context menu.
  if button == 2 then
    -- Only open if the click didn't land on a taskbar icon or app window.
    if my < h and not hitIcon(mx, my) then
      showContextMenu = true
      contextX = mx
      contextY = my
      return
    end
  end

  -- 4. Start button toggles the menu.
  if startButtonHit(mx, my) and button == 1 then
    showStartMenu = not showStartMenu
    menuIndex = 0
    return
  end

  -- 5. Tray button: focus or toggle-minimize.
  if my == h then
    local rec = trayButtonHit(mx, my)
    if rec then
      if rec.minimized then
        kernel.restoreWindow(rec.win_id)
      else
        kernel.focusWindow(rec.win_id)
      end
      return
    end
  end

  -- 6. Icon click launches.
  local iconIdx = hitIcon(mx, my)
  if iconIdx then
    launch(apps[iconIdx])
    return
  end

  -- 7. Otherwise: nothing. (Background click is ignored so we don't
  -- drag the desktop around by accident.)
end

-- ----------------------------------------------------------------------------
-- Main render / event loop
-- ----------------------------------------------------------------------------

local function render()
  drawWallpaper()
  drawIcons()
  drawTaskbar()
  if showStartMenu then drawStartMenu() end
  if showContextMenu then drawContextMenu() end
end

render()

while true do
  local ev, a, b, c = os.pullEvent()
  if ev == "mouse_click" then
    handleClick(a, b, c)
    render()
  elseif ev == "mouse_move" then
    -- Update context menu hover highlight as the mouse moves.
    if showContextMenu then
      contextMenuHover(b, c)
      render()
    end
  elseif ev == "mouse_up" then
    -- A click release is harmless; just keep the screen current.
    term.setCursorBlink(false)
  elseif ev == "timer" then
    -- Refresh the clock display on every CC timer's heartbeat. CC keeps
    -- a 0.05s-resolution global timer running internally so we get
    -- frequent refresh even when idle.
    render()
  elseif ev == "key" then
    if a == keys.escape then
      if showStartMenu then
        showStartMenu = false
        menuIndex = 0
        render()
      elseif showContextMenu then
        showContextMenu = false
        render()
      else
        -- Esc on bare desktop: terminate the desktop process. The
        -- kernel will then have no foreground, which we treat as a
        -- graceful shutdown.
        return
      end
    elseif a == keys.tab or a == keys.leftAlt then
      -- Convenience: Alt/tab opens the start menu.
      showStartMenu = not showStartMenu
      render()
    end
  elseif ev == "terminate" then
    return
  end
end
