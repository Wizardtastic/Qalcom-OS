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
  if options.isSystem then
    -- System window is full-bleed; no title bar; no specified geometry.
    title = options.title or "[system]"
    win_id, child = wm.createSystemWindow(sw, sh)
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

  local qos_table = {
    win_id    = win_id,
    child     = child,
    pid       = pid,
    registry  = registry,
    -- Expose the entire spawn options table so callers can hand off
    -- arbitrary state (theme_idx, locale, target username, etc.)
    -- without having to edit this module every time a new opt lands.
    -- Apps read via `qos.options.<field>`; the legacy
    -- `_QOS.theme_idx = options.theme_idx` shortcut is preserved
    -- so existing chunks continue to work.
    options   = options,
    theme_idx = options.theme_idx,
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
    error("kernel.spawn: loadfile failed for '" .. path ..
          "': " .. tostring(lerr))
  end

  local function runChunk()
    local prevTerm = term.current()
    local ok, err  = pcall(function()
      term.redirect(child)
      term.setBackgroundColor(colors.white)
      term.setTextColor(colors.black)
      term.clear()
      term.setCursorPos(1, 1)
      fn()
    end)
    -- Whatever happened, put term back where it was.
    term.redirect(prevTerm)
    if not ok then
      -- Surface error inside the child's window. The window will be
      -- reaped on the next reapAndRefocus() pass.
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

  proc.co = coroutine.create(runChunk)
  if not proc.isSystem then
    focused_pid = pid
  end
  wm.setFocus(win_id)

  -- First resume. The chunk will run until it yields or returns. The
  -- yield value isn't meaningful here; we discard it.
  coroutine.resume(proc.co)

  return pid
end

-- Public API used by the desktop process (system) and other apps that
-- request it via their env.

-- List currently-running non-system processes as {pid, title, win_id}.
-- Used by the desktop's taskbar.
function M.listRunning()
  local out = {}
  for pid, proc in pairs(P) do
    if pid ~= SYSTEM_PID and coroutine.status(proc.co) ~= "dead" then
      out[#out + 1] = {
        pid    = pid,
        title  = proc.title or "?",
        win_id = proc.win_id,
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

-- Terminate a non-system process early (e.g. user clicks taskbar X).
-- Works on both Lua 5.2+ (coroutine.kill, raises inside the chunk) and
-- Lua 5.4 (coroutine.close, marks it dead) so the offline lupa test
-- harness -- which only exposes coroutine.close -- can drive the
-- close-button path the same way real ComputerCraft will.
function M.killProcess(pid)
  local proc = P[pid]
  if not proc or pid == SYSTEM_PID then return false end
  if coroutine.kill then
    return pcall(coroutine.kill, proc.co) ~= false
  end
  if coroutine.close then
    return pcall(coroutine.close, proc.co) ~= false
  end
  return false
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
  return coroutine.status(proc.co) == "dead"
end

-- Reap any non-system processes whose coroutines have ended and re-pick
-- focused_pid. Same body as the inner part of kernel.run's reapAndRefocus
-- pass, but exposed so external drivers (e.g. tests) can step the kernel
-- state machine without driving an event.
function M.reapDead()
  for pid, proc in pairs(P) do
    if pid ~= SYSTEM_PID
       and coroutine.status(proc.co) == "dead" then
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
  if coroutine.status(proc.co) ~= "suspended" then return end

  -- Mismatch: buffer.
  if proc.filter and proc.filter ~= event_name then
    proc.pending[#proc.pending + 1] = { event_name, ... }
    return
  end

  local ok, kind, a1, a2, a3 = coroutine.resume(
    proc.co, "qos_event", event_name, ...
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
       and coroutine.status(proc.co) == "dead" then
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
      -- Close button takes precedence. titleHit would otherwise claim
      -- the same row, but we want a single click to kill, not to start
      -- a drag-then-release sequence. Routing closeHit first is the
      -- only place that has access to the close-button enlargement
      -- (titleHit / hitTest return the window regardless of region).
      local close_id = wm.closeHit(mx, my)
      if close_id then
        local wrec = wm.windows[close_id]
        if wrec then
          -- Refocus first so the visual click target lines up with
          -- the kill (avoids a frame where the click changes nothing).
          wm.setFocus(close_id)
          if wrec.pid and not M.isSystemProcess(wrec.pid) then
            M.killProcess(wrec.pid)
          end
        end
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
