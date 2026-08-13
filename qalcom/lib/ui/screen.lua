local Screen = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function token(UI, name, fallback)
    return UI and UI.colors and (UI.colors[name] or fallback) or fallback
end

function Screen.begin(target, title, _subtitle, options)
    options = options or {}
    local width, height = target.getSize()
    local UI = options.ui
    target.setBackgroundColor(options.background or (UI and token(UI, "surfaceBase", token(UI, "surface", colors.white)) or colors.white))
    target.setTextColor(options.foreground or (UI and token(UI, "text", colors.black) or colors.black))
    target.clear()
    if options.card ~= false and UI then
        -- Keep the app title in the window chrome. Content starts immediately
        -- below it; status and context belong to the individual app body.
        UI.sectionHeader(target, 1, 1, width, title, {
            background = token(UI, "section", colors.yellow),
            foreground = token(UI, "sectionText", colors.black),
        })
    end
    return width, height, 2
end

-- Standard responsive shell. The kernel still owns the outer window title bar;
-- this shell owns the app surface, status rail, tabs, content bounds, and footer.
-- Apps should use Screen.app rather than drawing a private top-level layout.
function Screen.shell(target, title, options)
    options = options or {}
    local UI = options.ui
    local width, height = Screen.begin(target, title, options.subtitle, options)
    local metrics = UI and (UI.metricsFor and UI.metricsFor(width, height) or UI.metrics) or {
        outerPadding = 2,
        headerHeight = 2,
        footerHeight = 2,
        sectionGap = 1,
    }
    local headerHeight = math.max(1, math.floor(tonumber(options.headerHeight) or metrics.headerHeight))
    local footerHeight = math.max(0, math.floor(tonumber(options.footerHeight) or (options.footer and metrics.footerHeight or 0)))
    local bodyY = math.min(height + 1, headerHeight + 1)
    local bodyBottom = math.min(height, math.max(bodyY - 1, height - footerHeight))
    local bodyX = math.max(1, math.floor(tonumber(options.bodyX) or metrics.outerPadding))
    local bodyWidth = math.max(0, width - bodyX * 2 + 1)
    local bodyHeight = bodyY <= bodyBottom and bodyBottom - bodyY + 1 or 0
    local bodySurface = token(UI, "surfaceBase", token(UI, "surface", colors.white))
    local bodyText = token(UI, "textPrimary", token(UI, "text", colors.black))
    local secondary = token(UI, "textSecondary", token(UI, "textMuted", colors.gray))

    local function consumeRow()
        bodyY = bodyY + 1
        bodyHeight = math.max(0, bodyBottom - bodyY + 1)
    end

    if UI and options.subtitle and options.subtitle ~= "" and bodyY <= bodyBottom then
        UI.text(target, bodyX, bodyY, options.subtitle, secondary, bodySurface, bodyWidth)
        consumeRow()
    end

    -- Every migrated app gets the same status rail directly below its title:
    -- quiet for normal state, but still visibly distinct from content and able to
    -- carry warning/success colors without each app inventing its own chrome.
    if UI and options.status and options.status ~= "" and bodyY <= bodyBottom then
        local statusBackground = options.statusBackground or token(UI, "surfaceInset", token(UI, "surfaceAlt", colors.lightGray))
        local statusColor = options.statusColor or secondary
        UI.fill(target, bodyX, bodyY, bodyWidth, 1, statusBackground)
        UI.fill(target, bodyX, bodyY, 1, 1, options.statusAccent or token(UI, "accent", colors.blue))
        UI.text(target, bodyX + 2, bodyY, options.status, statusColor, statusBackground, math.max(1, bodyWidth - 2))
        consumeRow()
    end

    local tabs = options.tabs
    local tabRects = {}
    if UI and type(tabs) == "table" and #tabs > 0 and bodyY <= bodyBottom then
        local tabWidth = math.max(1, math.floor(bodyWidth / #tabs))
        for index, tab in ipairs(tabs) do
            local label = type(tab) == "table" and tab.label or tab
            local x = bodyX + (index - 1) * tabWidth
            local currentWidth = index == #tabs and bodyX + bodyWidth - x or tabWidth
            local active = index == (options.activeTab or 1)
            UI.button(target, x, bodyY, currentWidth, label, active, {
                height = 1,
                variant = active and "accent" or "subtle",
                activeBackground = token(UI, "accent", colors.blue),
                activeForeground = token(UI, "textInverse", colors.white),
                background = token(UI, "surfaceInset", colors.lightGray),
                foreground = bodyText,
            })
            tabRects[index] = { x = x, y = bodyY, width = currentWidth, height = 1, index = index, value = tab }
        end
        consumeRow()
        if bodyY <= bodyBottom then consumeRow() end
    end

    if UI and type(options.footer) == "table" and height >= 1 then
        local footerText = table.concat(options.footer, "   ")
        local footerBackground = options.footerBackground or bodySurface
        UI.fill(target, bodyX, height, bodyWidth, 1, footerBackground)
        UI.text(target, bodyX, height, footerText, token(UI, "textSubtle", colors.gray), footerBackground, bodyWidth)
    end

    return {
        width = width,
        height = height,
        metrics = metrics,
        body = { x = bodyX, y = bodyY, width = bodyWidth, height = bodyHeight },
        tabs = tabRects,
        footer = { x = bodyX, y = height, width = bodyWidth, height = 1 },
    }
end

-- Canonical entry point for applications. Keeping this tiny wrapper separate
-- from Screen.shell makes the migration explicit and gives future apps one
-- stable contract: shell.body is the only area they should draw into.
function Screen.app(target, title, options)
    options = options or {}
    options.ui = options.ui or dofile("/qalcom/lib/ui.lua")
    return Screen.shell(target, title, options)
end

function Screen.bodyRect(shell, padding)
    local body = shell and shell.body or {}
    padding = math.max(0, math.floor(tonumber(padding) or 0))
    return {
        x = body.x + padding,
        y = body.y + padding,
        width = math.max(0, body.width - padding * 2),
        height = math.max(0, body.height - padding * 2),
    }
end

function Screen.splitRect(shell, ratio, gap)
    local body = shell and shell.body or {}
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0.5))
    gap = math.max(0, math.floor(tonumber(gap) or (shell.metrics and shell.metrics.sectionGap or 1)))
    local available = math.max(0, body.width - gap)
    local leftWidth = math.floor(available * ratio)
    return {
        left = { x = body.x, y = body.y, width = leftWidth, height = body.height },
        right = { x = body.x + leftWidth + gap, y = body.y, width = math.max(0, body.width - leftWidth - gap), height = body.height },
    }
end

function Screen.section(target, UI, rect, label, options)
    if not rect or rect.width < 1 or rect.height < 1 then return end
    options = options or {}
    UI.sectionHeader(target, rect.x, rect.y, rect.width, label, options)
    return { x = rect.x, y = rect.y + 1, width = rect.width, height = math.max(0, rect.height - 1) }
end

function Screen.emptyState(target, UI, rect, title, detail, options)
    options = options or {}
    local x = math.max(1, math.floor(tonumber(rect.x) or 1))
    local y = math.max(1, math.floor(tonumber(rect.y) or 1))
    local width = math.max(0, math.floor(tonumber(rect.width) or 0))
    local height = math.max(0, math.floor(tonumber(rect.height) or 0))
    if width < 1 or height < 1 then return end
    local centerY = y + math.max(0, math.floor(height / 2) - 1)
    UI.text(target, x, centerY, title, options.titleColor or token(UI, "text", colors.black), options.background or token(UI, "surface", colors.white), width)
    if detail and height > 2 then
        UI.text(target, x, centerY + 1, detail, options.detailColor or token(UI, "textMuted", colors.gray), options.background or token(UI, "surface", colors.white), width)
    end
end

function Screen.notice(target, UI, rect, message, kind)
    local color = token(UI, kind == "danger" and "dangerSoft" or kind == "warning" and "warningSoft" or kind == "success" and "successSoft" or "accentSoft", colors.lightBlue)
    local foreground = kind == "warning" and token(UI, "sectionText", colors.black) or token(UI, "textInverse", colors.white)
    UI.fill(target, rect.x, rect.y, rect.width, 1, color)
    UI.text(target, rect.x + 1, rect.y, message, foreground, color, math.max(1, rect.width - 2))
    return { x = rect.x, y = rect.y, width = rect.width, height = 1, kind = kind }
end

function Screen.card(target, UI, x, y, width, height, title)
    UI.card(target, x, y, width, height, title, token(UI, "accentSoft", token(UI, "surfaceInset", UI.colors.surfaceAlt)), true)
end

return Screen
