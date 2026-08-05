local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local path = ctx.path or "/"
    local lines = {}
    local cursor = 1
    local column = 1
    local scroll = 1
    local dirty = false
    local status = "Read-only viewer"

    local function loadFile()
        lines = {}
        local text, reason = ctx:readFile(path)
        if text then
            for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        elseif reason and reason ~= "File not found" then
            status = reason
        end
        if #lines == 0 then lines = { "" } end
        cursor = 1
        column = 1
        scroll = 1
    end

    local function saveFile()
        local ok, reason = ctx:writeFile(path, table.concat(lines, "\n"))
        if not ok then
            status = reason or "Unable to save file"
            ctx:notify(status, UI.colors.danger)
            return
        end
        dirty = false
        status = "Saved " .. UI.safeName(path)
        ctx:notify(status, UI.colors.success)
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, UI.safeName(path), status .. (dirty and " *" or ""), { ui = UI })
        local visible = math.max(1, height - contentStart - 1)
        scroll = math.max(1, math.min(scroll, math.max(1, #lines - visible + 1)))
        for row = 1, visible do
            local index = scroll + row - 1
            if lines[index] then
                local prefix = (index == cursor and "> " or "  ") .. string.format("%03d ", index)
                local text = lines[index]
                if index == cursor then
                    text = text:sub(1, 80)
                    if column <= #text + 1 then text = text:sub(1, column - 1) .. "_" .. text:sub(column) end
                end
                UI.text(ctx.win, 2, contentStart + row - 1, prefix .. text, index == cursor and UI.colors.accent or UI.colors.text, UI.colors.surface, width - 3)
            end
        end
        UI.footer(ctx.win, "Arrows select   Ctrl+S save   Esc close", {
            row = height,
            background = UI.colors.surfaceAlt,
        })
    end

    loadFile()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then
                cursor = math.max(1, cursor - 1)
                column = math.min(column, #lines[cursor] + 1)
                if cursor < scroll then scroll = cursor end
                render()
            elseif value == keys.down then
                cursor = math.min(#lines, cursor + 1)
                column = math.min(column, #lines[cursor] + 1)
                local visible = math.max(1, select(2, ctx.win.getSize()) - 4)
                if cursor >= scroll + visible then scroll = cursor - visible + 1 end
                render()
            elseif value == keys.left then
                column = math.max(1, column - 1)
                render()
            elseif value == keys.right then
                column = math.min(#lines[cursor] + 1, column + 1)
                render()
            elseif value == keys.enter then
                table.insert(lines, cursor + 1, lines[cursor]:sub(column))
                lines[cursor] = lines[cursor]:sub(1, column - 1)
                cursor = cursor + 1
                column = 1
                dirty = true
                status = "Editing"
                render()
            elseif value == keys.backspace then
                if column > 1 then
                    lines[cursor] = lines[cursor]:sub(1, column - 2) .. lines[cursor]:sub(column)
                    column = column - 1
                elseif cursor > 1 then
                    column = #lines[cursor - 1] + 1
                    lines[cursor - 1] = lines[cursor - 1] .. lines[cursor]
                    table.remove(lines, cursor)
                    cursor = cursor - 1
                end
                dirty = true
                status = "Editing"
                render()
            elseif value == keys.s and ctx.modifiers and ctx.modifiers.ctrl then
                saveFile()
                render()
            elseif value == keys.escape then
                ctx:close()
            end
        elseif event == "char" then
            lines[cursor] = lines[cursor]:sub(1, column - 1) .. value .. lines[cursor]:sub(column)
            column = column + #value
            dirty = true
            status = "Editing"
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
