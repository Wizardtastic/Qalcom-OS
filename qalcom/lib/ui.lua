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
    surfaceMuted = colors.gray,
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
local Hit = dofile("/qalcom/lib/ui/hit.lua")
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
    UI.text(target, x, y, value, foreground, background, #value)
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
        local headerBackground = accent or colors.yellow
        local headerForeground = headerBackground == colors.yellow and colors.black or UI.colors.accent
        UI.fill(target, x + 1, y + 1, width - 2, 1, headerBackground)
        UI.text(target, x + 2, y + 1, title, headerForeground, headerBackground, width - 4)
    end
end

function UI.button(target, x, y, width, label, active, options)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(1, math.floor(tonumber(width) or 1))
    options = options or {}
    local height = math.max(1, math.floor(tonumber(options.height) or 1))
    -- Use a distinct gray keycap by default. Previously inactive buttons used
    -- surfaceAlt, which is also the surrounding panel color, making the button
    -- disappear completely on character-cell displays.
    local background = active and (options.activeBackground or UI.colors.accent)
        or (options.background or colors.gray)
    local foreground = active and (options.activeForeground or colors.white)
        or (options.foreground or UI.colors.text)
    UI.fill(target, x, y, width, height, background)
    local textY = y + math.floor((height - 1) / 2)
    -- Keep the label centered inside the button's own rectangle. UI.center is
    -- screen-centered by design, so using it here would place every button
    -- label relative to column one instead of the keycap.
    local labelText = clampText(label, width)
    local labelX = x + math.max(0, math.floor((width - #labelText) / 2))
    UI.text(target, labelX, textY, labelText, foreground, background, #labelText)
    return { x = x, y = y, width = width, height = height, label = label }
end

function UI.inBounds(mouseX, mouseY, x, y, width, height)
    return Hit.inBounds(mouseX, mouseY, x, y, width, height)
end

function UI.hitButton(buttons, mouseX, mouseY)
    return Hit.button(buttons, mouseX, mouseY)
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

function UI.taskbarTrayWidth(width, requested)
    width = math.max(1, math.floor(tonumber(width) or 1))
    requested = math.max(1, math.floor(tonumber(requested) or 15))
    return math.min(requested, math.max(8, math.floor(width * 0.30)))
end

function UI.taskbarLayout(width, tasks, trayWidth)
    width = math.max(1, math.floor(tonumber(width) or 1))
    trayWidth = UI.taskbarTrayWidth(width, trayWidth)
    local visibleTasks = {}
    for _, task in ipairs(tasks or {}) do
        if not task.hidden then visibleTasks[#visibleTasks + 1] = task end
    end
    local taskCount = #visibleTasks
    local startWidth = width >= 36 and 5 or 3
    local firstAppX = startWidth + 1
    local lastX = math.max(firstAppX, width - trayWidth - 1)
    local available = math.max(1, lastX - firstAppX + 1)
    local gap = width >= 42 and 1 or 0
    local preferredIconWidth = width >= 64 and 5 or 3
    local iconWidth = preferredIconWidth
    local count = taskCount
    if taskCount > 0 then
        local fitted = math.floor((available + gap) / (iconWidth + gap))
        if fitted < count then
            iconWidth = 2
            fitted = math.floor((available + gap) / (iconWidth + gap))
        end
        if fitted < count then
            iconWidth = 1
            gap = 0
            fitted = available
        end
        count = math.min(taskCount, math.max(0, fitted))
        if count > 0 and count == taskCount then
            iconWidth = math.max(1, math.min(preferredIconWidth, math.floor((available - math.max(0, count - 1) * gap) / count)))
        end
    end
    local items = { { kind = "start", x = 1, width = startWidth, label = "Q", title = "Qalcom" } }
    -- Keep applications anchored to the left edge like a Windows taskbar:
    -- the first icon begins immediately after the Q launcher instead of being
    -- centered across the remaining tray space.
    local cursor = firstAppX
    for index = 1, count do
        local task = visibleTasks[index]
        items[#items + 1] = {
            kind = "task",
            task = task,
            x = cursor,
            width = iconWidth,
            label = tostring(task.meta.icon or "?"),
            title = tostring(task.meta.title or task.name or "Application"),
        }
        cursor = cursor + iconWidth + gap
    end
    if count < taskCount and cursor <= lastX then
        items[#items + 1] = { kind = "overflow", x = cursor, width = math.min(3, lastX - cursor + 1), label = "..", title = tostring(taskCount - count) .. " more applications" }
    end
    return items, firstAppX, available
end

function UI.taskbar(target, width, y, tasks, focused, launcher, trayWidth, hoverX, hoverY)
    width = math.max(1, math.floor(tonumber(width) or 1))
    y = math.floor(tonumber(y) or 1)
    trayWidth = UI.taskbarTrayWidth(width, trayWidth)
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    UI.fill(target, 1, y, width, height, UI.colors.surfaceAlt)
    local items = UI.taskbarLayout(width, tasks, trayWidth)
    local hovered
    for _, item in ipairs(items) do
        item.hovered = hoverX and hoverY and hoverX >= item.x and hoverX < item.x + item.width and hoverY >= y and hoverY < y + height
        if item.hovered then hovered = item end
        if item.kind == "start" then
            UI.taskbarStart(target, item.x, y, item.width, launcher, item.hovered)
        elseif item.kind == "task" then
            UI.taskbarIcon(target, item.x, y, item.width, item.label, item.task == focused and not item.task.minimized, item.hovered)
        else
            UI.taskbarIcon(target, item.x, y, item.width, item.label, false, item.hovered)
        end
    end
    local trayX = width - trayWidth
    UI.text(target, trayX, y + math.max(0, math.floor((height - 1) / 2)), os.date("%H:%M"), UI.colors.text, UI.colors.surfaceAlt, 6)
    UI.text(target, width - 8, y + math.max(0, math.floor((height - 1) / 2)), "ID " .. tostring(os.getComputerID()), UI.colors.muted, UI.colors.surfaceAlt, 7)
    if hovered and hovered.title and hovered.kind ~= "start" then
        local tipWidth = math.min(width - 2, math.max(8, #hovered.title + 2))
        local tipX = math.max(1, math.min(width - tipWidth + 1, hovered.x + math.floor((hovered.width - tipWidth) / 2)))
        local tipY = math.max(1, y - 1)
        UI.fill(target, tipX, tipY, tipWidth, 1, UI.colors.surfaceStrong)
        UI.text(target, tipX + 1, tipY, hovered.title, UI.colors.text, UI.colors.surfaceStrong, tipWidth - 2)
    end
end

function UI.sectionHeader(target, x, y, width, label, options)
    options = options or {}
    local background = options.background or colors.yellow
    local foreground = options.foreground or colors.black
    UI.fill(target, x, y, width, 1, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
end

function UI.listRow(target, x, y, width, label, value, active, options)
    options = options or {}
    local background = active and (options.activeBackground or UI.colors.accentLight)
        or (options.background or UI.colors.surface)
    local foreground = active and (options.activeForeground or colors.white)
        or (options.foreground or UI.colors.text)
    UI.fill(target, x, y, width, 1, background)
    local split = options.split or math.floor(width * 0.58)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, split - 1))
    if value ~= nil then
        UI.text(target, x + split, y, value, options.valueColor or foreground, background, math.max(1, width - split - 1))
    end
    return { x = x, y = y, width = width, height = 1 }
end

function UI.badge(target, x, y, label, color, width)
    width = math.max(3, math.floor(tonumber(width) or (#tostring(label or "") + 2)))
    color = color or UI.colors.accent
    UI.fill(target, x, y, width, 1, color)
    UI.text(target, x + 1, y, label, colors.white, color, width - 2)
    return { x = x, y = y, width = width, height = 1 }
end

function UI.meter(target, x, y, width, value, color, background)
    width = math.max(3, math.floor(tonumber(width) or 3))
    value = math.max(0, math.min(1, tonumber(value) or 0))
    local filled = math.floor((width - 2) * value + 0.5)
    background = background or UI.colors.surfaceMuted
    UI.fill(target, x, y, width, 1, background)
    if filled > 0 then UI.fill(target, x + 1, y, filled, 1, color or UI.colors.accent) end
    return { x = x, y = y, width = width, height = 1, value = value }
end

function UI.status(target, x, y, label, color, width)
    return UI.badge(target, x, y, label, color or UI.colors.accent, width)
end

function UI.divider(target, x, y, width, background)
    UI.fill(target, x, y, width, 1, background or UI.colors.border)
end

function UI.header(target, title)
    local width = select(1, target.getSize())
    UI.sectionHeader(target, 1, 1, width, title, {
        background = colors.yellow,
        foreground = colors.black,
    })
end

function UI.titleBar(target, x, y, width, title, icon, active, maximized)
    -- A simple, bright desktop chrome inspired by the supplied reference: the
    -- entire title row is yellow, controls sit on the left, and the content
    -- area below remains a clean white surface.
    local color = colors.yellow
    local foreground = colors.black
    local titleForeground = active and colors.black or colors.gray
    UI.fill(target, x, y, width, 1, color)
    if width < 9 then
        UI.text(target, x + 1, y, "x-+", foreground, color, math.max(1, width - 2))
        return
    end
    UI.text(target, x + 1, y, "x", foreground, color, 1)
    UI.text(target, x + 3, y, "-", foreground, color, 1)
    UI.text(target, x + 5, y, maximized and "=" or "+", foreground, color, 1)
    local titleText = tostring(icon or "") .. "  " .. tostring(title or "")
    local titleWidth = math.max(1, width - 8)
    local titleX = x + 8 + math.max(0, math.floor((titleWidth - #titleText) / 2))
    UI.text(target, titleX, y, titleText, titleForeground, color, titleWidth)
end

function UI.desktopBackground(target, width, height)
    -- Keep the desktop itself clean and uninterrupted. Window chrome and the
    -- taskbar provide the visual structure; the old branded strip at the top
    -- consumed desktop space and made the workspace look like a second bar.
    UI.fill(target, 1, 1, width, math.max(1, height - 2), UI.colors.desktop)
end

function UI.taskButton(target, x, y, width, label, active)
    local background = active and UI.colors.accent or UI.colors.surfaceAlt
    local foreground = active and colors.white or UI.colors.text
    UI.fill(target, x, y, width, 2, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
    if active then UI.fill(target, x, y + 1, width, 1, UI.colors.accentLight) end
end

function UI.taskbarIcon(target, x, y, width, icon, active, hovered)
    local background = UI.colors.surfaceAlt
    local foreground = UI.colors.text
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    -- Icons stay visually quiet on the taskbar. Hover is communicated by the
    -- name tooltip; selection is communicated only by the thin underline.
    UI.fill(target, x, y, width, height, background)
    local iconWidth = math.max(1, width - 2)
    local iconText = tostring(icon or "?")
    local iconX = x + math.max(0, math.floor((width - math.min(#iconText, iconWidth)) / 2))
    local iconY = y + math.floor((height - 1) / 2)
    UI.text(target, iconX, iconY, iconText, foreground, background, iconWidth)
    if active then UI.fill(target, x, y + height - 1, width, 1, UI.colors.accentLight) end
end

function UI.taskbarStart(target, x, y, width, active, hovered)
    local background = hovered and colors.lime or colors.green
    local foreground = colors.white
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    UI.fill(target, x, y, width, height, background)
    UI.center(target, y + math.floor((height - 1) / 2), "Q", foreground, background, width)
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
    UI.panel(target, x, y, boxWidth, boxHeight, UI.colors.surface, UI.colors.border)
    local headerBackground = accent or colors.yellow
    local headerForeground = headerBackground == colors.yellow and colors.black or colors.white
    UI.fill(target, x + 1, y + 1, boxWidth - 2, 1, headerBackground)
    UI.text(target, x + 2, y + 1, title, headerForeground, headerBackground, boxWidth - 4)
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
