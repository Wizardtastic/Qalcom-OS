local UI = dofile("/qalcom/lib/ui.lua")
local VERSION = dofile("/qalcom/version.lua")

return function(ctx)
    local lines = { "Welcome to Qalcom Terminal.", "Type help for available commands." }
    local input = ""
    local cwd = "/"
    local history = {}
    local historyIndex = 0
    local cursor = 0

    local function append(value)
        local wrote = false
        for line in tostring(value or ""):gmatch("[^\n]+") do
            lines[#lines + 1] = line
            wrote = true
        end
        if not wrote then lines[#lines + 1] = "" end
        while #lines > 200 do table.remove(lines, 1) end
    end

    local function absolute(path)
        path = tostring(path or "")
        local result = path:sub(1, 1) == "/" and fs.combine("/", path) or fs.combine(cwd, path)
        if result:sub(1, 1) ~= "/" then result = "/" .. result end
        return result
    end

    local function render()
        local width, height = ctx.win.getSize()
        ctx.win.setBackgroundColor(UI.colors.surface)
        ctx.win.setTextColor(UI.colors.text)
        ctx.win.clear()
        local usable = math.max(1, height - 2)
        local first = math.max(1, #lines - usable + 1)
        for row = 1, usable do
            local line = lines[first + row - 1]
            if line then UI.text(ctx.win, 2, row, line, UI.colors.text, UI.colors.surface, width - 2) end
        end
        UI.fill(ctx.win, 1, height - 1, width, 2, UI.colors.surfaceAlt)
        UI.text(ctx.win, 2, height - 1, cwd, UI.colors.accent, UI.colors.surfaceAlt, width - 4)
        UI.text(ctx.win, 2, height, "> " .. input, UI.colors.text, UI.colors.surfaceAlt, width - 4)
        ctx.win.setCursorPos(math.min(width, 4 + cursor), height)
        ctx.win.setCursorBlink(true)
    end

    local function complete()
        local before = input:sub(1, cursor)
        local prefix = before:match("(%S+)$") or ""
        local base = prefix:match("(.*/)") or ""
        local namePrefix = prefix:sub(#base + 1)
        local directory = absolute(base == "" and cwd or base)
        if not fs.exists(directory) or not fs.isDir(directory) then return end
        local matches = {}
        for _, name in ipairs(fs.list(directory)) do
            if name:sub(1, #namePrefix):lower() == namePrefix:lower() then matches[#matches + 1] = name end
        end
        if #matches == 1 then
            local replacement = base .. matches[1]
            input = before:sub(1, #before - #prefix) .. replacement .. input:sub(cursor + 1)
            cursor = cursor + #replacement - #prefix
        elseif #matches > 1 then
            append(table.concat(matches, "  "))
        end
        render()
    end

    local function run(command)
        command = command:gsub("^%s+", ""):gsub("%s+$", "")
        if command == "" then return end
        history[#history + 1] = command
        historyIndex = #history + 1
        append(cwd .. " > " .. command)
        local args = {}
        for word in command:gmatch("%S+") do args[#args + 1] = word end
        local name = args[1]
        if name == "help" then
            append("help clear ls cd cat mkdir rm cp mv touch view")
            append("pwd id label time whoami version logout about")
        elseif name == "clear" then lines = {}
        elseif name == "pwd" then append(cwd)
        elseif name == "id" then append("Computer ID: " .. tostring(os.getComputerID()))
        elseif name == "label" then append("Computer label: " .. tostring(os.getComputerLabel() or "(none)"))
        elseif name == "whoami" then append("Signed in as " .. tostring(ctx.user or "(unknown)"))
        elseif name == "version" then append("Qalcom OS " .. VERSION)
        elseif name == "time" then append(textutils.formatTime(os.time(), true))
        elseif name == "about" then append("Qalcom OS " .. VERSION .. " | Windows-inspired CC:T desktop")
        elseif name == "ls" or name == "dir" then
            local path = absolute(args[2] or cwd)
            if not fs.exists(path) or not fs.isDir(path) then append("Not a directory: " .. path)
            else
                local entries = fs.list(path); table.sort(entries)
                for _, entry in ipairs(entries) do append((fs.isDir(fs.combine(path, entry)) and "[DIR] " or "      ") .. entry) end
            end
        elseif name == "cd" then
            local path = absolute(args[2] or "/")
            if fs.exists(path) and fs.isDir(path) then cwd = path else append("Directory not found: " .. path) end
        elseif name == "cat" or name == "type" or name == "view" then
            local path = absolute(args[2])
            if not args[2] or not fs.exists(path) or fs.isDir(path) then append("File not found: " .. tostring(args[2]))
            else
                local file = fs.open(path, "r")
                if file then append(file.readAll() or ""); file.close() else append("Unable to read: " .. path) end
            end
        elseif name == "mkdir" then
            if not args[2] then append("Usage: mkdir <directory>") else fs.makeDir(absolute(args[2])); append("Created " .. absolute(args[2])) end
        elseif name == "touch" then
            if not args[2] then append("Usage: touch <file>") else local file = fs.open(absolute(args[2]), "a"); if file then file.close(); append("Touched " .. absolute(args[2])) end end
        elseif name == "rm" then
            local path = args[2] and absolute(args[2])
            if not path then append("Usage: rm <path>") elseif not fs.exists(path) then append("Path not found") elseif fs.isReadOnly(path) then append("Read-only path") else fs.delete(path); append("Deleted " .. path) end
        elseif name == "cp" or name == "mv" then
            if not args[2] or not args[3] then append("Usage: " .. name .. " <source> <destination>")
            else
                local source, destination = absolute(args[2]), absolute(args[3])
                if not fs.exists(source) then append("Source not found") elseif name == "cp" then fs.copy(source, destination); append("Copied") else fs.move(source, destination); append("Moved") end
            end
        elseif name == "logout" then os.queueEvent("qalcom_logout")
        elseif name == "reboot" then os.reboot()
        elseif name == "shutdown" then os.shutdown()
        else append("Command not found: " .. tostring(name)) end
    end

    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "char" then input = input:sub(1, cursor) .. value .. input:sub(cursor + 1); cursor = cursor + 1; render()
        elseif event == "paste" then local text = tostring(value); input = input:sub(1, cursor) .. text .. input:sub(cursor + 1); cursor = cursor + #text; render()
        elseif event == "key" then
            if value == keys.enter then run(input); input = ""; cursor = 0; render()
            elseif value == keys.backspace and cursor > 0 then input = input:sub(1, cursor - 1) .. input:sub(cursor + 1); cursor = cursor - 1; render()
            elseif value == keys.left then cursor = math.max(0, cursor - 1); render()
            elseif value == keys.right then cursor = math.min(#input, cursor + 1); render()
            elseif value == keys.home then cursor = 0; render()
            elseif value == keys["end"] then cursor = #input; render()
            elseif value == keys.tab then complete()
            elseif value == keys.up then if #history > 0 then historyIndex = math.max(1, historyIndex - 1); input = history[historyIndex] or ""; cursor = #input; render() end
            elseif value == keys.down then if #history > 0 then historyIndex = math.min(#history + 1, historyIndex + 1); input = history[historyIndex] or ""; cursor = #input; render() end end
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
