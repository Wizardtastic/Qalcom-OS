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
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w then
      api.blitWindow(w.child, M.master, w.x, w.bodyY)
    end
  end

  -- Title bars always sit above any child content because we draw them
  -- AFTER blitting children, on the master buffer directly. System
  -- windows have no title bar; their child is the full screen.
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and not w.isSystem then
      local bar = " " .. w.title .. " "
      local pad = math.max(0, w.w - #bar)
      local bg  = (id == M.focused) and api.theme.panel or api.theme.panelX
      local fg  = api.theme.text
      M.master.setBackgroundColor(bg)
      M.master.setTextColor(fg)
      M.master.setCursorPos(w.x, w.y)
      M.master.write(bar .. string.rep(" ", pad))
    end
  end

  api.presentMaster(M.master, M.oTerm)
end

return M
