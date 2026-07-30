-- os/startmenu.lua — popup menu shown above the start button.
-- Animated in/out is faked because we redraw every frame anyway.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local text   = require("os.text")
local input  = require("os.input")
local wm     = require("os.wm")
local sound  = require("os.sound")
local cfg    = require("os.config")
local programs = require("os.programs")

local M = {}
M.visible = false
M.offsetY = 0    -- negative during intro animation
M.searchQuery = ""

local function getScale() return cfg.appearance.uiScale or 1 end
local function dim(name) return theme.dimScaled(name, getScale()) end

-- ---------------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------------
local function geom()
    local W, H = gfx.width(), gfx.height()
    local barH = dim("taskbarH")
    -- Compact menu that fits on the small pixel canvas (306×171 on
    -- an advanced computer in mode 2).
    local menuW = math.floor(W * 0.60)
    local menuH = H - barH - 8
    local g = {
        W = W, H = H,
        barY = H - barH,
        menuW = menuW,
        menuH = menuH,
        menuX = 4,
        menuY = 4,
    }
    return g
end

-- search field
local function drawSearch(g)
    local pad = 4
    local h = 20
    local y = g.menuY + pad
    gfx.fillRoundRect(g.menuX + pad, y, g.menuW - pad*2, h, 4, theme.c("surfaceHigh"))
    gfx.outlineRect(g.menuX + pad, y, g.menuW - pad*2, h, theme.c("border"))
    local opts = {size = dim("fontSizeSmall"), style = "plain"}
    local cursorX = g.menuX + pad + 6
    gfx.text("Search", cursorX, y + (h - opts.size)/2,
        theme.c("textMuted"), opts)
    if M.searchQuery and #M.searchQuery > 0 then
        gfx.text(M.searchQuery, cursorX, y + (h - opts.size)/2,
            theme.c("textPrimary"), opts)
    end
end

-- apps list (single column, compact)
local function drawApps(g)
    local pad = 4
    local y0 = g.menuY + 28
    local x0 = g.menuX + pad
    local w0 = g.menuW - pad*2

    local filter = (M.searchQuery or ""):lower()
    local items = {}
    for _, app in ipairs(programs.all()) do
        if filter == "" or app.label:lower():find(filter, 1, true) then
            items[#items+1] = app
        end
    end
    local cellH = 22
    local hover = M._hover
    for i, app in ipairs(items) do
        local py = y0 + (i-1) * (cellH + 2)
        if py + cellH > g.menuY + g.menuH - 50 then break end
        local isHover = hover and hover.app == app.id
        local bg = isHover and theme.c("surfaceHigh") or theme.c("surfaceAlt")
        gfx.fillRoundRect(x0, py, w0, cellH, 3, bg)
        gfx.outlineRect(x0, py, w0, cellH, theme.c("border"))
        local catColor = app.category == "system" and theme.c("accent")
                         or (app.category == "creative" and theme.c("purpleLight")
                         or (app.category == "utility" and theme.c("greenLight")
                         or theme.c("amberDark")))
        -- icon
        local sz = 10
        gfx.text(app.icon, x0 + 4, py + (cellH - sz)/2, catColor,
            {size=sz, style="bold"})
        -- label
        local labelEllip = text.ellipsize(app.label, w0 - 24,
            {size=dim("fontSizeSmall"), style="plain"})
        gfx.text(labelEllip, x0 + 20, py + (cellH - dim("fontSizeSmall"))/2,
            theme.c("textPrimary"), {size=dim("fontSizeSmall"), style="plain"})
    end
end

-- footer with power actions (compact row)
local function drawFooter(g)
    local pad = 4
    local y = g.menuY + g.menuH - 40
    local x0 = g.menuX + pad
    local w0 = g.menuW - pad*2
    gfx.fillRect(g.menuX, y, g.menuW, 40, theme.c("surface"))
    gfx.outlineRect(g.menuX, y, g.menuW, 1, theme.c("border"))
    -- user name
    local userName = (M._activeUser and M._activeUser.name) or "guest"
    gfx.text(userName, x0, y + 4, theme.c("textPrimary"),
        {size=dim("fontSizeSmall"), style="bold"})
    -- action buttons in a row
    local actions = {
        {label = "Lock",      action = "lock"},
        {label = "Logout",    action = "logout"},
        {label = "Power",     action = "shutdown"},
    }
    local btnW = math.floor((w0 - 4) / #actions) - 2
    for i, a in ipairs(actions) do
        local bx = x0 + (i-1) * (btnW + 2)
        local by = y + 18
        local bh = 16
        local hov = M._hover and M._hover.action == a.action
        local bg = hov and theme.c("surfaceHigh") or theme.c("surfaceAlt")
        gfx.fillRoundRect(bx, by, btnW, bh, 3, bg)
        gfx.outlineRect(bx, by, btnW, bh, theme.c("border"))
        local opts = {size = 8, style = "plain"}
        local tw = gfx.textSize(a.label, opts)
        gfx.text(a.label, bx + (btnW - tw)/2, by + (bh - 8)/2,
            theme.c("textPrimary"), opts)
    end
end

-- ---------------------------------------------------------------------------
function M.drawAll()
    if not M.visible then return end
    local g = geom()

    -- Card background
    gfx.fillRoundRect(g.menuX, g.menuY, g.menuW, g.menuH, 6, theme.c("surface"))
    gfx.outlineRect(g.menuX, g.menuY, g.menuW, g.menuH, theme.c("borderBright"))
    -- Soft drop shadow
    if gfx.isDirectGPU() then
        for i = 0, 3 do
            local a = 0.4 * (1 - i/3)
            local c = {0, 0, 0}
            gfx.fillRect(g.menuX + i, g.menuY + g.menuH + i, g.menuW, 1, c[1], c[2], c[3])
            gfx.fillRect(g.menuX + g.menuW + i, g.menuY + i, 1, g.menuH + i, c[1], c[2], c[3])
        end
    end

    drawSearch(g)
    drawApps(g)
    drawFooter(g)
end

-- ---------------------------------------------------------------------------
-- Hit testing
-- ---------------------------------------------------------------------------
M._hover = nil
function M.hitTest(x, y)
    if not M.visible then return nil end
    local g = geom()
    if x < g.menuX or x > g.menuX + g.menuW or y < g.menuY or y > g.menuY + g.menuH then
        return nil
    end
    local pad = 4
    -- search area
    if y >= g.menuY + pad and y <= g.menuY + pad + 20 then
        return {zone="search"}
    end
    -- app list cells
    local x0 = g.menuX + pad
    local y0 = g.menuY + 28
    local w0 = g.menuW - pad*2
    local cellH = 22
    local col = math.floor((x - x0) / w0)
    local row = math.floor((y - y0) / (cellH + 2))
    if col == 0 and row >= 0 then
        local filter = (M.searchQuery or ""):lower()
        local items = {}
        for _, app in ipairs(programs.all()) do
            if filter == "" or app.label:lower():find(filter, 1, true) then
                items[#items+1] = app
            end
        end
        local idx = row + 1
        if idx >= 1 and idx <= #items and idx <= math.floor((g.menuH - 68) / (cellH + 2)) then
            return {zone="app", app = items[idx].id, appObj = items[idx]}
        end
    end
    -- footer power buttons
    local footerY = g.menuY + g.menuH - 40
    if y >= footerY + 18 and y <= footerY + 34 then
        local actions = {
            {label = "Lock",      action = "lock"},
            {label = "Logout",    action = "logout"},
            {label = "Power",     action = "shutdown"},
        }
        local btnW = math.floor((w0 - 4) / #actions) - 2
        for i, a in ipairs(actions) do
            local bx = x0 + (i-1) * (btnW + 2)
            if x >= bx and x <= bx + btnW then
                return {zone="action", action=a.action}
            end
        end
    end
    return {zone="menu"}
end

function M.activate(zone)
    sound.beep()
    if zone.zone == "search" then
        M._editingSearch = true
    elseif zone.zone == "app" then
        if M.onLaunch then M.onLaunch(zone.appObj) end
        M.visible = false
    elseif zone.zone == "action" then
        if M.onAction then M.onAction(zone.action) end
        M.visible = false
    end
end

function M.open(user)
    M.visible = true
    M._activeUser = user
end
function M.close() M.visible = false end
function M.toggle(user)
    M.visible = not M.visible
    if M.visible then M._activeUser = user end
end

-- Type into search.
function M.handleChar(ch)
    if not M._editingSearch then return false end
    if ch == "\b" then
        M.searchQuery = (M.searchQuery or ""):sub(1, -2)
    elseif type(ch) == "string" and #ch > 0 then
        M.searchQuery = (M.searchQuery or "") .. ch
    end
    return true
end

return M
