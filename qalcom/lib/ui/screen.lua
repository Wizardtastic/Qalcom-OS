local Screen = {}

function Screen.begin(target, title, _subtitle, options)
    options = options or {}
    local width, height = target.getSize()
    local UI = options.ui
    target.setBackgroundColor(options.background or (UI and UI.colors.surfaceAlt or colors.white))
    target.setTextColor(options.foreground or (UI and UI.colors.text or colors.black))
    target.clear()
    if options.card ~= false and UI then
        -- Keep the app title in the window chrome. Content starts immediately
        -- below it; status and context belong to the individual app body.
        UI.sectionHeader(target, 1, 1, width, title, {
            background = colors.yellow,
            foreground = colors.black,
        })
    end
    return width, height, 2
end

function Screen.card(target, UI, x, y, width, height, title)
    UI.card(target, x, y, width, height, title, UI.colors.surfaceAlt, true)
end

return Screen
