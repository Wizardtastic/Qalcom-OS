--[[
  /QalcomOS/Apps/Hello/main.lua - Demo application

  v0.1.1: tightened layout so it fits in a body of ~10 rows (the WM
  reserves one row for the title bar, so an OUTER h=11 gives a body
  of 10).
]]

local qos   = _QOS
local w, h  = term.getSize()  -- body dimensions (after WM redirected)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()
term.setCursorPos(1, 1)

-- Frame.
local function frame()
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  term.setCursorPos(1, 1)
  term.write("+" .. string.rep("-", w - 2) .. "+")
  term.setCursorPos(1, h)
  term.write("+" .. string.rep("-", w - 2) .. "+")
  for y = 2, h - 1 do
    term.setCursorPos(1, y); term.write("|")
    term.setCursorPos(w, y); term.write("|")
  end
  term.setBackgroundColor(colors.white)
  term.setCursorPos(1, 2)
end

local function centered(text, y)
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, y)
  term.write(text)
end

frame()
centered("Hello from Qalcom OS!",        3)
centered(string.format("pid = %d  win = %d  body = %dx%d",
                       qos.pid, qos.win_id, w, h), 5)
centered("Click the title bar and drag to move me.", 7)
centered("Press any key to advance,",   h - 3)
centered("backspace to close this app.", h - 2)
centered("last key:",                     h - 1)

local last = "(none)"
local label_pos = w - #last - 2  -- right-aligned on the last row

while true do
  -- Render the "last key" footer in cyan to make state changes visible.
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.cyan)
  term.setCursorPos(2, h - 1)
  term.write("last key: " .. last .. string.rep(" ", w - #last - 11))
  term.setTextColor(colors.black)

  local ev, key = os.pullEvent("key")
  last = tostring(key or "?")
  if key == keys.backspace then
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)
    term.write("Hello closing. Bye!")
    term.setCursorPos(2, 3)
    term.write("pid=" .. qos.pid .. " win=" .. qos.win_id)
    return
  end
end
