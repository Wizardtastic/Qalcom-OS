-- os/fsutil.lua — filesystem helpers used across the OS.

local M = {}

-- Read whole file; returns the string or nil + err.
function M.read(path)
    local f, err = fs.open(path, "r")
    if not f then return nil, err end
    local content = f.readAll()
    f.close()
    return content
end

-- Write text to a file atomically (writes via tmp, then fs.move overwrites).
function M.write(path, content)
    -- Make sure parent directory exists.
    local parent = path:match("^(.*)/[^/]+$")
    if parent and #parent > 0 then
        -- mkdir -p style: create each intermediate directory
        local seg, accum = "", ""
        for seg in parent:gmatch("[^/]+") do
            accum = accum .. "/" .. seg
            if not fs.exists(accum) then fs.makeDir(accum) end
        end
    end

    -- CC:T's fs.move overwrites an existing target so we don't lose data on
    -- failure; we still go via a tmp file so a partial write doesn't leave
    -- the real file truncated.
    local tmp = path .. ".tmp"
    local f, err = fs.open(tmp, "w")
    if not f then return false, err end
    f.write(content or "")
    f.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

function M.append(path, content)
    local existing = M.read(path) or ""
    M.write(path, existing .. (content or ""))
end

-- Serialize a Lua table to a "load()-able" script. NOT a JSON-replacement;
-- just produces valid Lua source our auth/registry files can later load with
-- loadfile().
function M.serialize(v, indent)
    indent = indent or ""
    if type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "number" then
        if v ~= v then return "0/0" end
        return tostring(v)
    elseif type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "nil" then
        return "nil"
    elseif type(v) == "table" then
        local pieces = {"{"}
        local n = #v
        for i = 1, n do
            pieces[#pieces+1] = M.serialize(v[i], indent .. "  ")
            pieces[#pieces+1] = ","
        end
        for k, val in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
                pieces[#pieces+1] = "[" .. M.serialize(tostring(k), "") .. "]="
                pieces[#pieces+1] = M.serialize(val, indent .. "  ")
                pieces[#pieces+1] = ","
            end
        end
        pieces[#pieces+1] = "}"
        return table.concat(pieces)
    end
    error("unsupported type " .. type(v))
end

-- Recursive filesystem walk. Calls cb(path, isDir, size) for every entry
-- in the subtree rooted at `root`. If cb returns false, recursion stops.
function M.walk(root, cb)
    if not fs.exists(root) then return end
    local list = fs.list(root)
    if not list then return end
    for _, name in ipairs(list) do
        local p = root .. "/" .. name
        local isDir = fs.isDir(p)
        local size = 0
        if not isDir then
            local f = fs.open(p, "r")
            if f then size = #(f.readAll() or ""); f.close() end
        end
        if cb(p, isDir, size) == false then return end
        if isDir then M.walk(p, cb) end
    end
end

-- Copy a single file or directory tree.
function M.copy(src, dst)
    if not fs.exists(src) then return false, "no source" end
    if fs.isDir(src) then
        if not fs.exists(dst) then fs.makeDir(dst) end
        for _, name in ipairs(fs.list(src)) do
            M.copy(src .. "/" .. name, dst .. "/" .. name)
        end
        return true
    else
        local content = M.read(src)
        if not content then return false, "read failed" end
        return M.write(dst, content)
    end
end

-- Pretty-print directory contents with sizes for the file explorer.
function M.listPretty(path)
    local entries = {}
    if not fs.exists(path) then return entries end
    local list = fs.list(path) or {}
    table.sort(list)
    for _, name in ipairs(list) do
        local p = path .. "/" .. name
        local isDir = fs.isDir(p)
        local size = 0
        if not isDir then
            local f = fs.open(p, "r")
            if f then size = #(f.readAll() or ""); f.close() end
        end
        entries[#entries+1] = {
            name = name,
            path = p,
            isDir = isDir,
            size = size,
        }
    end
    return entries
end

-- "12.3 KB" -> bytes
function M.humanSize(n)
    if n < 1024 then return string.format("%d B", n)
    elseif n < 1024*1024 then return string.format("%.1f KB", n / 1024)
    else return string.format("%.1f MB", n / (1024*1024))
    end
end

-- Make sure a directory and all parents exist.
function M.mkdirp(path)
    if not path or path == "/" or path == "" then return end
    if not fs.exists(path) then fs.makeDir(path) end
end

return M
