local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local cwd = "/"
    local entries = {}
    local selected = 1
    local clipboard = nil
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
        if fs.exists(cwd) and fs.isDir(cwd) then
            local names = fs.list(cwd)
            table.sort(names, function(a, b)
                local ad = fs.isDir(fs.combine(cwd, a))
                local bd = fs.isDir(fs.combine(cwd, b))
                if ad ~= bd then return ad end
                return a:lower() < b:lower()
            end)
            for _, name in ipairs(names) do
                local path = fs.combine(cwd, name)
                entries[#entries + 1] = { name = name, path = path, dir = fs.isDir(path) }
            end
        end
        selected = math.min(math.max(1, selected), math.max(1, #entries))
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, contentStart = Screen.begin(ctx.win, "File Explorer", cwd .. "  |  " .. status, { ui = UI })

        local visible = math.max(1, height - contentStart - 2)
        local start = math.max(1, selected - visible + 1)
        for row = 1, visible do
            local index = start + row - 1
            local item = entries[index]
            if item then
                local active = index == selected
                local bg = active and UI.colors.accentLight or UI.colors.surface
                local fg = active and colors.white or UI.colors.text
                local itemY = contentStart + row - 1
                UI.fill(ctx.win, 2, itemY, width - 2, 1, bg)
                local icon = item.dir and "▸ " or "· "
                UI.text(ctx.win, 3, itemY, icon .. item.name, fg, bg, width - 5)
            end
        end
        UI.text(ctx.win, 2, height - 1, "Enter open   N new folder   D delete   C copy   V paste", UI.colors.muted, UI.colors.surface, width - 3)
        UI.text(ctx.win, 2, height, "R rename   Backspace up   F5 refresh", UI.colors.muted, UI.colors.surface, width - 3)
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
        if fs.isReadOnly(item.path) then status = "Read-only: " .. item.name; render(); return end
        local task = ctx:launch("dialog", { modal = true, dialogTitle = "Delete " .. item.name .. "?", dialogMessage = "This cannot be undone." })
        if task then
            task.context.dialogCallback = function()
                if not fs.exists(item.path) then
                    return false, "Path no longer exists"
                end
                local ok, result = pcall(fs.delete, item.path)
                if not ok or result == false then
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
        while fs.exists(path) do
            suffix = suffix + 1
            path = fs.combine(cwd, name .. " " .. suffix)
        end
        local ok, result = pcall(fs.makeDir, path)
        if not ok or result == false then
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
            clipboard = item.path
            status = "Copied " .. item.name
            render()
        end
    end

    local function pasteClipboard()
        if not clipboard or not fs.exists(clipboard) then status = "Clipboard is empty"; render(); return end
        local destination = fs.combine(cwd, fs.getName(clipboard))
        if fs.exists(destination) then status = "Already exists: " .. fs.getName(destination); render(); return end
        if fs.isDir(clipboard) and (destination == clipboard or destination:sub(1, #clipboard + 1) == clipboard .. "/") then
            status = "Cannot paste a folder into itself"
            render()
            return
        end
        local ok, result = pcall(fs.copy, clipboard, destination)
        if not ok or result == false then
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
            elseif value == keys.r then status = "Rename is planned for the next patch"; render()
            end
        elseif event == "mouse_click" then
            local row = y - 3
            local visible = math.max(1, select(2, ctx.win.getSize()) - 6)
            local start = math.max(1, selected - visible + 1)
            if row >= 1 and row <= visible and start + row - 1 <= #entries then
                selected = start + row - 1
                openSelected()
            end
        elseif event == "term_resize" or event == "qalcom_tick" then render()
        end
    end
end
