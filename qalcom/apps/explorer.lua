local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local cwd = "/"
    local entries = {}
    local selected = 1
    local clipboard = ctx.getFileClipboard and ctx:getFileClipboard() or nil
    local status = "Ready"

    local function absolute(path)
        path = tostring(path or "")
        local result = path:sub(1, 1) == "/" and fs.combine("/", path) or fs.combine(cwd, path)
        if result:sub(1, 1) ~= "/" then result = "/" .. result end
        return result
    end

    local function refresh()
        entries = {}
        if cwd ~= "/" then entries[#entries + 1] = { name = "..", path = fs.getDir(cwd), dir = true, parent = true } end
        local listed, reason = ctx:listDirectory(cwd)
        if reason then status = reason end
        table.sort(listed, function(a, b)
            if a.dir ~= b.dir then return a.dir end
            return a.name:lower() < b.name:lower()
        end)
        for _, item in ipairs(listed) do
            entries[#entries + 1] = item
        end
        selected = math.min(math.max(1, selected), math.max(1, #entries))
    end

    local function render()
        ctx.contextPath = cwd
        local selectedEntry = entries[selected]
        ctx.contextSelection = selectedEntry and {
            name = selectedEntry.name,
            path = selectedEntry.path,
            dir = selectedEntry.dir == true,
            parent = selectedEntry.parent == true,
        } or nil
        local width, height = ctx.win.getSize()
        local shell = Screen.app(ctx.win, "File Explorer", {
            ui = UI,
            status = cwd .. "  |  " .. status,
            statusColor = UI.colors.textSecondary or UI.colors.muted,
        })
        local contentStart = shell.body.y

        local visible = math.max(1, height - contentStart)
        local start = math.max(1, selected - visible + 1)
        for row = 1, visible do
            local index = start + row - 1
            local item = entries[index]
            if item then
                local active = index == selected
                local itemY = contentStart + row
                local icon = item.dir and "> " or ". "
                UI.listRow(ctx.win, 2, itemY, width - 3, icon .. item.name, nil, active, {
                    activeBackground = UI.colors.surfaceSelected,
                    activeForeground = UI.colors.text,
                    foreground = UI.colors.text,
                    background = UI.colors.surface,
                })
            end
        end
    end

    local function selectedItem()
        return entries[selected]
    end

    local function openSelected()
        local item = selectedItem()
        if not item then return end
        if item.dir then
            cwd = item.path
            selected = 1
            refresh()
            status = "Opened " .. cwd
            render()
        elseif item.name:lower():match("%.lua$") or item.name:lower():match("%.txt$") or item.name:lower():match("%.log$") then
            local task = ctx:launch("editor", { path = item.path })
            status = task and ("Opened " .. item.name) or ("Unable to open " .. item.name)
            render()
        else
            status = "Selected " .. item.name
            render()
        end
    end

    local function deleteSelected()
        local item = selectedItem()
        if not item or item.parent then return end
        local info, infoReason = ctx:readPath(item.path)
        if not info then status = infoReason or "Unable to inspect path"; render(); return end
        if info.readOnly then status = "Read-only: " .. item.name; render(); return end
        local task = ctx:launch("dialog", { modal = true, dialogTitle = "Delete " .. item.name .. "?", dialogMessage = "This cannot be undone." })
        if task then
            task.context.dialogCallback = function()
                local ok, result = ctx:deletePath(item.path)
                if not ok then
                    return false, "Delete failed: " .. tostring(result or "filesystem error")
                end
                refresh()
                status = "Deleted " .. item.name
                render()
                return true
            end
        end
    end

    local function newFolder()
        local name = "New Folder"
        local path = fs.combine(cwd, name)
        local suffix = 1
        while true do
            local info = ctx:readPath(path)
            if not info or not info.exists then break end
            suffix = suffix + 1
            path = fs.combine(cwd, name .. " " .. suffix)
        end
        local ok, result = ctx:makeDir(path)
        if not ok then
            status = "Create failed: " .. tostring(result or "filesystem error")
            render()
            return
        end
        refresh()
        status = "Created " .. fs.getName(path)
        render()
    end

    local function copySelected()
        local item = selectedItem()
        if item and not item.parent then
            clipboard = { path = item.path, name = item.name, directory = item.dir == true }
            if ctx.setFileClipboard then ctx:setFileClipboard(clipboard) end
            status = "Copied " .. item.name
            render()
        end
    end

    local function pasteClipboard()
        if ctx.getFileClipboard then clipboard = ctx:getFileClipboard() end
        local sourcePath = clipboard and clipboard.path
        local sourceName = clipboard and (clipboard.name or fs.getName(sourcePath))
        local clipboardInfo = sourcePath and ctx:readPath(sourcePath)
        if not sourcePath or not clipboardInfo or not clipboardInfo.exists then status = "Clipboard is empty"; render(); return end
        local destination = fs.combine(cwd, sourceName)
        local destinationInfo = ctx:readPath(destination)
        if destinationInfo and destinationInfo.exists then status = "Already exists: " .. fs.getName(destination); render(); return end
        if clipboardInfo.directory and (destination == sourcePath or destination:sub(1, #sourcePath + 1) == sourcePath .. "/") then
            status = "Cannot paste a folder into itself"
            render()
            return
        end
        local ok, result = ctx:copyPath(sourcePath, destination)
        if not ok then
            status = "Paste failed: " .. tostring(result or "filesystem error")
            render()
            return
        end
        refresh()
        status = "Pasted " .. fs.getName(destination)
        render()
    end

    refresh()
    render()
    while true do
        local event, value, x, y = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(#entries, selected + 1); render()
            elseif value == keys.enter then openSelected()
            elseif value == keys.backspace then
                if cwd ~= "/" then cwd = fs.getDir(cwd); selected = 1; refresh(); render() end
            elseif value == keys.f5 then refresh(); status = "Refreshed"; render()
            elseif value == keys.n then newFolder()
            elseif value == keys.d then deleteSelected()
            elseif value == keys.c then copySelected()
            elseif value == keys.v then pasteClipboard()
            elseif value == keys.r then status = "Right-click an item to rename"; render()
            end
        elseif event == "qalcom_context_refresh" then
            refresh()
            status = "Refreshed"
            render()
        elseif event == "mouse_click" then
            local row = y - 2
            local visible = math.max(1, select(2, ctx.win.getSize()) - 2)
            local start = math.max(1, selected - visible + 1)
            if row >= 1 and row <= visible and start + row - 1 <= #entries then
                selected = start + row - 1
                openSelected()
            end
        elseif event == "term_resize" or event == "qalcom_tick" then render()
        end
    end
end
