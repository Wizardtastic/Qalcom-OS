--[[
  /QalcomOS/Apps/Desktop/main.lua - System desktop process (v1.0 CC: Graphics)

  GPU-accelerated desktop compositor. Uses the GPUFramebuffer and scene
  graph for all rendering. Features:

    * Full-bleed gradient wallpaper with brand accent
    * 3-column pixel-art icon grid (each icon is 3x3 cells of art)
    * 2-row taskbar with dark gradient, L tile, tray buttons, clock/date
    * Start menu with gradient panel, hover highlighting, shadow
    * Right-click context menu with fade-in animation
    * Notification toasts with shadow and dismiss
    * Smooth animations using scene-graph motion primitives
]]--

local qos      = _QOS
local registry = qos.registry
local kernel   = qos.kernel
local osApi    = qos.osApi
local scene    = dofile("/QalcomOS/System/scene.lua")
local api      = dofile("/QalcomOS/System/api.lua")
local gpu      = api.gpu

local w, h = term.getSize()

-- If GPU is not available, fall back silently.
if not gpu then
  -- Fallback: use old-style rendering.
  term.setBackgroundColor(colors.cyan)
  term.setTextColor(colors.lightGray)
  term.clear()
  term.setCursorPos(2, 2)
  term.write("GPU not available - running in legacy mode")
  while true do os.pullEvent() end
  return
end

-- Get the GPU framebuffer from the WM (created by createSystemWindow).
-- The WM composites this framebuffer onto the screen.
local desktopFB = qos.gpuFB
if not desktopFB then
  -- Fallback: create our own framebuffer.
  desktopFB = gpu.createFramebuffer(w, h, {
    doubleBuffer = true, dirtyAlways = false,
    clearChar = " ", clearBg = api.resolveColour(api.theme.bg or 9, 9),
  })
end

-- Tell the scene module to use our framebuffer.
scene.init(desktopFB)

-- Theme colours (resolved to palette indices).
local T = {
  bg     = api.resolveColour(api.theme.bg, 9),
  bgAlt  = api.resolveColour(api.theme.bgAlt or "#1A3A5C", 3),
  accent = api.resolveColour(api.theme.accent, 4),
  text   = api.resolveColour(api.theme.text, 0),
  dim    = api.resolveColour(api.theme.textDim, 7),
  taskbar = api.resolveColour(api.theme.taskbarBg or "#1A202C", 15),
  tray   = api.resolveColour(api.theme.trayBg or "#2D3748", 7),
  panel  = api.resolveColour(api.theme.panel, 11),
  white  = 0,
  black  = 15,
  cyan   = 9,
}

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

local apps = registry.scan()
local showStartMenu = false
local menuIndex     = 0
local menuTW        = 28
local menuTH        = #apps + 4
if menuTH + 4 > h then menuTH = h - 4 end
if menuTW    > w - 6 then menuTW = w - 6 end

local showContextMenu = false
local contextX, contextY = 0, 0
local contextItems = {
  { label = "Settings", icon = "S", action = "settings" },
  { label = "About",    icon = "A", action = "about"    },
  { label = "-" },
  { label = "Reboot",   icon = "R", action = "reboot"   },
}
local contextW   = 20
local contextMenuIndex = 0

-- Animation state.
local lastRenderClock      = os.clock()
local contextMenuLastShown = false
local _demoToastFired      = false

-- ----------------------------------------------------------------------------
-- Layout constants
-- ----------------------------------------------------------------------------

local START_LABEL = "[Q]"
local START_W     = 5
local ICON_X      = 2
local ICON_W      = 10
local ICON_GAP_X  = 6
local ICON_PITCH  = 4    -- 3 art rows + 1 name label
local ICON_Y0     = 3
local ICON_COLS   = 3
local ICON_MAX    = 9    -- 3 cols x 3 rows

-- Pixel art icons (5x3 cell art for each app, using CHAR-based art
-- where each character + bg colour forms a "pixel").
local ICON_ART = {
  About  = {
    art = {
      "  ___  ",
      " | o o|",
      " |_?_| ",
      "  ─────",
    },
    bg  = 3,  -- lightBlue
    fg  = 15, -- black
    alt = 4,  -- yellow
  },
  Hello  = {
    art = {
      "  ┌──┐ ",
      "  │@@│ ",
      "  └──┘ ",
      "  ()() ",
    },
    bg  = 5,  -- lime
    fg  = 15, -- black
    alt = 0,  -- white
  },
  Clock  = {
    art = {
      "  ╭──╮ ",
      "  │C │ ",
      "  │ L│ ",
      "  ╰──╯ ",
    },
    bg  = 9,  -- cyan
    fg  = 0,  -- white
    alt = 4,  -- yellow
  },
  System = {
    art = {
      "  ╔══╗ ",
      "  ║S ║ ",
      "  ║ Y║ ",
      "  ╚══╝ ",
    },
    bg  = 15, -- black
    fg  = 4,  -- yellow
    alt = 0,  -- white
  },
  TaskManager = {
    art = {
      "  ▓▓▓  ",
      "  ▓▓▓  ",
      "  ▓▓▓  ",
      "  ▓▓▓  ",
    },
    bg  = 14, -- red
    fg  = 0,  -- white
    alt = 4,  -- yellow
  },
}

local ICON_ART_FALLBACK = {
  art = {
    "   ___  ",
    "  /_?_\\ ",
    "  ──────",
    " (     )",
  },
  bg  = 7,  -- gray
  fg  = 15, -- black
  alt = 0,  -- white
}

local function getIconArt(desc)
  local known = ICON_ART[desc.name]
  if known then return known end
  return ICON_ART_FALLBACK
end

-- ----------------------------------------------------------------------------
-- Time/Date helpers
-- ----------------------------------------------------------------------------

local _cachedDateStr = "29-7-26"
local _cachedTimeStr = "00:00"

local function updateDateTime()
  _cachedTimeStr = osApi.formatTime(":")
  _cachedDateStr = osApi.formatDate("-")
end

-- ----------------------------------------------------------------------------
-- Drawing functions (GPU framebuffer)
-- ----------------------------------------------------------------------------

local function drawWallpaper()
  -- Gradient: top = accent, bottom = bg.
  desktopFB:gradientFill(1, 1, w, h, T.bgAlt, T.bg, 0)
  -- Brand label.
  local label = "Qalcom OS " .. _QOS_VERSION .. " \"" .. _QOS_CODENAME .. "\""
  desktopFB:drawText(math.floor((w - #label) / 2) + 1, 2, label, T.accent, T.bgAlt)
  -- Decorative corner bars.
  api.drawBrandCorner(desktopFB, w, h, T.accent, T.bgAlt)
end

local function drawIcons()
  local cellPitch = ICON_W + ICON_GAP_X
  for i, desc in ipairs(apps) do
    if i > ICON_MAX then break end
    local col = (i - 1) % ICON_COLS
    local row = math.floor((i - 1) / ICON_COLS)
    local x0  = ICON_X + col * cellPitch
    local y0  = ICON_Y0 + row * ICON_PITCH

    local art = getIconArt(desc)
    -- Draw each pixel-art line.
    for li = 1, math.min(#art.art, 3) do
      local line = art.art[li]
      local lineY = y0 + li - 1
      local lineX = x0 + math.floor((ICON_W - #line) / 2) + 1
      desktopFB:drawText(lineX, lineY, line, art.fg, art.bg)
    end

    -- Name label below the art.
    local name = desc.name
    if #name > ICON_W - 2 then name = name:sub(1, ICON_W - 4) .. "~" end
    desktopFB:drawText(
      x0 + math.floor((ICON_W - #name) / 2) + 1,
      y0 + 3,
      name, 0, T.bg)
  end
end

local function drawTaskbar()
  local yBot = h
  local yTop = h - 1

  -- Two-row dark taskbar.
  desktopFB:fillRect(1, yTop, w, yTop, " ", T.taskbar, T.taskbar)
  desktopFB:fillRect(1, yBot, w, yBot, " ", T.taskbar, T.taskbar)

  -- Top row: separator line + time on the right.
  desktopFB:drawHLine(1, w, yTop, " ", T.tray, T.tray)
  local timeStr = _cachedTimeStr
  desktopFB:drawText(w - #timeStr, yTop, timeStr, T.accent, T.taskbar)

  -- Bottom row: L tile + tray + date.
  -- L tile.
  desktopFB:fillRect(1, yBot, START_W, yBot, " ", T.panel, T.panel)
  desktopFB:drawText(2, yBot, START_LABEL, T.accent, T.panel)

  -- Tray buttons (Login-filtered).
  local prog = kernel.listRunning()
  local visible = {}
  for _, p in ipairs(prog) do
    if p.title ~= "Login" then visible[#visible + 1] = p end
  end

  local dateStr = _cachedDateStr
  local dateX   = math.max(START_W + 4, w - #dateStr)

  if #visible > 0 then
    local trayLeft = START_W + 2
    local trayRight = dateX - 3
    local trayTotal = trayRight - trayLeft + 1
    if trayTotal > 0 then
      local trayW = math.max(8, math.floor(trayTotal / #visible))
      for i, p in ipairs(visible) do
        local x = trayLeft + (i - 1) * trayW
        if x + trayW - 1 > trayRight then break end
        local label = " " .. (p.title or "?")
        if #label > trayW - 1 then label = label:sub(1, trayW - 2) .. "~" end
        local fg, bg
        if p.minimized  then fg, bg = T.dim, T.tray
        elseif p.focused then fg, bg = T.accent, T.panel
        else                  fg, bg = 0, T.tray
        end
        desktopFB:drawText(x, yBot, label, fg, bg)
      end
    end
  end

  -- Date.
  desktopFB:drawText(dateX, yBot, dateStr, T.dim, T.taskbar)
  -- Small separator before date.
  if dateX > START_W + 4 then
    desktopFB:drawText(dateX - 2, yBot, "|", T.dim, T.taskbar)
  end

  -- Bottom edge accent line.
  desktopFB:drawHLine(1, w, yBot, " ", T.accent, T.accent)
end

-- Start menu ---
local function menuRect()
  local mx = math.max(2, math.floor((w - menuTW) / 2) + 1)
  local my = math.max(2, math.floor((h - menuTH) / 2))
  return mx, my, mx + menuTW - 1, my + menuTH
end

local function drawStartMenu()
  if not showStartMenu then return end
  local mx1, my1, mx2, my2 = menuRect()

  -- Shadow.
  desktopFB:drawShadow(mx1, my1, mx2, my2, 2, 1, 15)

  -- Gradient panel.
  desktopFB:gradientFill(mx1, my1, mx2, my2, T.panel, T.bgAlt, 0)

  -- Title bar.
  local titleBg = T.accent
  desktopFB:fillRect(mx1, my1, mx2, my1, " ", 15, titleBg)
  desktopFB:drawText(mx1 + 2, my1, " Qalcom Apps ", T.text, titleBg)

  -- Bottom hint bar.
  desktopFB:fillRect(mx1, my2, mx2, my2, " ", T.dim, titleBg)
  desktopFB:drawText(mx1 + 2, my2,
    "Esc closes", 0, titleBg)

  -- Border.
  desktopFB:drawRect(mx1, my1, mx2, my2, T.bgAlt, T.bgAlt)

  -- App list.
  local iy = my1 + 2
  for i, desc in ipairs(apps) do
    if iy >= my2 - 1 then break end
    local rowBg = (i == menuIndex) and T.accent or T.panel
    local rowFg = (i == menuIndex) and T.text or 0
    desktopFB:fillRect(mx1 + 1, iy, mx2 - 1, iy, " ", rowFg, rowBg)
    local iconStr = (desc.icon or "?") .. "  " .. desc.name
    if #iconStr > menuTW - 6 then iconStr = iconStr:sub(1, menuTW - 8) .. "~" end
    desktopFB:drawText(mx1 + 2, iy, "  " .. iconStr, rowFg, rowBg)
    iy = iy + 1
  end
end

-- Context menu ---
local FADE_STEPS = { 7, 7, 7, 7, 0, 0, 0, 0 }

local function drawContextMenu()
  if not showContextMenu then
    contextMenuLastShown = false
    return
  end

  local menuH = #contextItems + 2
  local mx = math.max(1, math.min(w - contextW + 1, contextX))
  local my = math.max(1, math.min(h - menuH - 2, contextY))

  -- Shadow.
  desktopFB:drawShadow(mx, my, mx + contextW - 1, my + menuH - 1, 1, 1, 15)

  -- Panel bg.
  local panelBg = (not contextMenuLastShown) and 7 or 0
  desktopFB:fillRect(mx, my, mx + contextW - 1, my + menuH - 1, " ", 15, panelBg)
  contextMenuLastShown = true
  contextX, contextY = mx, my

  -- Border.
  desktopFB:drawRect(mx, my, mx + contextW - 1, my + menuH - 1, 15, 15)

  -- Items.
  local iy = my + 1
  for i, item in ipairs(contextItems) do
    if iy > my + menuH - 2 then break end
    if item.label == "-" then
      desktopFB:drawHLine(mx + 1, mx + contextW - 2, iy, " ", T.dim, panelBg)
    else
      local hovBg = (i == contextMenuIndex) and T.accent or panelBg
      local hovFg = (i == contextMenuIndex) and T.text or 15
      desktopFB:fillRect(mx + 1, iy, mx + contextW - 2, iy, " ", hovFg, hovBg)
      local row = " " .. (item.icon or "?") .. "  " .. item.label
      if #row > contextW - 4 then row = row:sub(1, contextW - 5) .. "~" end
      desktopFB:drawText(mx + 2, iy, row, hovFg, hovBg)
    end
    iy = iy + 1
  end
end

-- Notifications ---
local NOTIF_W   = 32
local NOTIF_H   = 4
local NOTIF_MAX = 3

local function notifX0() return math.max(1, w - NOTIF_W - 2) end

local function drawNotifications()
  local notifs = kernel.readNotifications() or {}
  if #notifs == 0 then return end
  local x0 = notifX0()
  for i, n in ipairs(notifs) do
    if i > NOTIF_MAX then break end
    local y0 = 1 + (i - 1) * (NOTIF_H + 1)
    if y0 + NOTIF_H - 1 <= h - 2 then
      -- Shadow.
      desktopFB:drawShadow(x0, y0, x0 + NOTIF_W - 1, y0 + NOTIF_H - 1, 1, 1, 15)
      -- Body.
      desktopFB:fillRect(x0, y0, x0 + NOTIF_W - 1, y0 + NOTIF_H - 1, " ", 15, 7)
      -- Title bar.
      desktopFB:fillRect(x0, y0, x0 + NOTIF_W - 1, y0, " ", 0, T.panel)
      local title = n.title or ""
      if #title > NOTIF_W - 6 then title = title:sub(1, NOTIF_W - 7) .. "~" end
      desktopFB:drawText(x0 + 1, y0, title, T.text, T.panel)
      desktopFB:drawText(x0 + NOTIF_W - 3, y0, "[X]", T.error, T.panel)
      -- Body line.
      if type(n.body) == "string" and #n.body > 0 then
        local body = n.body
        if #body > NOTIF_W - 4 then body = body:sub(1, NOTIF_W - 5) .. "~" end
        desktopFB:drawText(x0 + 2, y0 + 2, body, 15, 7)
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- Hit tests
-- ----------------------------------------------------------------------------

local function hitIcon(mx, my)
  if mx < ICON_X then return nil end
  local relX = mx - ICON_X
  local cellPitch = ICON_W + ICON_GAP_X
  local col = math.floor(relX / cellPitch)
  if (relX % cellPitch) >= ICON_W then return nil end
  if col < 0 or col >= ICON_COLS then return nil end
  local relY = my - ICON_Y0
  if relY < 0 then return nil end
  local row = math.floor(relY / ICON_PITCH)
  if (relY % ICON_PITCH) >= 3 then return nil end  -- on art rows only
  local idx = row * ICON_COLS + col + 1
  if idx < 1 or idx > #apps then return nil end
  return idx
end

local function startButtonHit(mx, my)
  return my == h and mx >= 1 and mx <= START_W
end

local function trayButtonHit(mx, my)
  if my ~= h then return nil end
  if mx <= START_W then return nil end
  local dateX = math.max(START_W + 4, w - #_cachedDateStr)
  local trayLeft = START_W + 2
  local trayRight = dateX - 3
  if mx < trayLeft or mx > trayRight then return nil end
  local prog = kernel.listRunning()
  local visible = {}
  for _, p in ipairs(prog) do
    if p.title ~= "Login" then visible[#visible + 1] = p end
  end
  if #visible == 0 then return nil end
  local trayTotal = trayRight - trayLeft + 1
  if trayTotal <= 0 then return nil end
  local trayW = math.max(8, math.floor(trayTotal / #visible))
  local idx = math.floor((mx - trayLeft) / trayW) + 1
  if idx < 1 or idx > #visible then return nil end
  return visible[idx]
end

local function menusContains(mx, my)
  local mx1, my1, mx2, my2 = menuRect()
  return mx >= mx1 and mx <= mx2 and my >= my1 and my <= my2
end

local function contextMenuHit(mx, my)
  if not showContextMenu then return nil end
  local menuH = #contextItems + 2
  local mx1, my1 = contextX, contextY
  if mx < mx1 or mx >= mx1 + contextW then return nil end
  if my < my1 + 1 or my >= my1 + menuH - 1 then return nil end
  local idx = my - my1
  if idx < 1 or idx > #contextItems then return nil end
  if contextItems[idx].label == "-" then return nil end
  return idx
end

local function contextMenuHover(mx, my)
  local old = contextMenuIndex
  contextMenuIndex = contextMenuHit(mx, my) or 0
  return old ~= contextMenuIndex
end

local function hitNotification(mx, my)
  local notifs = kernel.readNotifications() or {}
  if #notifs == 0 then return nil end
  local x0 = notifX0()
  for i = 1, math.min(#notifs, NOTIF_MAX) do
    local y0 = 1 + (i - 1) * (NOTIF_H + 1)
    if y0 + NOTIF_H - 1 > h - 2 then return nil end
    if mx == x0 + NOTIF_W - 3 and my == y0 then
      return i
    end
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Launch helper
-- ----------------------------------------------------------------------------

local function launch(desc)
  local opts = {
    title   = desc.title or desc.name,
    x = nil, y = nil,
    w = desc.window_w or 28,
    h = desc.window_h or 12,
  }
  if desc.trusted then opts.trusted = true end
  return kernel.spawn(desc.path, opts)
end

-- ----------------------------------------------------------------------------
-- Full render
-- ----------------------------------------------------------------------------

local function render()
  local now = os.clock()
  local dt  = now - lastRenderClock
  lastRenderClock = now

  -- One-time demo toast on first run.
  if not _demoToastFired then
    _demoToastFired = true
    kernel.notify("Qalcom OS ready",
      "Click [Q] for Start menu, right-click for Settings.", 5)
  end

  desktopFB:beginDraw()

  -- Layers: bottom to top.
  drawWallpaper()
  drawIcons()
  drawStartMenu()
  drawTaskbar()
  drawNotifications()
  drawContextMenu()

  desktopFB:endDraw()
  desktopFB:present()
end

-- ----------------------------------------------------------------------------
-- Click dispatch
-- ----------------------------------------------------------------------------

local function handleClick(button, mx, my)
  -- 1. Notification dismiss.
  if button == 1 then
    local ni = hitNotification(mx, my)
    if ni then
      kernel.dismissNotification(ni)
      render()
      return
    end
  end

  -- 2. Context menu.
  if showContextMenu then
    local ci = contextMenuHit(mx, my)
    if ci then
      local action = contextItems[ci].action
      showContextMenu = false
      contextMenuLastShown = false
      if action == "settings" then
        kernel.spawn("/QalcomOS/Apps/System/main.lua",
                     { title = "System", w = 40, h = 16 })
      elseif action == "about" then
        kernel.spawn("/QalcomOS/Apps/About/main.lua",
                     { title = "About", w = 34, h = 14 })
      elseif action == "reboot" then
        os.reboot()
      end
      return
    else
      showContextMenu = false
      contextMenuLastShown = false
      return
    end
  end

  -- 3. Start menu.
  if showStartMenu then
    if menusContains(mx, my) then
      local mx1, my1, _, my2 = menuRect()
      local idx = my - my1 - 2 + 1
      if idx >= 1 and idx <= #apps then
        menuIndex = idx
        launch(apps[idx])
        showStartMenu = false
        menuIndex = 0
      end
      return
    else
      showStartMenu = false
      menuIndex = 0
      return
    end
  end

  -- 4. Right-click opens context menu.
  if button == 2 then
    local onL = (my == h) and (mx >= 1 and mx <= START_W)
    if not onL and my < h and not hitIcon(mx, my) then
      showContextMenu = true
      contextX, contextY = mx, my
      return
    end
  end

  -- 5. L tile toggles Start menu.
  if startButtonHit(mx, my) and button == 1 then
    showStartMenu = not showStartMenu
    menuIndex = 0
    return
  end

  -- 6. Tray button.
  if my == h then
    local rec = trayButtonHit(mx, my)
    if rec then
      if rec.minimized then kernel.restoreWindow(rec.win_id)
      else                   kernel.focusWindow(rec.win_id)
      end
      return
    end
  end

  -- 7. Icon click.
  local iconIdx = hitIcon(mx, my)
  if iconIdx then
    launch(apps[iconIdx])
    return
  end
end

-- ----------------------------------------------------------------------------
-- Main event loop
-- ----------------------------------------------------------------------------

render()

while true do
  local ev, a, b, c = os.pullEvent()

  if ev == "mouse_click" then
    handleClick(a, b, c)
    render()

  elseif ev == "mouse_move" then
    if showContextMenu then
      if contextMenuHover(b, c) then render() end
    end

  elseif ev == "timer" then
    updateDateTime()
    render()

  elseif ev == "key" then
    if a == keys.escape then
      if showStartMenu then
        showStartMenu = false; menuIndex = 0; render()
      elseif showContextMenu then
        showContextMenu = false; contextMenuLastShown = false; render()
      else
        return
      end
    elseif a == keys.tab then
      showStartMenu = not showStartMenu; render()
    end

  elseif ev == "terminate" then
    return
  end
end
