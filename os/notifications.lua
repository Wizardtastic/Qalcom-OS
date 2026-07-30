-- os/notifications.lua — toast notification stack.
-- Toasts are drawn at the bottom-right of the screen above the taskbar.
-- A window manager that wants to render them calls notifications.drawAll().

local gfx   = require("os.gfx")
local theme = require("os.theme")
local sound = require("os.sound")

local M = {}
M.list = {}

local TOAST_W   = 280
local TOAST_H   = 64
local TOAST_GAP =  6
local TOAST_MARGIN = 14
local TOAST_LIFE_MS = 4000

-- Push a notification.  Fields: title, body, level.
-- level: "info" | "ok" | "warn" | "error"
function M.push(opts)
    opts = opts or {}
    opts.id     = opts.id     or (os.epoch and os.epoch("utc") or math.random(1e9))
    opts.title  = opts.title  or "Notice"
    opts.body   = opts.body   or ""
    opts.level  = opts.level  or "info"
    opts.shownAt = (os.epoch and os.epoch("utc") or 0)
    opts.dismissed = false

    M.list[#M.list+1] = opts
    if opts.level == "error" then sound.error()
    elseif opts.level == "warn" then sound.warn()
    elseif opts.level == "ok"   then sound.notify()
    end
    return opts.id
end

function M.dismiss(id)
    for i, n in ipairs(M.list) do
        if n.id == id or id == nil then
            M.list[i].dismissed = true
        end
    end
    -- GC
    local alive = {}
    for _, n in ipairs(M.list) do
        if not n.dismissed then alive[#alive+1] = n end
    end
    M.list = alive
end

local function colorFor(level)
    if level == "ok"    then return theme.c("ok")
    elseif level == "warn" then return theme.c("warning")
    elseif level == "error" then return theme.c("danger")
    else return theme.c("accent") end
end

-- Render every non-dismissed toast. Returns true if any were drawn.
function M.drawAll()
    local W = gfx.width()
    local H = gfx.height()
    local taskbarH = theme.dim.taskbarH
    local count = 0
    for i, n in ipairs(M.list) do
        local now = (os.epoch and os.epoch("utc") or 0)
        if not n.dismissed and (now - n.shownAt) < TOAST_LIFE_MS then
            local y = H - taskbarH - TOAST_MARGIN - (count+1)*TOAST_H - count*TOAST_GAP
            local x = W - TOAST_W - TOAST_MARGIN
            local col = colorFor(n.level)

            -- background panel
            gfx.fillRoundRect(x, y, TOAST_W, TOAST_H, 8, theme.c("surfaceHigh"))
            gfx.outlineRect(x, y, TOAST_W, TOAST_H, theme.c("border"), 1)
            -- accent strip on left
            gfx.fillRect(x, y+6, 4, TOAST_H-12, col)
            -- title
            gfx.text(n.title, x + 16, y + 8, theme.c("textPrimary"),
                {size = theme.d("fontSizeTitle"), style = theme.font.styleBold})
            -- body
            gfx.text(n.body, x + 16, y + 30, theme.c("textSecondary"),
                {size = theme.d("fontSizeBody"), style = theme.font.stylePlain})

            count = count + 1
        elseif not n.dismissed then
            -- mark expired
            n.dismissed = true
        end
    end
    return count > 0
end

function M.tick()
    -- GC
    local alive = {}
    for _, n in ipairs(M.list) do
        if not n.dismissed then alive[#alive+1] = n end
    end
    M.list = alive
end

return M
