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
local BIG_GLYPHS = {
["0"] = { "###", "# #", "# #", "# #", "###" },
["1"] = { " # ", "## ", " # ", " # ", "###" },
["2"] = { "###", "  #", "###", "#  ", "###" },
["3"] = { "###", "  #", "###", "  #", "###" },
["4"] = { "# #", "# #", "###", "  #", "  #" },
["5"] = { "###", "#  ", "###", "  #", "###" },
["6"] = { "###", "#  ", "###", "# #", "###" },
["7"] = { "###", "  #", "  #", "  #", "  #" },
["8"] = { "###", "# #", "###", "# #", "###" },
["9"] = { "###", "# #", "###", "  #", "###" },
[":"] = { " ", "#", " ", "#", " " },
}
local function bigTextWidth(text)
local total = 0
for index = 1, #text do
local glyph = BIG_GLYPHS[text:sub(index, index)]
if glyph then total = total + #glyph[1] + (index < #text and 1 or 0) end
end
return total
end
local function drawBigText(target, UI, centerX, topY, text, color, background)
local startX = centerX - math.floor(bigTextWidth(text) / 2)
local cursor = startX
for index = 1, #text do
local glyph = BIG_GLYPHS[text:sub(index, index)]
if glyph then
local glyphWidth = #glyph[1]
for row = 1, 5 do
local line = glyph[row]
for column = 1, glyphWidth do
if line:sub(column, column) == "#" then
UI.fill(target, cursor + column - 1, topY + row - 1, 1, 1, color)
end
end
end
cursor = cursor + glyphWidth + 1
end
end
return startX
end
local function drawLockScreen(target, UI, version)
local width, height = target.getSize()
local backdrop = UI.colors.loginBackdrop or UI.colors.accentStrong or UI.colors.desktop
local primary = UI.colors.textInverse or colors.white
local muted = UI.colors.loginMuted or UI.colors.textMuted or UI.colors.muted
target.setBackgroundColor(backdrop)
target.setTextColor(primary)
target.clear()
local clockText = os.date("%H:%M")
local dateText = width >= 34 and os.date("%A, %B %d") or os.date("%a %d %b")
local blockTop = math.max(2, math.floor(height / 2) - 3)
drawBigText(target, UI, math.floor(width / 2) + 1, blockTop, clockText, primary, backdrop)
UI.center(target, blockTop + 6, dateText, primary, backdrop, width)
if height >= 4 then
UI.center(target, height - 2, "Press any key or click to sign in", muted, backdrop, width)
end
UI.center(target, height, "Qalcom OS " .. version .. "   -   Esc shuts down", muted, backdrop, width)
end
local function cardLayout(target, UI, mode)
local width, height = target.getSize()
local metrics = UI.metricsFor and UI.metricsFor(width, height) or { tier = "compact", outerPadding = 1 }
local proportionalWidth = math.floor(width * (metrics.tier == "command" and 0.34 or 0.48))
local maxCardWidth = metrics.tier == "command" and 52 or (metrics.tier == "wide" and 48 or 42)
local cardWidth = math.max(24, math.min(maxCardWidth, proportionalWidth, width - (metrics.outerPadding or 1) * 2))
local function offsets(avatarRows, fieldGap)
local cursor = 1
local avatarY
if avatarRows > 0 then avatarY = cursor; cursor = cursor + avatarRows + 1 end
local titleY = cursor; cursor = cursor + 1
local usernameY = cursor + 1; cursor = usernameY + 1 + fieldGap
local passwordY = cursor + 1; cursor = passwordY + 1 + fieldGap
local confirmY
if mode == "setup" then confirmY = cursor + 1; cursor = confirmY + 1 + fieldGap end
local buttonY = cursor + 1
return {
avatarY = avatarY, titleY = titleY, usernameY = usernameY,
passwordY = passwordY, confirmY = confirmY, buttonY = buttonY,
requiredHeight = buttonY + 2,
}
end
local avail = height - 2
local configs = { { 3, 1 }, { 3, 0 }, { 0, 1 }, { 0, 0 } }
local chosen = offsets(0, 0)
for _, cfg in ipairs(configs) do
local candidate = offsets(cfg[1], cfg[2])
if candidate.requiredHeight <= avail then chosen = candidate; break end
end
local cardHeight = math.min(math.max(9, chosen.requiredHeight), math.max(9, avail))
local cardX = math.floor((width - cardWidth) / 2) + 1
local cardY = math.max(1, math.floor((height - cardHeight) / 2) + 1)
local fieldX = cardX + 3
local fieldWidth = cardWidth - 6
local toggleWidth = 4
local function abs(offset) return offset and (cardY + offset) or nil end
return {
width = width, height = height, compact = chosen.avatarY == nil,
cardX = cardX, cardY = cardY, cardWidth = cardWidth, cardHeight = cardHeight,
fieldX = fieldX, fieldWidth = fieldWidth,
avatarY = abs(chosen.avatarY), titleY = abs(chosen.titleY),
usernameY = abs(chosen.usernameY), passwordY = abs(chosen.passwordY),
confirmY = abs(chosen.confirmY), buttonY = abs(chosen.buttonY),
toggleX = fieldX + fieldWidth - toggleWidth, toggleY = abs(chosen.passwordY) - 1, toggleWidth = toggleWidth,
}
end
local function drawAvatar(target, UI, centerX, y, initial)
local avatarWidth = 7
local ax = centerX - math.floor(avatarWidth / 2)
local avatarBackground = UI.colors.accent or UI.colors.accentStrong
UI.fill(target, ax, y, avatarWidth, 3, avatarBackground)
UI.text(target, centerX, y + 1, initial, UI.colors.textInverse, avatarBackground, 1)
end
local function drawCard(target, UI, version, mode, fields, selected, showPassword, message, messageColor)
local L = cardLayout(target, UI, mode)
local width, height = L.width, L.height
local backdrop = UI.colors.loginBackdrop or UI.colors.accentStrong or UI.colors.desktop
local cardSurface = UI.colors.loginSurface or UI.colors.surfaceRaised or UI.colors.surface
local cardBorder = UI.colors.loginBorder or UI.colors.borderStrong or UI.colors.border
local cardText = UI.colors.loginText or UI.colors.text
target.setBackgroundColor(backdrop)
target.setTextColor(cardText)
target.clear()
UI.shadow(target, L.cardX, L.cardY, L.cardWidth, L.cardHeight, 1, UI.colors.shadow)
UI.panel(target, L.cardX, L.cardY, L.cardWidth, L.cardHeight, cardSurface, cardBorder)
local centerX = L.cardX + math.floor(L.cardWidth / 2)
if L.avatarY then
local initial = (fields.username ~= "" and fields.username:sub(1, 1):upper()) or "@"
drawAvatar(target, UI, centerX, L.avatarY, initial)
end
local title = mode == "setup" and "Create administrator" or "Sign in"
UI.text(target, L.cardX + math.max(0, math.floor((L.cardWidth - #title) / 2)), L.titleY, title, cardText, cardSurface, #title)
UI.input(target, L.fieldX, L.usernameY, L.fieldWidth, "Username", fields.username, selected == 1, false, { surface = cardSurface })
UI.input(target, L.fieldX, L.passwordY, L.fieldWidth, "Password", fields.password, selected == 2, not showPassword, { surface = cardSurface })
UI.text(target, L.toggleX, L.toggleY, showPassword and "hide" or "show", UI.colors.accent, cardSurface, L.toggleWidth)
if mode == "setup" then
UI.input(target, L.fieldX, L.confirmY, L.fieldWidth, "Confirm password", fields.confirm, selected == 3, not showPassword, { surface = cardSurface })
end
local buttonActive = selected == (mode == "setup" and 3 or 2)
UI.button(target, L.fieldX, L.buttonY, L.fieldWidth, mode == "setup" and "Create account" or "Sign in", buttonActive, {
variant = "accent",
focused = buttonActive,
})
if message and message ~= "" then
local messageY = L.cardY + L.cardHeight + 1
if messageY < height then
UI.center(target, messageY, message, messageColor or UI.colors.textMuted, backdrop, width)
end
end
UI.center(target, height, "Tab switches fields   -   Enter submits   -   Esc back", UI.colors.loginMuted or UI.colors.textSubtle or UI.colors.muted, backdrop, width)
end
function Auth.login(target, UI, version)
local mode = Auth.hasAccounts() and "login" or "setup"
local fields = { username = "", password = "", confirm = "" }
local selected = 1
local showPassword = false
local phase = mode == "setup" and "form" or "lock"
local message = mode == "setup" and "Set up a local administrator to begin." or ""
local messageColor = UI.colors.accentLight or UI.colors.accent
local failedAttempts = 0
local clockTimer = os.startTimer(1)
local function submit()
if mode == "setup" then
if fields.password ~= fields.confirm then
message, messageColor = "Passwords do not match.", UI.colors.danger
return nil
end
local ok, err = Auth.create(fields.username, fields.password)
if not ok then
message, messageColor = err, UI.colors.danger
return nil
end
mode = "login"
fields.password, fields.confirm = "", ""
selected = 2
message, messageColor = "Account created. Sign in to continue.", UI.colors.success
return nil
end
local ok, accountOrError = Auth.verify(fields.username, fields.password)
if ok then return accountOrError end
fields.password = ""
failedAttempts = failedAttempts + 1
message, messageColor = accountOrError, UI.colors.danger
os.sleep(math.min(3, failedAttempts))
return nil
end
local function fieldKey()
return selected == 1 and "username" or selected == 2 and "password" or "confirm"
end
while true do
if phase == "lock" then
drawLockScreen(target, UI, version)
else
drawCard(target, UI, version, mode, fields, selected, showPassword, message, messageColor)
end
local event, value, x, y = os.pullEventRaw()
if event == "timer" and value == clockTimer then
clockTimer = os.startTimer(1)
elseif event == "term_resize" then
elseif phase == "lock" then
if event == "key" then
if value == keys.escape then os.shutdown() else phase = "form" end
elseif event == "char" then
phase = "form"
selected = 1
if #fields.username < MAX_INPUT then fields.username = fields.username .. value end
elseif event == "mouse_click" then
phase = "form"
end
elseif event == "char" then
local key = fieldKey()
if #fields[key] < MAX_INPUT then fields[key] = fields[key] .. value end
elseif event == "paste" then
local key = fieldKey()
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
local key = fieldKey()
fields[key] = fields[key]:sub(1, math.max(0, #fields[key] - 1))
elseif value == keys.escape then
if mode == "setup" then os.shutdown() else phase = "lock"; selected = 1 end
end
elseif event == "mouse_click" then
local L = cardLayout(target, UI, mode)
if x >= L.toggleX and x < L.toggleX + L.toggleWidth and y == L.toggleY then
showPassword = not showPassword
elseif x >= L.fieldX and x < L.fieldX + L.fieldWidth then
if y == L.usernameY then selected = 1
elseif y == L.passwordY then selected = 2
elseif mode == "setup" and y == L.confirmY then selected = 3
elseif y == L.buttonY then
local account = submit()
if account then return account end
end
end
end
end
end
return Auth