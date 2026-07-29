--[[
  /startup.lua - QalcomOS entry point (v0.8 CraftOS-stamp-out)

  This file is loaded by the CC:Tweaked BIOS automatically on
  computer power-up. It delegates to Qalcom OS's own bootstrap; no
  Qalcom chunk depends on CraftOS shell APIs.

  If `/QalcomOS/System/boot.lua` raises during stage-1 setup, we
  fall back to Qalcom OS's own emergency shell at
  `/QalcomOS/Recovery/main.lua`. We never call `shell.run`,
  `shell.exit`, `/rom/programs/shell`, or any other CraftOS-shell
  API. The computer is no longer stranded if Qalcom itself crashes;
  the player can navigate, edit, or reboot without leaving the
  Qalcom OS namespace.

  The on-disk location of this file is still `/startup.lua` because
  that is the path the CC:Tweaked BIOS autoloads on power-up. The
  BIOS autoload is a CC:Tweaked architectural feature, not a
  CraftOS dependency -- it is satisfied regardless of whether
  CraftOS's shell is installed. (See §11 for the rationale.)

  To disable Qalcom OS as the BIOS autoload (for example in a
  workshop test rig), the player renames this file out of the way
  and the BIOS autoload is a no-op (CC's default shell still loads
  via the standard autoload path, not via Qalcom OS).
]]

local BOOT_PATH   = "/QalcomOS/System/boot.lua"
local RECOVERY    = "/QalcomOS/Recovery/main.lua"

local ok, err = pcall(function()
  dofile(BOOT_PATH)
end)

if not ok then
  -- Best-effort: reset the screen so any half-rendered boot frame
  -- doesn't leave the player staring at an unreadable mix of
  -- colours. Uses CC runtime APIs only -- no shell.* call.
  pcall(term.setBackgroundColor, colors.black)
  pcall(term.setTextColor,       colors.white)
  pcall(term.clear)
  pcall(term.setCursorPos,       1, 1)

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  print("Qalcom OS failed to boot.")
  print()
  term.setTextColor(colors.white)
  print("Error: " .. tostring(err))
  print()
  print("Dropping into Qalcom OS Recovery shell. Type 'help' for")
  print("commands, 'reboot' to retry boot, 'exit' to return to host.")
  print()
  print("Press any key to continue...")
  os.pullEvent("key")

  -- pcall the recovery entry, too: a buggy recovery chunk should
  -- not propagate back into the BIOS autoload's error path.
  pcall(dofile, RECOVERY)
end
