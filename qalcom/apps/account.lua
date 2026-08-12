local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Roles = dofile("/qalcom/lib/roles.lua")
local Capabilities = dofile("/qalcom/lib/capabilities.lua")

return function(ctx)
    local role = Roles.definition(ctx.role)
    local managing = false
    local accounts = {}
    local selectedAccount = 1
    local selectedRole = 1
    local status = "Current session and local identity"

    local function canManage()
        return ctx:hasCapability("account.manage")
    end

    local function syncSelectedRole()
        local account = accounts[selectedAccount]
        local names = Roles.names()
        selectedRole = 1
        if account then
            for index, name in ipairs(names) do
                if name == account.role then selectedRole = index; break end
            end
        end
    end

    local function loadAccounts()
        accounts = canManage() and ctx:accounts() or {}
        selectedAccount = math.max(1, math.min(selectedAccount, math.max(1, #accounts)))
        syncSelectedRole()
    end

    local function compactButtons(height)
        return math.max(5, height - 3), math.max(6, height - 2)
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "Account", nil, { ui = UI })
        UI.text(ctx.win, 2, contentStart, managing and "Administrator role management" or status, UI.colors.muted, UI.colors.surface, width - 3)
        contentStart = contentStart + 1
        if not managing then
            local compact = height < 16
            if compact then
                UI.text(ctx.win, 2, contentStart, tostring(ctx.user or "Unknown"), UI.colors.accent, UI.colors.surface, width - 3)
                UI.text(ctx.win, 2, contentStart + 1, "Role: " .. tostring(role and role.label or "Unknown"), UI.colors.text, UI.colors.surface, width - 3)
                UI.text(ctx.win, 2, contentStart + 2, canManage() and "Administrator access" or "Read-only role", UI.colors.muted, UI.colors.surface, width - 3)
                local manageY, signOutY = compactButtons(height)
                if canManage() then UI.button(ctx.win, 2, manageY, width - 3, "Manage roles", false) end
                UI.button(ctx.win, 2, signOutY, width - 3, "Sign out", true)
            else
                UI.card(ctx.win, 2, contentStart + 1, width - 4, 5, "Current user", UI.colors.surfaceAlt, false)
                UI.text(ctx.win, 4, contentStart + 3, tostring(ctx.user or "Unknown"), UI.colors.accent, UI.colors.surface, width - 8)
                UI.text(ctx.win, 3, contentStart + 7, "Role", UI.colors.muted, UI.colors.surface, 10)
                UI.text(ctx.win, 14, contentStart + 7, role and role.label or "Unknown", UI.colors.text, UI.colors.surface, width - 16)
                UI.text(ctx.win, 3, contentStart + 8, role and role.description or "No managed role assigned.", UI.colors.muted, UI.colors.surface, width - 5)
                UI.text(ctx.win, 3, contentStart + 9, "Local access is not encryption.", UI.colors.muted, UI.colors.surface, width - 5)
                if canManage() then
                    UI.button(ctx.win, 3, math.max(11, height - 5), width - 5, "Manage account roles", false)
                end
                UI.button(ctx.win, 3, math.max(11, height - 3), width - 5, "Sign out", true)
            end
        else
            local footer = height + 1
            UI.text(ctx.win, 2, contentStart, "Accounts", UI.colors.accent, UI.colors.surface, width - 3)
            local row = contentStart + 1
            local visible = math.max(1, footer - row)
            local start = math.max(1, math.min(selectedAccount - visible + 1, math.max(1, #accounts - visible + 1)))
            for index = start, math.min(#accounts, start + visible - 1) do
                local account = accounts[index]
                local active = index == selectedAccount
                UI.listRow(ctx.win, 2, row, width - 3, account.username, account.role, active, {
                    split = math.floor(width * 0.55),
                    activeBackground = UI.colors.surfaceSelected,
                    activeForeground = UI.colors.text,
                    valueColor = active and UI.colors.text or UI.colors.textMuted,
                    background = UI.colors.surface,
                })
                row = row + 1
            end
            if #accounts == 0 then UI.text(ctx.win, 3, row, "No accounts available", UI.colors.muted, UI.colors.surface, width - 5) end
        end
    end

    local function openManager()
        if not canManage() then
            status = "Administrator permission required"
            render()
            return
        end
        managing = true
        loadAccounts()
        status = "Role management opened"
        render()
    end

    local function confirmRoleChange()
        local account = accounts[selectedAccount]
        local targetRole = Roles.names()[selectedRole]
        if not account or not targetRole or account.role == targetRole then
            status = "No role change selected"
            render()
            return
        end
        local dialog = ctx:launch("dialog", {
            modal = true,
            dialogTitle = "Confirm role change",
            dialogMessage = account.username .. " → " .. targetRole .. "?",
        })
        if not dialog then
            status = "Unable to open confirmation"
            render()
            return
        end
        dialog.context.dialogCallback = function()
            local ok, result = ctx:updateAccountRole(account.username, targetRole)
            status = ok and ("Role changed: " .. account.username) or tostring(result)
            loadAccounts()
            render()
            return ok
        end
        dialog.context.dialogCancelCallback = function()
            Capabilities.auditRoleChange(ctx.user, ctx.role, account.username, account.role, targetRole, "cancelled")
            status = "Role change cancelled"
            render()
        end
    end

    render()
    while true do
        local event, value, _, y = ctx:pullEvent()
        if event == "key" then
            if managing then
                if value == keys.up then selectedAccount = math.max(1, selectedAccount - 1); syncSelectedRole(); render()
                elseif value == keys.down then selectedAccount = math.min(math.max(1, #accounts), selectedAccount + 1); syncSelectedRole(); render()
                elseif value == keys.left then selectedRole = ((selectedRole - 2) % #Roles.names()) + 1; render()
                elseif value == keys.right then selectedRole = (selectedRole % #Roles.names()) + 1; render()
                elseif value == keys.enter then confirmRoleChange()
                elseif value == keys.m then managing = false; status = "Current session and local identity"; render()
                elseif value == keys.escape then ctx:close() end
            else
                if value == keys.m and canManage() then openManager()
                elseif value == keys.enter then os.queueEvent("qalcom_logout")
                elseif value == keys.escape then ctx:close() end
            end
        elseif event == "mouse_click" then
            local _, currentHeight = ctx.win.getSize()
            if managing then
                local contentTop = 4
                local footer = currentHeight + 1
                local visible = math.max(1, footer - contentTop)
                local start = math.max(1, math.min(selectedAccount - visible + 1, math.max(1, #accounts - visible + 1)))
                local clicked = y - contentTop + 1
                local actual = start + clicked - 1
                if clicked >= 1 and clicked <= visible and actual <= #accounts and y >= contentTop and y < footer then
                    selectedAccount = actual
                    syncSelectedRole()
                    render()
                end
            elseif canManage() and currentHeight < 16 and y == compactButtons(currentHeight) then
                openManager()
            elseif canManage() and currentHeight >= 16 and y >= currentHeight - 5 and y < currentHeight - 3 then
                openManager()
            elseif currentHeight < 16 and y >= select(2, compactButtons(currentHeight)) then
                os.queueEvent("qalcom_logout")
            elseif currentHeight >= 16 and y >= currentHeight - 3 then
                os.queueEvent("qalcom_logout")
            end
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
