--[[
  QalcomOS.System.WM - Window Manager (v1.0 CC: Graphics)

  Hybrid compositing window manager:
    * Desktop (system) windows use a GPU framebuffer for pixel-perfect rendering
    * App windows use standard CC windows (for term.redirect compatibility)
    * WM composites everything onto the screen GPU framebuffer
    * Title bars are drawn directly on the screen framebuffer with GPU primitives

  Rendering pipeline (render()):
    1. Begin draw on screen FB
    2. Gradient wallpaper on screen FB
    3. Composite desktop FB (GPU) onto screen FB (full-bleed)
    4. For each app window (z-order), blit CC window content onto screen FB
    5. Draw title bars on screen FB using GPU primitives (colours, shadows)
    6. End draw and present screen FB to terminal
]]--

local api = dofile("/QalcomOS/System/api.lua")
local gpu = nil

local M = {}

local TITLE_H = 1

M.oTerm   = nil
M.master  = nil
M.windows = {}
M.z_order = {}
M.focused = nil
M.TITLE_H = TITLE_H

M.screenFB = nil   -- root compositing framebuffer
M.desktopFB = nil  -- desktop's GPU framebuffer (system window)

local next_id = 0

-- Initialise.
function M.init(oTerm)
  M.oTerm  = oTerm
  local w, h = oTerm.getSize()

  if not api.isGPUReady then
    api.initGPU()
  end
  gpu = api.gpu

  -- Master CC window (used IF GPU is not available; fallback).
  M.master = window.create(oTerm, 1, 1, w, h, true)
  M.master.setVisible(false)  -- hide master; we render via GPU FB

  -- Screen GPU framebuffer.
  M.screenFB = gpu.createScreen(w, h)
  M.screenFB.dirtyAlways = true

  -- Create the desktop's GPU framebuffer (full-bleed, no title bar).
  M.desktopFB = gpu.createFramebuffer(w, h, {
    doubleBuffer = true,
    dirtyAlways  = false,
    clearChar    = " ",
    clearBg      = api.resolveColour(api.theme.bg or 9, 9),
    clearFg      = 15,
  })

  -- Apply enhanced palette.
  gpu.applyPalette(oTerm, gpu.palettes.default)

  -- Sync palette to master CC window as well.
  for i = 0, 15 do
    local c = gpu.IDX_TO_COLOUR[i]
    local entry = gpu.CORE_PALETTE[i]
    if entry then
      M.master.setPaletteColour(c, entry.r, entry.g, entry.b)
    end
  end

  term.redirect(M.master)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  M.render()
end

-- Create a standard app window using CC window (compatible with term.redirect).
function M.createApp(x, y, w, h, title)
  next_id         = next_id + 1
  local id        = next_id
  local body_y    = y + TITLE_H
  local body_h    = math.max(1, h - TITLE_H)

  -- Create a standard CC window for the app.
  local child = window.create(M.master, x, body_y, w, body_h, true)

  -- Sync palette.
  for i = 0, 15 do
    local c = gpu.IDX_TO_COLOUR[i]
    local entry = gpu.CORE_PALETTE[i]
    if entry and child.setPaletteColour then
      child.setPaletteColour(c, entry.r, entry.g, entry.b)
    end
  end

  M.windows[id] = {
    id       = id,
    x        = x,
    y        = y,
    w        = w,
    h        = h,
    titleH   = TITLE_H,
    bodyY    = body_y,
    bodyH    = body_h,
    title    = title or "Window",
    child    = child,       -- CC window for term.redirect
    pid      = nil,
    dragging = false,
    dragOffX = 0,
    dragOffY = 0,
    minimized = false,
    maximized = false,
    isSystem = false,
    visible  = true,
    fb       = nil,         -- no GPU fb for regular apps
  }

  table.insert(M.z_order, id)
  M.focused = id

  -- Clear.
  child.setBackgroundColor(api.resolveColour(api.theme.panelBg or 0, 0))
  child.setTextColor(colors.black)
  child.clear()

  M.render()
  return id, child
end

-- Create a system window (full-bleed, uses GPU framebuffer).
-- Returns (id, fb) where fb is the GPUFramebuffer for direct GPU rendering.
function M.createSystemWindow(w, h)
  next_id = next_id + 1
  local id = next_id

  -- GPU framebuffer for system apps (desktop).
  local fb = gpu.createFramebuffer(w, h, {
    doubleBuffer = true,
    dirtyAlways  = false,
    clearChar    = " ",
    clearBg      = api.resolveColour(api.theme.bg or 9, 9),
    clearFg      = 15,
  })

  -- Create a minimal CC window stub for API compatibility.
  local stub = window.create(M.master, 1, 1, w, h, false)
  stub.setVisible(false)

  M.windows[id] = {
    id       = id,
    fb       = fb,          -- GPU framebuffer for rendering
    x        = 1,
    y        = 1,
    w        = w,
    h        = h,
    titleH   = 0,
    bodyY    = 1,
    bodyH    = h,
    title    = "",
    child    = stub,        -- CC window stub (invisible)
    pid      = nil,
    dragging = false,
    dragOffX = 0,
    dragOffY = 0,
    minimized = false,
    maximized = false,
    isSystem = true,
    visible  = true,
  }

  -- If this is the first system window, store as desktopFB.
  if not M.desktopFB or id == M.getDesktopId() then
    M.desktopFB = fb
  end

  table.insert(M.z_order, 1, id)
  M.focused = id

  fb:clear(" ", 15, api.resolveColour(api.theme.bg or 9, 9))
  M.render()
  return id, fb
end

-- Get the desktop's window id (the system window at the bottom).
function M.getDesktopId()
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and w.isSystem then return id end
  end
  return nil
end

-- Destroy a window.
function M.destroy(id)
  local w = M.windows[id]
  if not w then return end

  -- Hide the CC window.
  if w.child and w.child.setVisible then
    w.child.setVisible(false)
    w.child.reposition(1, 1, 1, 1)
  end

  for i, v in ipairs(M.z_order) do
    if v == id then table.remove(M.z_order, i); break end
  end
  M.windows[id] = nil

  if M.focused == id then
    M.focused = M.z_order[#M.z_order]
  end

  -- Desktop FB fallback.
  if not M.desktopFB or not M.windows[M.getDesktopId()] then
    M.desktopFB = nil
  end

  M.render()
end

function M.setFocus(id)
  if not M.windows[id] then return end
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

function M.hitTest(mx, my)
  for i = #M.z_order, 1, -1 do
    local w = M.windows[M.z_order[i]]
    if w and w.visible and not w.minimized then
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
    if w and not w.isSystem and w.titleH > 0 and w.visible and not w.minimized then
      if mx >= w.x and mx < w.x + w.w
         and my >= w.y and my < w.y + w.titleH then
        return M.z_order[i]
      end
    end
  end
  return nil
end

-- Button helpers ---
local function btnW()   return 3 end
local function numBtn() return 3 end
local function totalBtnW() return 9 end

local function closeRectOf(w)    return w.x + w.w - 3, w.x + w.w - 1, w.y end
local function maximizeRectOf(w) return w.x + w.w - 6, w.x + w.w - 4, w.y end
local function minimizeRectOf(w) return w.x + w.w - 9, w.x + w.w - 7, w.y end

local function hitBtn(rectFn, mx, my)
  for i = #M.z_order, 1, -1 do
    local w = M.windows[M.z_order[i]]
    if w and not w.isSystem and w.titleH > 0 and w.visible and not w.minimized then
      local x1, x2, y = rectFn(w)
      if mx >= x1 and mx <= x2 and my == y then
        return M.z_order[i]
      end
    end
  end
  return nil
end

function M.closeHit(mx, my)    return hitBtn(closeRectOf, mx, my) end
function M.minimizeHit(mx, my) return hitBtn(minimizeRectOf, mx, my) end
function M.maximizeHit(mx, my) return hitBtn(maximizeRectOf, mx, my) end

function M.minimize(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  w.minimized = true; w.visible = false
  if w.child and w.child.setVisible then w.child.setVisible(false) end
  if M.focused == id then
    M.focused = nil
    for i = #M.z_order, 1, -1 do
      local cand = M.windows[M.z_order[i]]
      if cand and not cand.minimized and not cand.isSystem then
        M.focused = M.z_order[i]; break end
    end
    if not M.focused then M.focused = M.z_order[1] end
  end
  M.render()
end

function M.maximize(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  local sw, sh = M.master.getSize()
  if w.maximized then
    w.maximized = false
    w.x = w.savedX or w.x; w.y = w.savedY or w.y
    w.w = w.savedW or w.w; w.h = w.savedH or w.h
  else
    w.savedX = w.x; w.savedY = w.y
    w.savedW = w.w; w.savedH = w.h
    w.maximized = true
    w.x = 1; w.y = 1
    w.w = sw; w.h = sh - 2
  end
  w.bodyY = w.y + w.titleH; w.bodyH = math.max(1, w.h - w.titleH)
  if w.child and w.child.reposition then
    w.child.reposition(w.x, w.bodyY, w.w, w.bodyH)
  end
  M.render()
end

function M.restore(id)
  local w = M.windows[id]
  if not w or w.isSystem then return end
  if w.minimized then
    w.minimized = false; w.visible = true
    if w.child and w.child.setVisible then w.child.setVisible(true) end
    M.setFocus(id)
  elseif w.maximized then
    M.maximize(id)
  end
end

function M.startDrag(id, mx, my)
  local w = M.windows[id]
  if not w then return end
  w.dragging = true; w.dragOffX = mx - w.x; w.dragOffY = my - w.y
end

function M.updateDrag(id, mx, my)
  local w = M.windows[id]
  if not w or not w.dragging then return end
  local sw, sh = M.screenFB.w, M.screenFB.h
  local nx = math.max(1, math.min(sw - w.w + 1, mx - w.dragOffX))
  local ny = math.max(1, math.min(sh - w.h + 1, my - w.dragOffY))
  w.x = nx; w.y = ny; w.bodyY = ny + w.titleH
  if w.child and w.child.reposition then
    w.child.reposition(nx, w.bodyY)
  end
end

function M.endDrag(id)
  local w = M.windows[id]
  if not w then return end
  w.dragging = false
end

-- ---------------------------------------------------------------------------
-- GPU Compositing Render
-- ---------------------------------------------------------------------------

-- Blit a CC window's content onto a GPU framebuffer row by row.
local function blitWindowToFB(fb, win, dstX, dstY)
  if not win or not win.getLine then return end
  local w, h = win.getSize()

  for line = 1, h do
    local text, fg, bg = api.readLine(win, line)
    if text and #text > 0 then
      local y = dstY + line - 1
      if y >= 1 and y <= fb.h then
        local x = dstX
        local n = math.min(#text, fb.w - x + 1)
        if n > 0 then
          -- Write directly to the framebuffer buffer.
          local buf = fb.back or fb
          local textSlice = text:sub(1, n)
          local fgSlice   = fg and fg:sub(1, n) or string.rep("f", n)
          local bgSlice   = bg and bg:sub(1, n) or string.rep("0", n)

          buf.text[y] = buf.text[y]:sub(1, x - 1) .. textSlice .. buf.text[y]:sub(x + n)
          buf.fg[y]   = (buf.fg[y] or ""):sub(1, x - 1) .. fgSlice .. (buf.fg[y] or ""):sub(x + n)
          buf.bg[y]   = (buf.bg[y] or ""):sub(1, x - 1) .. bgSlice .. (buf.bg[y] or ""):sub(x + n)
          fb.dirty[y] = true
        end
      end
    end
  end
end

function M.render()
  local fb = M.screenFB
  if not fb then return end
  local sw, sh = fb.w, fb.h
  local T = api.themeResolved or api.theme

  fb:beginDraw()

  -- 1. Gradient wallpaper.
  local bgIdx = api.resolveColour(T.bg or 9, 9)
  local bgAltIdx = api.resolveColour(T.bgAlt or "#1A3A5C", 3)
  fb:gradientFill(1, 1, sw, sh, bgAltIdx, bgIdx, 15)

  -- 2. Desktop GPU framebuffer (system window at z=0).
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and w.visible and not w.minimized then
      if w.isSystem and w.fb then
        fb:compositeFast(w.fb, w.x, w.bodyY, 0)
      end
      break  -- only first (system) window
    end
  end

  -- 3. App windows in z-order (skip desktop which we already rendered).
  for _, id in ipairs(M.z_order) do
    local w = M.windows[id]
    if w and w.visible and not w.minimized then
      if not w.isSystem and w.child then
        -- Draw title bar DIRECTLY on the screen FB (above everything).
        local isFocused = (id == M.focused)
        local titleBg   = api.resolveColour(isFocused and T.panel or T.panelX, 3)
        local titleFg   = api.resolveColour(T.text or 0, 0)
        local winX, winY = w.x, w.y

        -- Title bar shadow (below the title row).
        fb:drawShadow(winX, winY, winX + w.w - 1, winY, 0, 1, 15)

        -- Title bar background.
        fb:fillRect(winX, winY, winX + w.w - 1, winY, " ", titleFg, titleBg)

        -- Title text.
        local title = w.title or ""
        local maxTitleW = math.max(1, w.w - totalBtnW() - 2)
        if #title > maxTitleW then title = title:sub(1, maxTitleW - 1) .. "~" end
        fb:drawText(winX + 1, winY, title, titleFg, titleBg)

        -- Window buttons.
        local btnStr = "[_] "
        if w.maximized then btnStr = btnStr .. "[^] " else btnStr = btnStr .. "[#] " end
        btnStr = btnStr .. "[X]"
        fb:drawText(winX + w.w - totalBtnW(), winY, btnStr, titleFg, titleBg)

        -- Blit the app's CC window content onto the screen FB.
        blitWindowToFB(fb, w.child, winX, winY + w.titleH)
      end
    end
  end

  fb:endDraw()
  -- Render to the REAL terminal (M.oTerm), NOT to term.current()
  -- which is bound to the invisible master window.
  fb:render(M.oTerm)
end

function M.renderFull()
  if M.screenFB then M.screenFB:markDirty() end
  M.render()
end

-- Expose for kernel.
M.gpu = gpu

return M
