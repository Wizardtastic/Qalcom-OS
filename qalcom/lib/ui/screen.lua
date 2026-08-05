local Screen = {}

function Screen.begin(target, title, subtitle, options)
    options = options or {}
    local width, height = target.getSize()
    local UI = options.ui
    target.setBackgroundColor(options.background or (UI and UI.colors.surfaceAlt or colors.white))
    target.setTextColor(options.foreground or (UI and UI.colors.text or colors.black))
    target.clear()
    if options.card ~= false and UI then
        -- Shared app header: yellow identity strip, muted status strip, and a
        -- single blue accent rule. Apps below this point can focus on content.
        UI.sectionHeader(target, 1, 1, width, title, {
            background = colors.yellow,
            foreground = colors.black,
        })
        if subtitle and height >= 3 then
            UI.fill(target, 1, 2, width, 1, UI.colors.surfaceAlt)
            UI.text(target, 2, 2, subtitle, UI.colors.muted, UI.colors.surfaceAlt, width - 3)
            UI.divider(target, 1, 3, width, UI.colors.accentLight)
        end
    end
    return width, height, height >= 3 and 4 or 2
end

function Screen.footer(target, UI, lines, row)
    return UI.footer(target, lines, {
        row = row,
        background = UI.colors.surfaceAlt,
        foreground = UI.colors.muted,
    })
end

function Screen.card(target, UI, x, y, width, height, title)
    UI.card(target, x, y, width, height, title, UI.colors.surfaceAlt, true)
end

return Screen
