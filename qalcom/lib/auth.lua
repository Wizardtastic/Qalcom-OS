local Auth = {}
local Pure = dofile("/qalcom/lib/pure.lua")

local ACCOUNT_PATH = "/qalcom/data/accounts"
local MAX_INPUT = 24

local function ensureDirectory()
    if not fs.exists("/qalcom/data") then fs.makeDir("/qalcom/data") end
end

local function readAccounts()
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

local function writeAccounts(accounts)
    ensureDirectory()
    local file = fs.open(ACCOUNT_PATH, "w")
    if not file then return false end
    file.write(textutils.serialize(accounts))
    file.close()
    return true
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
    return readAccounts()
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
        created = os.epoch and os.epoch("utc") or 0,
    }
    if not writeAccounts(accounts) then return false, "Unable to save account data." end
    return true
end

function Auth.verify(username, password)
    local accounts = readAccounts()
    username = tostring(username or "")
    password = tostring(password or "")
    for _, account in ipairs(accounts) do
        if account.username:lower() == username:lower() and digest(password, account.salt) == account.digest then
            return true, account
        end
    end
    return false, "Incorrect username or password."
end

local function drawField(target, x, y, width, label, value, active, secret)
    local background = active and colors.lightBlue or colors.white
    local foreground = active and colors.white or colors.black
    target.setBackgroundColor(background)
    target.setTextColor(foreground)
    target.setCursorPos(x, y)
    target.write(string.rep(" ", width))
    target.setCursorPos(x + 1, y - 1)
    target.setTextColor(colors.gray)
    target.write(label)
    target.setCursorPos(x + 1, y)
    local display = secret and string.rep("*", #value) or value
    target.write(display:sub(1, math.max(1, width - 2)))
    if active then
        target.setCursorPos(math.min(x + width - 1, x + 1 + #display), y)
        target.setTextColor(colors.white)
        target.write("_")
    end
end

local function screenLayout(target, mode)
    local width, height = target.getSize()
    local compact = height < 22
    local panelWidth = math.min(38, width - 6)
    local panelHeight = compact and (mode == "setup" and 9 or 7) or (mode == "setup" and 13 or 11)
    local panelX = math.floor((width - panelWidth) / 2) + 1
    local panelY = compact and 3 or math.max(6, math.floor((height - panelHeight) / 2))
    local firstField = compact and 3 or 4
    local fieldGap = compact and 2 or 3
    local buttonOffset = compact and (mode == "setup" and 8 or 6) or (mode == "setup" and 12 or 9)
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

    UI.panel(target, layout.panelX, layout.panelY, layout.panelWidth, layout.panelHeight, UI.colors.surface, UI.colors.border)
    UI.text(target, layout.panelX + 2, layout.panelY + 1, mode == "setup" and "First-time setup" or "Sign in to continue", UI.colors.accent, UI.colors.surface, layout.panelWidth - 4)

    local fieldX = layout.panelX + 3
    local fieldWidth = layout.panelWidth - 6
    local usernameY = layout.panelY + layout.firstField
    local passwordY = usernameY + layout.fieldGap
    drawField(target, fieldX, usernameY, fieldWidth, "Username", fields.username, selected == 1, false)
    drawField(target, fieldX, passwordY, fieldWidth, "Password", fields.password, selected == 2, true)
    if mode == "setup" then
        drawField(target, fieldX, passwordY + layout.fieldGap, fieldWidth, "Confirm password", fields.confirm, selected == 3, true)
    end

    local buttonY = layout.panelY + layout.buttonOffset
    UI.button(target, fieldX, buttonY, fieldWidth, mode == "setup" and "Create account" or "Sign in", true)
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
