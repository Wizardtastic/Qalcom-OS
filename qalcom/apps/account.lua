local UI = dofile("/qalcom/lib/ui.lua")
return function(ctx)
    local function render()
        local width, height = ctx.win.getSize()
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        UI.fill(ctx.win, 1, 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, 1, "Account", UI.colors.accent, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, 2, "Current session and local identity", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.divider(ctx.win, 1, 3, width, UI.colors.border)
        UI.text(ctx.win, 3, 5, "Signed in as", UI.colors.muted, UI.colors.surface, width - 5)
        UI.text(ctx.win, 3, 6, tostring(ctx.user or "Unknown"), UI.colors.accent, UI.colors.surface, width - 5)
        UI.text(ctx.win, 3, 8, "Account data is local to this computer.", UI.colors.text, UI.colors.surface, width - 5)
        UI.text(ctx.win, 3, 9, "This is a local access screen, not encryption.", UI.colors.muted, UI.colors.surface, width - 5)
        UI.button(ctx.win, 3, math.max(11, height - 3), width - 5, "Sign out", true)
        UI.text(ctx.win, 3, height, "Enter or click Sign out", UI.colors.muted, UI.colors.surface, width - 5)
    end

    render()
    while true do
        local event, value, _, y = ctx:pullEvent()
        if event == "key" and value == keys.enter then
            os.queueEvent("qalcom_logout")
        elseif event == "mouse_click" and y >= ctx.win.getSize() - 3 then
            os.queueEvent("qalcom_logout")
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
