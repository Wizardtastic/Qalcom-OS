--[[
  QalcomOS.System.boot - Stage-1 bootstrap (v1.0 CC: Graphics)

  Boot flow:
    1. Splash screen on the master window with GPU-accelerated graphics.
    2. Spawn ONLY the Login process (regular, full-screen, trusted).
    3. kernel.run() takes over.
    4. Login shows a centered dialog; on submit it spawns the Desktop
       system process and exits.
]]--

local api = dofile("/QalcomOS/System/api.lua")

-- Initialise GPU subsystem early.
api.initGPU()
local gpu = api.gpu

-- Initialise the widget library with the shared API module.
local widgets = dofile("/QalcomOS/System/widgets.lua")
if widgets and widgets.setApi then
  widgets.setApi(api)
end

local oTerm = term.current()
local w, h = oTerm.getSize()

-- Apply enhanced palette.
api.applyThemePalette(oTerm, "default")

-- Create a splash framebuffer.
local splashFB = gpu.createScreen(w, h)

-- Draw splash on the framebuffer.
splashFB:beginDraw()
api.drawWallpaperFB(splashFB, w, h)

-- Large splash text with shadow effect.
splashFB:drawShadow(1, math.floor(h/2) - 1, w, math.floor(h/2) + 1, 1, 1, 15)

local splashLabel = "Qalcom OS " .. api.version
local subLabel    = "\"" .. api.codename .. "\""

splashFB:drawTextCentered(math.floor(h/2), splashLabel, 4, 9)
splashFB:drawTextCentered(math.floor(h/2) + 2, subLabel, 0, 9)

-- Loading indicator.
splashFB:drawText(3, h - 1, "Booting...", 7, 9)

splashFB:endDraw()
splashFB:present()

os.sleep(0.5)

-- Initialise window manager.
local wm = dofile("/QalcomOS/System/WM.lua")
wm.init(oTerm)

-- Kernel initialisation.
local kernel = dofile("/QalcomOS/System/kernel.lua")
kernel.init(wm)

-- Stage 2: Login.
kernel.spawn(api.paths.apps .. "/Login/main.lua", {
  title   = "Login",
  w       = w,
  h       = h,
  trusted = true,
})

-- Snapshot hook.
local snap_ok
do
  local snap_call_ok, result = pcall(kernel.snapshot)
  if snap_call_ok then snap_ok = result end
end

kernel.run()
