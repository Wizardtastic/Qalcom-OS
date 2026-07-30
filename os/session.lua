-- os/session.lua — runs after authentication.
-- Hosts the main event loop, wires up WM, taskbar, desktop, start menu.

local gfx    = require("os.gfx")
local theme  = require("os.theme")
local input  = require("os.input")
local wm     = require("os.wm")
local desktop= require("os.desktop")
local taskbar= require("os.taskbar")
local startmenu = require("os.startmenu")
local notifications = require("os.notifications")
local cfg    = require("os.config")
local programs = require("os.programs")

local M = {}

-- Launch helper ------------------------------------------------------------
local function launchApp(appId)
    local entry = programs.byId(appId)
    if not entry or not entry.launch then return end
    -- Provide env containing common UI helpers
    local env = setmetatable({
        gfx    = gfx,
        theme  = theme,
        input  = input,
        wm     = wm,
        cfg    = cfg,
        fsutil = require("os.fsutil"),
    }, { __index = _G })
    -- Call launch(env) which returns an inner "app object" (a table with paint, onEvent, destroy, etc.)
    local ok, app = pcall(entry.launch, env)
    if not ok or type(app) ~= "table" then
        notifications.push({
            title = "Launch failed",
            body  = appId .. ": " .. tostring(app),
            level = "error",
        })
        return
    end
    -- Create a window for this app
    app.appId = entry.id
    app.title = entry.label
    local win = wm.new({
        title = entry.label,
        x = 60 + (math.random and math.random(0, 60) or 0),
        y = 60 + (math.random and math.random(0, 30) or 0),
        w = app.w or 460,
        h = app.h or 320,
        minW = app.minW or 220,
        minH = app.minH or 120,
        app = app,
    })
    if app.init then
        pcall(app.init, win)
    end
    return win
end

M.launchApp = launchApp

-- Main loop ----------------------------------------------------------------
local function render(activeUser)
    -- Desktop (bottom)
    desktop.drawAll()
    -- Windows sorted by z
    wm.drawAll()
    -- Taskbar
    taskbar.drawAll()
    -- Start menu (top)
    startmenu.drawAll()
    -- Notifications
    notifications.drawAll()
    gfx.endFrame()
end

local activeUser = nil

-- Returns true if the event was consumed by the taskbar/start menu/desktop,
-- false otherwise.
local function routeDashboardEvent(ev)
    if ev.type == "mouse_move" then return false end

    local x, y = ev.x, ev.y

    -- Start menu is open
    if startmenu.visible then
        local hit = startmenu.hitTest(x, y)
        if hit then
            if ev.type == "mouse_down" then
                startmenu.activate(hit)
            end
            return true
        end
        -- Click outside start menu closes it
        if ev.type == "mouse_down" then
            startmenu.close()
        end
    end

    -- Taskbar
    local zone = taskbar.hitTest(x, y)
    if zone and (ev.type == "mouse_down") then
        if zone.zone == "start" then
            -- open menu
            if taskbar.openMenu then startmenu.open(activeUser) end
            return true
        end
        return taskbar.onClick(zone, x, y)
    end

    -- Desktop (icon click or right-click menu)
    if ev.type == "mouse_down" then
        -- Right-click on desktop
        if ev.button == 2 then
            desktop.onClick(x, y, 2)
            return true
        end
        local hit = desktop.iconAt(x, y)
        if hit then launchApp(hit.app.id); return true end
        -- Close any context menu
        desktop.closeContext()
    end

    return false
end

function M.start(user, _gfx, _theme)
    gfx = _gfx or gfx
    theme = _theme or require("os.theme")
    activeUser = user
    notifications = notifications

    -- Make sure dirs exist
    cfg.ensureDirs()

    -- Wire up cross-module callbacks the dashboard draws on.
    taskbar.onLaunchPinned = function(app) launchApp(app.id) end
    startmenu.onLaunch = function(app) launchApp(app.id) end
    startmenu.onAction = function(action)
        if action == "lock" or action == "logout" then
            os.queueEvent("qalcom_lock")
        elseif action == "restart" then
            os.queueEvent("qalcom_restart")
        elseif action == "shutdown" then
            os.queueEvent("qalcom_shutdown")
        end
    end
    desktop.onLaunch = function(app) launchApp(app.id) end
    desktop.onContextAction = function(id)
        if id == "settings" then launchApp("settings")
        elseif id == "terminal" then launchApp("about")  -- placeholder until terminal app ships
        elseif id == "refresh" then notifications.push({title="Refresh", body="Desktop refreshed.", level="ok"})
        elseif id == "wallpaper" then launchApp("settings")
        end
    end

    -- Welcome notification
    notifications.push({
        title = "Welcome",
        body  = ("Signed in as %s.  Right-click the desktop for options."):format(user.name),
        level = "ok",
    })

    -- Main loop
    while true do
        render(activeUser)

        local ev = input.poll(0.1)
        if ev then
            -- System-level events forwarded by start menu.
            if ev.type == "qalcom_lock" or ev.type == "qalcom_logout" then
                return  -- return from session.start -> login.run is called again
            elseif ev.type == "qalcom_restart" then
                -- Hard reboot: redraw splash, then log back in.
                local boot = require("os.boot")
                boot.show()
                return
            elseif ev.type == "qalcom_shutdown" then
                -- Power off the CC:T computer if available, otherwise just
                -- paint a blank screen and return so the outer loop goes
                -- back to login.
                gfx.clear(0, 0, 0)
                gfx.endFrame()
                if os.shutdown then pcall(os.shutdown) end
                return
            elseif ev.type == "terminate" then
                return  -- computer reboot / ctrl-T
            end

            if ev.type == "key" and ev.key == keys.escape then
                startmenu.close()
                desktop.closeContext()
            end

            -- Route: dashboard first, fall back to windows.
            if not routeDashboardEvent(ev) then
                wm.pump(ev)
            end
        end
    end
end

return M
