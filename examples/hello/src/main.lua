--[[ Example Qalcom package app --------------------------------------------------
    A minimal Software Center app. An installed app is an ordinary Qalcom app: a
    module that returns a function(ctx). Its entry file must be main.lua; after
    install it lives at /qalcom/pkg/hello/main.lua and is launched like any other
    app. Use this as a template for your own packages.
------------------------------------------------------------------------------]]

local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local function render()
        local shell = Screen.app(ctx.win, "Hello", { ui = UI, footer = { "Esc = close" } })
        local body = shell.body
        UI.text(ctx.win, body.x, body.y, "Hello from a Qalcom package!", UI.colors.text, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + 2, "Installed via the Software Center.", UI.colors.textSecondary, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + 4, "Edit src/main.lua to make it yours.", UI.colors.textMuted, UI.colors.surface, body.width)
    end

    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" and value == keys.escape then
            ctx:close()
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
