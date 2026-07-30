--[[
  /QalcomOS/Apps/TaskManager/main.lua - System task manager (v1.0 CC: Graphics)

  Lists every non-system process with GPU-enhanced styling.
  Selection highlighting, refresh on 'r', [End Task] button.
]]--

local qos      = _QOS
local kernel   = qos.kernel
local w, h     = term.getSize()

term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()

local selectedPid = nil

local function refetch()
  if not kernel or not kernel.listRunning then return {} end
  local ok, list = pcall(kernel.listRunning)
  if not ok or type(list) ~= "table" then return {} end
  return list
end

local procs = refetch()

local function writeRow(y, pid, title, sel)
  term.setCursorPos(1, y)
  if sel then
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
  else
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
  end
  term.write(string.rep(" ", w))
  term.setCursorPos(2, y)
  term.write(string.format("%-5d %s", pid or 0,
    tostring(title or "?"):sub(1, math.max(0, w - 7))))
end

local function render()
  -- Title bar with accent.
  term.setBackgroundColor(colors.cyan)
  term.setTextColor(colors.white)
  term.setCursorPos(1, 1)
  term.write(string.rep(" ", w))
  local label = "Task Manager"
  term.setCursorPos(math.max(1, math.floor((w - #label) / 2) + 1), 1)
  term.write(label)

  -- Column header.
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  term.setCursorPos(1, 2)
  term.write(string.rep(" ", w))
  term.setCursorPos(2, 2)
  term.write(string.format("%-5s %s", "PID", "TITLE"))

  -- Body.
  local rowsAvail = h - 4
  for i = 1, math.min(#procs, rowsAvail) do
    local p = procs[i]
    writeRow(2 + i, p.pid, p.title, p.pid == selectedPid)
  end
  for y = 3 + math.min(#procs, rowsAvail), h - 2 do
    term.setBackgroundColor(colors.white)
    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
  end

  -- Footer.
  term.setBackgroundColor(colors.lightGray)
  term.setCursorPos(1, h - 1)
  term.write(string.rep(" ", w))
  local btn = "[End Task]"
  term.setCursorPos(w - #btn - 1, h - 1)
  if selectedPid then
    term.setTextColor(colors.red)
  else
    term.setTextColor(colors.gray)
  end
  term.write(btn)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(2, h - 1)
  term.write(string.format("%d process%s (r=refresh)", #procs, #procs == 1 and "" or "es"))
end

render()

local function rowAt(my)
  if my < 3 or my > h - 2 then return nil end
  local idx = my - 2
  if idx < 1 or idx > #procs then return nil end
  return idx
end

local function endTaskHit(mx, my)
  if my ~= h - 1 then return false end
  local btn = "[End Task]"
  return mx >= w - #btn - 1 and mx <= w - 2
end

while true do
  local ev, a, b, c = os.pullEvent()
  if ev == "mouse_click" then
    local button, mx, my = a, b, c
    if button == 1 then
      local idx = rowAt(my)
      if idx then
        selectedPid = procs[idx].pid; render()
      elseif endTaskHit(mx, my) and selectedPid then
        pcall(kernel.killProcess, selectedPid)
        selectedPid = nil; procs = refetch(); render()
      end
    end
  elseif ev == "key" then
    if a == keys.r then procs = refetch(); render()
    elseif a == keys.escape then return end
  elseif ev == "terminate" then return end
end
