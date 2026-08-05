local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
return function(ctx)
    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "Account", "Current session and local identity", { ui = UI })
        UI.card(ctx.win, 2, contentStart + 1, width - 4, 5, "Current user", UI.colors.surfaceAlt, false)
        UI.text(ctx.win, 4, contentStart + 3, tostring(ctx.user or "Unknown"), UI.colors.accent, UI.colors.surface, width - 8)
        UI.text(ctx.win, 3, contentStart + 7, "Account data is local to this computer.", UI.colors.text, UI.colors.surface, width - 5)
        UI.text(ctx.win, 3, contentStart + 8, "This is a local access screen, not encryption.", UI.colors.muted, UI.colors.surface, width - 5)
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
