-- os/crash.lua — shared crash screen module.
-- Paints a full-screen red banner with the error message, then allows
-- the user to scroll through the full traceback from a log file.
-- Designed to be called from both /startup (boot failure) and
-- os/run.lua (session crash) so the user experience is consistent.
--
-- Usage:
--   local crash = require("os.crash")
--   crash.show{title="Session Crashed", msg="<error string>",
--              logPath="/os/data/boot.log", nextAction="Press any key to continue"}
--
-- The function blocks until the user presses a key.
--   - ENTER / SPACE / any key → scrolls the traceback page
--   - ESC / Q → returns (so the caller can drop to shell / retry)

local M = {}

-- Choose between pixel graphics (gfx) and term text fallback.
-- We detect which one is available at call time.
local gfx = nil
local term_native = nil

-- Paginate a multi-line string. Returns {lines = {..}, total = n}.
local function paginate(msg, rowsPerPage)
    local lines = {}
    for chunk in (msg .. "\n"):gmatch("([^\n]*)\n?") do
        if #chunk > 0 then
            -- Also word-wrap long lines to fit the pixel canvas width
            lines[#lines+1] = chunk
        end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

-- Paint the red banner on the pixel surface (gfx mode).
-- Blocks until user presses a key; returns "dropped" or "continue".
local function showPixelBanner(opts)
    local W, H = gfx.width(), gfx.height()
    -- Full black overlay
    gfx.fillRect(0, 0, W, H, {0, 0, 0})
    -- Red banner
    local bannerH = 80
    local bannerY = math.floor((H - bannerH) / 2)
    gfx.fillRect(0, bannerY, W, bannerH, {170, 46, 46})
    gfx.fillRect(0, bannerY, W, 1, {220, 62, 62})
    gfx.fillRect(0, bannerY + bannerH - 1, W, 1, {120, 30, 30})
    -- Title
    local title = opts.title or "CRASH"
    local titleSize = math.min(14, math.floor(H * 0.06))
    local tw = gfx.textSize(title, {size = titleSize, style = "bold"})
    local tx = math.floor((W - tw) / 2)
    gfx.text(title, tx, bannerY + 7, {255, 255, 255}, {size = titleSize, style = "bold"})
    -- Error message (truncate to fit width)
    local msg = opts.msg or ""
    local msgSize = math.min(9, math.floor(H * 0.04))
    local maxMsgW = W - 40
    -- Truncate with ellipsis
    local displayMsg = msg
    while gfx.textSize(displayMsg, {size = msgSize, style = "plain"}) > maxMsgW and #displayMsg > 0 do
        displayMsg = displayMsg:sub(1, -2)
    end
    if displayMsg ~= msg then displayMsg = displayMsg .. "..." end
    local mx = math.floor((W - gfx.textSize(displayMsg, {size = msgSize, style = "plain"})) / 2)
    gfx.text(displayMsg, mx, bannerY + titleSize + 16, {232, 236, 244}, {size = msgSize, style = "plain"})

    -- Hint
    local hint = opts.nextAction or "Press any key to continue"
    local hs = math.min(9, math.floor(H * 0.04))
    local hw = gfx.textSize(hint, {size = hs, style = "plain"})
    gfx.text(hint, math.floor((W - hw) / 2), bannerY + bannerH - hs - 7, {200, 200, 200}, {size = hs, style = "plain"})
    gfx.endFrame()

    -- Wait for a key press
    while true do
        local ev = {os.pullEvent("key")}
        local key = ev[2]
        if key == keys.q or key == keys.escape then
            return "dropped"
        end
        -- Any other key continues
        break
    end
    return "continue"
end

-- Paint the text-based crash screen (term mode, no pixel gfx).
-- Blocks until user presses a key; returns "dropped" or "continue".
local function showTermBanner(opts)
    local t = term_native or term
    if not t then return "continue" end

    -- Read the log file to show the traceback
    local logContent = ""
    if opts.logPath then
        pcall(function()
            local f = fs.open(opts.logPath, "r")
            if f then
                logContent = f.readAll() or ""
                f.close()
            end
        end)
    end
    local allText = opts.msg or ""
    if #logContent > 0 then
        allText = "--- Error ---\n" .. (opts.msg or "") .. "\n--- Log ---\n" .. logContent
    end

    local cx, cy = t.getSize()
    local rowsPerPage = math.max(4, cy - 4)
    local lines = paginate(allText, rowsPerPage)
    local page, dropped = 1, false

    while page <= #lines and not dropped do
        pcall(function()
            t.setBackgroundColor(colors.red)
            t.clear()
            t.setTextColor(colors.white)
        end)
        t.setCursorPos(1, 1)
        t.clearLine()
        t.write(" " .. (opts.title or "CRASH") .. " ")
        t.setCursorPos(1, 2)
        t.write(string.rep("-", math.max(10, cx - 5)))

        for row = 0, rowsPerPage - 1 do
            t.setCursorPos(1, 3 + row)
            t.clearLine()
            local ln = lines[page + row]
            if ln then
                -- Truncate to screen width
                if #ln > cx then ln = ln:sub(1, cx - 3) .. ".." end
                t.write(ln)
            end
        end

        t.setCursorPos(1, cy - 1)
        t.clearLine()
        if opts.nextAction then
            t.write(opts.nextAction)
        else
            local footer = string.format("[ %d-%d / %d ]  ENTER next  q shell",
                page, math.min(page + rowsPerPage - 1, #lines), #lines)
            t.write(footer)
        end
        t.setCursorPos(1, cy)
        t.clearLine()
        t.write("Full log: " .. (opts.logPath or "(none)"))

        local ev = {os.pullEvent("key")}
        local key = ev[2]
        if key == keys.q or key == keys.escape then
            dropped = true
        else
            page = page + rowsPerPage
        end
    end

    if dropped then
        pcall(function()
            t.setBackgroundColor(colors.black)
            t.setTextColor(colors.white)
            t.clear()
            t.setCursorPos(1, 1)
        end)
        t.write("Dropped to shell. See " .. (opts.logPath or "/os/data/boot_error.log") .. "\n")
    end
    return dropped and "dropped" or "continue"
end

-- Public entry point. Decides pixel vs term path automatically.
-- opts:
--   title       — string, e.g. "Session Crashed" | "Boot Failure"
--   msg         — string, the error message to display
--   logPath     — string, path to a log file for the full traceback
--   nextAction  — string, hint text like "Press any key to continue"
function M.show(opts)
    opts = opts or {}
    opts.title = opts.title or "CRASH"
    opts.msg = opts.msg or "Unknown error"
    opts.nextAction = opts.nextAction or "Press any key to continue"

    -- Try pixel path first
    local gfxOk, gfxMod = pcall(require, "os.gfx")
    gfx = gfxOk and gfxMod or nil
    if gfx and type(gfx.width) == "function" and gfx.width() > 0 then
        return showPixelBanner(opts)
    end

    -- Fall back to term path
    term_native = (type(term.native) == "function") and term.native() or term
    return showTermBanner(opts)
end

return M