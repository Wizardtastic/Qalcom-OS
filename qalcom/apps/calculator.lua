local UI = dofile("/qalcom/lib/ui.lua")
local Calculator = dofile("/qalcom/lib/calculator.lua")

return function(ctx)
    local state = Calculator.new()
    local keyLabels = {
        { "C", "+-", "%", "/" },
        { "7", "8", "9", "*" },
        { "4", "5", "6", "-" },
        { "1", "2", "3", "+" },
        { "", "0", ".", "=" },
    }
    local buttons = {}

    local function layout()
        local width, height = ctx.win.getSize()
        -- Match the reference proportions: a broad, right-aligned display and
        -- compact gray keys arranged in four columns with consistent spacing.
        local gapX = 2
        -- The reference uses small, clearly separated keycaps rather than
        -- full-width text rows. Keep four columns centered in wider windows.
        local keyWidth = math.max(3, math.min(5, math.floor((width - 8) / 4)))
        local gridWidth = keyWidth * 4 + gapX * 3
        local startX = math.max(1, math.floor((width - gridWidth) / 2) + 1)
        local keyHeight = 1
        local gridY
        local gapY
        if height >= 16 then
            gridY, gapY = 4, math.max(1, math.floor((height - 4 - 1) / 4) - 1)
        elseif height >= 10 then
            gridY = 3
            gapY = math.max(0, math.floor((height - gridY - 1) / 4) - 1)
        else
            gridY, gapY = 2, 0
        end
        return width, height, startX, gridY, keyWidth, keyHeight, gapX, gapY
    end

    local function render()
        local width, height, startX, gridY, keyWidth, keyHeight, gapX, gapY = layout()
        ctx.win.setBackgroundColor(colors.lightGray)
        ctx.win.setTextColor(colors.black)
        ctx.win.clear()
        buttons = {}

        -- The kernel owns the yellow title bar. This is the calculator body from
        -- the reference: gray surround, white display, then visible gray keys.
        UI.fill(ctx.win, 1, 1, width, height, colors.lightGray)
        local displayY = height >= 10 and 2 or 1
        UI.fill(ctx.win, 2, displayY, width - 4, 1, colors.white)
        local display = Calculator.display(state)
        UI.text(ctx.win, width - #display - 2, displayY, display, colors.black, colors.white, #display + 1)

        for row = 1, #keyLabels do
            for column = 1, 4 do
                local x = startX + (column - 1) * (keyWidth + gapX)
                local y = gridY + (row - 1) * (keyHeight + gapY)
                local label = keyLabels[row][column]
                local key = { x = x, y = y, width = keyWidth, height = keyHeight, label = label, row = row, column = column }
                buttons[#buttons + 1] = key
                -- Blank lower-left cell is intentionally a visible empty key,
                -- matching the reference image's keypad geometry.
                UI.button(ctx.win, x, y, keyWidth, label, false, {
                    background = colors.gray,
                    foreground = colors.black,
                })
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
