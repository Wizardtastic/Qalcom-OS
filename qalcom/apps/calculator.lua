local UI = dofile("/qalcom/lib/ui.lua")
local Calculator = dofile("/qalcom/lib/calculator.lua")

return function(ctx)
    local state = Calculator.new()
    -- Windows 11 Calculator style keypad: a clear row, digits, an accent operator
    -- column, and an accent equals.
    local keyLabels = {
        { "C", "+-", "%", "/" },
        { "7", "8", "9", "*" },
        { "4", "5", "6", "-" },
        { "1", "2", "3", "+" },
        { "", "0", ".", "=" },
    }
    local buttons = {}

    local function keyVariant(label)
        if label == "=" then return "accent" end
        if label == "/" or label == "*" or label == "-" or label == "+" then return "accent" end
        if label == "C" then return "danger" end
        if label == "+-" or label == "%" then return "subtle" end
        return "standard"
    end

    local function keyGlyph(label)
        if label == "*" then return "x" end
        if label == "/" then return "\247" end
        if label == "+-" then return "+/-" end
        return label
    end

    local function expression()
        if state.pending and state.accumulator ~= nil then
            local op = state.pending == "*" and "x" or state.pending
            return tostring(state.accumulator) .. " " .. op
        end
        return ""
    end

    local function layout()
        local width, height = ctx.win.getSize()
        local displayRows = height >= 15 and 3 or 2
        local gridTop = displayRows + 2
        local gapX = width >= 30 and 1 or 0
        local keyWidth = math.max(3, math.floor((width - 2 - gapX * 3) / 4))
        local gridWidth = keyWidth * 4 + gapX * 3
        local startX = math.max(2, math.floor((width - gridWidth) / 2) + 1)
        local available = math.max(1, height - gridTop + 1)
        local rowStride = math.max(1, math.floor(available / 5))
        local keyHeight = math.max(1, rowStride - (rowStride >= 2 and 1 or 0))
        return width, height, startX, gridTop, keyWidth, keyHeight, gapX, rowStride, displayRows
    end

    local function render()
        local width, height, startX, gridTop, keyWidth, keyHeight, gapX, rowStride, displayRows = layout()
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        buttons = {}

        -- Display: a dark inset panel with a muted expression line above the large
        -- right-aligned result.
        UI.fill(ctx.win, 1, 1, width, displayRows + 1, UI.colors.surfaceInset)
        local expr = expression()
        if expr ~= "" then
            UI.text(ctx.win, width - #expr - 1, 1, expr, UI.colors.textMuted or UI.colors.muted, UI.colors.surfaceInset, #expr + 1)
        end
        local display = Calculator.display(state)
        local resultColor = state.error and UI.colors.danger or UI.colors.text
        UI.text(ctx.win, width - #display - 1, displayRows, display, resultColor, UI.colors.surfaceInset, #display + 1)

        for row = 1, #keyLabels do
            for column = 1, 4 do
                local label = keyLabels[row][column]
                local x = startX + (column - 1) * (keyWidth + gapX)
                local y = gridTop + (row - 1) * rowStride
                local key = { x = x, y = y, width = keyWidth, height = keyHeight, label = label, row = row, column = column }
                buttons[#buttons + 1] = key
                if label ~= "" then
                    UI.button(ctx.win, x, y, keyWidth, keyGlyph(label), false, {
                        height = keyHeight,
                        variant = keyVariant(label),
                    })
                end
            end
        end
    end

    local function activate(key)
        local label = key.label
        if label == "" then return end
        if label == "C" then Calculator.clear(state)
        elseif label == "+-" then Calculator.toggleSign(state)
        elseif label == "%" then Calculator.percent(state)
        elseif label == "." then Calculator.decimal(state)
        elseif label == "=" then Calculator.equals(state)
        elseif label == "+" or label == "-" or label == "*" or label == "/" then Calculator.operator(state, label)
        elseif label:match("^[0-9]$") then Calculator.inputDigit(state, label)
        end
        render()
    end

    render()
    while true do
        local event, value, x, y = ctx:pullEvent()
        if event == "key" then
            if value == keys.escape then
                ctx:close()
            elseif value == keys.backspace then
                Calculator.backspace(state)
                render()
            elseif value == keys.enter or (keys.numPadEnter and value == keys.numPadEnter) then
                Calculator.equals(state)
                render()
            elseif keys.add and value == keys.add then activate({ label = "+" })
            elseif keys.subtract and value == keys.subtract then activate({ label = "-" })
            elseif keys.multiply and value == keys.multiply then activate({ label = "*" })
            elseif keys.divide and value == keys.divide then activate({ label = "/" })
            end
        elseif event == "char" then
            if value:match("^[0-9]$") then activate({ label = value })
            elseif value == "." or value == "+" or value == "-" or value == "*" or value == "/" or value == "%" then activate({ label = value }) end
        elseif event == "mouse_click" then
            local key = UI.hitButton(buttons, x, y)
            if key then activate(key) end
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
