--[[
  QalcomOS.System.kernel - Process supervisor + event pump (v0.1.1)

  v0.1.1 highlights from the v0.1 review:
    * loadfile(path, mode, env) is used instead of the deprecated
      setfenv() / getfenv() pattern.
    * Env exposes _QOS_VERSION / _QOS_CODENAME / _QOS_TITLE.
    * os.sleep is real: the chunk yields "qos_sleep", we schedule an
      os.startTimer, then resume on the matching "timer" event.
    * os.pullEvent(filter) filters correctly: non-matching events are
      queued in P[pid].pending and re-attempted after each delivery.
    * Mouse handling is split into three mutually-exclusive branches.
    * First resume() in spawn() sends no stale args.

  v0.5 addition:
    * M.isSystemProcess(pid) and M.reapDead() exposed for the offline
      test harness. These were always intended to be public; they are
      additive and do not change production behaviour.
]]

local api = dofile("/QalcomOS/System/api.lua")

local M = {}

-- Process registry. P[pid] = {
--   co       : coroutine handle
--   win_id   : WM window id
--   path     : string, for diagnostics
--   title     : string for taskbar display
--   filter   : string|nil  -- current pullEvent filter
--   pending  : list of { event_name, args... } still waiting to be
--              delivered to a future pullEvent() call
--   isSystem : boolean     -- if true, never reaped (e.g. desktop)
-- }
local P        = {}
local next_pid = 1

-- Reserved pid for the always-on desktop taskbar/desktop process. 0 is
-- out of the normal pid range (which starts at 1).
local SYSTEM_PID = 0

local wm           = nil   -- set by init()
local focused_pid  = nil

-- timer_id -> pid awaiting wakeup. Lets us correlate a "timer" event
-- with the chunk that called os.sleep(N).
local pid_for_timer = {}

function M.init(windowManager)
  wm = windowManager
end

-- ---------------------------------------------------------------------------
-- Safe-coroutine helpers
--
-- A registered proc can briefly have proc.co == nil if M.spawn()'s
-- bookkeeping inserts the proc into the P registry before proc.co =
-- coroutine.create(runChunk) is assigned, then a downstream step
-- (loadfile failing, a dofile error) raises before co can land. That
-- orphan would later crash coroutine.status(proc.co) with "bad
-- argument (thread expected, got nil)" the next time the event loop
-- visits it. The helpers below fold that case into the existing
-- reaping path so reap/deliver continue to behave correctly without
-- sprinkling nil-checks at each of the eight access sites.
--
-- Conventions:
--   coStatus() returns the real coroutine.status() for live procs,
--     and the synthetic sentinel "absent" for nil-co. NEVER "dead"
--     -- callers that want "this proc is reap-eligible" should use
--     isReapable() which covers both "absent" and "dead".
-- ---------------------------------------------------------------------------

local function coStatus(proc)
  if not proc or not proc.co then return "absent" end
  return coroutine.status(proc.co)
end

local function isReapable(proc)
  local s = coStatus(proc)
  return s == "absent" or s == "dead"
end

local function coResume(proc, ...)
  if not proc or not proc.co then return false end
  return coroutine.resume(proc.co, ...)
end

-- ---------------------------------------------------------------------------
-- Panic log
--
-- Append-only persistent log written from kernel.spawn's two failure
-- sites (loadfile returning nil + the chunk's first pcall). Goal: a
-- user can boot into Recovery after a black-screen failure and read
-- "what died" without setting breakpoints or rebooting with extra
-- print() statements sprinkled through the code.
--
-- Design notes:
--   * Every fs call is wrapped in pcall -- a half-up state (post-crash,
--     pre-mount) MUST NOT crash the panic-log writer; that would just
--     produce another black screen with no trace.
--   * Time source is os.time() if exposed, decoded as CC's HHMM (e.g.
--     17:53 -> 1753). Anything that doesn't fit is replaced with
--     "??:??" so the line is still parseable downstream.
--   * entries are line-flattened (no embedded newlines), capped at
--     PANIC_DETAIL_MAX chars, mangled to one-line of ASCII so a
--     `cat` in Recovery prints them clean.
--   * Size cap + rotation: when the file exceeds PANIC_FILE_MAX bytes
--     we truncate to the last PANIC_KEEP_LINES entries. Prevents a
--     runaway error loop from filling the disk.
--   * Path is hard-coded here so the log works even before/without
--     the api module's paths table (api.lua isn't always loaded if
--     the spawn itself fails before the dofile(api)).
-- ---------------------------------------------------------------------------

local PANIC_LOG_PATH    = "/QalcomOS/AppData/panic.log"
local PANIC_DETAIL_MAX  = 256
local PANIC_FILE_MAX    = 4096
local PANIC_KEEP_LINES  = 20

-- Byte-by-byte sanitizer for control characters (0x00..0x1F and 0x7F).
-- Lua pattern syntax does NOT support POSIX-style `\d-\d` byte ranges:
-- inside `[...]` each char literal (including escape sequences that
-- Lua doesn't recognise, which become the literal following char)
-- stands on its own, so a pattern like `[%s\0\1-\31]` would silently
-- match only a handful of unrelated characters. Iterate the bytes
-- numerically instead.
local function panicStripCtrl(s, replace)
  replace = replace or "?"
  local out = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    if b < 0x20 or b == 0x7F then
      out[#out + 1] = replace
    else
      out[#out + 1] = string.char(b)
    end
  end
  return table.concat(out)
end

-- Tolerant fs.exists wrapper. CC's fs.exists rarely throws, but a
-- post-crash, pre-mount state is exactly when this writer gets
-- called -- the assumption we don't need ALWAYS holds.
local function panicSafeExists(p)
  if not (fs and fs.exists) then return false end
  local ok, r = pcall(fs.exists, p)
  return ok and r == true
end

local function panicTimeStamp()
  if type(os) ~= "table" or type(os.time) ~= "function" then
    return "??:??"
  end
  local ok, v = pcall(os.time)
  if not ok or type(v) ~= "number" then return "??:??" end
  -- CC canonical: HHMM integer with H < 24 and M < 60. Anything
  -- else (epoch seconds, 0, negative, fractional) is unreadable.
  if v ~= math.floor(v) or v < 0 or v >= 2400 then return "??:??" end
  local h = math.floor(v / 100)
  local m = v - h * 100
  if h < 0 or h > 23 or m < 0 or m > 59 then return "??:??" end
  return string.format("%02d:%02d", h, m)
end

local function panicEnsureDir()
  if not (fs and fs.makeDir) then return end
  pcall(function()
    if not panicSafeExists("/QalcomOS") then
      pcall(fs.makeDir, "/QalcomOS")
    end
    if not panicSafeExists("/QalcomOS/AppData") then
      pcall(fs.makeDir, "/QalcomOS/AppData")
    end
  end)
end

-- If the file is past PANIC_FILE_MAX bytes, rewrite it retaining only
-- the final PANIC_KEEP_LINES lines. Done best-effort inside a pcall
-- so a read error doesn't block the append.
local function panicRotateIfBig()
  if not (fs and fs.getSize and fs.open) then return end
  local size = 0
  if panicSafeExists(PANIC_LOG_PATH) then
    local ok, s = pcall(fs.getSize, PANIC_LOG_PATH)
    if ok and type(s) == "number" then size = s end
  end
  if size <= PANIC_FILE_MAX then return end
  pcall(function()
    local f = fs.open(PANIC_LOG_PATH, "r")
    if not f then return end
    local lines = {}
    for raw in f.readLine do lines[#lines + 1] = raw end
    f.close()
    if #lines <= PANIC_KEEP_LINES then return end
    local start = #lines - PANIC_KEEP_LINES + 1
    local fw = fs.open(PANIC_LOG_PATH, "w")
    if not fw then return end
    for i = start, #lines do fw.write(lines[i] .. "\n") end
    fw.close()
  end)
end

local function panicLog(tag, details)
  -- NEVER raises. This writer runs in failure paths; it must not
  -- produce a *new* failure. Every step below is wrapped.
  tag    = panicStripCtrl(tostring(tag or "unknown"), "_")
  details = panicStripCtrl(tostring(details or ""), "?")
  details = details:gsub("\r", " "):gsub("\n", " | ")
  if #details > PANIC_DETAIL_MAX then
    details = details:sub(1, PANIC_DETAIL_MAX - 1) .. "..."
  end
  local line = string.format("[%s] [%s] %s\n",
                             panicTimeStamp(), tag, details)
  pcall(function()
    panicEnsureDir()
    panicRotateIfBig()
    if not (fs and fs.open) then return end
    local f = fs.open(PANIC_LOG_PATH, "a")
    if not f then return end
    f.write(line)
    f.close()
  end)
end

M.panicLog = panicLog

-- Take a snapshot of the OS code so the Recovery shell can later
-- restore it via `recover`. Called from boot.lua right after a
-- successful spawn of the Login chunk -- the OS is in a known-good
-- state, and any breakage that happens between this point and the
-- user's next boot is recoverable.
--
-- This is a deliberately thin wrapper: the real work (manifest
-- generation, copy, atomic swap) lives in /QalcomOS/System/snapshot.lua
-- where the offline test harness can dofile it directly.
function M.snapshot()
  local snapshot = dofile("/QalcomOS/System/snapshot.lua")
  return snapshot.take()
end

-- Spawn: load the file as a chunk bound to a per-app environment, wrap
-- it in a coroutine, and bind that coroutine to a child window.
function M.spawn(path, options)
  options = options or {}
  local sw, sh = wm.master.getSize()

  local win_id, child, title
  local gpuFB  -- GPUFramebuffer for system processes
  if options.isSystem then
    -- System window is full-bleed; no title bar; no specified geometry.
    title = options.title or "[system]"
    win_id, gpuFB = wm.createSystemWindow(sw, sh)
    child = gpuFB  -- GPU framebuffer IS the child for system processes
  else
    local ww = options.w or math.max(20, math.min(sw - 4, sw - 8))
    local wh = options.h or math.max(10, math.min(sh - 6, sh - 6))
    local wx = options.x or math.floor((sw - ww) / 2) + 1
    local wy = options.y or math.floor((sh - wh) / 2) + 1
    title = options.title or path
    win_id, child = wm.createApp(wx, wy, ww, wh, title)
  end

  local proc = {
    co       = nil,                -- set below
    win_id   = win_id,
    path     = path,
    title    = title,
    filter   = nil,
    pending  = {},
    isSystem = options.isSystem == true,
  }
  wm.windows[win_id].pid = pid  -- placeholder; overridden below

  -- Reserve the SYSTEM_PID slot for the desktop process (the only one
  -- marked isSystem). The regular pid counter is only consumed for
  -- non-system processes so a Login-trusted-pid -> Desktop-handoff ->
  -- next-non-system-spawn sequence gives 1 -> 0 -> 2, not 1 -> 0 -> 3.
  local pid
  if proc.isSystem then
    if P[SYSTEM_PID] then
      error("kernel.spawn: a system process is already running")
    end
    P[SYSTEM_PID] = proc
    pid = SYSTEM_PID
  else
    pid           = next_pid
    next_pid      = next_pid + 1
    P[pid]        = proc
  end
  wm.windows[win_id].pid = pid

  -- App env. Mirrors _G through __index so app code can use any built-in
  -- Lua function. We only shadow os.pullEvent / os.sleep to enable the
  -- kernel's interception.
  local registry = dofile("/QalcomOS/System/registry.lua")
  -- Load the date/time wrapper once per spawn and hand it to the chunk.
  -- Apps reach it via qos.osApi without having to know the dofile path,
  -- AND get a stable surface that never crashes on a missing host API.
  local osApi    = dofile("/QalcomOS/System/osApi.lua")

  local qos_table = {
    win_id    = win_id,
    child     = child,
    pid       = pid,
    registry  = registry,
    osApi     = osApi,
    -- Expose the entire spawn options table so callers can hand off
    -- arbitrary state (theme_idx, locale, target username, etc.)
    -- without having to edit this module every time a new opt lands.
    -- Apps read via `qos.options.<field>`; the legacy
    -- `_QOS.theme_idx = options.theme_idx` shortcut is preserved
    -- so existing chunks continue to work.
    options   = options,
    theme_idx = options.theme_idx,
    -- GPU framebuffer for system processes (so the desktop can
    -- render directly to the GPU buffer the WM composites).
    gpuFB     = gpuFB,
  }
  -- System processes get kernel access -- they need to spawn apps,
  -- focus windows, list running tasks, etc. Regular apps don't.
  -- Trusted apps (e.g. Login running the curtain animation) get a much
  -- narrower surface: kernel.spawn() for spawning, plus a single
  -- qos.resizeSelf() helper that mutates only THIS app's own window
  -- record. We deliberately do NOT publish the WM module so that a
  -- compromised or misbehaving trusted app cannot destroy other
  -- windows or hijack focus.
  if proc.isSystem then
    qos_table.kernel = M
  elseif options.trusted == true then
    qos_table.kernel = M
    qos_table.resizeSelf = function(newOuterH)
      if not wm or not wm.windows or not proc.win_id then return end
      local rec = wm.windows[proc.win_id]
      if not rec then return end
      local h = math.max(2, math.floor(tonumber(newOuterH) or 2))
      rec.h     = h
      rec.bodyH = math.max(1, h - 1)
      -- bodyY stays anchored -> bottom edge of the window moves up as
      -- h decreases, so the user sees the curtain rising while the
      -- desktop underneath is exposed.
      if child and child.reposition then
        child.reposition(rec.x, rec.y, rec.w, h)
      end
    end
  end

  local env = setmetatable({
    _QOS          = qos_table,
    _QOS_VERSION  = api.version,
    _QOS_CODENAME = api.codename,
    _QOS_TITLE    = title,
    _QOS_PATH     = path,
  }, { __index = _G })

  -- pullEvent wrapper: record the filter, yield, return the real event.
  local function pullEventN(filter)
    proc.filter = filter
    -- We allow retries in case the kernel hands us back an empty yield
    -- (defensive — should not normally happen).
    while true do
      local kind, ev, a, b, c, d, e = coroutine.yield("qos_event")
      if kind == "qos_event" then
        proc.filter = nil
        return ev, a, b, c, d, e
      end
    end
  end
  local function pullEventRawN(filter)
    -- v0.1 collapses raw vs filtered CC pull events into one code path.
    return pullEventN(filter)
  end
  local function sleepN(n)
    -- The kernel reads the second yield value back as the duration.
    coroutine.yield("qos_sleep", n or 0)
  end

  env.os = setmetatable({
    pullEvent    = pullEventN,
    pullEventRaw = pullEventRawN,
    sleep        = sleepN,
  }, { __index = os })

  -- Canonical Lua 5.2+ / Cobalt way to bind an env to a chunk.
  local fn, lerr = loadfile(path, "t", env)
  if not fn then
    -- Record the failure so a Recovery-mode user can read the cause.
    -- The panic log writer is pcall-protected and never raises, so
    -- this is always a safe addition even if fs is missing.
    panicLog("loadfile_fail", path .. " :: " .. tostring(lerr))
    -- Orphan procs are tolerated by coStatus / coResume / isReapable
    -- so we don't pre-clean P[pid] here -- the next reap tick will
    -- pick it up naturally. Adding a manual P[pid] = nil here would
    -- risk a double-destroy path if wm.destroy is not idempotent.
    error("kernel.spawn: loadfile failed for '" .. path ..
          "': " .. tostring(lerr))
  end

  local function runChunk()
    local prevTerm = term.current()
    local ok, err  = pcall(function()
      -- For system processes with a GPU framebuffer, we don't
      -- redirect term to child (the child is a GPU FB, not a
      -- CC window). The app renders directly to its GPU FB.
      if not options.isSystem or not gpuFB then
        term.redirect(child)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
      end
      fn()
    end)
    -- Whatever happened, put term back where it was.
    if not options.isSystem or not gpuFB then
      term.redirect(prevTerm)
    end
    if not ok then
      panicLog("chunk_runtime", path .. " :: " .. tostring(err))
      -- Surface error. For GPU apps, use term directly.
      if options.isSystem and gpuFB then
        term.redirect(prevTerm)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(2, 2)
        term.write("System app error in " .. path .. ":")
        term.setCursorPos(2, 3)
        term.write(tostring(err))
      else
        term.redirect(child)
        pcall(function()
          term.setBackgroundColor(colors.red)
          term.setTextColor(colors.white)
          term.clear()
          term.setCursorPos(2, 2)
          term.write("App error in " .. path .. ":")
          term.setCursorPos(2, 3)
          term.write(tostring(err))
        end)
        term.redirect(prevTerm)
      end
    end
  end

  proc.co = coroutine.create(runChunk)
  if not proc.isSystem then
    focused_pid = pid
  end
  wm.setFocus(win_id)

  -- First resume. The chunk will run until it yields or returns. The
  -- yield value isn't meaningful here; we discard it.
  coResume(proc)

  return pid
end

-- Public API used by the desktop process (system) and other apps that
-- request it via their env.

-- List currently-running non-system processes as
-- {pid, title, win_id, minimized, maximized}.
-- Used by the desktop's taskbar.
function M.listRunning()
  local out = {}
  for pid, proc in pairs(P) do
    if pid ~= SYSTEM_PID and not isReapable(proc) then
      local wrec = wm.windows[proc.win_id]
      out[#out + 1] = {
        pid       = pid,
        title     = proc.title or "?",
        win_id    = proc.win_id,
        minimized = wrec and wrec.minimized or false,
        maximized = wrec and wrec.maximized or false,
        focused   = (pid == focused_pid),
      }
    end
  end
  table.sort(out, function(a, b) return a.pid < b.pid end)
  return out
end

-- Focus a specific window id (called from Start Menu / taskbar in the
-- desktop process).
function M.focusWindow(win_id)
  wm.setFocus(win_id)
  local wrec = wm.windows[win_id]
  if wrec and wrec.pid then focused_pid = wrec.pid end
end

-- Minimize a window (hide it; taskbar keeps it listed).
function M.minimizeWindow(win_id)
  local wrec = wm.windows[win_id]
  if not wrec or wrec.isSystem then return end
  wm.minimize(win_id)
  -- Clear focused_pid if we just minimized the focused window so events
  -- stop routing to the hidden coroutine.
  if wrec.pid and wrec.pid == focused_pid then
    focused_pid = nil
  end
end

-- Maximize / restore-toggle a window.
function M.maximizeWindow(win_id)
  local wrec = wm.windows[win_id]
  if not wrec or wrec.isSystem then return end
  wm.maximize(win_id)
end

-- Restore a window from minimized or maximized state.
function M.restoreWindow(win_id)
  local wrec = wm.windows[win_id]
  if not wrec or wrec.isSystem then return end
  wm.restore(win_id)
  -- Re-focus so events route to the restored window.
  if wrec.pid then focused_pid = wrec.pid end
end

-- Terminate a non-system process early (e.g. user clicks taskbar X).
-- Works on Lua 5.2+ (coroutine.kill, raises inside the chunk) and on
-- Lua 5.4 / CC:Tweaked (coroutine.close, marks it dead) so the
-- offline lupa test harness -- which only exposes coroutine.close --
-- can drive the close-button path the same way real ComputerCraft
-- will. Both APIs leave the coroutine in "dead" status, which lets
-- reapAndRefocus() tear the window down on the next pass.
--
-- As a final fallback for hosts that lack BOTH functions (vanilla
-- ComputerCraft Lua 5.1, some test harnesses), we do the teardown
-- ourselves: hide the child window, drop the registry entry, and
-- clear focused_pid. The still-suspended chunk can never receive
-- another event because deliver() early-returns on a missing proc,
-- so it goes silent and gets garbage-collected. Without this
-- fallback, clicking X on those runtimes would look like a no-op --
-- the click reaches wm.closeHit, but reapAndRefocus() only destroys
-- windows whose coroutine.status is "dead", and with no kill API
-- available the chunk stays "suspended" forever.
function M.killProcess(pid)
  local proc = P[pid]
  if not proc or pid == SYSTEM_PID then return false end

  -- Prefer the runtime-provided coroutine terminator. The pcall
  -- wrappers are NOT defensive ritual: LuaJIT's coroutine.kill
  -- raises at the call site for already-dead coroutines (and any
  -- future host could behave the same way), so an un-wrapped call
  -- would propagate that raise back up into M.run and abort boot.
  -- Errors raised INSIDE the chunk by a successful kill/close are
  -- caught separately by runChunk's pcall in spawn(); here we
  -- only care whether the coroutine is now dead.
  local ok = false
  if coroutine.kill then
    pcall(coroutine.kill, proc.co)
    ok = isReapable(proc)
  end
  if not ok and coroutine.close then
    pcall(coroutine.close, proc.co)
    ok = isReapable(proc)
  end

  -- Fallback for hosts that lack BOTH kill APIs (vanilla CC Lua 5.1,
  -- some test harnesses). reapAndRefocus() only removes windows
  -- whose coroutine.status is "dead", so without a kill API the
  -- window would stay open and the X button would look like a no-op.
  -- Delegate to the canonical wm.destroy so this path stays in sync
  -- with future changes to WM (one extra render vs. duplicating the
  -- body inline -- acceptable cost). The chunk is then dropped from
  -- P; deliver() early-returns on missing proc, so the suspended
  -- chunk can never receive another event and gets garbage-collected.
  if not ok then
    wm.destroy(proc.win_id)
    P[pid] = nil
    if focused_pid == pid then focused_pid = nil end
  end

  return true
end

-- Notification queue: apps call M.notify(title, body, ttl) to surface
-- user-visible toasts. The Desktop process polls via
-- M.readNotifications() each frame and renders the active set; entries
-- whose deadline has passed are evicted on read. The queue is
-- capped so a misbehaving caller cannot pin memory.
local _activeNotifications = {}
local MAX_NOTIFICATIONS    = 16

-- Push a new toast. ttl is clamped to [0.5, 60] seconds. Returns the
-- queue index, or nil if the call was malformed (no title).
function M.notify(title, body, ttl)
  if type(title) ~= "string" or #title == 0 then return nil end
  ttl = tonumber(ttl) or 4
  if ttl < 0.5 then ttl = 0.5 end
  if ttl > 60  then ttl = 60  end
  _activeNotifications[#_activeNotifications + 1] = {
    title    = title,
    body     = (type(body) == "string") and body or "",
    deadline = os.clock() + ttl,
  }
  while #_activeNotifications > MAX_NOTIFICATIONS do
    table.remove(_activeNotifications, 1)
  end
  return #_activeNotifications
end

-- Return a stable SNAPSHOT of unexpired notifications as a fresh
-- shallow table. Eviction is internal-only; callers see indices 1..N
-- without surprise shifts underfoot, so multiple readers (or one
-- reader iterating twice in a tick) all see the same view.
function M.readNotifications()
  local now = os.clock()
  local i   = 1
  while i <= #_activeNotifications do
    if _activeNotifications[i].deadline <= now then
      table.remove(_activeNotifications, i)
    else
      i = i + 1
    end
  end
  local out = {}
  for j = 1, #_activeNotifications do
    out[j] = _activeNotifications[j]
  end
  return out
end

-- Drop a specific notification by 1-based index. Returns true if the
-- index was valid (and an entry was removed), false otherwise -- the
-- caller can use this to drive a redraw only when something changed.
function M.dismissNotification(idx)
  if type(idx) ~= "number" then return false end
  if idx < 1 or idx > #_activeNotifications then return false end
  table.remove(_activeNotifications, idx)
  return true
end

-- Wipe the queue. Mainly useful as an admin/debug entry point.
function M.clearNotifications()
  _activeNotifications = {}
end

-- Public reference to the WM so system processes can drive it.
function M.wm() return wm end

-- Is a registered process (or the system slot) the system process?
-- Used by the offline harness to verify the Login -> Desktop hand-off.
function M.isSystemProcess(pid)
  local proc = P[pid]
  return proc ~= nil and proc.isSystem == true
end

-- Has the chunk for this pid ended (returned, errored, or been killed)?
-- Used by the offline harness to verify close-button kills land on
-- the chunk's coroutine. Missing pids count as dead -- the slot has
-- either been reaped or never existed.
function M.isProcDead(pid)
  local proc = P[pid]
  if not proc then return true end
  return isReapable(proc)
end

-- Reap any non-system processes whose coroutines have ended and re-pick
-- focused_pid. Same body as the inner part of kernel.run's reapAndRefocus
-- pass, but exposed so external drivers (e.g. tests) can step the kernel
-- state machine without driving an event.
function M.reapDead()
  for pid, proc in pairs(P) do
    if pid ~= SYSTEM_PID
       and isReapable(proc) then
      wm.destroy(proc.win_id)
      P[pid] = nil
      if focused_pid == pid then focused_pid = nil end
    end
  end
  if focused_pid == nil or P[focused_pid] == nil then
    if P[SYSTEM_PID] then focused_pid = SYSTEM_PID end
  end
  wm.render()
end

-- Recursively deliver an event to a chunk. Honors proc.filter and
-- drains pending events that now match the new filter.
local function deliver(pid, event_name, ...)
  local proc = P[pid]
  if not proc then return end
  if coStatus(proc) ~= "suspended" then return end

  -- Mismatch: buffer.
  if proc.filter and proc.filter ~= event_name then
    proc.pending[#proc.pending + 1] = { event_name, ... }
    return
  end

  local ok, kind, a1, a2, a3 = coResume(
    proc, "qos_event", event_name, ...
  )
  if not ok then
    -- Error inside the chunk: reapAndRefocus() will collect it.
    return
  end

  -- Chunk asked to sleep: schedule a CC timer. We'll resume it from
  -- the matching "timer" event in M.run().
  if kind == "qos_sleep" then
    local dur = tonumber(a1) or 0
    local tid = os.startTimer(math.max(0.05, dur))
    pid_for_timer[tid] = pid
    return
  end
  if kind ~= "qos_event" then
    return
  end

  -- After consuming an event, the chunk probably ran for a while and
  -- re-entered pullEvent with a (possibly different) filter. If we
  -- have buffered events that match, dispatch one into the chunk now.
  if proc.filter then
    for i = 1, #proc.pending do
      local qev = proc.pending[i]
      local qname = qev[1]
      if not proc.filter or qname == proc.filter then
        table.remove(proc.pending, i)
        -- Recursively deliver; deliver() handles resume + cleanup.
        -- Pass spread args except the leading event name.
        return deliver(pid, qname, table.unpack(qev, 2))
      end
    end
    -- No match yet; chunk stays suspended until a matching event arrives.
  end
end

-- Test whether (mx, my) is inside a window. Returns (win_id, region).
local function hitTestWithTitle(mx, my)
  local id = wm.titleHit(mx, my)
  if id then return id, "titlebar" end
  id = wm.hitTest(mx, my)
  if id then return id, "body" end
  return nil, nil
end

-- After every event, reap dead user-level processes and re-pick
-- focused_pid. The system process (desktop) is never reaped even if
-- its coroutine somehow ends -- a missing desktop is a hard error.
local function reapAndRefocus()
  for pid, proc in pairs(P) do
    if pid ~= SYSTEM_PID
       and isReapable(proc) then
      wm.destroy(proc.win_id)
      P[pid] = nil
      if focused_pid == pid then focused_pid = nil end
    end
  end
  -- If we lost the previous focus, hand it back to the desktop so the
  -- taskbar / Start menu / icons keep responding.
  if focused_pid == nil or P[focused_pid] == nil then
    if P[SYSTEM_PID] then focused_pid = SYSTEM_PID end
  end
  wm.render()
end

function M.run()
  while true do
    local event, a, b, c, d, e, f = os.pullEventRaw()

    if event == "terminate" then
      if focused_pid then deliver(focused_pid, "terminate") end
      reapAndRefocus()

    elseif event == "mouse_click" then
      local button, mx, my = a, b, c
      -- Close button takes precedence. Minimize/maximize are checked
      -- next; only the title-bar click path (drag) falls through.
      local close_id = wm.closeHit(mx, my)
      if close_id then
        local wrec = wm.windows[close_id]
        if wrec then
          wm.setFocus(close_id)
          if wrec.pid and not M.isSystemProcess(wrec.pid) then
            M.killProcess(wrec.pid)
          end
        end
      else
        local min_id = wm.minimizeHit(mx, my)
        if min_id then
          M.minimizeWindow(min_id)
        else
          local max_id = wm.maximizeHit(mx, my)
          if max_id then
            M.maximizeWindow(max_id)
          else
            local win_id, region = hitTestWithTitle(mx, my)
            if win_id then
              local wrec = wm.windows[win_id]
              wm.setFocus(win_id)
              focused_pid = wrec.pid
              if region == "titlebar" and button == 1 then
                wm.startDrag(win_id, mx, my)
              end
              deliver(focused_pid, "mouse_click", button,
                      mx - wrec.x + 1, my - wrec.bodyY + 1)
            end
          end
        end
      end
      reapAndRefocus()

    elseif event == "mouse_drag" then
      local button, mx, my = a, b, c
      if focused_pid then
        local wrec = wm.windows[P[focused_pid].win_id]
        if wrec.dragging then
          wm.updateDrag(wrec.id, mx, my)
        else
          deliver(focused_pid, "mouse_drag", button,
                  mx - wrec.x + 1, my - wrec.bodyY + 1)
        end
      end
      reapAndRefocus()

    elseif event == "mouse_up" then
      -- End any in-progress drag operations.
      for _, wrec in pairs(wm.windows) do
        if wrec.dragging then wm.endDrag(wrec.id) end
      end
      -- If released inside the focused window's body, forward to the
      -- focused app as a normal mouse_up event. Coords are computed
      -- relative to the focused window's geometry regardless of which
      -- window the release point was on top of.
      local button, mx, my = a, b, c
      if focused_pid then
        local focused_wid = P[focused_pid].win_id
        local focused_wrec = wm.windows[focused_wid]
        if focused_wrec and wm.hitTest(mx, my) == focused_wid then
          deliver(focused_pid, "mouse_up", button,
                  mx - focused_wrec.x + 1, my - focused_wrec.bodyY + 1)
        end
      end
      reapAndRefocus()

    elseif event == "timer" then
      -- Two timer sources converge here:
      --   1. An os.sleep() inside a chunk. We mapped timer_id -> pid
      --      in pid_for_timer so we can deliver a wakeup to the right
      --      coroutine.
      --   2. Any other os.startTimer call the chunk made directly
      --      through the unwrapped `os.startTimer` (it inherits via
      --      __index). Forward it as a plain "timer" event so chunks
      --      that use CC's native timer API still work.
      local tid = a
      local sleeping_pid = pid_for_timer[tid]
      if sleeping_pid then
        pid_for_timer[tid] = nil
        deliver(sleeping_pid, "timer_resume")
      elseif focused_pid then
        deliver(focused_pid, "timer", a, b, c, d, e)
      end
      reapAndRefocus()

    elseif event == "key" or event == "char" or event == "paste"
        or event == "alarm" or event == "redstone"
        or event == "peripheral" or event == "peripheral_detach"
        or event == "disk" or event == "disk_eject"
        or event == "http_success" or event == "http_failure"
        or event == "modem_message" then
      if focused_pid then
        deliver(focused_pid, event, a, b, c, d, e, f)
      end
      reapAndRefocus()
    end
  end
end

return M
