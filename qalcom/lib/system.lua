local System = {}

local function safeFreeSpace()
    if fs.getFreeSpace then
        local ok, value = pcall(fs.getFreeSpace, "/")
        if ok and value then return value end
    end
    return "unknown"
end

local function safeMemory()
    -- CC:T does not expose Lua's standard collectgarbage API in every version.
    if type(collectgarbage) == "function" then
        local ok, value = pcall(collectgarbage, "count")
        if ok and type(value) == "number" then
            return string.format("%.1f KB", value)
        end
    end
    return "unavailable"
end

function System.info()
    local width, height = term.getSize()
    local peripherals = {}
    local okNames, names = pcall(peripheral.getNames)
    if okNames and type(names) == "table" then peripherals = names end
    local modemCount = 0
    for _, name in ipairs(peripherals) do
        local okType, peripheralType = pcall(peripheral.getType, name)
        if okType and peripheralType == "modem" then modemCount = modemCount + 1 end
    end
    return {
        computerId = os.getComputerID(),
        label = os.getComputerLabel(),
        width = width,
        height = height,
        memory = safeMemory(),
        freeSpace = safeFreeSpace(),
        peripherals = peripherals,
        modems = modemCount,
        time = os.clock(),
    }
end

return System
