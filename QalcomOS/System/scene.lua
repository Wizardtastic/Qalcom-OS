--[[
  /QalcomOS/System/scene.lua - GPU-accelerated scene graph (v1.0 CC: Graphics)

  Replaces the old character-cell scene graph with a GPU framebuffer-based
  rendering system. Each scene node draws directly to a GPUFramebuffer.

  Node types:
    * RECT   - filled rectangle (bg colour)
    * TEXT   - single-row text (fg + bg)
    * GRADIENT - vertical gradient fill
    * PANEL  - framed panel with title bar
    * LINE   - line (Bresenham)
    * CIRCLE - circle outline
    * IMAGE  - pixel art from a string grid

  Animations:
    * Motions advance per render() call with dt in seconds.
    * Supports: move (position tween), fade (bg/fg tween), scale, reveal.

  This module is used by the Desktop process and can be used by any
  app that wants declarative UI rendering.
]]--

local M = {}

-- Node kinds
M.RECT     = "rect"
M.TEXT     = "text"
M.GRADIENT = "gradient"
M.PANEL    = "panel"
M.LINE     = "line"
M.CIRCLE   = "circle"

-- Reference to the GPU module is set at init time.
local gpu = nil
local _fb = nil
local _w, _h = 0, 0

-- Initialise the scene module with a GPU framebuffer target.
-- `targetFB` is the GPUFramebuffer that all render() calls will
-- draw into.  If nil, you must pass fb= to each render() call.
function M.init(targetFB)
  -- Use the shared GPU module from api if available, otherwise load fresh.
  local api = dofile("/QalcomOS/System/api.lua")
  gpu = api.gpu or dofile("/QalcomOS/System/gpu.lua")
  _fb = targetFB
  if _fb then
    _w, _h = _fb.w, _fb.h
  end
end

-- Set the target framebuffer.
function M.setTarget(fb)
  _fb = fb
  if fb then _w, _h = fb.w, fb.h end
end

-- ---------------------------------------------------------------------------
-- Node constructors
-- ---------------------------------------------------------------------------

function M.rect(x, y, w, h, bg, fg)
  return {
    kind = M.RECT,
    x = x, y = y, w = w, h = h,
    bg = bg or 0,
    fg = fg or 15,
    _motion = nil, _motionT = 0, _motionDur = 0.001,
  }
end

function M.text(x, y, str, fg, bg)
  return {
    kind = M.TEXT,
    x = x, y = y,
    str = str or "",
    fg  = fg or 15,
    bg  = bg or 0,
    w   = #(str or ""),
    h   = 1,
    _motion = nil,
  }
end

function M.gradient(x, y, w, h, topBg, botBg, fg)
  return {
    kind = M.GRADIENT,
    x = x, y = y, w = w, h = h,
    topBg = topBg or 0,
    botBg = botBg or 9,
    fg = fg or 15,
  }
end

function M.panel(x, y, w, h, title, titleBg, titleFg, bodyBg, active)
  return {
    kind = M.PANEL,
    x = x, y = y, w = w, h = h,
    title   = title or "",
    titleBg = titleBg or 3,
    titleFg = titleFg or 15,
    bodyBg  = bodyBg or 0,
    active  = active ~= false,
  }
end

function M.line(x1, y1, x2, y2, char, fg, bg)
  return {
    kind = M.LINE,
    x1 = x1, y1 = y1, x2 = x2, y2 = y2,
    char = char or " ",
    fg = fg or 15,
    bg = bg or 0,
  }
end

function M.circle(cx, cy, r, char, fg, bg)
  return {
    kind = M.CIRCLE,
    cx = cx, cy = cy, r = r,
    char = char or " ",
    fg = fg or 15,
    bg = bg or 0,
  }
end

-- ---------------------------------------------------------------------------
-- Composition
-- ---------------------------------------------------------------------------

function M.compose(...)
  return { ... }
end

-- ---------------------------------------------------------------------------
-- Animation
-- ---------------------------------------------------------------------------

-- Attach a motion to a node. The motion function receives (node, k)
-- where k goes from 0 to 1 over `dur` seconds. Mutation of node
-- fields (x, y, bg, fg, w, h, etc.) takes effect on the next render.
function M.animate(node, dur, motionFn, onDone)
  node._motion     = motionFn
  node._motionT    = 0
  node._motionDur  = (tonumber(dur) and dur > 0) and dur or 0.001
  node._onDone     = onDone
  return node
end

-- Animate position from (fromX, fromY) to current (x, y).
function M.animateFrom(node, dur, fromX, fromY)
  local startX, startY = fromX or node.x, fromY or node.y
  local endX, endY = node.x, node.y
  node.x, node.y = startX, startY  -- reset to start
  return M.animate(node, dur, function(n, k)
    n.x = startX + (endX - startX) * k
    n.y = startY + (endY - startY) * k
  end)
end

-- Animate fade in (bg colour transitions from bg0 to bg1).
function M.animateFadeIn(node, dur, bg0, bg1)
  bg0 = bg0 or 15
  bg1 = bg1 or node.bg or 0
  node.bg = bg0
  return M.animate(node, dur, function(n, k)
    n.bg = k < 0.5 and bg0 or bg1
  end)
end

-- Cancel any motion on a node.
function M.cancel(node)
  node._motion     = nil
  node._motionT    = nil
  node._motionDur  = nil
  node._onDone     = nil
  return node
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

-- Render a scene of nodes to a GPU framebuffer.
--   fb   : GPUFramebuffer target (defaults to the init() target)
--   scene: list of nodes
--   dt   : delta time in seconds (for animations)
--   clear: whether to clear the fb first (default true)
function M.render(fb, scene, dt, clear)
  fb = fb or _fb
  if not fb then return end
  dt = tonumber(dt) or 0
  clear = clear == nil or clear

  local T = dofile("/QalcomOS/System/api.lua").themeResolved or {}

  fb:beginDraw()

  if clear then
    fb:clear(" ", 15, T.bg or 0)
  end

  for i = 1, #scene do
    local n = scene[i]

    -- Advance motion.
    if n._motion then
      n._motionT = n._motionT + dt
      local k = n._motionT / n._motionDur
      if k > 1 then k = 1 end
      n._motion(n, k)
      if k >= 1 and n._onDone then
        local done = n._onDone
        M.cancel(n)
        done(n)
      end
    end

    -- Render based on kind.
    if n.kind == M.RECT then
      local x = math.floor(n.x + 0.5)
      local y = math.floor(n.y + 0.5)
      fb:fillRect(x, y, x + n.w - 1, y + n.h - 1, " ", n.fg, n.bg)

    elseif n.kind == M.TEXT then
      local x = math.floor(n.x + 0.5)
      local y = math.floor(n.y + 0.5)
      fb:drawText(x, y, n.str, n.fg, n.bg)

    elseif n.kind == M.GRADIENT then
      local x = math.floor(n.x + 0.5)
      local y = math.floor(n.y + 0.5)
      fb:gradientFill(x, y, x + n.w - 1, y + n.h - 1, n.topBg, n.botBg, n.fg)

    elseif n.kind == M.PANEL then
      local x = math.floor(n.x + 0.5)
      local y = math.floor(n.y + 0.5)
      fb:drawPanel(x, y, n.w, n.h, n.title,
                    n.titleBg, n.titleFg,
                    T.border or 15, n.bodyBg, n.active)

    elseif n.kind == M.LINE then
      fb:drawLine(math.floor(n.x1+0.5), math.floor(n.y1+0.5),
                  math.floor(n.x2+0.5), math.floor(n.y2+0.5),
                  n.char, n.fg, n.bg)

    elseif n.kind == M.CIRCLE then
      fb:drawCircle(math.floor(n.cx+0.5), math.floor(n.cy+0.5),
                    math.floor(n.r+0.5), n.char, n.fg, n.bg)
    end
  end

  fb:endDraw()
  fb:present()
end

-- Render to any framebuffer without presenting (for compositing use).
function M.renderToFB(fb, scene, dt, clear)
  fb = fb or _fb
  if not fb then return end
  dt = tonumber(dt) or 0
  clear = clear == nil or clear

  local T = dofile("/QalcomOS/System/api.lua").themeResolved or {}

  fb:beginDraw()
  if clear then
    fb:clear(" ", 15, T.bg or 0)
  end

  for i = 1, #scene do
    local n = scene[i]
    if n._motion then
      n._motionT = n._motionT + dt
      local k = n._motionT / n._motionDur
      if k > 1 then k = 1 end
      n._motion(n, k)
      if k >= 1 and n._onDone then
        local done = n._onDone
        M.cancel(n)
        done(n)
      end
    end
    if n.kind == M.RECT then
      fb:fillRect(math.floor(n.x+0.5), math.floor(n.y+0.5),
                  math.floor(n.x+n.w-1+0.5), math.floor(n.y+n.h-1+0.5),
                  " ", n.fg, n.bg)
    elseif n.kind == M.TEXT then
      fb:drawText(math.floor(n.x+0.5), math.floor(n.y+0.5),
                  n.str, n.fg, n.bg)
    elseif n.kind == M.GRADIENT then
      fb:gradientFill(math.floor(n.x+0.5), math.floor(n.y+0.5),
                      math.floor(n.x+n.w-1+0.5), math.floor(n.y+n.h-1+0.5),
                      n.topBg, n.botBg, n.fg)
    elseif n.kind == M.PANEL then
      fb:drawPanel(math.floor(n.x+0.5), math.floor(n.y+0.5),
                   n.w, n.h, n.title,
                   n.titleBg, n.titleFg,
                   T.border or 15, n.bodyBg, n.active)
    end
  end
  fb:endDraw()
end

return M
