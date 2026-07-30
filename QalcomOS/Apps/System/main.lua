--[[
  /QalcomOS/Apps/System/main.lua - System Settings app (v1.1 Widgets)

  Uses the new pixel-art widget library for tabbed settings interface.
  Renders widgets to a local GPUFramebuffer, then blits to the CC window.
]]--

local qos    = _QOS
local themes = dofile("/QalcomOS/System/themes.lua")
local api    = dofile("/QalcomOS/System/api.lua")
local widgets = dofile("/QalcomOS/System/widgets.lua")
if widgets.setApi then widgets.setApi(api) end

-- Use API colour resolution.
local function idx(c, d) return api.resolveColour(c, d or 0) end
local T = api.themeResolved or api.theme

local w, h = term.getSize()

-- Create a local GPUFramebuffer for widget rendering.
local gpu = api.gpu
if not gpu then
  -- Fallback: load a fresh instance.
  gpu = dofile("/QalcomOS/System/gpu.lua")
end

local fb = gpu.createFramebuffer(w, h, {
  doubleBuffer = true,
  dirtyAlways  = true,
  clearChar    = " ",
  clearBg      = idx(T.panelBg or "#F0F4FF", 0),
  clearFg      = 15,
})

-- State.
local state = {
  themeIdx = themes.normalize(
    (qos.options and qos.options.preset_theme_idx) or themes.load()
  ),
}

-- Content renderer for theme tab.
local function renderThemeTab(f, cx, cy, cw, ch)
  local t = themes.themes[state.themeIdx]
  local accent = idx(T.accent or 4, 4)
  local textCol = idx(T.text or 0, 0)
  local dimCol = idx(T.textDim or 7, 7)
  local bodyBg = idx(T.panelBg or "#F0F4FF", 0)

  f:drawText(cx + 1, cy, "Theme: " .. t.name, accent, bodyBg)
  f:drawText(cx + 1, cy + 1, "(click to preview; SAVE to persist)", dimCol, bodyBg)

  local swW = 10
  local swatchY = cy + 3
  for i, sw in ipairs(themes.themes) do
    local sx = cx + 1 + (i - 1) * 13
    local sel = (i == state.themeIdx)
    local swatchBg = idx(sw.panel or 0, 0)

    f:fillRect(sx, swatchY, sx + swW - 1, swatchY, " ", textCol, swatchBg)
    f:drawText(sx + math.floor(swW / 2) - 3, swatchY, "  " .. sw.name:sub(1, 1) .. "  ", textCol, swatchBg)
    f:drawText(sx + math.floor((swW - #sw.name) / 2), swatchY + 1, sw.name, textCol, bodyBg)

    if sel then
      f:drawRect(sx - 1, swatchY - 1, sx + swW, swatchY + 1, accent, accent)
    end
  end

  f:drawText(cx + 1, cy + ch - 2, "Persists across reboots.", dimCol, bodyBg)
end

-- Content renderer for about tab.
local function renderAboutTab(f, cx, cy, cw, ch)
  local bodyBg = idx(T.panelBg or "#F0F4FF", 0)
  local accent = idx(T.accent or 4, 4)
  local textCol = idx(T.text or 0, 0)
  local dimCol = idx(T.textDim or 7, 7)

  f:drawText(cx + 1, cy, "Qalcom OS " .. tostring(_QOS_VERSION or "?"), accent, bodyBg)
  f:drawText(cx + 1, cy + 1, '"' .. tostring(_QOS_CODENAME or "?") .. '"', textCol, bodyBg)
  f:drawText(cx + 1, cy + 3, "A pixel-perfect operating system", dimCol, bodyBg)
  f:drawText(cx + 1, cy + 4, "for CC:Tweaked with GPU acceleration.", dimCol, bodyBg)
  f:drawText(cx + 1, cy + 6, "App: " .. tostring(_QOS_TITLE or "?"), dimCol, bodyBg)
  f:drawText(cx + 1, cy + 7, "Path: " .. tostring(_QOS_PATH or "?"), dimCol, bodyBg)
  f:drawText(cx + 1, cy + 9, "System v1.1: Widget library", dimCol, bodyBg)
end

-- Create widgets.
local tabPanel = widgets.TabPanel({
  x = 1, y = 1, w = w, h = h - 2,
  tabs = {
    { label = "Theme", content = renderThemeTab },
    { label = "About", content = renderAboutTab },
  },
})

local saveBtn = widgets.Button({
  x = 2, y = h - 1, w = 7, h = 1,
  label = "SAVE",
  style = "pill",
})

local closeBtn = widgets.Button({
  x = 14, y = h - 1, w = 7, h = 1,
  label = "CLOSE",
  style = "flat",
})

-- Render function: draw widgets to FB, then blit to CC window.
local function render()
  fb:beginDraw()

  -- Clear.
  local bodyBg = idx(T.panelBg or "#F0F4FF", 0)
  local textCol = idx(T.text or 0, 0)
  fb:clear(" ", textCol, bodyBg)

  -- Render widgets to the framebuffer.
  tabPanel:render(fb)
  saveBtn:render(fb)
  closeBtn:render(fb)

  fb:endDraw()

  -- Blit FB to the CC window using the built-in render method.
  fb:render(term.current())
end

-- Main loop.
local closeRequested = false

render()

while not closeRequested do
  local ev, a, b, c = os.pullEvent()

  if ev == "mouse_click" then
    -- Track click coords.
    local mx, my = b, c

    -- Dispatch to close button first.
    if closeBtn:contains(mx, my) then
      closeRequested = true
      render()
      return
    end

    -- Dispatch to save button.
    if saveBtn:contains(mx, my) then
      themes.save(state.themeIdx)
      -- Flash "Saved" feedback on the CC window.
      local termW = w
      term.setCursorPos(math.floor((termW - 7) / 2) + 1, h)
      term.setBackgroundColor(colors.lime)
      term.setTextColor(colors.black)
      term.write(" Saved ")
      os.sleep(0.4)
      return
    end

    -- Dispatch to tab panel.
    local tabIdx = tabPanel:tabAt(mx, my)
    if tabIdx and tabIdx ~= tabPanel.activeTab then
      tabPanel.activeTab = tabIdx
      render()
    else
      -- Check swatch clicks.
      if tabPanel.activeTab == 1 then
        -- Compute swatch positions (mirroring renderThemeTab layout).
        local cx = 2
        local swatchY = 4
        local swW = 10
        for i = 1, #themes.themes do
          local sx = cx + (i - 1) * 13
          if my == swatchY and mx >= sx and mx < sx + swW then
            state.themeIdx = i
            render()
            break
          end
        end
      end
    end
  end

  if ev == "key" and a == keys.escape then return end
  if ev == "terminate" then return end
end
