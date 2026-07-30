-- os/apps/taskmgr.lua — Task Manager.
-- Lists every running window in the WM with a CPU / memory placeholder bar.
-- Allows ending tasks and switching to them.

local gfx     = require("os.gfx")
local theme   = require("os.theme")
local text    = require("os.text")
local sound   = require("os.sound")
local notif   = require("os.notifications")
local wm      = require("os.wm")
local programs= require("os.programs")
local cfg     = require("os.config")

local M = { minW = 180, minH = 120, appId = "taskmgr" }

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- CPU style fake graph (uses os.clock() to look alive)
local history = {}

local function titleBar(win)
    local tbH = dim("titlebarH")
    gfx.text("Task Manager", win.x + 10, win.y + (tbH - dim("fontSizeTitle"))/2,
        theme.c("textPrimary"), {size=dim("fontSizeTitle"), style="bold"})
end

local function drawList(win, state)
    local pad = dim("padding")
    local listX = pad + win.x
    local listY = win.y + dim("titlebarH") + pad + 30
    local listW = win.w - 2*pad
    local listH = win.h - dim("titlebarH")*2 - pad*2 - 80
    gfx.fillRoundRect(listX, listY, listW, listH, 6, theme.c("surface"))
    gfx.outlineRect(listX, listY, listW, listH, theme.c("border"))

    -- header
    gfx.text("App", listX + 8, listY + 6, theme.c("textSecondary"),
        {size = dim("fontSizeSmall"), style = "bold"})
    gfx.text("Window", listX + 140, listY + 6, theme.c("textSecondary"),
        {size = dim("fontSizeSmall"), style = "bold"})
    gfx.text("State", listX + 320, listY + 6, theme.c("textSecondary"),
        {size = dim("fontSizeSmall"), style = "bold"})

    -- rows: enumerate over wm.windows
    local rowH = 22
    local y = listY + 28
    for _, w in ipairs(wm.visible()) do
        local app = programs.byId(w.app and w.app.appId or "") or nil
        local appLabel = app and app.label or (w.app and w.app.appId or "Unknown")
        local sel = (state.selected == w.id)
        if sel then
            gfx.fillRoundRect(listX + 4, y - 3, listW - 8, rowH, 4, theme.c("selected"))
        end
        gfx.text(appLabel, listX + 8, y, theme.c("textPrimary"),
            {size = dim("fontSizeBody"), style = "plain"})
        local title = text.ellipsize(w.title, 160, {size=dim("fontSizeBody")})
        gfx.text(title, listX + 140, y, theme.c("textSecondary"),
            {size = dim("fontSizeBody"), style = "plain"})
        gfx.text(w.state, listX + 320, y, theme.c("textMuted"),
            {size = dim("fontSizeBody"), style = "plain"})
        y = y + rowH
    end
    if #wm.visible() == 0 then
        gfx.text("No apps running.", listX + 8, y, theme.c("textMuted"),
            {size = dim("fontSizeBody"), style = "plain"})
    end
end

local function drawFooter(win)
    local pad = dim("padding")
    local barY = win.y + win.h - 80
    -- CPU + memory bars
    local bx = win.x + pad
    local bw = win.w - 2*pad
    gfx.fillRoundRect(bx, barY, bw, 64, 6, theme.c("surface"))
    gfx.outlineRect(bx, barY, bw, 64, theme.c("border"))
    gfx.text("CPU", bx + 8, barY + 6, theme.c("textSecondary"),
        {size=dim("fontSizeSmall"), style="bold"})
    -- bar (animated based on how recently we've drawn)
    local now = os.clock()
    history[#history+1] = now
    if #history > 30 then table.remove(history, 1) end
    local utilization = math.random(8, 30)  -- placeholder
    local barW = bw - 16
    gfx.fillRect(bx + 8, barY + 22, barW, 8, theme.c("surfaceAlt"))
    gfx.fillRect(bx + 8, barY + 22,
        math.floor(barW * utilization/100), 8, theme.c("accent"))

    gfx.text(("Performance: ~%d%%"):format(utilization),
        bx + 8, barY + 36, theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "plain"})
    gfx.text(("Resolutions: %dx%d  |  DirectGPU: %s"):format(
        gfx.width(), gfx.height(),
        gfx.isDirectGPU() and "yes" or "no"),
        bx + 8, barY + 50, theme.c("textMuted"),
        {size = dim("fontSizeSmall"), style = "plain"})
end

local function drawButtons(win, state)
    local pad = dim("padding")
    local by = win.y + dim("titlebarH") + pad + 4
    local bw, bh = 80, 24
    local function btn(x, label, hot)
        local bg = hot and theme.c("accentPressed") or theme.c("accent")
        gfx.fillRoundRect(x, by, bw, bh, 4, bg)
        gfx.outlineRect(x, by, bw, bh, theme.c("border"))
        local opts = {size = dim("fontSizeSmall"), style = "bold"}
        local tw = gfx.textSize(label, opts)
        gfx.text(label, x + (bw - tw)/2, by + (bh - opts.size)/2,
            theme.c("textPrimary"), opts)
    end
    btn(win.x + pad, "End task",  state.hot == "end")
    btn(win.x + pad + bw + 6, "Switch to", state.hot == "switch")
    btn(win.x + pad + (bw + 6)*2, "Always on top", state.hot == "aot")
end

function M.init(win)
    win.appState = win.appState or { selected = nil, hot = nil }
    win.title = "Task Manager"
end

function M.destroy() end

function M.paint(win, cx, cy, cxw, ch)
    local state = win.appState or {}
    titleBar(win)
    drawButtons(win, state)
    drawList(win, state)
    drawFooter(win)
end

function M.onEvent(win, ev, lx, ly)
    local state = win.appState or {}
    -- Convert local to absolute coords
    local absX = lx + win.x + 0
    local absY = ly + win.y + dim("titlebarH")

    if ev.type == "mouse_move" then
        state.hot = nil
        local pad = dim("padding")
        local by = win.y + dim("titlebarH") + pad + 4
        if absY >= by and absY <= by + 24 then
            if absX >= win.x + pad and absX <= win.x + pad + 80 then state.hot = "end"
            elseif absX >= win.x + pad + 86 and absX <= win.x + pad + 166 then state.hot = "switch"
            elseif absX >= win.x + pad + 172 and absX <= win.x + pad + 252 then state.hot = "aot" end
        end
    end

    if ev.type == "mouse_down" then
        -- End task / Switch / AOT
        local pad = dim("padding")
        local by = win.y + dim("titlebarH") + pad + 4
        if absY >= by and absY <= by + 24 then
            sound.beep()
            if absX >= win.x + pad and absX <= win.x + pad + 80
                and state.selected then
                wm.close(state.selected)
                notif.push({title="Task ended", body=(state.selected or "?").." closed.", level="ok"})
                state.selected = nil
            elseif absX >= win.x + pad + 86 and absX <= win.x + pad + 166
                and state.selected then
                wm.focusWindow(state.selected)
            elseif absX >= win.x + pad + 172 and absX <= win.x + pad + 252
                and state.selected then
                notif.push({title="Pinned", body="Window always-on-top is on by default.", level="info"})
            end
            return
        end
        -- Click on a row
        local listY = win.y + dim("titlebarH") + pad + 30
        local rowH = 22
        local rowsTop = listY + 28
        if absY >= rowsTop and absY <= rowsTop + #wm.visible()*rowH then
            local idx = math.floor((absY - rowsTop) / rowH) + 1
            local visible = wm.visible()
            if idx >= 1 and idx <= #visible then
                state.selected = visible[idx].id
            else
                state.selected = nil
            end
        end
    end
end

return M
