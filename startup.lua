--[[
  /startup.lua - QalcomOS entry point

  This file is loaded by CraftOS's BIOS automatically on computer power-up.
  It loads /QalcomOS/System/boot.lua which finishes Stage-1 setup and then
  hands control to the kernel event loop.

  If Qalcom OS fails to boot we drop back to the default CraftOS shell so
  the computer is never stranded.
]]

local ok, err = pcall(function()
  dofile("/QalcomOS/System/boot.lua")
end)

if not ok then
  -- Best-effort: clear any half-rendered state by reusing CraftOS's
  -- terminal reset behaviour. /rom/programs/shell is a guaranteed file
  -- on every CC:Tweaked installation.
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  printError("Qalcom OS failed to boot: " .. tostring(err))
  print("Press any key to start CraftOS shell...")
  os.pullEvent("key")
  shell.run("/rom/programs/shell")
end
