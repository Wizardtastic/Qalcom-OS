local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Capabilities = dofile("/qalcom/lib/capabilities.lua")
local Roles = dofile("/qalcom/lib/roles.lua")

return function(ctx)
    local apps = Capabilities.all()
    local selected = 1
    local status = "Built-in policy profiles; not a sandbox"

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "Capabilities", status, { ui = UI })
        local manifest = Capabilities.manifest(apps[selected])
        local role = Roles.definition(ctx.role)
        local footer = math.max(contentStart, height - 1)
        local split = math.max(12, math.floor(width * 0.43))
        local row = contentStart
        UI.text(ctx.win, 2, row, "Applications", UI.colors.accent, UI.colors.surface, split - 3)
        UI.text(ctx.win, split, row, "Requested capabilities", UI.colors.accent, UI.colors.surface, width - split - 1)
        row = row + 1
        local visible = math.max(0, footer - row)
        local start = math.max(1, math.min(selected - math.max(1, visible) + 1, #apps - math.max(1, visible) + 1))
        for index = start, math.min(#apps, start + visible - 1) do
            local y = row + index - start
            local active = index == selected
            local background = active and UI.colors.accentLight or UI.colors.surface
            local foreground = active and colors.white or UI.colors.text
            UI.fill(ctx.win, 2, y, split - 3, 1, background)
            UI.text(ctx.win, 3, y, Capabilities.manifest(apps[index]).title, foreground, background, split - 5)
        end
        if manifest and row < footer then
            local requested = manifest.requested
            UI.text(ctx.win, split, row, (manifest.trusted and "Trusted built-in application" or "Untrusted") .. " / role: " .. tostring(role and role.label or "unknown"), UI.colors.success, UI.colors.surface, width - split - 1)
            row = row + 1
            for index, capability in ipairs(requested) do
                if row >= footer then break end
                local decision = Capabilities.policy(ctx.role, apps[selected], capability, ctx:isSafeMode())
                UI.status(ctx.win, split, row, decision.allowed and "APPROVED" or "DENIED", decision.allowed and UI.colors.success or UI.colors.warning, 10)
                UI.text(ctx.win, split + 12, row, capability, UI.colors.text, UI.colors.surface, width - split - 13)
                row = row + 1
            end
            if #requested == 0 and row < footer then
                UI.text(ctx.win, split, row, "No managed capabilities requested", UI.colors.muted, UI.colors.surface, width - split - 1)
            end
        end
        UI.fill(ctx.win, 1, height - 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, height - 1, "Up/Down select   R refresh audit   Esc close", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
        UI.text(ctx.win, 2, height, "Role policy only; trusted Lua still has CC:T globals", UI.colors.muted, UI.colors.surfaceAlt, width - 3)
    end

    local function auditView()
        if ctx.audit then ctx:audit("inspection", apps[selected]) else Capabilities.audit("inspection", apps[selected]) end
        status = "Inspection recorded for " .. tostring(apps[selected])
        render()
    end

    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(#apps, selected + 1); render()
            elseif value == keys.r then auditView()
            elseif value == keys.escape then ctx:close() end
        elseif event == "mouse_scroll" then
            selected = value < 0 and math.max(1, selected - 1) or math.min(#apps, selected + 1)
            render()
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
