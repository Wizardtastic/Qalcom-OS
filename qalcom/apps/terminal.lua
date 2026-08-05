local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
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
        local _, _, contentStart = Screen.begin(ctx.win, "Terminal", cwd, { ui = UI })
        local usable = math.max(1, height - contentStart - 2)
        local first = math.max(1, #lines - usable + 1)
        for row = 1, usable do
            local line = lines[first + row - 1]
            if line then UI.text(ctx.win, 2, contentStart + row - 1, line, UI.colors.text, UI.colors.surface, width - 2) end
        end
        UI.footer(ctx.win, {
            cwd,
            "> " .. input,
        }, { row = height - 1, background = UI.colors.surfaceAlt, foreground = UI.colors.text })
        UI.text(ctx.win, 2, height - 1, cwd, UI.colors.accent, UI.colors.surfaceAlt, width - 4)
        ctx.win.setCursorPos(math.min(width, 4 + cursor), height)
        ctx.win.setCursorBlink(true)
    end

    local function complete()
        local before = input:sub(1, cursor)
        local prefix = before:match("(%S+)$") or ""
        local base = prefix:match("(.*/)") or ""
        local namePrefix = prefix:sub(#base + 1)
        local directory = absolute(base == "" and cwd or base)
        local directoryInfo = ctx:readPath(directory)
        if not directoryInfo or not directoryInfo.exists or not directoryInfo.directory then return end
        local matches = {}
        for _, item in ipairs(ctx:listDirectory(directory) or {}) do
            local name = item.name
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
            local info, reason = ctx:readPath(path)
            if not info or not info.exists or not info.directory then append(reason or ("Not a directory: " .. path))
            else
                local entries = ctx:listDirectory(path) or {}
                table.sort(entries, function(a, b) return a.name < b.name end)
                for _, entry in ipairs(entries) do append((entry.dir and "[DIR] " or "      ") .. entry.name) end
            end
        elseif name == "cd" then
            local path = absolute(args[2] or "/")
            local info, reason = ctx:readPath(path)
            if info and info.exists and info.directory then cwd = path else append(reason or ("Directory not found: " .. path)) end
        elseif name == "cat" or name == "type" or name == "view" then
            local path = absolute(args[2])
            local text, reason
            if args[2] then text, reason = ctx:readFile(path) end
            if not args[2] or not text then append(reason or ("File not found: " .. tostring(args[2])))
            else append(text) end
        elseif name == "mkdir" then
            if not args[2] then append("Usage: mkdir <directory>") else
                local ok, reason = ctx:makeDir(absolute(args[2]))
                if ok then append("Created " .. absolute(args[2])) else append(reason or "Unable to create directory") end
            end
        elseif name == "touch" then
            if not args[2] then append("Usage: touch <file>") else
                local ok, reason = ctx:touch(absolute(args[2]))
                if ok then append("Touched " .. absolute(args[2])) else append(reason or "Unable to create file") end
            end
        elseif name == "rm" then
            local path = args[2] and absolute(args[2])
            local info, reason = path and ctx:readPath(path) or nil, nil
            if not path then append("Usage: rm <path>") elseif not info or not info.exists then append(reason or "Path not found") elseif info.readOnly then append("Read-only path") else
                local ok, failure = ctx:deletePath(path)
                if ok then append("Deleted " .. path) else append(failure or "Unable to delete path") end
            end
        elseif name == "cp" or name == "mv" then
            if not args[2] or not args[3] then append("Usage: " .. name .. " <source> <destination>")
            else
                local source, destination = absolute(args[2]), absolute(args[3])
                local sourceInfo, sourceReason = ctx:readPath(source)
                if not sourceInfo or not sourceInfo.exists then append(sourceReason or "Source not found")
                elseif name == "cp" then
                    local ok, reason = ctx:copyPath(source, destination)
                    if ok then append("Copied") else append(reason or "Unable to copy") end
                else
                    local ok, reason = ctx:movePath(source, destination)
                    if ok then append("Moved") else append(reason or "Unable to move") end
                end
            end
        elseif name == "logout" then os.queueEvent("qalcom_logout")
        elseif name == "reboot" then
            local ok, reason = ctx:managedPower("reboot")
            append(ok and "Reboot requested; confirm through the desktop if prompted." or (reason or "Reboot denied"))
        elseif name == "shutdown" then
            local ok, reason = ctx:managedPower("shutdown")
            append(ok and "Shutdown requested; confirm through the desktop if prompted." or (reason or "Shutdown denied"))
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
