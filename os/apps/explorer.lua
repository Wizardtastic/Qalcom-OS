-- os/apps/explorer.lua — File Explorer.
-- Two-column layout: sidebar (Quick Access + This PC) and main file grid.
-- States (current path, scroll offset, hover, selected).

local theme   = require("os.theme")
local text    = require("os.text")
local fsutil  = require("os.fsutil")
local cfg     = require("os.config")
local sound   = require("os.sound")
local notif   = require("os.notifications")
local programs= require("os.programs")

local M = {
    -- application dimensions (passed to wm.new)
    w = 600, h = 380, minW = 320, minH = 220,
    appId = "explorer",
}

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- Each app instance has its own state.
local function newState()
    return {
        currentPath  = "/",
        upStk        = {},
        fwdStk       = {},
        hover        = nil,
        selected     = nil,
        entries      = {},
        scrollY      = 0,
        view         = "grid",
        lastClickTs  = 0,
        lastClickEntry = nil,
    }
end

local function state(win) win.appState = win.appState or newState(); return win.appState end
local _WIN = nil  -- last window whose onclick routed into navigate

function M.init(win)
    state(win)
    win.title = "File Explorer — /"
    M.refresh(win)
end

function M.destroy(win) end

local function navigate(state, path)
    if path == state.currentPath then return end
    if path and fs.exists(path) then
        if fs.isDir(path) then
            table.insert(state.upStk, state.currentPath)
            state.fwdStk = {}
            state.currentPath = path
            state.selected = nil
            state.scrollY = 0
            if _WIN then M.refresh(_WIN) else state.entries = fsutil.listPretty(state.currentPath) end
        else
            -- file: if it's .lua or .txt, open in notepad; otherwise error.
            if path:match("%.lua$") or path:match("%.txt$") or path:match("%.md$") then
                win.title = "File Explorer — " .. path
                local session = require("os.session")
                session.launchApp("notepad")
                notif.push({title="Opened in Notepad", body=path, level="ok"})
            else
                notif.push({title="Cannot open", body="No handler for " .. path, level="warn"})
            end
            return
        end
    end
end

function M.refresh(win)
    state(win).entries = fsutil.listPretty(state(win).currentPath)
end

local function sidebarGeom(win)
    local pad = dim("padding")
    return {x = win.x + pad, y = win.y + dim("titlebarH") + pad,
            w = 130, h = win.h - dim("titlebarH") - pad*2 - 24}
end

local function mainGeom(win)
    local sb = sidebarGeom(win)
    local pad = dim("padding")
    local x = sb.x + sb.w + pad + 1
    local y = sb.y
    return {
        x = x, y = y,
        w = win.x + win.w - x - pad,
        h = win.h - dim("titlebarH") - pad*2 - 24,
    }
end

local function addressBarGeom(win)
    local pad = dim("padding")
    local r = mainGeom(win)
    return {x = r.x, y = r.y, w = r.w, h = 20}
end

local function backBtnGeom(win)
    local pad = dim("padding")
    return {x = mainGeom(win).x, y = mainGeom(win).y, w = pad*2 + 12, h = 20}
end

local function drawSidebar(win, state)
    local s = sidebarGeom(win)
    gfx.fillRoundRect(s.x, s.y, s.w, s.h, 4, theme.c("surface"))
    gfx.outlineRect(s.x, s.y, s.w, s.h, theme.c("border"))
    local opts = {size = dim("fontSizeSmall"), style = "bold"}
    gfx.text("Quick Access", s.x + 8, s.y + 6, theme.c("textSecondary"), opts)
    local qaY = s.y + 26
    for _, e in ipairs({
        {label = "Home",     path = cfg.paths.homes .. "/admin"},
        {label = "Desktop",  path = "/"},
        {label = "Documents",path = cfg.paths.homes .. "/admin"},
    }) do
        local hover = (state.hover and state.hover.zone == "sidebar" and state.hover.path == e.path)
        if hover then
            gfx.fillRoundRect(s.x + 4, qaY, s.w - 8, 22, 4, theme.c("selected"))
        end
        gfx.text(e.label, s.x + 12, qaY + 4, theme.c("textPrimary"),
            {size=dim("fontSizeBody"), style="plain"})
        qaY = qaY + 26
    end
    -- This PC
    gfx.text("This PC", s.x + 8, qaY + 6, theme.c("textSecondary"), opts)
    qaY = qaY + 26
    for _, e in ipairs({
        {label = "Root",        path = "/"},
        {label = "OS files",    path = cfg.paths.osRoot},
        {label = "Apps",        path = cfg.paths.apps},
        {label = "Users",       path = cfg.paths.users},
    }) do
        local hover = (state.hover and state.hover.zone == "sidebar" and state.hover.path == e.path)
        if hover then
            gfx.fillRoundRect(s.x + 4, qaY, s.w - 8, 22, 4, theme.c("selected"))
        end
        gfx.text(e.label, s.x + 12, qaY + 4, theme.c("textPrimary"),
            {size = dim("fontSizeBody"), style = "plain"})
        qaY = qaY + 26
    end
end

local function drawAddressBar(win, state)
    local r = addressBarGeom(win)
    -- address input
    local pad = dim("padding")
    -- back/up buttons
    local bx = r.x
    local btnW = pad*2 + 12
    -- Display path
    local barX = bx + btnW + 6
    local barW = r.w - (barX - bx)
    gfx.fillRoundRect(bx, r.y, r.w, 22, 6, theme.c("surface"))
    gfx.outlineRect(bx, r.y, r.w, 22, theme.c("border"))
    gfx.text("⟵", bx + 8, r.y + (22 - dim("fontSizeBody"))/2 + 1,
        #state.upStk > 0 and theme.c("accent") or theme.c("textMuted"),
        {size=dim("fontSizeBody"), style="bold"})
    gfx.text("⟰", bx + btnW/2 + 6, r.y + (22 - dim("fontSizeBody"))/2 + 1,
        state.currentPath ~= "/" and theme.c("accent") or theme.c("textMuted"),
        {size=dim("fontSizeBody"), style="bold"})

    local pathText = state.currentPath
    local opts = {size = dim("fontSizeBody"), style = "plain"}
    local px = barX + 8
    gfx.text(pathText, px, r.y + (22 - opts.size)/2,
        theme.c("textPrimary"), opts)
end

local function drawGrid(win, state)
    local g = mainGeom(win)
    -- background
    gfx.fillRoundRect(g.x, g.y + 30, g.w, g.h - 30, 4, theme.c("surface"))
    gfx.outlineRect(g.x, g.y + 30, g.w, g.h - 30, theme.c("border"))
    cellW = 80; cellH = 70
    pad = 8
    for i, e in ipairs(state.entries) do
        local col = (i-1) % math.max(1, math.floor((g.w - 2*pad) / cellW))
        local row = math.floor((i-1) / math.max(1, math.floor((g.w - 2*pad) / cellW)))
        local ix = g.x + pad + col*cellW
        local iy = g.y + 36 + row*cellH - state.scrollY
        if iy + cellH >= g.y + 36 and iy <= g.y + g.h - 8 then
            local hot = state.hover and state.hover.entry == e.name
            local sel = state.selected == e.name
            local bg = sel and theme.c("selected") or (hot and theme.c("surfaceHigh") or nil)
            if bg then gfx.fillRoundRect(ix, iy, cellW - 6, cellH - 6, 4, bg) end
            -- icon
            local iconColor = e.isDir and theme.c("accent") or
                              (e.name:match("%.lua$") and theme.c("greenLight") or theme.c("textSecondary"))
            local ic = e.isDir and "📁" or "📄"
            if not (gfx and gfx.text) then ic = e.isDir and "DIR" or "FIL" end
            local s = 28
            local ww = gfx.textSize(ic, {size=s, style="bold"})
            gfx.text(ic, ix + (cellW-6-ww)/2, iy + 6, iconColor, {size=s, style="bold"})
            -- label
            local label = text.ellipsize(e.name, cellW - 12,
                {size=dim("fontSizeSmall"), style="plain"})
            local lw = gfx.textSize(label, {size=dim("fontSizeSmall"), style="plain"})
            gfx.text(label, ix + (cellW - 6 - lw)/2, iy + cellH - 18,
                theme.c("textPrimary"),
                {size = dim("fontSizeSmall"), style = "plain"})
        end
    end
end

local function drawFooter(win, state)
    local sb = sidebarGeom(win)
    local pad = dim("padding")
    local y = win.y + win.h - 22
    gfx.fillRect(sb.x, y, win.w - pad*2, 20, theme.c("surface"))
    gfx.outlineRect(sb.x, y, win.w - pad*2, 20, theme.c("border"))
    local txt = string.format("%d item(s)", #state.entries)
    local opts = {size = dim("fontSizeSmall"), style = "plain"}
    gfx.text(txt, sb.x + 6, y + 3, theme.c("textSecondary"), opts)
end

function M.paint(win, cx, cy, cw, ch)
    local s = state(win)
    drawAddressBar(win, s)
    drawGrid(win, s)
    drawSidebar(win, s)
    drawFooter(win, s)
end

local function pointInRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function M.onEvent(win, ev, lx, ly)
    local state = win.appState
    -- Translate to absolute coords from local (client) coords.
    -- local points lx, ly are relative to clientRect (cx,cy)
    local absX, absY = lx + (win.x + 0), ly + (win.y + dim("titlebarH"))
    -- Refresh entries / hover
    if ev.type == "mouse_move" then
        -- sidebar hover
        local s = sidebarGeom(win)
        if pointInRect(absX, absY, s) then
            -- determine sidebar item
            local qaY = s.y + 26
            local qa = {
                {label="Home", path=(cfg.paths.homes .. "/admin")},
                {label="Desktop", path="/"},
                {label="Documents", path=(cfg.paths.homes .. "/admin")},
            }
            if absY >= qaY then
                local idx = math.floor((absY - qaY)/26) + 1
                if idx >= 1 and idx <= #qa then
                    state.hover = {zone="sidebar", path=qa[idx].path}
                elseif idx > #qa then
                    local pcStart = qaY + #qa*26 + 16
                    if absY >= pcStart then
                        local idx2 = math.floor((absY - pcStart)/26) + 1
                        local pc = {
                            {label="Root", path="/"},
                            {label="OS files", path=cfg.paths.osRoot},
                            {label="Apps", path=cfg.paths.apps},
                            {label="Users", path=cfg.paths.users},
                        }
                        if idx2 >= 1 and idx2 <= #pc then
                            state.hover = {zone="sidebar", path=pc[idx2].path}
                        end
                    end
                end
            end
        end
        -- grid hover
        local g = mainGeom(win)
        if pointInRect(absX, absY, {x = g.x, y = g.y + 30, w = g.w, h = g.h - 30}) then
            -- compute cell
            cellW = 80; cellH = 70; pad = 8
            local cols = math.max(1, math.floor((g.w - 2*pad) / cellW))
            local col = math.floor((absX - g.x - pad) / cellW)
            local row = math.floor((absY - g.y - 36 + state.scrollY) / cellH)
            local idx = row * cols + col + 1
            if idx >= 1 and idx <= #state.entries then
                state.hover = {zone="grid", entry=state.entries[idx].name}
            else
                state.hover = {zone="grid", entry=nil}
            end
        end
        return
    end

    if ev.type == "mouse_down" then
        -- sidebar
        local s = sidebarGeom(win)
        if pointInRect(absX, absY, s) then
            local qaY = s.y + 26
            local qa = {
                {label="Home", path=(cfg.paths.homes .. "/admin")},
                {label="Desktop", path="/"},
                {label="Documents", path=(cfg.paths.homes .. "/admin")},
            }
            if absY >= qaY then
                local idx = math.floor((absY - qaY)/26) + 1
                if idx >= 1 and idx <= #qa then
                    _WIN = win; navigate(state, qa[idx].path)
                    win.title = "File Explorer — " .. state.currentPath
                    return
                end
                local pcStart = qaY + #qa*26 + 16
                if absY >= pcStart then
                    local idx2 = math.floor((absY - pcStart)/26) + 1
                    local pc = {
                        {label="Root", path="/"},
                        {label="OS files", path=cfg.paths.osRoot},
                        {label="Apps", path=cfg.paths.apps},
                        {label="Users", path=cfg.paths.users},
                    }
                    if idx2 >= 1 and idx2 <= #pc then
                        _WIN = win; navigate(state, pc[idx2].path)
                        win.title = "File Explorer — " .. state.currentPath
                        return
                    end
                end
            end
        end

        -- address bar / back / up
        local r = addressBarGeom(win)
        local pad = dim("padding")
        if pointInRect(absX, absY, r) then
            local bx = r.x
            local btnW = pad*2 + 12
            -- back button area
            if absX >= bx and absX <= bx + btnW/2 + 4 then
                if #state.upStk > 0 then
                    local prev = table.remove(state.upStk)
                    table.insert(state.fwdStk, state.currentPath)
                    state.currentPath = prev
                    M.refresh(win)
                    win.title = "File Explorer — " .. state.currentPath
                end
                return
            end
            -- up button
            if absX >= bx + btnW/2 + 4 and absX <= bx + btnW*1.5 then
                if state.currentPath ~= "/" then
                    local parent = state.currentPath:match("^(.*)/[^/]+$") or "/"
                    _WIN = win; navigate(state, parent)
                    win.title = "File Explorer — " .. state.currentPath
                end
                return
            end
        end

        -- grid click
        local g = mainGeom(win)
        if pointInRect(absX, absY, {x=g.x, y=g.y+30, w=g.w, h=g.h-30}) then
            cellW = 80; cellH = 70; pad = 8
            local cols = math.max(1, math.floor((g.w - 2*pad) / cellW))
            local col = math.floor((absX - g.x - pad) / cellW)
            local row = math.floor((absY - g.y - 36 + state.scrollY) / cellH)
            local idx = row * cols + col + 1
            if idx >= 1 and idx <= #state.entries then
                state.selected = state.entries[idx].name
                sound.beep()
                -- double-click
                if ev.isClick and ev.ts - (state.lastClickTs or 0) < 500
                    and state.lastClickEntry == state.selected then
                    local entry = state.entries[idx]
                    local target = state.currentPath == "/" and ("/" .. entry.name) or (state.currentPath .. "/" .. entry.name)
                    navigate(state, target)
                    win.title = "File Explorer — " .. state.currentPath
                    state.lastClickTs = 0
                else
                    state.lastClickTs = ev.ts
                    state.lastClickEntry = state.selected
                end
                return
            end
        end
    end
end

return M
