local UI = {}
UI.version = dofile("/qalcom/version.lua")

-- The native UI deliberately owns drawing primitives only. The kernel continues to
-- own event routing, processes, windows, sessions, and recovery.
UI.framework = "Qalcom Native UI"
UI.frameworkVersion = UI.version

UI.colors = {
    -- Legacy names remain stable for existing applications.
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

    -- Semantic tokens for new and migrated applications.
    desktopElevated = colors.lightBlue,
    surfaceInset = colors.lightGray,
    surfaceSelected = colors.lightBlue,
    surfaceHover = colors.lightBlue,
    surfaceDisabled = colors.gray,
    textMuted = colors.gray,
    textSubtle = colors.gray,
    textInverse = colors.white,
    divider = colors.gray,
    focus = colors.lightBlue,
    accentSoft = colors.lightBlue,
    accentStrong = colors.blue,
    info = colors.lightBlue,
    successSoft = colors.lime,
    warningSoft = colors.yellow,
    dangerSoft = colors.red,
    button = colors.gray,
    buttonText = colors.black,
    buttonActive = colors.blue,
    section = colors.yellow,
    sectionText = colors.black,
    taskbar = colors.lightGray,
    taskbarHover = colors.gray,
    titleActive = colors.yellow,
    titleInactive = colors.gray,
    titleControl = colors.black,
    statusText = colors.white,
    infoText = colors.black,
    successText = colors.black,
    dangerText = colors.white,
    warningText = colors.black,

    -- Compatibility aliases used by older shell code.
    lightBlue = colors.lightBlue,
}

UI.metrics = {
    outerPadding = 2,
    contentPadding = 1,
    sectionGap = 1,
    compactRow = 1,
    standardRow = 2,
    headerHeight = 2,
    footerHeight = 2,
    minButtonWidth = 7,
    minContentWidth = 4,
    minContentHeight = 2,
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

function UI.clampText(text, width)
    return clampText(text, width)
end

function UI.clampRect(x, y, width, height, minimumWidth, minimumHeight)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    minimumWidth = math.floor(tonumber(minimumWidth) or 0)
    minimumHeight = math.floor(tonumber(minimumHeight) or 0)
    return x, y, math.max(minimumWidth, width), math.max(minimumHeight, height)
end

function UI.layoutPadded(x, y, width, height, paddingX, paddingY)
    width = math.max(0, math.floor(tonumber(width) or 0))
    height = math.max(0, math.floor(tonumber(height) or 0))
    paddingX = math.max(0, math.floor(tonumber(paddingX) or UI.metrics.contentPadding))
    paddingY = math.max(0, math.floor(tonumber(paddingY) or UI.metrics.contentPadding))
    local contentWidth = math.max(0, width - paddingX * 2)
    local contentHeight = math.max(0, height - paddingY * 2)
    return x + paddingX, y + paddingY, contentWidth, contentHeight
end

function UI.layoutSplit(x, y, width, height, ratio, vertical, gap)
    width = math.max(0, math.floor(tonumber(width) or 0))
    height = math.max(0, math.floor(tonumber(height) or 0))
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0.5))
    gap = math.max(0, math.floor(tonumber(gap) or UI.metrics.sectionGap))
    local available = math.max(0, (vertical and height or width) - gap)
    gap = math.min(gap, vertical and height or width)
    available = math.max(0, (vertical and height or width) - gap)
    if vertical then
        local firstHeight = math.floor(available * ratio)
        local secondY = y + firstHeight + gap
        return x, y, width, firstHeight, x, secondY, width, math.max(0, height - firstHeight - gap)
    end
    local firstWidth = math.floor(available * ratio)
    local secondX = x + firstWidth + gap
    return x, y, firstWidth, height, secondX, y, math.max(0, width - firstWidth - gap), height
end

function UI.layoutContent(width, height, options)
    options = options or {}
    width = math.max(0, math.floor(tonumber(width) or 0))
    height = math.max(0, math.floor(tonumber(height) or 0))
    local left = math.max(1, math.floor(tonumber(options.x) or UI.metrics.outerPadding))
    local top = math.max(1, math.floor(tonumber(options.y) or UI.metrics.headerHeight + 1))
    local right = math.min(width, math.max(left, math.floor(tonumber(options.right) or width - UI.metrics.outerPadding)))
    local bottom = math.min(height, math.max(top, math.floor(tonumber(options.bottom) or height - UI.metrics.footerHeight)))
    if left > width or top > height or left > right or top > bottom then
        return left, top, 0, 0
    end
    return left, top, right - left + 1, bottom - top + 1
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
        local headerBackground = accent or UI.colors.section
        local headerForeground = headerBackground == UI.colors.section and UI.colors.sectionText or UI.colors.textInverse
        UI.fill(target, x + 1, y + 1, width - 2, 1, headerBackground)
        UI.text(target, x + 2, y + 1, title, headerForeground, headerBackground, width - 4)
    end
end

-- Fluent button variants. The default ("standard") preserves the historic
-- gray-keycap / accent-when-active behavior, so existing call sites are
-- unaffected; new call sites can pass options.variant = "accent" | "subtle" |
-- "ghost" | "danger" and options.disabled = true.
local function buttonVariant(name)
    if name == "accent" then
        return { bg = UI.colors.accent, fg = UI.colors.textInverse, abg = UI.colors.accentStrong or UI.colors.accent, afg = UI.colors.textInverse }
    elseif name == "danger" then
        local dfg = UI.colors.dangerText or UI.colors.textInverse
        return { bg = UI.colors.danger, fg = dfg, abg = UI.colors.danger, afg = dfg }
    elseif name == "subtle" or name == "ghost" then
        return { bg = UI.colors.surface, fg = UI.colors.text, abg = UI.colors.surfaceHover or UI.colors.surfaceAlt, afg = UI.colors.text }
    end
    return { bg = UI.colors.button, fg = UI.colors.buttonText, abg = UI.colors.buttonActive, afg = UI.colors.textInverse }
end

function UI.button(target, x, y, width, label, active, options)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(1, math.floor(tonumber(width) or 1))
    options = options or {}
    local height = math.max(1, math.floor(tonumber(options.height) or 1))
    local variant = buttonVariant(options.variant)
    local background, foreground
    if options.disabled then
        background = options.background or UI.colors.surfaceDisabled or UI.colors.surfaceMuted
        foreground = UI.colors.textMuted or UI.colors.muted
    else
        -- Explicit option colors still win, keeping older call sites pixel-identical.
        background = active and (options.activeBackground or variant.abg)
            or (options.background or variant.bg)
        foreground = active and (options.activeForeground or variant.afg)
            or (options.foreground or variant.fg)
    end
    UI.fill(target, x, y, width, height, background)
    local textY = y + math.floor((height - 1) / 2)
    -- Keep the label centered inside the button's own rectangle. UI.center is
    -- screen-centered by design, so using it here would place every button
    -- label relative to column one instead of the keycap.
    local labelText = clampText(label, width)
    local labelX = x + math.max(0, math.floor((width - #labelText) / 2))
    UI.text(target, labelX, textY, labelText, foreground, background, #labelText)
    return { x = x, y = y, width = width, height = height, label = label, disabled = options.disabled == true }
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
    local background = active and UI.colors.surfaceSelected or UI.colors.surfaceInset
    local foreground = active and UI.colors.textInverse or UI.colors.text
    UI.text(target, x, y - 1, label, UI.colors.muted, UI.colors.surface)
    UI.fill(target, x, y, width, 1, background)
    local display = secret and string.rep("*", #tostring(value or "")) or tostring(value or "")
    UI.text(target, x + 1, y, display, foreground, background, width - 2)
    if active then
        local cursor = math.min(width - 2, math.max(0, #display))
        UI.text(target, x + 1 + cursor, y, "_", UI.colors.textInverse, background, 1)
    end
end

function UI.toggle(target, x, y, width, label, on, options)
    -- Fluent switch: label on the left, a 3-cell track on the right that turns
    -- accent with the knob to the right when on. Returns the switch rect so the
    -- caller can hit-test a click or use the whole row.
    options = options or {}
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(4, math.floor(tonumber(width) or 4))
    local trackWidth = 3
    local switchX = x + width - trackWidth
    local labelBg = options.background or UI.colors.surface
    UI.fill(target, x, y, width, 1, labelBg)
    UI.text(target, x, y, tostring(label or ""), options.foreground or UI.colors.text, labelBg, math.max(1, width - trackWidth - 1))
    local track = on and UI.colors.accent or (UI.colors.surfaceMuted or UI.colors.surfaceInset)
    UI.fill(target, switchX, y, trackWidth, 1, track)
    local knobX = on and (switchX + trackWidth - 1) or switchX
    UI.fill(target, knobX, y, 1, 1, UI.colors.statusText or UI.colors.textInverse or colors.white)
    return { x = switchX, y = y, width = trackWidth, height = 1, rowX = x, rowWidth = width, on = on == true }
end

function UI.checkbox(target, x, y, label, checked, options)
    -- A compact checkbox: an accent box with a check when set, an inset box when
    -- clear, followed by the label. Returns the clickable box + row rect.
    options = options or {}
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    local boxBg = checked and UI.colors.accent or (UI.colors.surfaceInset or UI.colors.surfaceMuted)
    local boxFg = checked and UI.colors.textInverse or UI.colors.text
    UI.text(target, x, y, checked and "x" or " ", boxFg, boxBg, 1)
    local labelText = tostring(label or "")
    local labelWidth = math.max(0, math.floor(tonumber(options.width) or (#labelText + 2)) - 2)
    if labelWidth > 0 then
        UI.text(target, x + 2, y, labelText, options.foreground or UI.colors.text, options.background or UI.colors.surface, labelWidth)
    end
    return { x = x, y = y, width = 1, height = 1, checked = checked == true, label = labelText }
end

function UI.segmented(target, x, y, width, segments, selectedIndex, options)
    -- A segmented control: a row of touching buttons where the selected segment
    -- is accented. Returns a list of segment rects for hit-testing.
    options = options or {}
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.max(1, math.floor(tonumber(width) or 1))
    local count = math.max(1, #(segments or {}))
    local segWidth = math.max(1, math.floor(width / count))
    local rects = {}
    local cursor = x
    for index = 1, count do
        local label = tostring((segments and segments[index]) or index)
        local currentWidth = index == count and (x + width - cursor) or segWidth
        local active = index == (selectedIndex or 1)
        UI.button(target, cursor, y, currentWidth, label, active, {
            height = 1,
            variant = active and "accent" or "subtle",
            background = active and nil or (UI.colors.surfaceInset or UI.colors.surfaceAlt),
        })
        rects[index] = { x = cursor, y = y, width = currentWidth, height = 1, index = index, value = (segments and segments[index]) or index }
        cursor = cursor + currentWidth
    end
    return rects
end

function UI.progress(target, x, y, width, value, options)
    -- A rounded-feeling progress track: an inset rail with an accent fill. Shares
    -- the meter's math but uses the inset surface as the empty track.
    options = options or {}
    return UI.meter(target, x, y, width, value, options.color or UI.colors.accent, options.background or UI.colors.surfaceInset or UI.colors.surfaceMuted)
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
    local gap = width >= 42 and 1 or 0
    local preferredIconWidth = width >= 64 and 5 or 3
    -- The Start button and app icons form one cluster that is centered across the
    -- taskbar (Windows 11 style), with the system tray reserved on the right. The
    -- cluster may use everything from the left edge up to just before the tray.
    local maxCluster = math.max(startWidth, width - trayWidth - 1)
    local available = math.max(0, maxCluster - startWidth - gap)

    local iconWidth = preferredIconWidth
    local count = taskCount
    if taskCount > 0 then
        local fitted = math.floor((available + gap) / (iconWidth + gap))
        if fitted < count then
            iconWidth = 3
            fitted = math.floor((available + gap) / (iconWidth + gap))
        end
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
    end
    local overflow = count < taskCount
    -- Reserve room for a 2-wide overflow marker (plus its leading gap) by shrinking
    -- the icon count until the whole cluster still fits the available region. One
    -- icon may not free enough cells when icons are a single column wide.
    local function clusterSpan(c, withMarker)
        local span = startWidth
        if c > 0 then span = span + gap + c * iconWidth + math.max(0, c - 1) * gap end
        if withMarker then span = span + gap + 2 end
        return span
    end
    if overflow then
        while count > 0 and clusterSpan(count, true) > maxCluster do count = count - 1 end
        overflow = count < taskCount
    end
    local clusterWidth = clusterSpan(count, overflow)

    -- Center the cluster, then clamp so it never runs under the tray or off-screen.
    local clusterX = math.max(1, math.floor((width - clusterWidth) / 2) + 1)
    local maxEnd = math.max(startWidth, width - trayWidth - 1)
    if clusterX + clusterWidth - 1 > maxEnd then
        clusterX = math.max(1, maxEnd - clusterWidth + 1)
    end

    local items = { { kind = "start", x = clusterX, width = startWidth, label = "Q", title = "Qalcom" } }
    local cursor = clusterX + startWidth + (count > 0 and gap or 0)
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
    if overflow then
        items[#items + 1] = { kind = "overflow", x = cursor, width = 2, label = "..", title = tostring(taskCount - count) .. " more applications" }
    end
    return items, clusterX, clusterWidth
end

function UI.taskHealth(task)
    if not task then return nil end
    if task.failed or task.restartLocked or task.state == "crashed" then
        return { name = "error", glyph = "!", color = UI.colors.danger }
    end
    if task.kind == "service" and (task.state == "stopped" or task.closeRequested) then
        return { name = "warning", glyph = "~", color = UI.colors.warning }
    end
    if task.watchdog == "slow" then
        return { name = "warning", glyph = "~", color = UI.colors.warning }
    end
    if task.kind == "service" then
        return { name = "service", glyph = ".", color = UI.colors.info }
    end
    return nil
end

function UI.taskbar(target, width, y, tasks, focused, launcher, trayWidth, hoverX, hoverY)
    width = math.max(1, math.floor(tonumber(width) or 1))
    y = math.floor(tonumber(y) or 1)
    trayWidth = UI.taskbarTrayWidth(width, trayWidth)
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    UI.fill(target, 1, y, width, height, UI.colors.taskbar or UI.colors.surfaceAlt)
    local serviceHealth
    for _, task in ipairs(tasks or {}) do
        if task.hidden and task.kind == "service" then
            local health = UI.taskHealth(task)
            if health and (not serviceHealth or health.name == "error" or (health.name == "warning" and serviceHealth.name == "service")) then
                serviceHealth = health
            end
        end
    end
    local items = UI.taskbarLayout(width, tasks, trayWidth)
    local hovered
    for _, item in ipairs(items) do
        item.hovered = hoverX and hoverY and hoverX >= item.x and hoverX < item.x + item.width and hoverY >= y and hoverY < y + height
        if item.hovered then hovered = item end
        if item.kind == "start" then
            UI.taskbarStart(target, item.x, y, item.width, launcher, item.hovered)
        elseif item.kind == "task" then
            UI.taskbarIcon(target, item.x, y, item.width, item.label, item.task == focused and not item.task.minimized, item.hovered, UI.taskHealth(item.task))
        else
            UI.taskbarIcon(target, item.x, y, item.width, item.label, false, item.hovered, nil)
        end
    end
    -- Windows 11 system tray, right-aligned: stacked time over date, with a
    -- status line (computer ID + a service-health glyph) on the top row when
    -- there is room. Everything is anchored to the right edge of the taskbar.
    local trayX = width - trayWidth
    local taskbarBackground = UI.colors.taskbar or UI.colors.surfaceAlt
    local timeText = os.date("%H:%M")
    local dateText = os.date("%m/%d")
    local statusColor = serviceHealth and serviceHealth.color or UI.colors.textMuted or UI.colors.muted
    local timeColor = UI.colors.statusText or UI.colors.text
    local dateColor = UI.colors.textMuted or UI.colors.muted
    if height >= 3 then
        local statusText = "ID " .. tostring(os.getComputerID())
        if serviceHealth and serviceHealth.glyph then statusText = serviceHealth.glyph .. " " .. statusText end
        local statusWidth = math.min(#statusText, math.max(0, width - trayX + 1))
        if statusWidth > 0 then
            UI.text(target, width - statusWidth + 1, y, statusText, statusColor, taskbarBackground, statusWidth)
        end
        UI.text(target, width - #timeText + 1, y + 1, timeText, timeColor, taskbarBackground, #timeText)
        UI.text(target, width - #dateText + 1, y + 2, dateText, dateColor, taskbarBackground, #dateText)
    else
        -- Compact fallback: a single centered clock line with an optional glyph.
        local marker = serviceHealth and (serviceHealth.glyph .. " ") or ""
        local clockText = marker .. timeText
        local rowY = y + math.max(0, math.floor((height - 1) / 2))
        local clockWidth = math.min(#clockText, math.max(0, width - trayX + 1))
        if clockWidth > 0 then
            UI.text(target, width - clockWidth + 1, rowY, clockText, serviceHealth and serviceHealth.color or timeColor, taskbarBackground, clockWidth)
        end
    end
    if hovered and hovered.title and hovered.kind ~= "start" then
        local tipWidth = math.min(width - 2, math.max(8, #hovered.title + 2))
        local tipX = math.max(1, math.min(width - tipWidth + 1, hovered.x + math.floor((hovered.width - tipWidth) / 2)))
        -- Keep the tooltip on the taskbar's own top row. Windows never reach
        -- this row, so taskbar-only repaints do not need to restore window
        -- content that a tooltip was drawn over.
        local tipY = y
        UI.fill(target, tipX, tipY, tipWidth, 1, UI.colors.surfaceStrong)
        UI.text(target, tipX + 1, tipY, hovered.title, UI.colors.text, UI.colors.surfaceStrong, tipWidth - 2)
    end
end

function UI.sectionHeader(target, x, y, width, label, options)
    options = options or {}
    local background = options.background or UI.colors.section
    local foreground = options.foreground or UI.colors.sectionText
    UI.fill(target, x, y, width, 1, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
end

function UI.listRow(target, x, y, width, label, value, active, options)
    options = options or {}
    local background = active and (options.activeBackground or UI.colors.surfaceSelected)
        or (options.background or UI.colors.surface)
    local foreground = active and (options.activeForeground or UI.colors.textInverse)
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
    UI.text(target, x + 1, y, label, UI.colors.textInverse, color, width - 2)
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
        background = UI.colors.section,
        foreground = UI.colors.sectionText,
    })
end

function UI.captionButtons(x, y, width)
    -- Shared geometry for the Windows-11 style right-aligned caption buttons so
    -- rendering (UI.titleBar) and the kernel's hit-testing agree exactly.
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    if width < 3 then return nil end
    if width < 9 then
        -- Too narrow for three captions; expose only a close cell at the edge.
        return { close = { x = x + width - 1, y = y, width = 1 } }
    end
    return {
        minimize = { x = x + width - 6, y = y, width = 1 },
        maximize = { x = x + width - 4, y = y, width = 1 },
        close = { x = x + width - 2, y = y, width = 1 },
    }
end

function UI.titleBar(target, x, y, width, title, icon, active, maximized, hovered)
    -- Windows-11 title bar: body-matching surface, left-aligned icon + title,
    -- right-aligned minimize / maximize-restore / close captions. The close cell
    -- reddens on hover; the focused window shows a brighter title and an accent
    -- app icon while inactive windows recede.
    local color = active and (UI.colors.titleActive or UI.colors.surface) or (UI.colors.titleInactive or UI.colors.surfaceAlt or UI.colors.border)
    local titleForeground = active and (UI.colors.titleControl or UI.colors.text) or (UI.colors.textMuted or UI.colors.muted)
    local controlForeground = titleForeground
    UI.fill(target, x, y, width, 1, color)
    local caps = UI.captionButtons(x, y, width)

    if width < 9 then
        UI.text(target, x + 1, y, "-", controlForeground, color, 1)
        if caps and caps.close then
            local narrowClose = hovered == "close" and (UI.colors.danger) or color
            local narrowCloseFg = hovered == "close" and (UI.colors.dangerText or UI.colors.textInverse) or controlForeground
            UI.text(target, caps.close.x, y, "x", narrowCloseFg, narrowClose, 1)
        end
        return
    end

    -- Icon + left-aligned title, stopping one cell before the first caption.
    local iconText = tostring(icon or "")
    local labelX = x + 1
    if iconText ~= "" then
        local iconColor = active and (UI.colors.accent or controlForeground) or controlForeground
        UI.text(target, labelX, y, iconText, iconColor, color, math.max(1, math.min(#iconText, width - 8)))
        labelX = labelX + #iconText + 1
    end
    local titleWidth = math.max(0, (x + width - 6) - labelX)
    if titleWidth > 0 then
        UI.text(target, labelX, y, tostring(title or ""), titleForeground, color, titleWidth)
    end

    -- Right-aligned captions. Minimize and maximize/restore share a subtle hover
    -- highlight; close uses the danger color on hover per Windows convention.
    local hoverBg = UI.colors.surfaceHover or color
    local minBg = hovered == "minimize" and hoverBg or color
    UI.text(target, caps.minimize.x, y, "-", controlForeground, minBg, 1)
    local maxBg = hovered == "maximize" and hoverBg or color
    UI.text(target, caps.maximize.x, y, maximized and "=" or "+", controlForeground, maxBg, 1)
    local closeBg = hovered == "close" and (UI.colors.danger) or color
    local closeFg = hovered == "close" and (UI.colors.dangerText or UI.colors.textInverse) or controlForeground
    UI.text(target, caps.close.x, y, "x", closeFg, closeBg, 1)
end

function UI.windowFrame(target, x, y, width, height, active)
    -- A one-cell neutral hairline around a window body for gentle definition on
    -- the desktop. It is deliberately NOT accent-colored: focus is conveyed by
    -- the title bar (brighter title + accent icon), not a blue outline. Drawn
    -- entirely inside the window rectangle so it never extends past the frame the
    -- kernel already restores, keeping the targeted-repaint / window-move
    -- invariants intact. (active is accepted for call-site compatibility.)
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width < 2 or height < 2 then return end
    local color = UI.colors.border or UI.colors.divider
    UI.fill(target, x, y, 1, height, color)                  -- left column
    UI.fill(target, x + width - 1, y, 1, height, color)      -- right column
    UI.fill(target, x, y + height - 1, width, 1, color)      -- bottom row
end

-- Wallpaper styles selectable in Settings. "bloom" (a soft gradient) is a
-- graphics-mode (Track B) style; in text mode it falls back to the solid base.
UI.wallpapers = { "solid", "dots" }

function UI.desktopRegion(target, x, y, width, height, style)
    -- Paint a desktop region with the selected wallpaper. Every style is a pure
    -- function of the absolute (x, y) cell, so restoring a window-exposed
    -- sub-region redraws pixel-identically to a full desktop paint -- this is what
    -- lets the kernel restore moved/closed windows without a full repaint.
    style = style or "solid"
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width < 1 or height < 1 then return end
    UI.fill(target, x, y, width, height, UI.colors.desktop)
    if style == "dots" then
        -- A subtle, evenly spaced dot grid -- a calm modern desktop texture.
        local dotColor = UI.colors.desktopGlow or UI.colors.divider or UI.colors.desktop
        for cy = y, y + height - 1 do
            if cy % 3 == 0 then
                for cx = x, x + width - 1 do
                    if cx % 6 == 0 then
                        UI.text(target, cx, cy, ".", dotColor, UI.colors.desktop, 1)
                    end
                end
            end
        end
    end
end

function UI.desktopBackground(target, width, height, style)
    -- The desktop occupies everything above the taskbar. Window chrome and the
    -- taskbar provide the visual structure; the wallpaper stays calm behind them.
    UI.desktopRegion(target, 1, 1, width, math.max(1, height - 2), style)
end

function UI.taskButton(target, x, y, width, label, active)
    local background = active and UI.colors.accent or UI.colors.surfaceAlt
    local foreground = active and UI.colors.textInverse or UI.colors.text
    UI.fill(target, x, y, width, 2, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
    if active then UI.fill(target, x, y + 1, width, 1, UI.colors.accentLight) end
end

function UI.taskbarIcon(target, x, y, width, icon, active, hovered, health)
    -- Focused or hovered apps get a highlighted tile; a colored top rail and glyph
    -- still expose health without relying on color alone.
    local highlighted = active or hovered
    local background = highlighted and (UI.colors.taskbarHover or UI.colors.surfaceAlt) or (UI.colors.taskbar or UI.colors.surfaceAlt)
    local foreground = UI.colors.text
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    UI.fill(target, x, y, width, height, background)
    if health then
        UI.fill(target, x, y, width, 1, health.color)
        if width >= 2 then UI.text(target, x + width - 1, y, health.glyph, UI.colors.textInverse, health.color, 1) end
    end
    local iconWidth = health and math.max(1, width - 2) or math.max(1, width)
    local iconText = tostring(icon or "?")
    local iconX = x + math.max(0, math.floor((width - math.min(#iconText, iconWidth)) / 2))
    local iconY = y + math.floor((height - 1) / 2)
    UI.text(target, iconX, iconY, iconText, foreground, background, iconWidth)
    -- Running/focus indicator on the bottom row: a wide accent pill for the
    -- focused window, a small muted dot for other running apps (Windows 11 style).
    local bottomRow = y + height - 1
    if active then
        local pillWidth = math.max(1, width - 2)
        local pillX = x + math.floor((width - pillWidth) / 2)
        UI.fill(target, pillX, bottomRow, pillWidth, 1, UI.colors.accent)
    else
        local dotX = x + math.floor((width - 1) / 2)
        UI.fill(target, dotX, bottomRow, 1, 1, UI.colors.textMuted or UI.colors.muted)
    end
end

function UI.taskbarStart(target, x, y, width, active, hovered)
    -- Windows-style Start button: no colored fill, an accent "Q" logo, a hover/open
    -- tile highlight, and an accent indicator when the launcher is open.
    local background = (active or hovered) and (UI.colors.taskbarHover or UI.colors.surfaceHover or UI.colors.surfaceAlt)
        or (UI.colors.taskbar or UI.colors.surfaceAlt)
    local foreground = UI.colors.accent or UI.colors.textInverse
    local height = math.min(3, select(2, target.getSize()) - y + 1)
    UI.fill(target, x, y, width, height, background)
    local label = "Q"
    local labelX = x + math.max(0, math.floor((width - #label) / 2))
    local labelY = y + math.floor((height - 1) / 2)
    UI.text(target, labelX, labelY, label, foreground, background, math.max(1, width))
    if active then
        local pillWidth = math.max(1, width - 2)
        local pillX = x + math.floor((width - pillWidth) / 2)
        UI.fill(target, pillX, y + height - 1, pillWidth, 1, UI.colors.accent)
    end
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
    local headerBackground = accent or UI.colors.section
    local headerForeground = headerBackground == UI.colors.section and UI.colors.sectionText or UI.colors.textInverse
    UI.fill(target, x + 1, y + 1, boxWidth - 2, 1, headerBackground)
    UI.text(target, x + 2, y + 1, title, headerForeground, headerBackground, boxWidth - 4)
    local messageWidth = math.max(1, boxWidth - 4)
    local messageText = tostring(message or "")
    local row = y + 3
    for rawLine in (messageText .. "\n"):gmatch("(.-)\n") do
        local segment = rawLine
        while #segment > 0 and row < y + boxHeight - 2 do
            UI.text(target, x + 2, row, segment, UI.colors.text, UI.colors.surface, messageWidth)
            segment = segment:sub(messageWidth + 1)
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
