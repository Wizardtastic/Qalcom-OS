local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
return function(ctx)
local title = ctx.dialogTitle or "Confirm action"
local message = ctx.dialogMessage or "Are you sure?"
local selected = 1
local inputValue = tostring(ctx.dialogInputValue or "")
local inputRect = nil
local function buttonLayout(width, height)
local metrics = UI.metricsFor and UI.metricsFor(width, height) or { outerPadding = 1, headerHeight = 1 }
local bodyX = math.max(1, math.floor(tonumber(metrics.outerPadding) or 1))
local bodyY = math.min(height + 1, math.max(1, math.floor(tonumber(metrics.headerHeight) or 1) + 1))
local bodyWidth = math.max(1, width - bodyX * 2 + 1)
return bodyX, bodyY, bodyWidth
end
local function render()
local width, height = ctx.win.getSize()
local shell = Screen.app(ctx.win, title, { ui = UI })
local body = shell.body
local panelX, panelY, panelWidth, panelHeight = UI.dialog(ctx.win, title, message, UI.colors.accent)
local buttonWidth = math.max(3, math.floor((body.width - 1) / 2))
local buttonY = math.max(body.y, height - 3)
local yesX = body.x
local noX = math.min(body.x + buttonWidth + 1, body.x + body.width - buttonWidth)
inputRect = nil
if ctx.dialogInput then
local inputY = math.max(body.y, math.min(buttonY - 2, panelY + panelHeight - 2))
local inputWidth = math.max(4, panelWidth - 4)
inputRect = { x = panelX + 2, y = inputY, width = inputWidth, height = 1 }
UI.input(ctx.win, inputRect.x, inputRect.y, inputRect.width,
ctx.dialogInputLabel or "Name", inputValue, true, false, { surface = UI.colors.surface })
end
UI.button(ctx.win, yesX, buttonY, buttonWidth, "Yes", selected == 1, { variant = "accent" })
UI.button(ctx.win, noX, buttonY, buttonWidth, "No", selected == 2)
end
local function confirm()
local callback = ctx.dialogInput and ctx.dialogInputCallback or ctx.dialogCallback
if callback then
local ok, result, detail = pcall(callback, ctx.dialogInput and inputValue or nil)
if not ok then
ctx:notify("Action failed: " .. tostring(result), UI.colors.danger)
elseif result == false then
ctx:notify(tostring(detail or "Action failed"), UI.colors.danger)
end
end
ctx:close()
end
render()
while true do
local event, value, x, y = ctx:pullEvent()
if event == "key" then
if value == keys.left or value == keys.right then
selected = selected == 1 and 2 or 1
render()
elseif value == keys.enter then
if selected == 1 then
confirm()
elseif selected == 2 and ctx.dialogCancelCallback then
pcall(ctx.dialogCancelCallback)
ctx:close()
else
ctx:close()
end
elseif value == keys.backspace and ctx.dialogInput then
inputValue = inputValue:sub(1, math.max(0, #inputValue - 1))
render()
elseif value == keys.escape then
if ctx.dialogCancelCallback then pcall(ctx.dialogCancelCallback) end
ctx:close()
end
elseif event == "char" and ctx.dialogInput then
if #inputValue < 80 then inputValue = inputValue .. tostring(value or "") end
render()
elseif event == "paste" and ctx.dialogInput then
if #inputValue < 80 then inputValue = inputValue .. tostring(value or ""):sub(1, 80 - #inputValue) end
render()
elseif event == "mouse_click" then
local width, height = ctx.win.getSize()
local bodyX, bodyY, bodyWidth = buttonLayout(width, height)
local buttonWidth = math.max(3, math.floor((bodyWidth - 1) / 2))
local yesX = bodyX
local noX = math.min(bodyX + buttonWidth + 1, bodyX + bodyWidth - buttonWidth)
local buttonY = math.max(bodyY, height - 3)
if inputRect and y == inputRect.y and x and x >= inputRect.x and x < inputRect.x + inputRect.width then
selected = 1
render()
elseif y == buttonY and x and x >= yesX and x < yesX + buttonWidth then
confirm()
elseif y == buttonY and x and x >= noX and x < noX + buttonWidth then
if ctx.dialogCancelCallback then pcall(ctx.dialogCancelCallback) end
ctx:close()
end
elseif event == "term_resize" then
render()
end
end
end