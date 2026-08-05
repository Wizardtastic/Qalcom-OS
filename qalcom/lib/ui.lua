local UI = {}
UI.version = dofile("/qalcom/version.lua")

UI.colors = {
    desktop = colors.blue,
    desktopDark = colors.darkBlue,
    surface = colors.white,
    surfaceAlt = colors.lightGray,
    border = colors.gray,
    text = colors.black,
    muted = colors.gray,
    accent = colors.blue,
    accentLight = colors.lightBlue,
    success = colors.lime,
    warning = colors.yellow,
    danger = colors.red,
}

local function clampText(text, width)
    text = tostring(text or "")
    if #text <= width then return text end
    if width <= 1 then return text:sub(1, width) end
    return text:sub(1, width - 1) .. "~"
end

function UI.fill(target, x, y, width, height, background)
    if width < 1 or height < 1 then return end
    target.setBackgroundColor(background)
    local line = string.rep(" ", width)
    for row = y, y + height - 1 do
        target.setCursorPos(x, row)
        target.write(line)
    end
end

function UI.text(target, x, y, value, foreground, background, width)
    value = clampText(value, width or #tostring(value or ""))
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

function UI.panel(target, x, y, width, height, background, border)
    UI.fill(target, x, y, width, height, background)
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

function UI.button(target, x, y, width, label, active)
    local background = active and UI.colors.accent or UI.colors.surfaceAlt
    local foreground = active and colors.white or UI.colors.text
    UI.fill(target, x, y, width, 1, background)
    UI.text(target, x + 1, y, label, foreground, background, math.max(1, width - 2))
end

function UI.divider(target, x, y, width, background)
    UI.fill(target, x, y, width, 1, background or UI.colors.border)
end

function UI.dialog(target, title, message, accent)
    local width, height = target.getSize()
    local boxWidth = math.min(width - 4, math.max(24, #tostring(message or "") + 6))
    -- Leave the bottom rows available for modal actions on compact terminals.
    local boxHeight = math.max(3, math.min(7, height - 5))
    local x = math.floor((width - boxWidth) / 2) + 1
    local y = math.max(2, math.floor((height - boxHeight) / 2))
    UI.panel(target, x, y, boxWidth, boxHeight, UI.colors.surface, UI.colors.border)
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
