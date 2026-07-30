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
    local g = {
        W = W, H = H,
        barY = H - barH,
        menuW = 360,
        menuH = 420,
        menuX = 6,
        menuY = H - barH - (420 + 8),
    }
    return g
end

-- search field
local function drawSearch(g)
    local pad = dim("padding")
    local h = 28
    local y = g.menuY + pad
    gfx.fillRoundRect(g.menuX + pad, y, g.menuW - pad*2, h, 6, theme.c("surfaceHigh"))
    gfx.outlineRect(g.menuX + pad, y, g.menuW - pad*2, h, theme.c("border"))
    local opts = {size = dim("fontSizeBody"), style = "plain"}
    local cursorX = g.menuX + pad + 8
    gfx.text("🔍 Search", cursorX, y + (h - opts.size)/2,
        theme.c("textMuted"), opts)
    if M.searchQuery and #M.searchQuery > 0 then
        gfx.text(M.searchQuery, cursorX, y + (h - opts.size)/2,
            theme.c("textPrimary"), opts)
    end
end

-- left pane: categories + apps
local function drawLeftPane(g)
    local pad = dim("padding")
    local y0 = g.menuY + 60
    local h0 = g.menuH - 60 - 60  -- leave footer
    local x0 = g.menuX + pad
    local w0 = g.menuW * 0.65 - pad*2

    -- title
    gfx.text("Apps", x0, g.menuY + 38,
        theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "bold"})

    -- list filtered by search
    local filter = (M.searchQuery or ""):lower()
    local items = {}
    for _, app in ipairs(programs.all()) do
        if filter == "" or app.label:lower():find(filter, 1, true) then
            items[#items+1] = app
        end
    end
    -- render as a flat horizontal grid of 3 cols
    local cellH = 60
    local cellW = math.floor((w0 - 8) / 3) - 4
    local curY = y0
    local curX = x0
    local idx = 0
    local hover = M._hover
    for _, app in ipairs(items) do
        local row = math.floor(idx / 3)
        local col = idx % 3
        local px = x0 + col * (cellW + 6)
        local py = y0 + row * (cellH + 4)
        if py + cellH > g.menuY + g.menuH - 60 then break end
        local isHover = hover and hover.app == app.id
        local bg = isHover and theme.c("surfaceHigh") or theme.c("surfaceAlt")
        gfx.fillRoundRect(px, py, cellW, cellH, 6, bg)
        gfx.outlineRect(px, py, cellW, cellH, theme.c("border"))
        local catColor = app.category == "system" and theme.c("accent")
                         or (app.category == "creative" and theme.c("purpleLight")
                         or (app.category == "utility" and theme.c("greenLight")
                         or theme.c("amberDark")))
        -- Icon glyph
        local s = 24
        local ww = gfx.textSize(app.icon, {size=s, style="bold"})
        gfx.text(app.icon, px + (cellW - ww)/2, py + 6, catColor, {size=s, style="bold"})
        -- label
        local labelEllip = text.ellipsize(app.label, cellW - 8,
            {size=dim("fontSizeSmall"), style="plain"})
        local measured = gfx.textSize(labelEllip, {size=dim("fontSizeSmall"), style="plain"})
        gfx.text(labelEllip, px + (cellW - measured)/2, py + cellH - measured - 2,
            theme.c("textPrimary"), {size=dim("fontSizeSmall"), style="plain"})
        idx = idx + 1
    end
end

-- right pane: user / lock / power
local function drawRightPane(g)
    local pad = dim("padding")
    local leftW = g.menuW * 0.65
    local x0 = g.menuX + leftW + 8
    local w0 = g.menuW - leftW - pad*2 - 12
    local y0 = g.menuY + 60

    -- title
    gfx.text("Qalcom OS", x0, g.menuY + 38,
        theme.c("textPrimary"),
        {size = dim("fontSizeBody"), style = "bold"})

    -- User card
    local userCardY = y0
    local userCardH = 60
    gfx.fillRoundRect(x0, userCardY, w0, userCardH, 6, theme.c("surfaceHigh"))
    gfx.outlineRect(x0, userCardY, w0, userCardH, theme.c("border"))
    local userText = (M._activeUser and M._activeUser.name) or "guest"
    gfx.text(userText, x0 + 12, userCardY + 12,
        theme.c("textPrimary"), {size=dim("fontSizeTitle"), style="bold"})
    gfx.text(M._activeUser and M._activeUser.role or "user",
        x0 + 12, userCardY + 36,
        theme.c("textSecondary"), {size=dim("fontSizeSmall"), style="plain"})

    -- power actions
    local actions = {
        {label = "Lock",           action = "lock"},
        {label = "Log out",        action = "logout"},
        {label = "Restart",        action = "restart"},
        {label = "Shut down",      action = "shutdown"},
    }
    local ay = userCardY + userCardH + 12
    for _, a in ipairs(actions) do
        local hover = M._hover and M._hover.action == a.action
        local bg = hover and theme.c("surfaceHigh") or theme.c("surfaceAlt")
        gfx.fillRoundRect(x0, ay, w0, 26, 4, bg)
        gfx.outlineRect(x0, ay, w0, 26, theme.c("border"))
        gfx.text(a.label, x0 + 12, ay + (26 - dim("fontSizeBody"))/2,
            theme.c("textPrimary"), {size=dim("fontSizeBody"), style="plain"})
        ay = ay + 30
    end
end

-- footer with "All apps" link
local function drawFooter(g)
    local pad = dim("padding")
    local y = g.menuY + g.menuH - 60
    gfx.fillRect(g.menuX, y, g.menuW, 60, theme.c("surface"))
    gfx.outlineRect(g.menuX, y, g.menuW, 1, theme.c("border"))
    local opts = {size = dim("fontSizeBody"), style = "bold"}
    local txt = "All apps →"
    local tw = gfx.textSize(txt, opts)
    gfx.text(txt, g.menuX + g.menuW - tw - 18, y + (60 - opts.size)/2,
        theme.c("accent"), opts)

    gfx.text("Qalcom OS v0.1", g.menuX + pad, y + (60 - opts.size)/2,
        theme.c("textMuted"), opts)
end

-- ---------------------------------------------------------------------------
function M.drawAll()
    if not M.visible then return end
    local g = geom()

    -- Card background
    gfx.fillRoundRect(g.menuX, g.menuY, g.menuW, g.menuH, 8, theme.c("surface"))
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
    drawLeftPane(g)
    drawRightPane(g)
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
    local pad = dim("padding")
    -- search area
    if y >= g.menuY + pad and y <= g.menuY + pad + 28 then
        return {zone="search"}
    end
    -- left pane cells
    local leftW = g.menuW * 0.65
    local x0 = g.menuX + pad
    local y0 = g.menuY + 60
    local cellH = 60
    local cellW = (math.floor((leftW - 8) / 3) - 4)
    local localX, localY = x - x0, y - y0
    local col = math.floor(localX / (cellW + 6))
    local row = math.floor(localY / (cellH + 4))
    if col >= 0 and col < 3 and row >= 0 then
        local idx = row*3 + col + 1
        local filter = (M.searchQuery or ""):lower()
        local items = {}
        for _, app in ipairs(programs.all()) do
            if filter == "" or app.label:lower():find(filter, 1, true) then
                items[#items+1] = app
            end
        end
        if idx <= #items then
            return {zone="app", app = items[idx].id, appObj = items[idx]}
        end
    end
    -- right pane actions
    local actions = {
        {label = "Lock",      action = "lock"},
        {label = "Log out",   action = "logout"},
        {label = "Restart",   action = "restart"},
        {label = "Shut down", action = "shutdown"},
    }
    local actionX = g.menuX + leftW + 8
    local actionW = g.menuW - leftW - pad*2 - 12
    local actionY0 = g.menuY + 60 + 60 + 12
    for i, a in ipairs(actions) do
        local ay = actionY0 + (i-1) * 30
        if x >= actionX and x <= actionX + actionW and y >= ay and y <= ay + 26 then
            return {zone="action", action=a.action}
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
