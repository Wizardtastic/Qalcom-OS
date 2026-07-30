--[[
  /QalcomOS/Apps/Clock/main.lua - Big clock display (v1.0 CC: Graphics)

  Uses large pixel-art digits for the time display.
  Renders through the standard term API for WM compositing compatibility.
]]--

local w, h = term.getSize()

-- Colour helpers.
local function idx(c)
  local api = _QOS and _QOS._api
  if api and api.resolveColour then return api.resolveColour(c, 0) end
  return c or 0
end

-- Big digit rendering using standard term API.
-- Each digit is 3 chars wide, 3 chars tall.
local DIGIT_ART = {
  ["0"] = { "███", "█ █", "███" },
  ["1"] = { " █ ", " █ ", " █ " },
  ["2"] = { "███", " ██", "███" },
  ["3"] = { "███", "  █", "███" },
  ["4"] = { "█ █", "███", "  █" },
  ["5"] = { "███", "██ ", "███" },
  ["6"] = { "███", "██ ", "███" },
  ["7"] = { "███", "  █", "  █" },
  ["8"] = { "███", "█ █", "███" },
  ["9"] = { "███", "███", "  █" },
}

local function writeCentered(y, text, fg, bg)
  local x = math.floor((w - #text) / 2) + 1
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.setTextColor(fg)
  term.write(text)
end

local function drawTime(hStr, mStr, colonVisible)
  -- Clear.
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.clear()

  -- Background gradient (simplified: color bands).
  for row = 1, h do
    local bg
    if row < h/3 then
      bg = colors.cyan
    elseif row < 2*h/3 then
      bg = colors.lightBlue
    else
      bg = colors.lightGray
    end
    term.setBackgroundColor(bg)
    term.setCursorPos(1, row)
    term.write(string.rep(" ", w))
  end

  -- Draw big digits using block characters with background color.
  local totalW = 3 + 2 + 3 + 2 + 3  -- HH:MM with gaps
  local x0 = math.floor((w - totalW) / 2)
  local y0 = math.floor(h / 2) - 1
  local fg = colors.yellow
  local bg = colors.blue

  local function drawDigitAt(dx, digit)
    local art = DIGIT_ART[digit]
    if not art then return end
    for row = 1, 3 do
      local line = art[row] or "   "
      term.setCursorPos(x0 + dx, y0 + row - 1)
      term.setBackgroundColor(bg)
      term.setTextColor(fg)
      if #line < 3 then line = line .. string.rep(" ", 3 - #line) end
      term.write(line)
    end
  end

  drawDigitAt(0, hStr:sub(1, 1))
  drawDigitAt(4, hStr:sub(2, 2))

  -- Colon (blinking).
  if colonVisible then
    term.setCursorPos(x0 + 8, y0 + 1)
    term.setBackgroundColor(bg); term.setTextColor(fg)
    term.write("█")
    term.setCursorPos(x0 + 8, y0 + 2)
    term.write("█")
  end

  drawDigitAt(11, mStr:sub(1, 1))
  drawDigitAt(15, mStr:sub(2, 2))

  -- Date below.
  local d, m, y = 1, 1, 26
  if os.day then d = os.day() or 1 end
  if os.date then
    local ds = os.date()
    local mo, yr = ds:match("(%a+)%s+(%d%d%d%d)")
    if mo then
      local months = { Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12 }
      m = months[mo:sub(1,3)] or 1
    end
    if yr then y = yr:sub(3,4) end
  end
  local dateStr = string.format("%02d-%02d-%02d", d, m, y)
  writeCentered(y0 + 5, dateStr, colors.gray, colors.lightBlue)
  writeCentered(h - 1, "Backspace closes", colors.lightGray, colors.lightGray)
end

-- Main loop.
local colonOn = true

while true do
  local t = os.time() or 1200
  local hr, min = math.floor(t / 100), t % 100
  if hr > 23 then hr = hr % 24 end
  local hStr = string.format("%02d", hr)
  local mStr = string.format("%02d", min)

  drawTime(hStr, mStr, colonOn)
  colonOn = not colonOn

  local ev, a = os.pullEvent()
  if ev == "key" then
    if a == keys.backspace then return end
    if a == keys.escape then return end
  elseif ev == "terminate" then
    return
  end
  os.sleep(0.5)  -- tick timer
end
