local UI = dofile("/qalcom/lib/ui.lua")

return function(ctx)
    local title = ctx.dialogTitle or "Confirm action"
    local message = ctx.dialogMessage or "Are you sure?"
    local selected = 1

    local function render()
        local width, height = ctx.win.getSize()
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        UI.dialog(ctx.win, title, message, UI.colors.warning)
        local buttonWidth = math.floor((width - 7) / 2)
        UI.button(ctx.win, 3, height - 3, buttonWidth, "Yes", selected == 1, { background = colors.gray })
        UI.button(ctx.win, 5 + buttonWidth, height - 3, buttonWidth, "No", selected == 2, { background = colors.gray })
        UI.text(ctx.win, 3, height, "Left/Right choose   Enter confirm", UI.colors.muted, UI.colors.surface, width - 5)
    end

    render()
    while true do
        local event, value, x, y = ctx:pullEvent()
        if event == "key" then
            if value == keys.left or value == keys.right then
                selected = selected == 1 and 2 or 1
                render()
            elseif value == keys.enter then
                if selected == 1 and ctx.dialogCallback then
                    local ok, result, detail = pcall(ctx.dialogCallback)
                    if not ok then
                        ctx:notify("Action failed: " .. tostring(result), UI.colors.danger)
                    elseif result == false then
                        ctx:notify(tostring(detail or "Action failed"), UI.colors.danger)
                    end
                elseif selected == 2 and ctx.dialogCancelCallback then
                    pcall(ctx.dialogCancelCallback)
                end
                ctx:close()
            elseif value == keys.escape then
                if ctx.dialogCancelCallback then pcall(ctx.dialogCancelCallback) end
                ctx:close()
            end
        elseif event == "mouse_click" then
            local width, height = ctx.win.getSize()
            local buttonWidth = math.floor((width - 7) / 2)
            local yesX = 3
            local noX = 5 + buttonWidth
            if y == height - 3 and x and x >= yesX and x < yesX + buttonWidth then
                if ctx.dialogCallback then
                    local ok, result, detail = pcall(ctx.dialogCallback)
                    if not ok then
                        ctx:notify("Action failed: " .. tostring(result), UI.colors.danger)
                    elseif result == false then
                        ctx:notify(tostring(detail or "Action failed"), UI.colors.danger)
                    end
                end
                ctx:close()
            elseif y == height - 3 and x and x >= noX and x < noX + buttonWidth then
                if ctx.dialogCancelCallback then pcall(ctx.dialogCancelCallback) end
                ctx:close()
            end
        elseif event == "term_resize" then
            render()
        end
    end
end
