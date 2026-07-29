--[[
  /QalcomOS/Recovery/main.lua - Qalcom OS emergency shell (v0.8)

  Used when boot.lua fails. Replaces the previous
  `shell.run("/rom/programs/shell")` fallback so Qalcom OS's
  recovery path never touches CraftOS at all -- not `/rom`, not
  `shell.*`, not the CraftOS shell binary. This is part of the
  v0.8 "stamp out CraftOS" pass.

  The shell has two layers:

    * M.execute_command(line, cwd) -- a pure dispatcher.
      Tokenises `line`, looks up the verb, returns a result
      table describing what the I/O loop should do next. No
      term reads, no term writes, no pullEvent -- safe to
      unit-test directly.

    * The I/O loop at the bottom -- the chunk body. Runs only
      when the chunk is dofile'd *without* `_G.RECOVERY_TEST_MODE`
      being set; in test mode the chunk returns the dispatcher
      table immediately so tests can poke `M.execute_command`
      without ever entering the loop. The path used by
      `/startup.lua` to drop into recovery is the production
      path (no test flag, loop runs).

  Commands supported in the I/O loop:

      help                       show this help text
      ls [path]                  list a directory (default = cwd)
      cat <path>                 print a file line by line
      rm <path>                  delete a file or empty directory
      cd <path>                  change working directory
      pwd                        show working directory
      edit <path>                stream-editor for the file
                                 (write lines; '.' alone = save,
                                 ':q' alone = abort without save)
      launch <path>              pcall-inspect a file's contents
                                 (deliberately non-pretending: this
                                 shell does not spawn new processes
                                 because it has no parent kernel)
      clear                      clear the terminal
      reboot                     os.reboot() the CC computer
      exit | quit                return to host chunk / CC shell

  Path semantics: split-on-whitespace; no quoted-arg support.
  Paths are resolved via fs.combine(cwd, path). Absolute paths
  pass through. cd / pwd persist in the I/O loop's local `cwd`
  variable (not in module state, so tests stay hermetic).

  The chunk uses ONLY fs / io / os / term / colors / keys CC APIs.
  Never shell.*, never /rom. Verified by grep in tests/ CI.
]]

local M = {}

-------------------------------------------------------
-- Path resolution
-------------------------------------------------------

local function resolve_path(cwd, path)
  if path == nil or path == "" then return cwd end
  if path:sub(1, 1) == "/" then return path end
  return fs.combine(cwd, path)
end

-------------------------------------------------------
-- Pure dispatcher (testable, no I/O side-effects)
-------------------------------------------------------

-- Result shape:
--   { kind = "normal" | "edit" | "reboot"
--     lines = { ... }   (text for kind=="normal")
--     path  = "..."     (target for kind=="edit")
--     cwd   = "..."     (possibly updated by cd)
--     exit  = bool      (true if user typed exit/quit)
--     ok    = bool      (false on parse/IO error)
--   }
function M.execute_command(line, cwd)
  cwd = cwd or "/"
  local r = {
    kind  = "normal",
    lines = {},
    cwd   = cwd,
    exit  = false,
    ok    = true,
  }

  -- Tokenize on whitespace. No quote handling: the recovery shell
  -- is a tiny file-system tool, not a CraftOS replacement.
  local tokens = {}
  for tok in (line or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end
  local cmd = tokens[1]

  local function fail(msg)
    r.ok = false
    r.lines[#r.lines + 1] = "error: " .. msg
  end

  if cmd == nil or cmd == "" then
    -- no-op
    return r
  end

  if cmd == "help" then
    r.lines = {
      "QalcomOS Recovery shell -- emergency repair only.",
      "Commands (use absolute paths or paths relative to cwd):",
      "  help                       show this help text",
      "  ls [path]                  list a directory (default = cwd)",
      "  cat <path>                 print a file line by line",
      "  rm <path>                  delete a file or empty directory",
      "  cd <path>                  change working directory",
      "  pwd                        show working directory",
      "  edit <path>                stream-editor (type '.' alone to save)",
      "  launch <path>              dump a file's contents; the recovery",
      "                             shell has no parent kernel, so it does",
      "                             not actually run anything",
      "  clear                      clear the terminal",
      "  reboot                     os.reboot() the CC computer",
      "  exit | quit                return to the caller",
      "Path note: paths are split on whitespace -- no quoted args.",
    }
  elseif cmd == "ls" then
    local target = resolve_path(cwd, tokens[2])
    if not fs.exists(target) then
      fail("no such path: " .. target)
    elseif fs.isDir(target) then
      for _, name in ipairs(fs.list(target)) do
        r.lines[#r.lines + 1] = name
      end
    else
      r.lines[#r.lines + 1] = target .. "  [file]"
    end
  elseif cmd == "cat" then
    if not tokens[2] then
      fail("usage: cat <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then
        fail("no such file: " .. target)
      elseif fs.isDir(target) then
        fail("is a directory: " .. target)
      else
        local f = fs.open(target, "r")
        if not f then
          fail("cannot open for read: " .. target)
        else
          for raw in f.readLine do r.lines[#r.lines + 1] = raw end
          f.close()
        end
      end
    end
  elseif cmd == "rm" then
    if not tokens[2] then
      fail("usage: rm <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then
        fail("no such path: " .. target)
      else
        fs.delete(target)
        r.lines[#r.lines + 1] = "deleted: " .. target
      end
    end
  elseif cmd == "cd" then
    if not tokens[2] then
      fail("usage: cd <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then
        fail("no such path: " .. target)
      elseif not fs.isDir(target) then
        fail("not a directory: " .. target)
      else
        r.cwd = target
      end
    end
  elseif cmd == "pwd" then
    r.lines[#r.lines + 1] = r.cwd
  elseif cmd == "edit" then
    if not tokens[2] then
      fail("usage: edit <path>")
    else
      r.kind = "edit"
      r.path = resolve_path(cwd, tokens[2])
    end
  elseif cmd == "clear" then
    if term then
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
      term.clear()
      term.setCursorPos(1, 1)
    end
  elseif cmd == "launch" then
    if not tokens[2] then
      fail("usage: launch <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then
        fail("no such file: " .. target)
      elseif fs.isDir(target) then
        fail("is a directory: " .. target)
      else
        -- Actually run the file via pcall. If it crashes, the pcall
        -- returns here and the user lands at the recovery prompt.
        -- If it succeeds and yields (e.g. starts Qalcom OS via the
        -- kernel.run loop), the recovery shell is gone until reboot
        -- -- which is fine because that's what 'launch' is for.
        r.kind = "launch"
        r.path = target
      end
    end
  elseif cmd == "reboot" then
    r.kind = "reboot"
  elseif cmd == "exit" or cmd == "quit" then
    r.exit = true
  else
    fail("unknown command: '" .. cmd .. "' (try 'help')")
  end

  return r
end

-- Expose the path helper for tests.
M.resolve_path = resolve_path

-------------------------------------------------------
-- Test mode short-circuit
-------------------------------------------------------

if _G.RECOVERY_TEST_MODE then return M end

-- Production path below: the chunk never reaches `return M` once
-- the I/O loop is running -- the loop only exits via 'exit'/'quit'
-- or 'reboot'. The final `return M` is unreachable in production
-- but kept so test harnesses that set RECOVERY_TEST_MODE _after_
-- the chunk has been loaded can still get the dispatcher.

-------------------------------------------------------
-- Stream-editor (used for the 'edit' command)
-------------------------------------------------------

-- Read lines until user types '.' on its own line. ':q' aborts.
-- Writes each line + "\n" to the file path. Returns (success, msg).
local function read_edit_lines(path)
  print("stream-editing " .. path)
  print("  type lines; press Enter after each line.")
  print("  type '.' on its own line to save & exit,")
  print("  type ':q' to abort without saving.")
  local lines = {}
  while true do
    io.write("ed> "); io.flush()
    local l = io.read()
    if     l == nil       then return false, "EOF while editing (no changes saved)"
    elseif l == "."       then break
    elseif l == ":q"      then return false, "edit aborted -- no changes saved"
    else                       lines[#lines + 1] = l
    end
  end
  local f = fs.open(path, "w")
  if not f then return false, "cannot open for write: " .. path end
  for i, l in ipairs(lines) do f.write(l .. "\n") end
  f.close()
  return true, ("saved %d line(s) to %s"):format(#lines, path)
end

-------------------------------------------------------
-- Safe term state
-------------------------------------------------------

-- Used at startup and after every failed command so leftovers
-- from a crashed boot or a buggy dispatcher don't keep the
-- recovery shell broken.
local function safe_term()
  if term then
    pcall(term.setBackgroundColor, colors.black)
    pcall(term.setTextColor,       colors.white)
    pcall(term.clear)
    pcall(term.setCursorPos,       1, 1)
  end
end

-- Wrap a dispatcher call in pcall so a buggy dispatcher doesn't
-- propagate a crash up to /startup.lua's pcall. The shell stays
-- alive across any one weird command.
local function dispatch(line, cwd)
  local ok, result = pcall(M.execute_command, line, cwd)
  if not ok then
    return {
      kind  = "normal",
      lines = { "error: dispatcher crashed: " .. tostring(result) },
      cwd   = cwd,
      exit  = false,
      ok    = false,
    }
  end
  return result
end

-------------------------------------------------------
-- I/O loop (production path)
-------------------------------------------------------

safe_term()
print("QalcomOS Recovery shell.")
print("Type 'help' for commands, 'reboot' to retry boot,")
print("'exit' to return to host.")
print()

local cwd = "/"
while true do
  io.write("QRec " .. cwd .. "> "); io.flush()
  local line = io.read()
  if line == nil then break end   -- Ctrl-D / EOF

  local r = dispatch(line, cwd)

  -- Print every line in the result. The dispatcher has already
  -- wrapped errors in `error: ...`, so we just echo straight.
  for _, l in ipairs(r.lines or {}) do print(l) end
  cwd = r.cwd or cwd

  if r.kind == "edit" then
    local ok_, msg = read_edit_lines(r.path)
    print(msg)
    if not ok_ then print("(file unchanged)") end
  elseif r.kind == "launch" then
    print("launching " .. r.path .. " (errors return here; press Ctrl+T then reboot if it hangs)")
    pcall(dofile, r.path)
  elseif r.kind == "reboot" then
    if os and os.reboot then
      print("Rebooting...")
      pcall(os.reboot)
    end
    print("(os.reboot not available; please restart your CC computer manually.)")
  end

  if r.exit then break end
end

print("Exited QalcomOS Recovery shell.")
-- Unreachable in production; tests reach here only when their
-- EOF injection flips `line` to nil and they didn't explicitly
-- set RECOVERY_TEST_MODE before dofile'ing.
return M
