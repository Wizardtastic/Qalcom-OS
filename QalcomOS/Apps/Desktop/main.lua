--[[
  /QalcomOS/Apps/Desktop/main.lua - System desktop process (v0.2)

  The desktop owns the bottom z-order layer. It draws:
    * Wallpaper on a full-bleed system window.
    * Desktop icons (right-side vertical grid).
    * A 1-row taskbar at the bottom with [Start], running-window tray,
      and a clock.
    * A Start menu overlay (managed by toggling showStartMenu state)
      that lists every .qalcom app.

  On click, it:
    * Hits an icon -> kernel.spawn the app at its declared geometry.
    * Hits the Start button -> toggles the Start menu.
    * Hits a running-window tray button -> kernel.focusWindow.
    * Hits a menu item -> kernel.spawn + close menu.
    * Esc -> terminate (drops to CraftOS).
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

local function drawTaskbar()
  -- 1 row at the bottom of our system window.
  local y = h
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.setCursorPos(1, y)
  term.write(string.rep(" ", w))

  -- Start button label.
  term.setBackgroundColor(colors.lightBlue)
  term.setTextColor(colors.white)
  term.setCursorPos(1, y)
  term.write("[Start]")

  -- Running-window tray buttons. Each gets an equal slice.
  local prog = kernel.listRunning()
  if #prog > 0 then
    local tray_x0 = 9
    local tray_w  = math.max(8, math.floor((w - 22) / math.max(1, #prog)))
    for i, p in ipairs(prog) do
      local x = tray_x0 + (i - 1) * tray_w
      if x + tray_w > w - 9 then break end
      local label = " " .. (p.title or "?")
      if #label > tray_w - 1 then label = label:sub(1, tray_w - 2) .. "~" end
      term.setCursorPos(x, y)
      term.setBackgroundColor(colors.gray)
      term.setTextColor(colors.white)
      term.write(label)
    end
  end

  -- Clock on the far right.
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.lightGray)
  local clk = clockText()
  term.setCursorPos(w - #clk - 1, y)
  term.setTextColor(colors.white)
  term.write(clk)
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
  return mx >= 1 and mx <= 8
end

local function trayButtonHit(mx, my)
  if my ~= h then return false end
  if mx < 9 or mx > w - 9 then return false end
  local prog = kernel.listRunning()
  if #prog == 0 then return nil end
  local tray_w = math.max(8, math.floor((w - 22) / math.max(1, #prog)))
  local idx = math.floor((mx - 9) / tray_w) + 1
  if idx < 1 or idx > #prog then return nil end
  return prog[idx]
end

local function menusContains(mx, my)
  local mx1, my1, mx2, my2 = menuRect()
  return mx >= mx1 and mx <= mx2 and my >= my1 and my <= my2
end

local function handleClick(button, mx, my)
  -- 1. If the menu is open, handle clicks inside or outside.
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

  -- 2. Start button toggles the menu.
  if startButtonHit(mx, my) and button == 1 then
    showStartMenu = not showStartMenu
    menuIndex = 0
    return
  end

  -- 3. Tray button focuses the running window.
  if my == h then
    local rec = trayButtonHit(mx, my)
    if rec then
      kernel.focusWindow(rec.win_id)
      return
    end
  end

  -- 4. Icon click launches.
  local iconIdx = hitIcon(mx, my)
  if iconIdx then
    launch(apps[iconIdx])
    return
  end

  -- 5. Otherwise: nothing. (Background click is ignored so we don't
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
end

render()

while true do
  local ev, a, b, c = os.pullEvent()
  if ev == "mouse_click" then
    handleClick(a, b, c)
    render()
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
