local Auth = {}
local Pure = dofile("/qalcom/lib/pure.lua")
local Roles = dofile("/qalcom/lib/roles.lua")

local ACCOUNT_PATH = "/qalcom/data/accounts"
local ROLE_SCHEMA_VERSION = Roles.schemaVersion
local MAX_INPUT = 24
local readAccounts
local writeAccounts

local function ensureDirectory()
    if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
end

readAccounts = function()
    if not fs.exists(ACCOUNT_PATH) then return {} end
    local file = fs.open(ACCOUNT_PATH, "r")
    if not file then return {} end
    local raw = file.readAll()
    file.close()
    local data = textutils.unserialize(raw or "")
    if type(data) ~= "table" then return {} end
    local accounts = {}
    for _, account in ipairs(data) do
        if Pure.validateAccountRecord(account) then
            accounts[#accounts + 1] = account
        end
    end
    return accounts
end

writeAccounts = function(accounts)
    ensureDirectory()
    local file = fs.open(ACCOUNT_PATH, "w")
    if not file then return false end
    file.write(textutils.serialize(accounts))
    file.close()
    return true
end

local function normalizeAccount(account, firstAccount)
    if not Pure.validateAccountRecord(account) then return nil end
    local normalized = {}
    for key, value in pairs(account) do normalized[key] = value end
    normalized.role = Roles.normalize(account.role, firstAccount)
    normalized.roleSchemaVersion = ROLE_SCHEMA_VERSION
    return normalized
end

local function migrateAccounts(accounts)
    local changed = false
    local normalized = {}
    for index, account in ipairs(accounts) do
        local value = normalizeAccount(account, index == 1)
        if value then
            if account.role ~= value.role or account.roleSchemaVersion ~= ROLE_SCHEMA_VERSION then changed = true end
            normalized[#normalized + 1] = value
        end
    end
    return normalized, changed
end

local function ensureRoleMigration()
    local accounts = readAccounts()
    local normalized, changed = migrateAccounts(accounts)
    if changed then writeAccounts(normalized) end
    return normalized
end

-- This is a local deterrent, not cryptographic protection. CC:T files remain accessible
-- to anyone with physical/server access or a CraftOS recovery shell.
local function digest(password, salt)
    local value = tonumber(salt) or 7919
    for index = 1, #password do
        value = (value * 33 + string.byte(password, index) + index * 17) % 2147483647
        value = (value * 65599 + index) % 2147483647
    end
    return tostring(value)
end

local function newSalt()
    local epoch = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000000)
    return tostring((epoch + os.getComputerID() * 7919) % 2147483647)
end

local function validUsername(username)
    return Pure.validateUsername(username, MAX_INPUT)
end

function Auth.accounts()
    return ensureRoleMigration()
end

function Auth.updateRole(username, role, actorRole, actorUsername)
    if actorRole ~= Roles.legacyAdministrator then return false, "Administrator permission required." end
    if not Roles.exists(role) then return false, "Unknown role." end
    local accounts = ensureRoleMigration()
    local target
    local previousRole
    local administrators = 0
    for _, account in ipairs(accounts) do
        if account.role == Roles.legacyAdministrator then administrators = administrators + 1 end
        if account.username:lower() == tostring(username or ""):lower() then target = account end
    end
    if not target then return false, "Account not found." end
    if actorUsername and target.username:lower() == tostring(actorUsername):lower() and role ~= Roles.legacyAdministrator then
        return false, "You cannot demote the active Administrator session." end
    if target.role == Roles.legacyAdministrator and role ~= Roles.legacyAdministrator and administrators <= 1 then
        return false, "At least one Administrator is required." end
    previousRole = target.role
    target.role = role
    target.roleSchemaVersion = ROLE_SCHEMA_VERSION
    if not writeAccounts(accounts) then return false, "Unable to save account data." end
    return true, target, previousRole
end

function Auth.hasAccounts()
    return #readAccounts() > 0
end

function Auth.create(username, password)
    if not validUsername(username) then return false, "Use 2-24 letters, numbers, _ or -." end
    if type(password) ~= "string" or #password < 4 then return false, "Password must be at least 4 characters." end
    local accounts = readAccounts()
    for _, account in ipairs(accounts) do
        if account.username:lower() == username:lower() then return false, "That username already exists." end
    end
    local salt = newSalt()
    accounts[#accounts + 1] = {
        username = username,
        salt = salt,
        digest = digest(password, salt),
        role = #accounts == 0 and Roles.legacyAdministrator or Roles.default,
        roleSchemaVersion = ROLE_SCHEMA_VERSION,
        created = os.epoch and os.epoch("utc") or 0,
    }
    if not writeAccounts(accounts) then return false, "Unable to save account data." end
    return true
end

function Auth.verify(username, password)
    local accounts = ensureRoleMigration()
    username = tostring(username or "")
    password = tostring(password or "")
    for _, account in ipairs(accounts) do
        if account.username:lower() == username:lower() and digest(password, account.salt) == account.digest then
            return true, account
        end
    end
    return false, "Incorrect username or password."
end

local function screenLayout(target, mode)
    local width, height = target.getSize()
    local compact = height < 22
    local panelWidth = math.min(38, width - 6)
    local panelHeight = compact and (mode == "setup" and 11 or 9) or (mode == "setup" and 13 or 11)
    local panelX = math.floor((width - panelWidth) / 2) + 1
    local panelY = compact and 3 or math.max(6, math.floor((height - panelHeight) / 2))
    local firstField = 4
    local fieldGap = compact and 2 or 3
    local buttonOffset = compact and (mode == "setup" and 10 or 8) or (mode == "setup" and 12 or 9)
    return {
        width = width,
        height = height,
        compact = compact,
        panelWidth = panelWidth,
        panelHeight = panelHeight,
        panelX = panelX,
        panelY = panelY,
        firstField = firstField,
        fieldGap = fieldGap,
        buttonOffset = buttonOffset,
    }
end

local function drawScreen(target, UI, version, mode, fields, selected, message, messageColor)
    local layout = screenLayout(target, mode)
    local width, height = layout.width, layout.height
    target.setBackgroundColor(UI.colors.desktop)
    target.setTextColor(colors.white)
    target.clear()

    UI.center(target, layout.compact and 1 or 3, "QALCOM", colors.white, UI.colors.desktop, width)
    if not layout.compact then
        UI.center(target, 4, mode == "setup" and "Create your administrator account" or "Welcome back", colors.lightBlue, UI.colors.desktop, width)
    end

    UI.shadow(target, layout.panelX, layout.panelY, layout.panelWidth, layout.panelHeight, 1)
    UI.card(target, layout.panelX, layout.panelY, layout.panelWidth, layout.panelHeight, nil, nil, false)
    UI.fill(target, layout.panelX + 1, layout.panelY + 1, layout.panelWidth - 2, 2, UI.colors.accent)
    UI.text(target, layout.panelX + 2, layout.panelY + 1, "QALCOM", colors.white, UI.colors.accent, layout.panelWidth - 4)
    UI.text(target, layout.panelX + 2, layout.panelY + 2, mode == "setup" and "First-time setup" or "Sign in to continue", colors.lightBlue, UI.colors.accent, layout.panelWidth - 4)

    local fieldX = layout.panelX + 3
    local fieldWidth = layout.panelWidth - 6
    local usernameY = layout.panelY + layout.firstField
    local passwordY = usernameY + layout.fieldGap
    UI.input(target, fieldX, usernameY, fieldWidth, "Username", fields.username, selected == 1, false)
    UI.input(target, fieldX, passwordY, fieldWidth, "Password", fields.password, selected == 2, true)
    if mode == "setup" then
        UI.input(target, fieldX, passwordY + layout.fieldGap, fieldWidth, "Confirm password", fields.confirm, selected == 3, true)
    end

    local buttonY = layout.panelY + layout.buttonOffset
    UI.button(target, fieldX, buttonY, fieldWidth, mode == "setup" and "Create account" or "Sign in", selected == (mode == "setup" and 3 or 2))
    if message and message ~= "" then
        local messageY = math.min(height - 2, layout.panelY + layout.panelHeight + 1)
        UI.center(target, messageY, message, messageColor or colors.yellow, UI.colors.desktop, width)
    end
    UI.center(target, height, "Qalcom OS " .. version .. "  |  Tab switches fields  |  Esc shuts down", colors.gray, UI.colors.desktop, width)
end

function Auth.login(target, UI, version)
    local mode = Auth.hasAccounts() and "login" or "setup"
    local fields = { username = "", password = "", confirm = "" }
    local selected = 1
    local message = mode == "setup" and "Set up a local administrator to begin." or ""
    local messageColor = colors.lightBlue
    local failedAttempts = 0

    local function submit()
        if mode == "setup" then
            if fields.password ~= fields.confirm then
                message, messageColor = "Passwords do not match.", colors.red
                return nil
            end
            local ok, err = Auth.create(fields.username, fields.password)
            if not ok then
                message, messageColor = err, colors.red
                return nil
            end
            mode = "login"
            fields.password, fields.confirm = "", ""
            selected = 2
            message, messageColor = "Account created. Sign in to continue.", colors.lime
            return nil
        end
        local ok, accountOrError = Auth.verify(fields.username, fields.password)
        if ok then return accountOrError end
        fields.password = ""
        failedAttempts = failedAttempts + 1
        message, messageColor = accountOrError, colors.red
        os.sleep(math.min(3, failedAttempts))
        return nil
    end

    while true do
        drawScreen(target, UI, version, mode, fields, selected, message, messageColor)
        local event, value, x, y = os.pullEventRaw()
        if event == "term_resize" then
            -- Redraw on the next loop with the new terminal dimensions.
        elseif event == "char" then
            local key = selected == 1 and "username" or selected == 2 and "password" or "confirm"
            if #fields[key] < MAX_INPUT then fields[key] = fields[key] .. value end
        elseif event == "paste" then
            local key = selected == 1 and "username" or selected == 2 and "password" or "confirm"
            fields[key] = fields[key] .. tostring(value):sub(1, MAX_INPUT - #fields[key])
        elseif event == "key" then
            if value == keys.tab or value == keys.down then
                selected = selected % (mode == "setup" and 3 or 2) + 1
            elseif value == keys.up then
                selected = (selected - 2) % (mode == "setup" and 3 or 2) + 1
            elseif value == keys.enter then
                if selected == (mode == "setup" and 3 or 2) then
                    local account = submit()
                    if account then return account end
                else
                    selected = selected + 1
                end
            elseif value == keys.backspace then
                local key = selected == 1 and "username" or selected == 2 and "password" or "confirm"
                fields[key] = fields[key]:sub(1, math.max(0, #fields[key] - 1))
            elseif value == keys.escape then
                os.shutdown()
            end
        elseif event == "mouse_click" then
            local layout = screenLayout(target, mode)
            local panelX, panelY = layout.panelX, layout.panelY
            local fieldX = panelX + 3
            local fieldWidth = layout.panelWidth - 6
            local usernameY = panelY + layout.firstField
            local passwordY = usernameY + layout.fieldGap
            local buttonY = panelY + layout.buttonOffset
            if x >= fieldX and x < fieldX + fieldWidth then
                if y == usernameY then selected = 1
                elseif y == passwordY then selected = 2
                elseif mode == "setup" and y == passwordY + layout.fieldGap then selected = 3
                elseif y == buttonY then
                    local account = submit()
                    if account then return account end
                end
            end
        end
    end
end

return Auth
