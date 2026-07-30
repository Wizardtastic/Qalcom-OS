-- os/run.lua — the kernel entry point.
-- This file is loaded by /startup AFTER all dependencies are wired.
-- Sequence: ensureDirs -> config (with user prefs) -> gfx.init -> boot ->
-- auth.bootstrap -> login -> session.

-- Per-phase diag logger so we can pinpoint which step crashed without a
-- disassembly.  Writes into /os/data/boot.log (one line per phase).
local function bootlog(line)
    pcall(function()
        if not fs.exists("/os/data") then fs.makeDir("/os/data") end
        local f = fs.open("/os/data/boot.log", "a")
        f.write("[" .. (os.epoch and os.epoch("utc") or 0) .. "] " .. line .. "\n")
        f.close()
    end)
end

-- One-line status echo to the COMPUTER's own terminal screen, bypassing
-- any term.redirect() so the user can see boot progress even when gfx
-- is painting on the CC:Graphics pixel surface.
local function bprintln(line)
    pcall(function()
        local native = (term and type(term.native) == "function") and term.native() or nil
        local t = native or term
        if not t or type(t.write) ~= "function" then return end
        t.write(line)
        if type(t.setCursorPos) == "function" and type(t.getCursorPos) == "function" then
            local _, cy = t.getCursorPos()
            t.setCursorPos(1, cy + 1)
        end
    end)
end

bootlog("run.lua: enter")
bprintln("[*] Qalcom OS booting...")

-- require() is wrapped by /startup to (a) handle dashed module names like
-- "os.config" -> /os/config.lua via loadfile and (b) cache results in
-- package.loaded so repeated require() calls return the same module table.
-- That means we can use plain require() here without worrying about CC:T's
-- fragile package.loaders chain.
local function safeLoad(name, label)
    local ok, val = pcall(require, name)
    if not ok then
        bootlog(("run.lua: %s load FAILED: %s"):format(label or name, tostring(val)))
        bprintln("[!] " .. (label or name) .. " load failed: " .. tostring(val))
        error("Qalcom OS: cannot load " .. (label or name) .. " — " .. tostring(val))
    end
    bootlog("run.lua: " .. (label or name) .. " loaded")
    bprintln("[+] " .. (label or name) .. " ready")
    return val
end

local cfg    = safeLoad("os.config",   "config")
local boot   = safeLoad("os.boot",     "boot")
local auth   = safeLoad("os.auth",     "auth")
local login  = safeLoad("os.login",    "login")
local session= safeLoad("os.session",  "session")

cfg.loadUserPrefs()
bootlog("run.lua: user prefs merged")

cfg.ensureDirs()
bootlog("run.lua: ensureDirs complete")

-- graphics module
local gfx = safeLoad("os.gfx", "gfx")

local initOk, msg = pcall(gfx.init, {
    mode = cfg.display.graphicsMode,
})
bootlog("run.lua: gfx.init -> " .. tostring(initOk) .. "  " .. tostring(msg))
bprintln("[+] graphics: " .. tostring(msg))

if not initOk and cfg.display.requireGraphics then
    error("Qalcom OS: CC:Graphics is required but gfx.init failed")
end

-- Per-phase require so a single broken module leaves a clear breadcrumb.
local function safeRequire(mod)
    local _ok, val = pcall(require, mod)
    if not _ok then bootlog("run.lua: require " .. mod .. " FAILED: " .. tostring(val)) end
    return _ok, val
end

boot.show()
bootlog("run.lua: splash shown")
bprintln("[+] splash shown")
auth.bootstrap()
bootlog("run.lua: auth bootstrapped (" .. #auth.list() .. " users)")
bprintln("[+] users ready (" .. #auth.list() .. ")")
bprintln("[*] opening login...")

local function loop()
    while true do
        local user = login.run()
        if not user then return end
        local sOk, sErr = pcall(function()
            session.start(user, gfx, require("os.theme"))
        end)
        if not sOk then
            bootlog("session crashed: " .. tostring(sErr))
            local nOk, notif = safeRequire("os.notifications")
            if nOk then
                notif.push({title = "OS Error", body = tostring(sErr), level="error"})
                sleep(3)
            end
            bprintln("[!] session crashed: " .. tostring(sErr))
        else
            bootlog("session returned (logout/restart/shutdown)")
        end
    end
end

local ok2, err = pcall(loop)
if not ok2 then
    bootlog("kernel halted: " .. tostring(err))
    bprintln("[!] kernel halted: " .. tostring(err))
end
