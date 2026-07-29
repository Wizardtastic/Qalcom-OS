--[[
  QalcomOS.System.WM - Window Manager (v0.1.1)

  Owns a master window covering the whole screen and lets the kernel
  spawn child windows inside it. Each child window is divided:

       ┌──────────────────────────┐   <- row w.y      : title bar (drawn by WM on master)
       │  [ Hello ]               │
       ├──────────────────────────┤   <- row w.bodyY  : child window starts here (apps live here)
       │  Hello, world!           │
       │  ...                     │
       └──────────────────────────┘   <- row w.bodyY + w.bodyH - 1

  This way the title bar lives on the master buffer only and apps
  receive a clean (w x bodyH) rectangle to draw into via term.redirect.
]]

local api = dofile("/QalcomOS/System/api.lua")

local M = {}

-- Title bar is exactly one row in v0.1.3 reserved at the top of each
-- window. Kept as a module-level constant so the math is shareable.
local TITLE_H = 1

M.oTerm   = nil
M.master  = nil
M.windows = {}
M.z_order = {}
M.focused = nil
M.TITLE_H = TITLE_H  -- expose for kernel's coord math

local next_id = 0

-- Initialise the window manager. Must be called before any other WM
-- function. Sets up master window, draws an initial wallpaper, and makes
-- the master the active term target.
function M.init(oTerm)
  M.oTerm  = oTerm
  local w, h = oTerm.getSize()
  M.master = window.create(oTerm, 1, 1, w, h, true)

  -- Sync the master's palette so child's getLine() returns the same
  -- colours we want to blit.
  for i = 0, 15 do
    local r, g, b = oTerm.getPaletteColour(2 ^ i)
    M.master.setPaletteColour(2 ^ i, r, g, b)
  end

  term.redirect(M.master)
  -- Reset both background AND foreground so neither shell leftovers
  -- nor default CraftOS colours leak into the first child's view.
  term.setBackgroundColor(api.theme.bg)
  term.setTextColor(api.theme.text)
  term.clear()
  term.setCursorPos(1, 1)

  M.render()
end

-- Create a child window inside the master. (x, y, w, h) describe the
-- OUTER rectangle including the title bar. If options.isSystem is true
-- (or the caller wants a "system window" with no title bar and a
-- forced bottom z-order slot), call M.createSystemWindow instead.
function M.createApp(x, y, w, h, title)
  next_id         = next_id + 1
  local id        = next_id
  local body_y    = y + TITLE_H
  local body_h    = math.max(1, h - TITLE_H)
  local child     = window.create(M.master, x, body_y, w, body_h, true)
  M.windows[id] = {
    id       = id,
    x        = x,
    y        = y,
    w        = w,
    h        = h,                -- OUTER height including title
    titleH   = TITLE_H,
    bodyY    = body_y,           -- absolute master Y where body begins
    bodyH    = body_h,
    title    = title or "Window",
    child    = child,
    pid      = nil,
    dragging = false,
    dragOffX = 0,
    dragOffY = 0,
    isSystem = false,
  }
  table.insert(M.z_order, id)
  M.focused = id
  M.render()
  return id, child
end

-- Create a system window: full-bleed, no title bar, no resize, no drag,
-- pinned at the bottom of z_order. Used by the desktop process. (w, h)
-- are the BODY dimensions (no TITLE_H reservation since TITLE_H = 0).
function M.createSystemWindow(w, h)
  next_id = next_id + 1
  local id = next_id
  local child = window.create(M.master, 1, 1, w, h, true)
  M.windows[id] = {
    id       = id,
    x        = 1,
    y        = 1,
    w        = w,
    h        = h,
    titleH   = 0,
    bodyY    = 1,
    bodyH    = h,
    title    = "",
    child    = child,
    pid      = nil,
    dragging = false,
    dragOffX = 0,
    dragOffY = 0,
    isSystem = true,
  }
  -- System window sits at the bottom of z_order so apps are drawn on
  -- top. Insert at index 1.
  table.insert(M.z_order, 1, id)
  M.focused = id
  M.render()
  return id, child
end

function M.destroy(id)
  local w = M.windows[id]
  if not w then return end
  -- CC windows have no destroy(): hide and shrink them so they never
  -- reappear under a future render. We also do not touch dragging
  -- because M.windows[id] is gone.
  w.child.setVisible(false)
  w.child.reposition(1, 1, 1, 1)
  for i, v in ipairs(M.z_order) do
    if v == id then table.remove(M.z_order, i); break end
  end
  M.windows[id] = nil
  if M.focused == id then
    M.focused = M.z_order[#M.z_order]
  end
  M.render()
end

function M.setFocus(id)
  if not M.windows[id] then return end
  -- System windows are pinned at the bottom of z_order. Refuse to move
  -- them -- their only purpose is the desktop layer.
  if M.windows[id].isSystem then
    M.focused = id
    M.render()
    return
  end
  for i, v in ipairs(M.z_order) do
    if v == id then table.remove(M.z_order, i); break end
  end
  table.insert(M.z_order, id)
  M.focused = id
  M.render()
end

-- Hit-test the BODY region only (excluding the title bar). Apps receive
-- only clicks inside their content area this way; the kernel uses
-- M.titleHit to claim title-bar clicks for dragging/focus.
function M.hitTest(mx, my)
  for i = #M.z_order, 1, -1 do
    local w = M.windows[M.z_order[i]]
    if w then
      if mx >= w.x and mx < w.x + w.w
         and my >= w.bodyY and my < w.bodyY + w.bodyH then
        return M.z_order[i]
      end
    end
  end
  return nil
end

function M.titleHit(mx, my)
  for i = #M.z_order, 1, -1 do
    local w = M.windows[M.z_order[i]]
    -- System windows have no title bar so titleHit never fires for them.
    if w and not w.isSystem and w.titleH > 0 then
      if mx >= w.x and mx < w.x + w.w
         and my >= w.y and my < w.y + w.titleH then
        return M.z_order[i]
      end
    end
  end
  return nil
end

-- The rightmost columns of a non-system title row hold three buttons:
-- minimize [_], maximize [#] (or restore [^]), and close [X].
-- Each button is BTN_W (3) chars wide; three side-by-side consume
-- NUM_BTN * BTN_W (9) columns. The glyph set lives in api.formats
-- so the WM and any app that draws matching chrome stay in lock-step.
local function btnW()   return api.formats.BTN_W   or 3 end
local function numBtn() return api.formats.NUM_BTN or 3 end
local function totalBtnW() return btnW() * numBtn() end

-- Right-to-left layout: close | maximize | minimize
--   close:    w.x + w.w - 3 .. w.x + w.w - 1
--   maximize: w.x + w.w - 6 .. w.x + w.w - 4
--   minimize: w.x + w.w - 9 .. w.x + w.w - 7
local function closeRectOf(w)
  local bw = btnW()
  return w.x + w.w - bw, w.x + w.w - 1, w.y
end

local function maximizeRectOf(w)
  local bw = btnW()
  local tw = totalBtnW()
  return w.x + w.w - tw + bw, w.x + w.w - tw + bw * 2 - 1, w.y
end

local function minimizeRectOf(w)
  local bw = btnW()
  local tw = totalBtnW()
  return w.x + w.w - tw, w.x + w.w - tw + bw - 1, w.y
end

function M.closeButtonRect(id)
  local w = M.windows[id]
  if not w or w.isSystem or w.titleH == 0 then return nil end
  return closeRectOf(w)
end

function M.minimizeButtonRect(id)
  local w = M.windows[id]
  if not w or w.isSystem or w.titleH == 0 then return nil end
  return minimizeRectOf(w)
end

function M.maximizeButtonRect(id)
  local w = M.windows[id]
  if not w or w.isSystem or w.titleH == 0 then return nil end
  return maximizeRectOf(w)
end

local function hitBtn(rectFn, mx, my)
  for i = #M.z_order, 1, -1 do
    local w = M.windows[M.z_order[i]]
    if w and not w.isSystem and w.titleH > 0 then
      local x1, x2, y = rectFn(w)
      if mx >= x1 and mx <= x2 and my == y then
        return M.z_order[i]
      end
    end
  end
  return nil
end

function M.closeHit(mx, my)    return hitBtn(closeRectOf,    mx, my) end
function M.minimizeHit(mx, my) return hitBtn(minimizeRectOf, mx, my) end
function M.maximizeHit(mx, my) return hitBtn(maximizeRectOf, mx, my) end

-- Window state helpers -----------------------------------------------------------------

-- Minimize: hide the child window and mark it. The render pass
-- skips minimized windows entirely so the desktop (or whatever
-- sits beneath) is exposed. The window record stays alive so
-- the taskbar can re-show it later.
function M.minimize(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  w.minimized = true
  w.child.setVisible(false)
  if M.focused == id then
    -- Hand focus to the next visible window on top of the stack.
    M.focused = nil
    for i = #M.z_order, 1, -1 do
      local cand = M.windows[M.z_order[i]]
      if cand and not cand.minimized and not cand.isSystem then
        M.focused = M.z_order[i]
        break
      end
    end
    if not M.focused then M.focused = M.z_order[1] end  -- fall back to desktop
  end
  M.render()
end

-- Maximize: expand the window to fill the screen (leaving room for the
-- 1-row taskbar the desktop draws at the very bottom). The original
-- geometry is saved so a second click on the maximize button (now
-- showing the restore glyph [^]) snaps it back.
function M.maximize(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  local sw, sh = M.master.getSize()
  if w.maximized then
    -- Restore.
    w.maximized = false
    w.x = w.savedX or w.x
    w.y = w.savedY or w.y
    w.w = w.savedW or w.w
    w.h = w.savedH or w.h
  else
    -- Save current geometry, then expand.
    w.savedX = w.x
    w.savedY = w.y
    w.savedW = w.w
    w.savedH = w.h
    w.maximized = true
    w.x = 1
    w.y = 1
    w.w = sw
    w.h = sh - 1  -- leave bottom row for the taskbar
  end
  w.bodyY  = w.y + w.titleH
  w.bodyH  = math.max(1, w.h - w.titleH)
  w.child.reposition(w.x, w.bodyY, w.w, w.bodyH)
  M.render()
end

-- Restore from minimized or maximized state.
function M.restore(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  if w.minimized then
    w.minimized = false
    w.child.setVisible(true)
    M.setFocus(id)
    M.render()
  elseif w.maximized then
    M.maximize(id)  -- toggle back
  end
end

-- Snap-to-edge: called at the end of a drag. If the mouse is close
-- to the left, right, or top screen edge the window is repositioned
-- to fill that half or the whole screen respectively. Returns true
-- if a snap was applied.
function M.snapToEdge(id, mx, my)
  local w = M.windows[id]
  if not w or w.isSystem then return false end
  local sw, sh = M.master.getSize()
  local snapped = false

  -- Top edge -> maximize.
  if my <= 2 and not w.maximized then
    M.maximize(id)
    return true
  end

  -- Left edge -> left half.
  if mx <= 2 then
    w.maximized = false
    w.savedX, w.savedY, w.savedW, w.savedH = nil, nil, nil, nil
    w.x = 1
    w.y = 1
    w.w = math.floor(sw / 2)
    w.h = sh - 1
    snapped = true
  -- Right edge -> right half.
  elseif mx >= sw - 1 then
    w.maximized = false
    w.savedX, w.savedY, w.savedW, w.savedH = nil, nil, nil, nil
    w.w = math.floor(sw / 2)
    w.x = sw - w.w + 1
    w.y = 1
    w.h = sh - 1
    snapped = true
  end

  if snapped then
    w.bodyY = w.y + w.titleH
    w.bodyH = math.max(1, w.h - w.titleH)
    w.child.reposition(w.x, w.bodyY, w.w, w.bodyH)
    M.render()
  end
  return snapped
end

function M.startDrag(id, mx, my)
  local w = M.windows[id]
  if not w then return end
  w.dragging = true
  w.dragOffX = mx - w.x
  w.dragOffY = my - w.y
end

function M.updateDrag(id, mx, my)
  local w = M.windows[id]
  if not w or not w.dragging then return end
  local sw, sh = M.master.getSize()
  -- Clamp so the entire outer window stays on screen.
  local nx = mx - w.dragOffX
  local ny = my - w.dragOffY
  nx = math.max(1, math.min(sw - w.w + 1, nx))
  ny = math.max(1, math.min(sh - w.h + 1, ny))
  w.x      = nx
  w.y      = ny
  w.bodyY  = ny + w.titleH
  w.child.reposition(nx, w.bodyY)
end

function M.endDrag(id)
  local w = M.windows[id]
  if not w then return end
  w.dragging = false
end

function M.render()
  api.drawWallpaper(M.master)

  -- Children, back to front, blitted into their body's region.
  -- Minimized windows are skipped -- their child is hidden and
  -- the desktop (or whatever sits beneath) shows through.
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and not w.minimized then
      api.blitWindow(w.child, M.master, w.x, w.bodyY)
    end
  end

  -- Title bars always sit above any child content because we draw them
  -- AFTER blitting children, on the master buffer directly. System
  -- windows have no title bar; their child is the full screen.
  --
  -- Non-system title bars reserve NUM_BTN * BTN_W columns on the
  -- right for [minimize] [maximize] [close]. The label area is
  -- shrunk so the title text never clips into the button region.
  local tw = totalBtnW()
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and not w.isSystem then
      -- Build the button glyphs. Maximize shows [^] (restore) when
      -- the window is already maximized, [#] otherwise.
      local minG  = api.formats and api.formats.minimizeGlyph or "[_]"
      local maxG  = api.formats and api.formats.maximizeGlyph or "[#]"
      if w.maximized then
        maxG = api.formats and api.formats.restoreGlyph or "[^]"
      end
      local closeG = api.formats and api.formats.closeGlyph or "[X]"
      local buttons = minG .. maxG .. closeG

      local labelMaxW = math.max(0, w.w - tw - 1)
      local bar = " " .. (w.title or "") .. " "
      if #bar > labelMaxW then bar = bar:sub(1, labelMaxW) end
      local pad = math.max(0, w.w - #bar - tw)
      local bg  = (id == M.focused) and api.theme.panel or api.theme.panelX
      local fg  = api.theme.text
      M.master.setBackgroundColor(bg)
      M.master.setTextColor(fg)
      M.master.setCursorPos(w.x, w.y)
      M.master.write(bar .. string.rep(" ", pad) .. buttons)
    end
  end

  api.presentMaster(M.master, M.oTerm)
end

return M
