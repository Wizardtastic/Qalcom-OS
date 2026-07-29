--[[
  QalcomOS.System.boot - Stage-1 bootstrap (v0.3 boot flow)

  The earlier v0.2 boot spawned both Login AND Desktop at the same time,
  which left the user staring at icons instead of a login prompt. v0.3
  fixes this with a strict handoff:

    1. Splash on the master window.
    2. Spawn ONLY the Login process (regular, full-screen, trusted).
    3. kernel.run() takes over. Login shows a centered dialog; once the
       user enters a username and clicks <Login> (or presses Enter),
       Login spawns the Desktop system process and exits.
    4. Desktop owns the rest of the session.

  No Desktop is spawned at this level anymore. Boot returns control to
  the user only after Login hands off.
]]

local api = dofile("/QalcomOS/System/api.lua")

local oTerm = term.current()
api.applyPalette(oTerm)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
term.clear()
term.setCursorPos(1, 1)
print("Qalcom OS " .. api.version .. " \"" .. api.codename .. "\" booting...")

local wm = dofile("/QalcomOS/System/WM.lua")
wm.init(oTerm)

local sw, sh = wm.master.getSize()

-- Splash: paint once on the master, present, then hold briefly so the
-- user registers the brand before the Login UI takes over.
local splashLabel = "Qalcom OS " .. api.version
local subLabel    = "\"" .. api.codename .. "\""
wm.master.setBackgroundColor(colors.cyan)
wm.master.setTextColor(colors.yellow)
wm.master.clear()
wm.master.setCursorPos(math.floor((sw - #splashLabel) / 2) + 1,
                        math.floor(sh / 2))
wm.master.write(splashLabel)
wm.master.setTextColor(colors.white)
wm.master.setCursorPos(math.floor((sw - #subLabel) / 2) + 1,
                        math.floor(sh / 2) + 2)
wm.master.write(subLabel)
api.presentMaster(wm.master, oTerm)
os.sleep(0.3)

local kernel = dofile("/QalcomOS/System/kernel.lua")
kernel.init(wm)

-- Stage 2 (and only stage at boot): Login. The Desktop is launched by
-- the Login app itself once the user submits. Login is "trusted" so it
-- can call kernel.spawn() to start the desktop.
kernel.spawn(api.paths.apps .. "/Login/main.lua", {
  title   = "Login",
  w       = sw,
  h       = sh,
  trusted = true,
})

kernel.run()
