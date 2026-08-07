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
    target.setBackgroundColor(options.background or (UI and token(UI, "surfaceAlt", colors.white) or colors.white))
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

-- New standard shell. Existing apps can keep using Screen.begin unchanged and
-- migrate incrementally by switching to Screen.shell when their layouts are
-- ready for the shared header/status/footer contract.
function Screen.shell(target, title, options)
    options = options or {}
    local UI = options.ui
    local width, height = Screen.begin(target, title, options.subtitle, options)
    local metrics = UI and UI.metrics or {
        outerPadding = 2,
        headerHeight = 2,
        footerHeight = 2,
        sectionGap = 1,
    }
    local headerHeight = math.max(1, math.floor(tonumber(options.headerHeight) or metrics.headerHeight))
    local footerHeight = math.max(0, math.floor(tonumber(options.footerHeight) or metrics.footerHeight))
    local bodyY = math.min(height + 1, headerHeight + 1)
    local bodyBottom = math.min(height, math.max(bodyY - 1, height - footerHeight))
    local bodyX = math.max(1, math.floor(tonumber(options.bodyX) or metrics.outerPadding))
    local bodyWidth = math.max(0, width - bodyX * 2 + 1)
    local bodyHeight = bodyY <= bodyBottom and bodyBottom - bodyY + 1 or 0

    if UI and options.subtitle and options.subtitle ~= "" and bodyY <= bodyBottom then
        UI.text(target, bodyX, bodyY, options.subtitle, token(UI, "textMuted", colors.gray), token(UI, "surfaceAlt", colors.white), bodyWidth)
        bodyY = bodyY + 1
        bodyHeight = math.max(0, bodyBottom - bodyY + 1)
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
                activeBackground = token(UI, "accent", colors.blue),
                activeForeground = token(UI, "textInverse", colors.white),
                background = token(UI, "surfaceInset", colors.lightGray),
                foreground = token(UI, "text", colors.black),
            })
            tabRects[index] = { x = x, y = bodyY, width = currentWidth, height = 1, index = index, value = tab }
        end
        bodyY = bodyY + 2
        bodyHeight = math.max(0, bodyBottom - bodyY + 1)
    end

    if UI and options.status and bodyY <= bodyBottom then
        local statusY = math.max(bodyY, bodyBottom - 1)
        UI.text(target, bodyX, statusY, options.status, token(UI, "textMuted", colors.gray), token(UI, "surface", colors.white), bodyWidth)
        bodyBottom = math.max(bodyY - 1, statusY - 1)
        bodyHeight = bodyY <= bodyBottom and bodyBottom - bodyY + 1 or 0
    end

    if UI and type(options.footer) == "table" and height >= 1 then
        local footerText = table.concat(options.footer, "   ")
        UI.text(target, bodyX, height, footerText, token(UI, "textSubtle", colors.gray), token(UI, "surface", colors.white), bodyWidth)
    end

    return {
        width = width,
        height = height,
        body = { x = bodyX, y = bodyY, width = bodyWidth, height = bodyHeight },
        tabs = tabRects,
        footer = { x = bodyX, y = height, width = bodyWidth, height = 1 },
    }
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
    UI.card(target, x, y, width, height, title, token(UI, "accentSoft", UI.colors.surfaceAlt), true)
end

return Screen
