local UI = {}
UI.version = dofile("/qalcom/version.lua")

-- The native UI deliberately owns drawing primitives only. The kernel continues to
-- own event routing, processes, windows, sessions, and recovery.
UI.framework = "Qalcom Native UI"
UI.frameworkVersion = UI.version

UI.colors = {
    desktop = colors.blue,
    desktopDark = colors.darkBlue,
    desktopGlow = colors.lightBlue,
    surface = colors.white,
    surfaceAlt = colors.lightGray,
    surfaceStrong = colors.white,
    border = colors.gray,
    borderStrong = colors.lightBlue,
    text = colors.black,
    muted = colors.gray,
    accent = colors.blue,
    accentLight = colors.lightBlue,
    hover = colors.lightBlue,
    success = colors.lime,
    warning = colors.yellow,
    danger = colors.red,
    shadow = colors.gray,
}

local Animation = dofile("/qalcom/lib/ui/animation.lua")
UI.animator = Animation.new()
UI.reducedMotion = false
UI.dirty = true

local function clampText(text, width)
    text = tostring(text or "")
    width = math.max(0, tonumber(width) or #text)
    if #text <= width then return text end
    if width <= 1 then return text:sub(1, width) end
    return text:sub(1, width - 1) .. "~"
end

function UI.markDirty()
    UI.dirty = true
end

function UI.clearDirty()
    UI.dirty = false
end

function UI.fill(target, x, y, width, height, background)
    -- Normalize coordinates at the primitive boundary. This keeps a malformed
    -- optional layout value from reaching CC:T's strict setCursorPos API.
    local targetWidth, targetHeight = target.getSize()
    x = math.max(1, math.min(targetWidth, math.floor(tonumber(x) or 1)))
    y = math.max(1, math.min(targetHeight, math.floor(tonumber(y) or 1)))
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    width = math.min(width, targetWidth - x + 1)
    height = math.min(height, targetHeight - y + 1)
    if width < 1 or height < 1 then return end
    target.setBackgroundColor(background or UI.colors.surface)
    local line = string.rep(" ", width)
    for row = y, y + height - 1 do
        target.setCursorPos(x, row)
        target.write(line)
    end
end

function UI.text(target, x, y, value, foreground, background, width)
    local targetWidth, targetHeight = target.getSize()
    x = math.max(1, math.min(targetWidth, math.floor(tonumber(x) or 1)))
    y = math.max(1, math.min(targetHeight, math.floor(tonumber(y) or 1)))
    width = math.floor(tonumber(width) or #tostring(value or ""))
    width = math.min(width, targetWidth - x + 1)
    value = clampText(value, width)
    if width < 1 then return end
    if background then target.setBackgroundColor(background) end
    if foreground then target.setTextColor(foreground) end
    target.setCursorPos(x, y)
    target.write(value)
end

function UI.center(target, y, value, foreground, background, width)
    local screenWidth = width
    if not screenWidth then screenWidth = select(1, target.getSize()) end
    value = clampText(value, screenWidth)
    local x = math.max(1, math.floor((screenWidth - #value) / 2) + 1)
    UI.text(target, x, y, value, foreground, background)
end

function UI.clearSurface(target, background)
    target.setBackgroundColor(background or UI.colors.surface)
    target.setTextColor(UI.colors.text)
    target.clear()
end

function UI.panel(target, x, y, width, height, background, border)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width < 1 or height < 1 then return end
    UI.fill(target, x, y, width, height, background or UI.colors.surface)
    if not border or width < 2 or height < 2 then return end
    target.setBackgroundColor(border)
    target.setCursorPos(x, y)
    target.write(string.rep(" ", width))
    target.setCursorPos(x, y + height - 1)
    target.write(string.rep(" ", width))
    for row = y + 1, y + height - 2 do
        target.setCursorPos(x, row)
        target.write(" ")
        target.setCursorPos(x + width - 1, row)
        target.write(" ")
    end
end

function UI.shadow(target, x, y, width, height, depth, color)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    depth = math.max(0, math.floor(tonumber(depth) or 1))
    if depth < 1 then return end
    color = color or UI.colors.shadow
    local targetWidth, targetHeight = target.getSize()
    for offset = 1, depth do
        local bottomX = math.max(1, x + offset)
        local bottomY = y + height - 1 + offset
        local bottomWidth = math.min(width, targetWidth - bottomX + 1)
        if bottomY >= 1 and bottomY <= targetHeight and bottomWidth > 0 then
            UI.fill(target, bottomX, bottomY, bottomWidth, 1, color)
        end
        local sideX = x + width - 1 + offset
        local sideY = math.max(1, y + offset)
        local sideHeight = math.min(height, targetHeight - sideY + 1)
        if sideX >= 1 and sideX <= targetWidth and sideHeight > 0 then
            UI.fill(target, sideX, sideY, 1, sideHeight, color)
        end
    end
end

function UI.card(target, x, y, width, height, title, accent, withShadow)
    if withShadow ~= false then UI.shadow(target, x, y, width, height, 1) end
    UI.panel(target, x, y, width, height, UI.colors.surfaceStrong, UI.colors.border)
    if title and height >= 3 then
        UI.fill(target, x + 1, y + 1, width - 2, 1, accent or UI.colors.surfaceAlt)
        UI.text(target, x + 2, y + 1, title, UI.colors.accent, accent or UI.colors.surfaceAlt, width - 4)
    end
end

function UI.button(target, x, y, width, label, active)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(1, math.floor(tonumber(width) or 1))
    local background = active and UI.colors.accent or UI.colors.surfaceAlt
    local foreground = active and colors.white or UI.colors.text
    UI.fill(target, x, y, width, 1, background)
    -- Flat Fluent-style controls: state is communicated by contrast, not brackets.
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
end

function UI.input(target, x, y, width, label, value, active, secret)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(4, math.floor(tonumber(width) or 4))
    local background = active and UI.colors.accentLight or UI.colors.surfaceAlt
    local foreground = active and colors.white or UI.colors.text
    UI.text(target, x, y - 1, label, UI.colors.muted, UI.colors.surface)
    UI.fill(target, x, y, width, 1, background)
    local display = secret and string.rep("*", #tostring(value or "")) or tostring(value or "")
    UI.text(target, x + 1, y, display, foreground, background, width - 2)
    if active then
        local cursor = math.min(width - 2, math.max(0, #display))
        UI.text(target, x + 1 + cursor, y, "_", colors.white, background, 1)
    end
end

function UI.taskbarLayout(width, tasks)
    width = math.max(1, math.floor(tonumber(width) or 1))
    local items = { { kind = "start", x = 1, width = 10, label = "Start" } }
    local total = 10
    for _, task in ipairs(tasks or {}) do
        local label = task.meta.icon .. (task.minimized and " + " or " ") .. task.meta.title
        local buttonWidth = math.min(16, math.max(8, #label + 2))
        items[#items + 1] = { kind = "task", task = task, x = 1, width = buttonWidth, label = label }
        total = total + 1 + buttonWidth
    end
    local usableWidth = math.max(10, width - 15)
    local start = math.max(2, math.floor((usableWidth - total) / 2) + 1)
    local cursor = start
    for _, item in ipairs(items) do
        item.x = cursor
        cursor = cursor + item.width + 1
    end
    return items, start, total
end

function UI.taskbar(target, width, y, tasks, focused, launcher, trayWidth)
    width = math.max(1, math.floor(tonumber(width) or 1))
    y = math.floor(tonumber(y) or 1)
    trayWidth = math.max(1, math.floor(tonumber(trayWidth) or 15))
    UI.fill(target, 1, y, width, 2, UI.colors.surfaceAlt)
    local items = UI.taskbarLayout(width, tasks)
    for _, item in ipairs(items) do
        if item.kind == "start" then
            UI.taskButton(target, item.x, y, item.width, launcher and "Q" or "Start", launcher)
        else
            UI.taskButton(target, item.x, y, item.width, item.label, item.task == focused and not item.task.minimized)
        end
    end
    UI.text(target, width - trayWidth, y, os.date("%H:%M"), UI.colors.text, UI.colors.surfaceAlt, 6)
    UI.text(target, width - 8, y, "ID " .. tostring(os.getComputerID()), UI.colors.muted, UI.colors.surfaceAlt, 7)
end

function UI.status(target, x, y, label, color, width)
    width = math.max(3, math.floor(width or (#tostring(label) + 2)))
    UI.fill(target, x, y, width, 1, color or UI.colors.accent)
    UI.text(target, x + 1, y, label, colors.white, color or UI.colors.accent, width - 2)
end

function UI.divider(target, x, y, width, background)
    UI.fill(target, x, y, width, 1, background or UI.colors.border)
end

function UI.header(target, title, subtitle)
    local width = select(1, target.getSize())
    UI.fill(target, 1, 1, width, 3, UI.colors.surfaceAlt)
    UI.text(target, 2, 1, title, UI.colors.accent, UI.colors.surfaceAlt, width - 3)
    if subtitle then UI.text(target, 2, 2, subtitle, UI.colors.muted, UI.colors.surfaceAlt, width - 3) end
    UI.divider(target, 1, 3, width, UI.colors.borderStrong)
end

function UI.titleBar(target, x, y, width, title, icon, active)
    local color = active and UI.colors.accent or UI.colors.border
    UI.fill(target, x, y, width, 1, color)
    local titleWidth = math.max(1, width - 12)
    local titleText = tostring(icon or "") .. "  " .. tostring(title or "")
    local titleX = x + math.max(2, math.floor((titleWidth - #titleText) / 2) + 1)
    UI.text(target, titleX, y, titleText, colors.white, color, titleWidth)
    if width >= 10 then
        UI.fill(target, x + width - 8, y, 3, 1, UI.colors.muted)
        UI.text(target, x + width - 7, y, "-", colors.white, UI.colors.muted, 1)
        UI.fill(target, x + width - 4, y, 3, 1, UI.colors.danger)
        UI.text(target, x + width - 3, y, "x", colors.white, UI.colors.danger, 1)
    end
end

function UI.desktopBackground(target, width, height)
    UI.fill(target, 1, 1, width, math.max(1, height - 2), UI.colors.desktop)
    if height >= 8 then
        UI.fill(target, 1, 1, width, 1, UI.colors.desktopDark)
        UI.fill(target, 1, 4, width, 1, UI.colors.desktopDark)
        UI.fill(target, 1, 5, width, 1, UI.colors.desktop)
    end
end

function UI.taskButton(target, x, y, width, label, active)
    local background = active and UI.colors.accent or UI.colors.surfaceAlt
    local foreground = active and colors.white or UI.colors.text
    UI.fill(target, x, y, width, 2, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
    if active then UI.fill(target, x, y + 1, width, 1, UI.colors.accentLight) end
end

function UI.composite(target, layers)
    for _, layer in ipairs(layers or {}) do
        if layer.visible ~= false and type(layer.draw) == "function" then layer.draw(target) end
    end
end

function UI.animate(target, properties, duration, curve, onUpdate, onComplete)
    if UI.reducedMotion then
        for key, value in pairs(properties or {}) do target[key] = value end
        if onUpdate then onUpdate(target, 1) end
        if onComplete then onComplete(target) end
        return nil
    end
    UI.markDirty()
    return UI.animator:to(target, properties, duration, curve, function(value, progress)
        UI.markDirty()
        if onUpdate then onUpdate(value, progress) end
    end, onComplete)
end

function UI.tick(now)
    local changed = UI.animator:update(now)
    if changed then UI.markDirty() end
    return changed
end

function UI.setReducedMotion(enabled)
    UI.reducedMotion = enabled == true
    if UI.reducedMotion then UI.animator:clear() end
end

function UI.dialog(target, title, message, accent)
    local width, height = target.getSize()
    local boxWidth = math.min(width - 4, math.max(24, #tostring(message or "") + 6))
    local boxHeight = math.max(3, math.min(7, height - 5))
    local x = math.floor((width - boxWidth) / 2) + 1
    local y = math.max(2, math.floor((height - boxHeight) / 2))
    UI.shadow(target, x, y, boxWidth, boxHeight, 1)
    UI.panel(target, x, y, boxWidth, boxHeight, UI.colors.surface, UI.colors.borderStrong)
    UI.fill(target, x + 1, y + 1, boxWidth - 2, 1, accent or UI.colors.accent)
    UI.text(target, x + 2, y + 1, title, colors.white, accent or UI.colors.accent, boxWidth - 4)
    local messageWidth = math.max(1, boxWidth - 4)
    local messageText = tostring(message or "")
    local row = y + 3
    for line in (messageText .. "\n"):gmatch("(.-)\n") do
        while #line > 0 and row < y + boxHeight - 2 do
            UI.text(target, x + 2, row, line, UI.colors.text, UI.colors.surface, messageWidth)
            line = line:sub(messageWidth + 1)
            row = row + 1
        end
        if row >= y + boxHeight - 2 then break end
    end
    return x, y, boxWidth, boxHeight
end

function UI.safeName(path)
    local name = fs.getName(path)
    if name == "" then return "/" end
    return name
end

return UI
