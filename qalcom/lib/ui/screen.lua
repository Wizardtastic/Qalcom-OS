local Screen = {}

function Screen.begin(target, title, subtitle, options)
    options = options or {}
    local width, height = target.getSize()
    target.setBackgroundColor(options.background or colors.white)
    target.setTextColor(options.foreground or colors.black)
    target.clear()
    if options.card ~= false then
        local UI = options.ui
        if UI then
            UI.fill(target, 1, 1, width, 1, UI.colors.accent)
            UI.text(target, 2, 1, title, colors.white, UI.colors.accent, width - 3)
            if subtitle and height >= 3 then
                UI.fill(target, 1, 2, width, 1, UI.colors.surfaceAlt)
                UI.text(target, 2, 2, subtitle, UI.colors.muted, UI.colors.surfaceAlt, width - 3)
                UI.divider(target, 1, 3, width, UI.colors.borderStrong)
            end
        end
    end
    return width, height, height >= 3 and 4 or 2
end

function Screen.footer(target, UI, lines, row)
    local width, height = target.getSize()
    row = row or math.max(1, height - #lines + 1)
    UI.fill(target, 1, row, width, height - row + 1, UI.colors.surfaceAlt)
    for index, line in ipairs(lines) do
        if row + index - 1 <= height then
            UI.text(target, 2, row + index - 1, line, UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        end
    end
end

function Screen.card(target, UI, x, y, width, height, title)
    UI.card(target, x, y, width, height, title, UI.colors.surfaceAlt, true)
end

return Screen
