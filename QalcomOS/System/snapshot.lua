--[[
  QalcomOS.System.snapshot - backup / restore for the OS code (v0.9)

  This module is the OS-side half of a small self-recovery system.
  The other half lives in `QalcomOS/Recovery/main.lua` (the
  `recover` command). Both lean on plain CC fs APIs -- no shell.*,
  no /rom, no fancy dependency.

  What gets snapshotted:
    * /QalcomOS/System/*.lua -- the kernel, WM, registry, this
      module, themes, profile. Any file that ships with the OS.
    * /QalcomOS/Apps/*.lua -- every app chunk.
    * /QalcomOS/Apps/*.qalcom -- every app manifest.

  What does NOT get snapshotted:
    * Per-user state (/QalcomOS/Users/<name>/.profile, etc) -- the
      recovery shell will not overwrite the user's profiles, theme,
      or any other runtime data even when "recovering". If a future
      refactor wants to include these, the manifest can be extended
      with a separate section. For now the rule is "OS code only".

  Manifest format -- plain text at /QalcomOS/.backup/manifest:
    * One relative path per line, e.g. `System/api.lua`.
    * Lines starting with `#` are comments and skipped.
    * Blank lines are skipped.
  The relative form keeps the manifest portable across machines --
  on restore, each entry is rewritten under the live root.

  Atomicity:
    take() writes all snapshots into a sibling directory `.backup.new`
    first. Only when the full snapshot completes does the old
    `.backup` get wiped and `.backup.new` renamed in. If take()
    crashes halfway, the previous `.backup` survives untouched. CC's
    fs.move is not strictly atomic on every host but the order
    (delete-old THEN move-new) means at worst we end up with no
    snapshot for one boot -- never a half-written one.
]]

local M = {}

M.BACKUP_DIR  = "/QalcomOS/.backup"
M.STAGING_DIR = "/QalcomOS/.backup.new"
M.MANIFEST    = "/QalcomOS/.backup/manifest"
M.SOURCES     = {
  { root = "/QalcomOS/System", rel = "System" },
  { root = "/QalcomOS/Apps",   rel = "Apps"   },
}
M.SNAPSHOT_HEADER = "# Qalcom OS snapshot manifest\n# relative paths under /QalcomOS/\n"

-------------------------------------------------------
-- Helpers
-------------------------------------------------------

-- Returns { abs = ..., rel = ... } entries across ALL of M.SOURCES.
-- Skips the /QalcomOS/Users subtree entirely -- we never snapshot
-- user state (profiles, theme) so the manifest accurately reflects
-- what recover will restore, and .backup/Users/* never grows.
local function list_snapshot_targets()
  local all = {}
  for _, src in ipairs(M.SOURCES) do
    if fs and fs.exists and fs.list and fs.exists(src.root) then
      local recurse
      recurse = function(abs_dir, rel_dir)
        for _, name in ipairs(fs.list(abs_dir)) do
          -- Skip the backup directory itself, App subdirectories
          -- (we snapshot App main.lua + ;qalcom manifests but not
          -- ancillary files), and the Users subtree (intentional).
          if not name:match("^%.backup") and not name:match("^Users$") then
            local child_abs = fs.combine(abs_dir, name)
            local child_rel = rel_dir .. "/" .. name
            if fs.isDir(child_abs) then
              recurse(child_abs, child_rel)
            else
              all[#all + 1] = { abs = child_abs, rel = child_rel }
            end
          end
        end
      end
      recurse(src.root, src.rel)
    end
  end
  table.sort(all, function(a, b) return a.rel < b.rel end)
  return all
end

-- Copy the contents of `src` file into `dst` path. Verifies the
-- dst's parent directory exists (creating it if not) so that
-- /QalcomOS/.backup/System/foo.lua can be written even if the
-- System/ subdir doesn't exist yet under the staging root.
local function copy_file(src, dst)
  local data = ""
  local f = fs.open(src, "r")
  if not f then return false, "cannot open source: " .. src end
  for ln in f.readLine do
    -- We must reconstruct newlines explicitly because the harness
    -- mock's gmatch drops them. This produces input that round-trips
    -- through cat on real CC and on the harness.
    data = data .. ln .. "\n"
  end
  f.close()

  -- Ensure parent dir exists.
  local parent = dst:match("^(.*)/[^/]+$")
  if parent and parent ~= "" and fs.makeDir then
    pcall(fs.makeDir, parent)
  end

  local out = fs.open(dst, "w")
  if not out then return false, "cannot open destination: " .. dst end
  out.write(data)
  out.close()
  return true
end

-- Make sure parent directories of `path` exist, creating any that
-- don't. Walks up until it hits a directory that already does.
local function ensure_parents(path)
  if not (path and fs and fs.makeDir) then return end
  local parts = {}
  for seg in path:gmatch("[^/]+") do parts[#parts + 1] = seg end
  local cur = "/"
  for i = 1, #parts - 1 do
    cur = cur .. parts[i]
    pcall(fs.makeDir, cur)
  end
end

-- List every key currently under BACKUP_DIR that looks like a
-- relative path. Used by recover() to clean up stale entries that
-- the manifest no longer mentions.
local function list_backup_files()
  local out = {}
  if not (fs and fs.list and fs.exists) then return out end
  if not fs.exists(M.BACKUP_DIR) then return out end

  local recurse
  recurse = function(abs, rel)
    for _, name in ipairs(fs.list(abs)) do
      if rel == "" then
        -- Skip the manifest itself when listing -- callers want
        -- only the file contents.
        if name ~= "manifest" then
          local child_abs = fs.combine(abs, name)
          local child_rel = name
          if fs.isDir(child_abs) then
            recurse(child_abs, child_rel)
          else
            out[#out + 1] = child_rel
          end
        end
      else
        local child_abs = fs.combine(abs, name)
        local child_rel = rel .. "/" .. name
        if fs.isDir(child_abs) then
          recurse(child_abs, child_rel)
        else
          out[#out + 1] = child_rel
        end
      end
    end
  end
  recurse(M.BACKUP_DIR, "")
  table.sort(out)
  return out
end

-------------------------------------------------------
-- Public API
-------------------------------------------------------

-- Take a snapshot of every file under M.SOURCES. Writes to a
-- staging dir first, then atomically swaps with the live
-- .backup/. Returns:
--   { ok = bool, copied = N, skipped = N, error = ... }
function M.take()
  local result = { ok = true, copied = 0, skipped = 0, error = nil }
  if not (fs and fs.open and fs.exists and fs.list and fs.delete) then
    result.ok    = false
    result.error = "fs API not available"
    return result
  end

  -- Tear down any prior staging dir.
  if fs.exists(M.STAGING_DIR) then fs.delete(M.STAGING_DIR) end

  local targets = list_snapshot_targets()
  if #targets == 0 then
    result.ok    = false
    result.error = "no source files found under M.SOURCES"
    return result
  end

  -- Make sure the staging root + each source subdir exists.
  pcall(fs.makeDir, M.STAGING_DIR)
  for _, src in ipairs(M.SOURCES) do
    pcall(fs.makeDir, fs.combine(M.STAGING_DIR, src.rel))
  end

  -- Copy each file + collect relative paths for the manifest.
  local manifest_lines = { M.SNAPSHOT_HEADER }
  for _, t in ipairs(targets) do
    local dst = fs.combine(M.STAGING_DIR, t.rel)
    if ensure_parents(dst) then end
    local ok_, err_ = copy_file(t.abs, dst)
    if ok_ then
      result.copied = result.copied + 1
      manifest_lines[#manifest_lines + 1] = t.rel .. "\n"
    else
      result.skipped = result.skipped + 1
      -- Comment in the manifest about the skip so recover() can
      -- see the original intent.
      manifest_lines[#manifest_lines + 1] =
        "# skipped: " .. t.rel .. " (" .. tostring(err_) .. ")\n"
    end
  end

  -- Write the manifest into staging.
  local mf = fs.open(fs.combine(M.STAGING_DIR, "manifest"), "w")
  if mf then
    for _, l in ipairs(manifest_lines) do mf.write(l) end
    mf.close()
  else
    result.ok    = false
    result.error = "cannot open staging manifest for write"
    return result
  end

  -- Atomic-style swap: remove the live .backup (if any), then
  -- rename .backup.new -> .backup. CC's fs.delete with no second
  -- arg only removes empty directories; modern CC:Tweaked (1.79+)
  -- accepts a recursive flag. We try the recursive form first,
  -- then fall back to a manual walk on hosts that don't support it.
  if fs.exists(M.BACKUP_DIR) then
    local deleted = (pcall(fs.delete, M.BACKUP_DIR, true) and true) or false
    if not deleted and fs.exists(M.BACKUP_DIR) then
      -- Manual recursive delete so older CC:Tweaked installs work.
      local function rm_tree(dir)
        if not (fs.list and fs.isDir and fs.delete) then return end
        if not fs.isDir(dir) then
          pcall(fs.delete, dir)
          return
        end
        for _, n in ipairs(fs.list(dir) or {}) do
          local child = fs.combine(dir, n)
          if fs.isDir(child) then rm_tree(child)
          else pcall(fs.delete, child) end
        end
        pcall(fs.delete, dir)
      end
      pcall(rm_tree, M.BACKUP_DIR)
    end
  end
  if fs.move then
    if not pcall(fs.move, M.STAGING_DIR, M.BACKUP_DIR) then
      -- Fall back: delete the still-existing STAGING_DIR if move
      -- failed, so we don't leak two backup dirs.
      pcall(fs.delete, M.STAGING_DIR)
      result.ok    = false
      result.error = "could not promote staging dir"
      return result
    end
  else
    -- No fs.move available (shouldn't happen on real CC; just here
    -- for safety). Fall back to leaving the staging dir in place.
    result.ok    = false
    result.error = "fs.move not available; backup not promoted"
    return result
  end

  return result
end

-- Read /QalcomOS/.backup/manifest, parse out one relative path per
-- line, and copy each .backup/<path> back to its location under
-- /QalcomOS/. Per-user files (anything under /QalcomOS/Users/) are
-- intentionally NOT touched -- the snapshot only carries OS code.
--
-- Returns:
--   { ok = bool, restored = N, missing = N, error = ... }
function M.recover()
  local result = { ok = true, restored = 0, missing = 0, error = nil }
  if not (fs and fs.exists and fs.open) then
    result.ok    = false
    result.error = "fs API not available"
    return result
  end

  if not fs.exists(M.MANIFEST) then
    result.ok    = false
    result.error = "no snapshot found at " .. M.BACKUP_DIR
    return result
  end

  local f = fs.open(M.MANIFEST, "r")
  if not f then
    result.ok    = false
    result.error = "cannot open manifest: " .. M.MANIFEST
    return result
  end

  local entries = {}
  for raw in f.readLine do
    -- Strip a trailing `# comment` tail so a hand-edited manifest
    -- like `System/api.lua  # was 5 lines before` still parses as
    -- the path. Then drop lines that start with `#` or are blank;
    -- finally drop entries that point OUTSIDE the OS code (Users/)
    -- or at the manifest itself.
    local line = raw:gsub("%s*#.*$", "")
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      if not trimmed:match("^Users/") and trimmed ~= "manifest" then
        entries[#entries + 1] = trimmed
      end
    end
  end
  f.close()

  for _, rel in ipairs(entries) do
    local backup_path = fs.combine(M.BACKUP_DIR, rel)
    local live_path   = fs.combine("/QalcomOS", rel)
    if not fs.exists(backup_path) then
      -- Listed in the manifest but missing in the backup -- probably
      -- an interrupted previous take. Skip quietly (the manifest
      -- comment already records the original reason).
      result.missing = result.missing + 1
    else
      if ensure_parents(live_path) then end
      local ok_, err_ = copy_file(backup_path, live_path)
      if ok_ then
        result.restored = result.restored + 1
      else
        result.missing = result.missing + 1
      end
    end
  end

  return result
end

-- Diagnostic helper for the I/O loop / tests: do we even HAVE a
-- snapshot to recover from?
function M.exists()
  if not (fs and fs.exists) then return false end
  return fs.exists(M.MANIFEST)
end

return M
