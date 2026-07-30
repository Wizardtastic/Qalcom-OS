--[[
  /QalcomOS/Apps/About/main.lua - About dialog (v1.0 CC: Graphics)

  GPU-accelerated about dialog with panel frame, gradient title bar,
  and pixel art Qalcom logo.
]]--

local w, h = term.getSize()

-- Try to load GPU.
local gpuAvailable, gpu = pcall(dofile, "/QalcomOS/System/gpu.lua")
if not gpuAvailable then
  -- Legacy fallback.
  term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
  term.setCursorPos(3, 3); term.write("Qalcom OS " .. _QOS_VERSION)
  term.setCursorPos(3, 5); term.write("A Windows-like OS for CC:Tweaked")
  while true do
    local ev, k = os.pullEvent()
    if ev == "key" and k == keys.backspace then return end
    if ev == "terminate" then return end
  end
  return
end

local fb = gpu.createFramebuffer(w, h, {
  doubleBuffer = true, dirtyAlways = false,
  clearChar = " ", clearBg = 0, clearFg = 15,
})

-- Qalcom logo (pixel art).
local LOGO = {
  "  ╔══╗╔══╗╔╗  ╔══╗  ",
  "  ║  ║║  ║║║  ║  ║  ",
  "  ║  ║║  ║║║  ║  ║  ",
  "  ╚══╝╚══╝╚╝  ╚══╝  ",
  "  ╔══╗╔══╗╔══╗╔══╗  ",
  "  ╚══╝╚══╝╚══╝╚══╝  ",
}

-- Resolve colours.
local COL = {
  bg     = gpu.rgbToPaletteIndex(0.15, 0.20, 0.35),  -- deep blue
  panel  = gpu.rgbToPaletteIndex(0.30, 0.55, 0.90),  -- lightBlue
  text   = 0,
  accent = 4,
  dim    = 7,
  bodyBg = 0,
}

local function draw()
  fb:beginDraw()

  -- Background gradient.
  fb:gradientFill(1, 1, w, h, COL.bg, COL.panel, 15)

  -- Logo centered.
  local logoX = math.floor((w - #LOGO[1]) / 2) + 1
  local logoY = 2
  for i, line in ipairs(LOGO) do
    fb:drawText(logoX, logoY + i - 1, line, COL.accent, COL.bg)
  end

  -- Info text.
  local lines = {
    "Qalcom OS " .. _QOS_VERSION .. " \"" .. _QOS_CODENAME .. "\"",
    "",
    "A pixel-perfect OS for CC:Tweaked",
    "Built with the CC: Graphics engine",
    "",
    "Window: " .. tostring(_QOS.win_id),
    "PID: " .. tostring(_QOS.pid),
    "",
    "Backspace closes this window.",
  }

  for i, line in ipairs(lines) do
    local fg = (line == "" and 15) or (line:match("Backspace") and COL.dim) or COL.text
    fb:drawTextCentered(logoY + #LOGO + 1 + i, line, fg, COL.bg)
  end

  fb:endDraw()
  fb:present()
end

draw()

local last_event = "nothing yet"
while true do
  local ev, k1 = os.pullEvent()
  if ev == "key" and k1 == keys.backspace then return end
  if ev == "terminate" then return end
end
