--[[
  /QalcomOS/Apps/About/main.lua - Demo #2: About dialog

  v0.1.1 fixes:
    * Reads _QOS_VERSION / _QOS_CODENAME out of the per-app env
      instead of the absent _G._QOS_VERSION.
    * Layout fits a body of ~12 rows.
    * Routes click events through QOS coordinates correctly.
]]

local qos = _QOS
local w, h = term.getSize()
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()

local function frame()
  term.setBackgroundColor(colors.lightBlue)
  term.setTextColor(colors.white)
  term.setCursorPos(1, 1)
  term.write("--" .. string.rep(" ", w - 4) .. "--")
  for y = 2, h - 1 do
    term.setCursorPos(1, y); term.write("|")
    term.setCursorPos(w, y); term.write("|")
  end
  term.setCursorPos(1, h)
  term.write("--" .. string.rep(" ", w - 4) .. "--")
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
end

local function write_at(x, y, text, fg)
  if fg then term.setTextColor(fg) end
  term.setCursorPos(x, y)
  term.write(text)
  if fg then term.setTextColor(colors.black) end
end

local last_event = "nothing yet"
local function draw()
  frame()
  write_at(3, 3, "Qalcom OS " .. _QOS_VERSION,         colors.yellow)
  write_at(3, 5, "A Windows-like operating system")
  write_at(3, 6, "for ComputerCraft: Tweaked on 1.21.1.")
  write_at(3, 8, "Codename:")
  write_at(14, 8, "\"" .. _QOS_CODENAME .. "\"",      colors.yellow)
  write_at(3, h - 3, "Window: " .. qos.win_id,        colors.gray)
  write_at(3, h - 2, "Last event: " .. last_event,    colors.lightGray)
  write_at(3, h - 1, "Press backspace to close.",    colors.gray)
end

draw()

while true do
  local ev, k1, k2, k3 = os.pullEvent()
  if ev == "key" then
    last_event = "key: " .. tostring(k1)
    if k1 == keys.backspace then return end
    draw()
  elseif ev == "terminate" then
    return
  elseif ev == "mouse_click" then
    last_event = string.format("click btn=%s in-window (%s, %s)",
                               tostring(k1), tostring(k2), tostring(k3))
    draw()
  end
end
