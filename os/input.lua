-- os/input.lua — unified input event pump.
-- CC:Graphics surfaces **fire the standard ComputerCraft** mouse events
-- (`mouse_click`, `mouse_drag`, `mouse_up`) with pixel coordinates auto-
-- scaled to the graphics surface's size when the user clicks; no custom
-- peripheral polling is required. We just consume os.pullEventRaw and
-- normalise to a single event table.

local M = {}
local gfx = require("os.gfx")

local lastX, lastY = 0, 0
local dragging = false
local lastClickT = 0
local lastClickX, lastClickY = 0, 0
local lastClickButton = nil

local function ts()
    if os and os.epoch then return os.epoch("utc") end
    if os and os.clock then return math.floor(os.clock() * 1000) end
    return 0
end

-- Pull one event, blocking until it arrives.
-- On timeout (seconds) returns nil.  If timeout is nil, blocks forever.
function M.poll(timeout)
    local timer = (timeout and timeout > 0) and os.startTimer(timeout) or nil
    while true do
        local rawName, p1, p2, p3 = os.pullEventRaw()
        if rawName == "timer" and timer and p1 == timer then
            return nil
        end
        -- Forward qalcom-domain events that we queued from the start menu.
        if rawName == "qalcom_lock" or rawName == "qalcom_logout"
            or rawName == "qalcom_restart" or rawName == "qalcom_shutdown"
        then
            return {type = rawName}
        end
        local mapped = M._mapCC(rawName, p1, p2, p3)
        if mapped then return mapped end
    end
end

-- Non-blocking poll: returns nil if no event is currently available.
function M.pollNoBlock()
    local ok, rawName, p1, p2 = os.pullEventRaw("key", "char",
        "mouse_click", "mouse_up", "mouse_drag", "mouse_move",
        "monitor_touch",
        "qalcom_lock", "qalcom_logout", "qalcom_restart", "qalcom_shutdown")
    if not ok then return nil end
    return (rawName == "qalcom_lock" or rawName == "qalcom_logout"
        or rawName == "qalcom_restart" or rawName == "qalcom_shutdown")
        and {type = rawName} or M._mapCC(rawName, p1, p2)
end

-- Translate a ComputerCraft os.pullEvent block.
function M._mapCC(name, p1, p2, p3)
    if not name then return nil end
    local tms = ts()
    if name == "mouse_click" then
        lastX, lastY = p2, p3
        lastClickT, lastClickX, lastClickY, lastClickButton = tms, p2, p3, p1
        return {type="mouse_down", x=p2, y=p3, button=p1 or 1, ts=tms, isClick=true}
    elseif name == "mouse_drag" then
        local dx = (p2 or lastX) - lastX
        local dy = (p3 or lastY) - lastY
        lastX, lastY = p2 or lastX, p3 or lastY
        dragging = true
        return {type="mouse_drag", x=lastX, y=lastY, button=p1 or 1, ts=tms, dx=dx, dy=dy}
    elseif name == "mouse_up" then
        local wasDragging = dragging
        dragging = false
        return {type="mouse_up", x=p2 or lastX, y=p3 or lastY, button=p1 or 1,
                ts=tms, wasDragging=wasDragging}
    elseif name == "mouse_move" then
        -- CC:Graphics surfaces fire mouse_move with pixel coordinates while
        -- the user hovers.  Apps can use these for cursor-aware UX
        -- (tool-tips, hover affordances) instead of waiting for a click.
        lastX, lastY = p2, p3
        return {type="mouse_move", x=p2 or 0, y=p3 or 0, ts=tms}
    elseif name == "monitor_touch" then
        -- Treat monitor-touch as mouse_down at that coordinate
        lastX, lastY = p2, p3
        return {type="mouse_down", x=p2 or 0, y=p3 or 0, button=1, ts=tms, isClick=true}
    elseif name == "key" then
        return {type="key", key=p1, ts=tms, held=p3}
    elseif name == "char" then
        return {type="char", ch=p1, ts=tms}
    elseif name == "terminate" then
        return {type="terminate"}
    elseif name == "redstone" or name == "peripheral" or name == "peripheral_detach"
        or name == "disk" or name == "disk_eject"
        or name == "http_success" or name == "http_failure"
        or name == "http_check_success" or name == "http_check_failure"
        or name == "task_complete" then
        -- Pass through; handled by app/wm as needed.
        return {type = name, payload=p1, ts=tms}
    end
    return nil
end

-- Synthetic / auxiliary event helpers ---------------------------------------
function M.doubleClick(x, y, button, maxMs)
    button = button or 1
    maxMs  = maxMs or 500
    local now = ts()
    if lastClickButton == button and lastClickX == x and lastClickY == y
        and (now - lastClickT) <= maxMs then
        return true
    end
    return false
end

-- Reset cached state.
function M.reset()
    lastX, lastY = 0, 0
    dragging = false
    lastClickT = 0
    lastClickX, lastClickY, lastClickButton = 0, 0, nil
end

-- Currently known position (best-effort if no events have fired yet).
function M.cursor() return lastX, lastY end
function M.isDragging() return dragging end

return M
