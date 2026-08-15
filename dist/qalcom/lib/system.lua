local System = {}
local function safeFreeSpace(ctx)
if ctx and ctx.freeSpace then
local value = ctx:freeSpace()
if value then return value end
return "denied"
end
if fs.getFreeSpace then
local ok, value = pcall(fs.getFreeSpace, "/")
if ok and value then return value end
end
return "unknown"
end
local function safeMemory()
if type(collectgarbage) == "function" then
local ok, value = pcall(collectgarbage, "count")
if ok and type(value) == "number" then
return string.format("%.1f KB", value)
end
end
return "unavailable"
end
function System.info(ctx)
local width, height = term.getSize()
local peripherals = {}
if ctx and ctx.peripheralNames then
peripherals = ctx:peripheralNames() or {}
else
local okNames, names = pcall(peripheral.getNames)
if okNames and type(names) == "table" then peripherals = names end
end
local modemCount = 0
for _, name in ipairs(peripherals) do
local peripheralType
if ctx and ctx.peripheralType then
peripheralType = ctx:peripheralType(name)
else
local okType, value = pcall(peripheral.getType, name)
if okType then peripheralType = value end
end
if peripheralType == "modem" then modemCount = modemCount + 1 end
end
return {
computerId = os.getComputerID(),
label = os.getComputerLabel(),
width = width,
height = height,
memory = safeMemory(),
freeSpace = safeFreeSpace(ctx),
peripherals = peripherals,
modems = modemCount,
time = os.clock(),
}
end
return System