local Calculator = {}
local MAX_DIGITS = 12
local function finite(value)
return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function formatNumber(value)
if not finite(value) then return "Error" end
local text = string.format("%.10g", value)
if text == "-0" then return "0" end
return text
end
local function numberFromDisplay(display)
local value = tonumber(display)
return value and finite(value) and value or nil
end
function Calculator.new()
return {
display = "0",
accumulator = nil,
pending = nil,
resetInput = false,
error = false,
}
end
function Calculator.clear(state)
state.display = "0"
state.accumulator = nil
state.pending = nil
state.resetInput = false
state.error = false
end
function Calculator.inputDigit(state, digit)
digit = tostring(digit or "")
if not digit:match("^[0-9]$") then return end
if state.error or state.resetInput then
state.display = digit
state.resetInput = false
state.error = false
elseif state.display == "0" then
state.display = digit
elseif #state.display < MAX_DIGITS + 1 then
state.display = state.display .. digit
end
end
function Calculator.decimal(state)
if state.error or state.resetInput then
state.display = "0."
state.resetInput = false
state.error = false
elseif not state.display:find(".", 1, true) and #state.display < MAX_DIGITS + 1 then
state.display = state.display .. "."
end
end
function Calculator.toggleSign(state)
if state.error then return end
if state.display == "0" or state.display == "0." then return end
if state.display:sub(1, 1) == "-" then
state.display = state.display:sub(2)
else
state.display = "-" .. state.display
end
end
function Calculator.percent(state)
local value = numberFromDisplay(state.display)
if not value then return end
state.display = formatNumber(value / 100)
end
local function calculate(left, operator, right)
if operator == "+" then return left + right end
if operator == "-" then return left - right end
if operator == "*" then return left * right end
if operator == "/" then
if right == 0 then return nil end
return left / right
end
return right
end
function Calculator.operator(state, operator)
if state.error then Calculator.clear(state) end
local value = numberFromDisplay(state.display)
if not value then return end
if state.pending and state.accumulator ~= nil and not state.resetInput then
local result = calculate(state.accumulator, state.pending, value)
if not finite(result) then
state.display, state.error = "Error", true
state.accumulator, state.pending = nil, nil
return
end
state.accumulator = result
state.display = formatNumber(result)
else
state.accumulator = value
end
state.pending = operator
state.resetInput = true
end
function Calculator.equals(state)
if state.error or not state.pending or state.accumulator == nil then return end
local value = numberFromDisplay(state.display)
if not value then return end
local result = calculate(state.accumulator, state.pending, value)
if not finite(result) then
state.display, state.error = "Error", true
state.accumulator, state.pending = nil, nil
state.resetInput = true
return
end
state.display = formatNumber(result)
state.accumulator, state.pending = nil, nil
state.resetInput = true
end
function Calculator.backspace(state)
if state.error or state.resetInput then return end
if #state.display <= 1 or (#state.display == 2 and state.display:sub(1, 1) == "-") then
state.display = "0"
else
state.display = state.display:sub(1, -2)
if state.display == "-" or state.display == "" then state.display = "0" end
end
end
function Calculator.display(state)
return tostring(state.display or "0")
end
return Calculator