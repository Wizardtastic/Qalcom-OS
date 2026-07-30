-- os/apps/notepad.lua — minimal plain-text editor.
-- Has a menu bar, text area (monospace), and Open / Save actions.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local fsutil = require("os.fsutil")
local cfg    = require("os.config")
local sound  = require("os.sound")
local notif  = require("os.notifications")

local M = {minW = 140, minH = 80, appId = "notepad"}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

local function newState()
    return {
        text     = "",
        path     = nil,       -- nil means "untitled"
        cursorX  = 1,         -- 1-based column
        cursorY  = 1,         -- 1-based row
        scrollY  = 0,         -- offset (in lines) from top
        dirty    = false,
    }
end

local function state(win) win.appState = win.appState or newState(); return win.appState end

function M.init(win)
    state(win)
    win.title = "Notepad — Untitled"
end

function M.destroy() end

local function lineHeight(state) return dim("fontSizeBody") + 2 end
local function linesFromState(state)
    local out = {}
    for line in (state.text or ""):gmatch("([^\n]*)\n?") do
        out[#out+1] = line
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function drawMenu(win, state)
    local mh = 22
    local y = win.y + dim("titlebarH")
    gfx.fillRect(win.x, y, win.w, mh, theme.c("surface"))
    gfx.outlineRect(win.x, y, win.w, mh, theme.c("border"))
    local items = {"File", "Edit", "View"}
    local idx = 0
    for _, it in ipairs(items) do
        local px = win.x + 4 + idx*52
        local opts = {size = dim("fontSizeBody"), style = "plain"}
        local hot = (state.hover and state.hover.menu == it)
        if hot then gfx.fillRoundRect(px, y+2, 50, mh-4, 4, theme.c("surfaceHigh")) end
        gfx.text(it, px + 8, y + (mh - opts.size)/2,
            theme.c("textPrimary"), opts)
        idx = idx + 1
    end
end

local function drawBody(win, state)
    local y = win.y + dim("titlebarH") + 22
    local h = win.h - dim("titlebarH") - 22 - 22
    local pad = dim("padding")
    gfx.fillRect(win.x + pad, y, win.w - 2*pad, h, theme.c("surface"))
    gfx.outlineRect(win.x + pad, y, win.w - 2*pad, h, theme.c("border"))
    local lines = linesFromState(state)
    local lh = lineHeight(state)
    local opts = {size = dim("fontSizeBody"), style = "plain", font = theme.font.monoFamily}
    local ty = y + 4 - state.scrollY*lh
    for i = state.scrollY + 1, #lines do
        if ty > y + h then break end
        local ln = lines[i] or ""
        -- render
        gfx.text(ln, win.x + pad + 6, ty, theme.c("textPrimary"), opts)
        -- underline current line
        if i == state.cursorY then
            local lineW = gfx.textSize(ln, opts)
            local cy = ty + lh - 2
            gfx.fillRect(win.x + pad + 6 + 4 + lineW,
                ty + lh/2, 6, 1, theme.c("accent"))
        end
        ty = ty + lh
    end
end

local function drawStatus(win, state)
    local y = win.y + win.h - 22
    gfx.fillRect(win.x, y, win.w, 22, theme.c("surface"))
    gfx.outlineRect(win.x, y, win.w, 22, theme.c("border"))
    local lines = linesFromState(state)
    local cs = lines[state.cursorY] or ""
    local info = string.format("Ln %d, Col %d   |   %s%s",
        state.cursorY, state.cursorX, state.path or "Untitled", state.dirty and " •" or "")
    gfx.text(info, win.x + 6, y + 4,
        theme.c("textSecondary"), {size = dim("fontSizeSmall"), style = "plain"})
end

function M.paint(win, cx, cy, cw, ch)
    local s = state(win)
    drawMenu(win, s)
    drawBody(win, s)
    drawStatus(win, s)
end

local function insert(state, ch)
    if state.cursorY < 1 then state.cursorY = 1 end
    local lines = linesFromState(state)
    while #lines < state.cursorY do lines[#lines+1] = "" end
    local row = lines[state.cursorY] or ""
    if state.cursorX > #row + 1 then state.cursorX = #row + 1 end
    local newRow = row:sub(1, state.cursorX - 1) .. ch .. row:sub(state.cursorX)
    lines[state.cursorY] = newRow
    state.text = table.concat(lines, "\n")
    state.cursorX = state.cursorX + 1
    state.dirty = true
end

local function backspace(state)
    local lines = linesFromState(state)
    if state.cursorY > #lines and state.cursorY > 1 then state.cursorY = #lines end
    local row = lines[state.cursorY] or ""
    if state.cursorX > 1 then
        local newRow = row:sub(1, state.cursorX - 2) .. row:sub(state.cursorX)
        lines[state.cursorY] = newRow
        state.cursorX = state.cursorX - 1
    elseif state.cursorY > 1 then
        local prev = lines[state.cursorY - 1] or ""
        lines[state.cursorY - 1] = prev
        table.remove(lines, state.cursorY)
        state.cursorY = state.cursorY - 1
        state.cursorX = #(lines[state.cursorY] or "") + 1
    end
    state.text = table.concat(lines, "\n")
    state.dirty = true
end

function M.onKey(win, ev)
    local s = state(win)
    if ev.key == keys.left then s.cursorX = math.max(1, s.cursorX - 1)
    elseif ev.key == keys.right then
        local lines = linesFromState(s)
        s.cursorX = math.min(#(lines[s.cursorY] or "") + 1, s.cursorX + 1)
    elseif ev.key == keys.up then
        s.cursorY = math.max(1, s.cursorY - 1)
        s.scrollY = math.max(0, math.min(s.scrollY, s.cursorY - 1))
    elseif ev.key == keys.down then
        local lines = linesFromState(s)
        s.cursorY = math.min(#lines, s.cursorY + 1)
    elseif ev.key == keys.home then s.cursorX = 1
    elseif ev.key == keys["end"] then
        local lines = linesFromState(s)
        s.cursorX = #(lines[s.cursorY] or "") + 1
    elseif ev.key == keys.backspace then backspace(s)
    elseif ev.key == keys.enter then insert(s, "\n")
    elseif ev.key == keys.f5 then
        -- F5 has no conflict with typing.  Save current buffer in place
        -- (or to a freshly timestamped path if the document was untitled).
        local path = s.path
        if not path then
            path = (cfg.paths.homes or "/home") .. "/admin/untitled.txt."
                .. tostring(os.epoch and os.epoch("utc") or 0)
        end
        local ok, err = fsutil.write(path, s.text or "")
        if ok then
            s.path = path
            s.dirty = false
            win.title = "Notepad — " .. path
            notif.push({title="Saved", body=path, level="ok"})
        else
            notif.push({title="Save failed", body=tostring(err), level="error"})
        end
    end
end

function M.onChar(win, ev)
    if not ev.ch or #ev.ch == 0 then return end
    if ev.ch == "\b" then return end
    insert(state(win), ev.ch)
end

function M.onEvent(win, ev, lx, ly)
    -- Click handling is light: just place cursor near click in a future
    -- iteration; for now we don't accept freeform cursor positioning to
    -- keep this notepad simple and robust.
end

return M
