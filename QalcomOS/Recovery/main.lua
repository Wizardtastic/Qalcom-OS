--[[
  /QalcomOS/Recovery/main.lua - Qalcom OS emergency shell (v1.0 CC: Graphics)

  Enhanced with a `gpu` command that shows the GPU framebuffer state
  and palette diagnostics.

  All original commands preserved: help, ls, cat, rm, cd, pwd, edit,
  launch, recover, panic, panic-clear, clear, reboot, exit, quit.
]]--

local M = {}

local function resolve_path(cwd, path)
  if path == nil or path == "" then return cwd end
  if path:sub(1, 1) == "/" then return path end
  return fs.combine(cwd, path)
end

local PANIC_LOG_PATH        = "/QalcomOS/AppData/panic.log"
local PANIC_PREVIEW_LINES   = 50
local PANIC_PREVIEW_COLS    = 160

local function read_panic_log_tail(max_lines)
  if not (fs and fs.exists and fs.open) then return nil end
  if not fs.exists(PANIC_LOG_PATH) then return {} end
  if fs.isDir and fs.isDir(PANIC_LOG_PATH) then return nil end
  local f = fs.open(PANIC_LOG_PATH, "r")
  if not f then return nil end
  local lines = {}
  for raw in f.readLine do
    lines[#lines + 1] = raw
    if max_lines and #lines > max_lines * 4 then
      local drop = math.max(1, #lines - max_lines * 2)
      for _ = 1, drop do table.remove(lines, 1) end
    end
  end
  f.close()
  if max_lines and #lines > max_lines then
    for _ = 1, (#lines - max_lines) do table.remove(lines, 1) end
  end
  return lines
end

local function trim_panic_line(s, max_cols)
  if not s then return "" end
  if #s <= max_cols then return s end
  return "... " .. s:sub(#s - max_cols + 5)
end

-- GPU diagnostics ---
local function gpu_status()
  local lines = {}
  local ok, gpu = pcall(dofile, "/QalcomOS/System/gpu.lua")
  if not ok then
    lines[#lines + 1] = "GPU module: not available (" .. tostring(gpu) .. ")"
    return lines
  end
  lines[#lines + 1] = "GPU module: loaded"
  lines[#lines + 1] = "Palette: " .. (gpu.CORE_PALETTE and "initialised" or "missing")
  if gpu.CORE_PALETTE then
    for i = 0, 15 do
      local e = gpu.CORE_PALETTE[i]
      if e then
        local h = gpu.IDX_TO_COLOUR and gpu.IDX_TO_COLOUR[i] or 0
        lines[#lines + 1] = string.format("  [%x] (%s) R=%.2f G=%.2f B=%.2f",
          i, tostring(h), e.r or 0, e.g or 0, e.b or 0)
      end
    end
  end
  local fb = gpu.getScreen and gpu.getScreen()
  if fb then
    lines[#lines + 1] = string.format("Screen FB: %dx%d", fb.w or 0, fb.h or 0)
    lines[#lines + 1] = string.format("Double-buffer: %s", fb.doubleBuffer and "yes" or "no")
  else
    lines[#lines + 1] = "Screen FB: not created"
  end
  return lines
end

-- Pure dispatcher ---
function M.execute_command(line, cwd)
  cwd = cwd or "/"
  local r = { kind = "normal", lines = {}, cwd = cwd, exit = false, ok = true }

  local tokens = {}
  for tok in (line or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end
  local cmd = tokens[1]

  local function fail(msg)
    r.ok = false; r.lines[#r.lines + 1] = "error: " .. msg
  end

  if cmd == nil or cmd == "" then return r end

  if cmd == "help" then
    r.lines = {
      "QalcomOS Recovery shell -- emergency repair only.",
      "Commands (use absolute paths or paths relative to cwd):",
      "  help              show this help text",
      "  ls [path]         list a directory (default = cwd)",
      "  cat <path>        print a file line by line",
      "  rm <path>         delete a file or empty directory",
      "  mkdir <path>      create an empty directory",
      "  cp <src> <dst>    copy file src to dst",
      "  mv <src> <dst>    move file src to dst",
      "  cd <path>         change working directory",
      "  pwd               show working directory",
      "  edit <path>       stream-editor (type '.' alone to save)",
      "  launch <path>     dofile(path); pcall-protected",
      "  recover           restore OS from /QalcomOS/.backup/",
      "  panic             show kernel boot-failure log",
      "  panic-clear       delete the panic log",
      "  gpu               show GPU/palette diagnostics",
      "  clear             clear the terminal",
      "  reboot            os.reboot()",
      "  exit | quit       return to the caller",
    }
  elseif cmd == "ls" then
    local target = resolve_path(cwd, tokens[2])
    if not fs.exists(target) then fail("no such path: " .. target)
    elseif fs.isDir(target) then
      for _, name in ipairs(fs.list(target)) do r.lines[#r.lines + 1] = name end
    else r.lines[#r.lines + 1] = target .. "  [file]"
    end
  elseif cmd == "cat" then
    if not tokens[2] then fail("usage: cat <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then fail("no such file: " .. target)
      elseif fs.isDir(target) then fail("is a directory: " .. target)
      else
        local f = fs.open(target, "r")
        if not f then fail("cannot open: " .. target)
        else for raw in f.readLine do r.lines[#r.lines + 1] = raw end; f.close() end
      end
    end
  elseif cmd == "rm" then
    if not tokens[2] then fail("usage: rm <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then fail("no such path: " .. target)
      else fs.delete(target); r.lines[#r.lines + 1] = "deleted: " .. target end
    end
  elseif cmd == "cd" then
    if not tokens[2] then fail("usage: cd <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then fail("no such path: " .. target)
      elseif not fs.isDir(target) then fail("not a directory: " .. target)
      else r.cwd = target end
    end
  elseif cmd == "mkdir" then
    if not tokens[2] then fail("usage: mkdir <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if fs.exists(target) then fail("already exists: " .. target)
      elseif fs.makeDir then fs.makeDir(target); r.lines[#r.lines + 1] = "created: " .. target
      else fail("fs.makeDir unavailable") end
    end
  elseif cmd == "cp" then
    if not tokens[2] or not tokens[3] then fail("usage: cp <src> <dst>")
    else
      local src = resolve_path(cwd, tokens[2]); local dst = resolve_path(cwd, tokens[3])
      if not fs.exists(src) then fail("no such source: " .. src)
      elseif fs.isDir(src) then fail("source is a directory: " .. src)
      elseif not fs.copy then fail("fs.copy unavailable")
      else
        local ok_, err_ = pcall(fs.copy, src, dst)
        if not ok_ then fail("copy failed: " .. tostring(err_))
        else r.lines[#r.lines + 1] = "copied: " .. src .. " -> " .. dst end
      end
    end
  elseif cmd == "mv" then
    if not tokens[2] or not tokens[3] then fail("usage: mv <src> <dst>")
    else
      local src = resolve_path(cwd, tokens[2]); local dst = resolve_path(cwd, tokens[3])
      if not fs.exists(src) then fail("no such source: " .. src)
      elseif not fs.move then fail("fs.move unavailable")
      else
        local ok_, err_ = pcall(fs.move, src, dst)
        if not ok_ then fail("move failed: " .. tostring(err_))
        else r.lines[#r.lines + 1] = "moved: " .. src .. " -> " .. dst end
      end
    end
  elseif cmd == "recover" then r.kind = "recover"
  elseif cmd == "gpu" then r.lines = gpu_status()
  elseif cmd == "pwd" then r.lines[#r.lines + 1] = r.cwd
  elseif cmd == "edit" then
    if not tokens[2] then fail("usage: edit <path>")
    else r.kind = "edit"; r.path = resolve_path(cwd, tokens[2]) end
  elseif cmd == "clear" then
    if term then
      term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
      term.clear(); term.setCursorPos(1, 1)
    end
  elseif cmd == "launch" then
    if not tokens[2] then fail("usage: launch <path>")
    else
      local target = resolve_path(cwd, tokens[2])
      if not fs.exists(target) then fail("no such file: " .. target)
      elseif fs.isDir(target) then fail("is a directory: " .. target)
      else r.kind = "launch"; r.path = target end
    end
  elseif cmd == "reboot" then r.kind = "reboot"
  elseif cmd == "panic" then
    local lines = read_panic_log_tail(PANIC_PREVIEW_LINES)
    if lines == nil then fail("cannot read " .. PANIC_LOG_PATH)
    elseif #lines == 0 then r.lines[#r.lines + 1] = "(panic log empty)"
    else
      r.lines[#r.lines + 1] = ("-- last %d entries of %s --"):format(#lines, PANIC_LOG_PATH)
      for _, l in ipairs(lines) do r.lines[#r.lines + 1] = "  " .. l end
    end
  elseif cmd == "panic-clear" then
    if not fs or not fs.exists or not fs.delete then fail("fs.delete unavailable")
    elseif not fs.exists(PANIC_LOG_PATH) then r.lines[#r.lines + 1] = "(no panic log)"
    else fs.delete(PANIC_LOG_PATH); r.lines[#r.lines + 1] = "cleared: " .. PANIC_LOG_PATH end
  elseif cmd == "exit" or cmd == "quit" then r.exit = true
  else fail("unknown command: '" .. cmd .. "' (try 'help')")
  end
  return r
end

M.resolve_path = resolve_path

if _G.RECOVERY_TEST_MODE then return M end

-- Stream-editor ---
local function read_edit_lines(path)
  print("stream-editing " .. path)
  print("  type lines; Enter after each. '.' alone = save, ':q' = abort.")
  local lines = {}
  while true do
    io.write("ed> "); io.flush()
    local l = io.read()
    if l == nil then return false, "EOF (no changes saved)"
    elseif l == "." then break
    elseif l == ":q" then return false, "edit aborted" end
    lines[#lines + 1] = l
  end
  local f = fs.open(path, "w")
  if not f then return false, "cannot open for write: " .. path end
  for i, l in ipairs(lines) do f.write(l .. "\n") end
  f.close()
  return true, ("saved %d line(s) to %s"):format(#lines, path)
end

-- Safe term ---
local function safe_term()
  if term then
    pcall(term.setBackgroundColor, colors.black)
    pcall(term.setTextColor, colors.white)
    pcall(term.clear)
    pcall(term.setCursorPos, 1, 1)
  end
end

local function dispatch(line, cwd)
  local ok, result = pcall(M.execute_command, line, cwd)
  if not ok then
    return { kind = "normal", lines = { "error: " .. tostring(result) }, cwd = cwd, exit = false, ok = false }
  end
  return result
end

-- I/O loop ---
safe_term()
print("QalcomOS Recovery shell (CC: Graphics)")
print("Type 'help' for commands, 'reboot' to retry boot.")
print()

do
  local lines = read_panic_log_tail(PANIC_PREVIEW_LINES)
  if lines and #lines > 0 then
    print("-- Recent panic log (" .. PANIC_LOG_PATH .. ") --")
    local max_cols = PANIC_PREVIEW_COLS
    if term and term.getSize then
      local ok, w = pcall(term.getSize)
      if ok and type(w) == "number" and w > 0 then max_cols = w end
    end
    for i = 1, #lines do print("  " .. trim_panic_line(lines[i], max_cols)) end
    print("-- use 'panic' to refresh, 'panic-clear' to dismiss --")
    print()
  end
end

local cwd = "/"
while true do
  io.write("QRec " .. cwd .. "> "); io.flush()
  local line = io.read()
  if line == nil then break end

  local r = dispatch(line, cwd)
  for _, l in ipairs(r.lines or {}) do print(l) end
  cwd = r.cwd or cwd

  if r.kind == "edit" then
    local ok_, msg = read_edit_lines(r.path); print(msg)
    if not ok_ then print("(file unchanged)") end
  elseif r.kind == "launch" then
    print("launching " .. r.path .. " (Ctrl+T then reboot if it hangs)")
    pcall(dofile, r.path)
  elseif r.kind == "recover" then
    print("recovering from /QalcomOS/.backup/ ...")
    local dofile_ok, snapshot = pcall(dofile, "/QalcomOS/System/snapshot.lua")
    if not dofile_ok or type(snapshot) ~= "table" then
      print("error: recovery module: " .. tostring(snapshot))
    elseif not (snapshot.exists and snapshot.exists()) then
      print("error: no snapshot found")
    else
      local ok_, result = pcall(snapshot.recover)
      if ok_ and result and result.ok then
        print(string.format("restored %d file(s) (%d missing).",
          result.restored or 0, result.missing or 0))
      else
        print("error: " .. tostring(ok_ and (result and result.error or "?") or result))
      end
    end
  elseif r.kind == "reboot" then
    if os and os.reboot then print("Rebooting..."); pcall(os.reboot) end
    print("(os.reboot unavailable; restart manually.)")
  end

  if r.exit then break end
end

print("Exited QalcomOS Recovery shell.")
return M
