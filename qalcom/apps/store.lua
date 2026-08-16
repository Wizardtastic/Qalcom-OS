--[[ Qalcom Software Center -----------------------------------------------------
    A Linux-software-manager-style front end for Qalcom Packages (`.qpkg`).

    Launched from the Terminal (`store <code>`) or the launcher. Fetches a
    self-contained package from Pastebin, validates it (schema, size bounds,
    path allow-list, SHA-256 payload checksum), and presents a detail page with
    the package logo, description, and an Install button. Installing writes the
    declared files through the capability-gated managed filesystem and records
    the package in /qalcom/data/packages.meta.

    All package logic lives in /qalcom/lib/store.lua so it stays unit-testable;
    this file is presentation, network, and the confirm/install flow only.
------------------------------------------------------------------------------]]

local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Store = dofile("/qalcom/lib/store.lua")
local VERSION = dofile("/qalcom/version.lua")

local REGISTRY_PATH = "/qalcom/data/packages.meta"

return function(ctx)
    -- === View state =========================================================
    local view = "landing"          -- landing | loading | detail | confirm | installing | done | error
    local codeInput = ""
    local pendingUrl = nil
    local descriptor = nil          -- validated package descriptor
    local plan = nil                -- install plan
    local registry = Store.newRegistry()
    local message = nil             -- error / status text
    local progress = { done = 0, total = 0, label = "" }
    local buttons = {}

    -- === Helpers ============================================================
    local function loadRegistry()
        local text = ctx:readFile(REGISTRY_PATH)
        registry = Store.parseRegistry(text or "")
        if registry.error then registry = Store.newRegistry() end
    end

    local function installedRecord(id)
        return registry.packages and registry.packages[id] or nil
    end

    local function pastebinUrl(code)
        code = tostring(code or ""):gsub("%s+", "")
        if code:match("^https?://") then return code end
        -- Accept a bare code or a normal pastebin.com/<code> link.
        code = code:gsub("^pastebin%.com/", ""):gsub("^raw/", "")
        return "https://pastebin.com/raw/" .. code
    end

    -- Word-wrap a paragraph to a column width, returning a list of lines.
    local function wrap(textValue, columns)
        local lines = {}
        columns = math.max(1, columns)
        for paragraph in (tostring(textValue or "") .. "\n"):gmatch("(.-)\n") do
            if paragraph == "" then
                lines[#lines + 1] = ""
            else
                local current = ""
                for word in paragraph:gmatch("%S+") do
                    if current == "" then
                        current = word
                    elseif #current + 1 + #word <= columns then
                        current = current .. " " .. word
                    else
                        lines[#lines + 1] = current
                        current = word
                    end
                end
                if current ~= "" then lines[#lines + 1] = current end
            end
        end
        return lines
    end

    -- Convert a CC blit hex char to a color value (2^n), or nil to skip.
    local function blitColor(character)
        local index = tonumber(character, 16)
        if not index then return nil end
        return math.floor(2 ^ index + 0.5)
    end

    -- Draw the package logo as chunky pixels (2 cells wide each), or a glyph card.
    local function drawLogo(x, y)
        local logo = descriptor and descriptor.logo
        if type(logo) == "table" and type(logo.pixels) == "table" and #logo.pixels > 0 then
            for row, rowText in ipairs(logo.pixels) do
                for column = 1, #rowText do
                    local color = blitColor(rowText:sub(column, column))
                    if color then
                        UI.fill(ctx.win, x + (column - 1) * 2, y + row - 1, 2, 1, color)
                    end
                end
            end
            return #logo.pixels
        end
        local glyph = (descriptor and descriptor.icon) or "?"
        UI.card(ctx.win, x, y, 8, 4, nil, UI.colors.accent, false)
        UI.text(ctx.win, x + math.max(0, math.floor((8 - #glyph) / 2)), y + 1, glyph, UI.colors.textInverse, UI.colors.accent, #glyph)
        return 4
    end

    -- The primary action for the current package given what is installed.
    local function primaryAction()
        if not descriptor then return "install" end
        local record = installedRecord(descriptor.id)
        if not record then return "install" end
        local comparison = Store.compareVersions(descriptor.version, record.version)
        if comparison > 0 then return "update" end
        if comparison < 0 then return "downgrade" end
        return "reinstall"
    end

    local function canInstall()
        return ctx:hasCapability("fs.write")
    end

    -- === Rendering ==========================================================
    local function addButton(button, id, action)
        button.id = id
        button.action = action
        buttons[#buttons + 1] = button
    end

    local function renderLanding(body)
        UI.text(ctx.win, body.x, body.y, "Install a package by its Pastebin code, or", UI.colors.text, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + 1, "pick one you already installed below.", UI.colors.textSecondary, UI.colors.surface, body.width)

        UI.input(ctx.win, body.x, body.y + 4, math.min(30, body.width - 12), "Pastebin code", codeInput, true, false)
        addButton(UI.button(ctx.win, body.x + math.min(30, body.width - 12) + 1, body.y + 4, 9, "Open", false, { variant = "accent" }), "open", "open")

        UI.text(ctx.win, body.x, body.y + 6, "Installed", UI.colors.textSecondary, UI.colors.surface, body.width)
        local ids = {}
        for id in pairs(registry.packages or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids == 0 then
            UI.text(ctx.win, body.x, body.y + 7, "Nothing installed yet.", UI.colors.textMuted, UI.colors.surface, body.width)
        end
        local row = body.y + 7
        for _, id in ipairs(ids) do
            if row < body.y + body.height then
                local record = registry.packages[id]
                UI.text(ctx.win, body.x, row, id, UI.colors.text, UI.colors.surface, body.width - 10)
                UI.text(ctx.win, body.x + body.width - 8, row, "v" .. tostring(record.version), UI.colors.textMuted, UI.colors.surface, 8)
                row = row + 1
            end
        end
    end

    local function renderDetail(body)
        local logoHeight = drawLogo(body.x, body.y)
        local textX = body.x + 18
        local textWidth = body.width - 18
        UI.text(ctx.win, textX, body.y, descriptor.name, UI.colors.text, UI.colors.surface, textWidth)
        local subline = tostring(descriptor.publisher) .. "  v" .. tostring(descriptor.version) .. "  " .. tostring(descriptor.category)
        UI.text(ctx.win, textX, body.y + 1, subline, UI.colors.textSecondary, UI.colors.surface, textWidth)

        local action = primaryAction()
        local disabled = not canInstall()
        addButton(UI.button(ctx.win, textX, body.y + 3, 14, Store.actionLabel(action), false, {
            variant = "accent", disabled = disabled,
        }), "primary", "confirm")
        if installedRecord(descriptor.id) then
            addButton(UI.button(ctx.win, textX + 15, body.y + 3, 10, "Remove", false, {
                variant = "danger", disabled = disabled,
            }), "remove", "remove")
        end
        if disabled then
            UI.text(ctx.win, textX, body.y + 5, ctx:isSafeMode() and "Safe Mode blocks installs." or "Requires an Administrator account.",
                UI.colors.warning, UI.colors.surface, textWidth)
        end

        -- Description below the hero band.
        local descTop = body.y + math.max(logoHeight, 6) + 1
        local lines = wrap(descriptor.description or descriptor.summary or "", body.width)
        for index, line in ipairs(lines) do
            local ly = descTop + index - 1
            if ly < body.y + body.height - 6 then
                UI.text(ctx.win, body.x, ly, line, UI.colors.text, UI.colors.surface, body.width)
            end
        end

        -- Details rail at the bottom.
        local detailY = body.y + body.height - 5
        local checksumShort = tostring(descriptor.checksum or ""):sub(1, 12)
        local rows = {
            "Version    " .. tostring(descriptor.version),
            "Size       " .. tostring(descriptor.totalBytes) .. " bytes  (" .. tostring(descriptor.fileCount) .. " files)",
            "Requires   " .. table.concat(descriptor.capabilities, ", "),
            "Integrity  sha256:" .. checksumShort .. (descriptor.integrityChecked and " (verified)" or " (unverified)"),
        }
        for index, text in ipairs(rows) do
            UI.text(ctx.win, body.x, detailY + index - 1, text, UI.colors.textMuted, UI.colors.surface, body.width)
        end
    end

    local function renderConfirm(body)
        UI.text(ctx.win, body.x, body.y, "Install " .. descriptor.name .. " v" .. descriptor.version .. "?", UI.colors.text, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + 1, "From " .. tostring(pendingUrl or "pastebin"), UI.colors.textSecondary, UI.colors.surface, body.width)

        local y = body.y + 3
        UI.text(ctx.win, body.x, y, "These files will be written:", UI.colors.textSecondary, UI.colors.surface, body.width)
        y = y + 1
        for _, file in ipairs(descriptor.files) do
            if y < body.y + body.height - 6 then
                UI.text(ctx.win, body.x + 1, y, file.path .. "  (" .. file.size .. "b)", UI.colors.text, UI.colors.surface, body.width - 1)
                y = y + 1
            end
        end
        if plan and #plan.deletes > 0 then
            UI.text(ctx.win, body.x, y, tostring(#plan.deletes) .. " stale file(s) will be removed.", UI.colors.textMuted, UI.colors.surface, body.width)
            y = y + 1
        end

        -- Honest trust notice: the checksum proves the download was not altered
        -- in transit, not that the publisher is benign. Installed code runs with
        -- the same access as built-in apps, so this is a trust-the-source moment.
        UI.text(ctx.win, body.x, body.y + body.height - 6, "! Runs code from the internet. Only install from", UI.colors.warning, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + body.height - 5, "  publishers you trust; the checksum verifies the", UI.colors.warning, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + body.height - 4, "  download, not the author's intent.", UI.colors.warning, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + body.height - 3, "Integrity sha256:" .. tostring(descriptor.checksum):sub(1, 12) .. "  Caps: " .. table.concat(descriptor.capabilities, ", "), UI.colors.textMuted, UI.colors.surface, body.width)

        addButton(UI.button(ctx.win, body.x, body.y + body.height - 1, 14, "Install now", false, { variant = "accent" }), "do-install", "install")
        addButton(UI.button(ctx.win, body.x + 15, body.y + body.height - 1, 10, "Cancel", false, { variant = "subtle" }), "cancel", "back-detail")
    end

    local function renderInstalling(body)
        UI.text(ctx.win, body.x, body.y, "Installing " .. descriptor.name .. "...", UI.colors.text, UI.colors.surface, body.width)
        local fraction = progress.total > 0 and progress.done / progress.total or 0
        UI.progress(ctx.win, body.x, body.y + 2, body.width, fraction)
        UI.text(ctx.win, body.x, body.y + 3, progress.label, UI.colors.textMuted, UI.colors.surface, body.width)
    end

    local function renderDone(body)
        UI.text(ctx.win, body.x, body.y, descriptor.name .. " installed.", UI.colors.success, UI.colors.surface, body.width)
        UI.text(ctx.win, body.x, body.y + 1, message or "", UI.colors.text, UI.colors.surface, body.width)
        if plan and plan.reboot then
            UI.text(ctx.win, body.x, body.y + 3, "A reboot is needed to finish.", UI.colors.textSecondary, UI.colors.surface, body.width)
            addButton(UI.button(ctx.win, body.x, body.y + 5, 14, "Reboot now", false, { variant = "accent" }), "reboot", "reboot")
            addButton(UI.button(ctx.win, body.x + 15, body.y + 5, 10, "Later", false, { variant = "subtle" }), "later", "close")
        else
            addButton(UI.button(ctx.win, body.x, body.y + 3, 10, "Done", false, { variant = "accent" }), "close", "close")
        end
    end

    local function renderError(body)
        UI.text(ctx.win, body.x, body.y, "Could not load package", UI.colors.danger, UI.colors.surface, body.width)
        for index, line in ipairs(wrap(message or "Unknown error", body.width)) do
            UI.text(ctx.win, body.x, body.y + 1 + index, line, UI.colors.text, UI.colors.surface, body.width)
        end
        addButton(UI.button(ctx.win, body.x, body.y + body.height - 1, 10, "Back", false, { variant = "subtle" }), "back", "back-landing")
    end

    local function render()
        buttons = {}
        local titles = {
            landing = "Software Center", loading = "Software Center",
            detail = "Software Center", confirm = "Confirm install",
            installing = "Installing", done = "Installed", error = "Software Center",
        }
        local footers = {
            landing = { "Enter = open", "Esc = close" },
            detail = { "Enter = install", "Esc = back" },
            confirm = { "Enter = install", "Esc = cancel" },
            error = { "Esc = back" },
        }
        local shell = Screen.app(ctx.win, titles[view] or "Software Center", { ui = UI, footer = footers[view] })
        local body = shell.body
        if view == "landing" then renderLanding(body)
        elseif view == "loading" then UI.text(ctx.win, body.x, body.y, "Fetching package...", UI.colors.textSecondary, UI.colors.surface, body.width)
        elseif view == "detail" then renderDetail(body)
        elseif view == "confirm" then renderConfirm(body)
        elseif view == "installing" then renderInstalling(body)
        elseif view == "done" then renderDone(body)
        elseif view == "error" then renderError(body) end
    end

    -- === Network ============================================================
    -- Cooperative fetch: uses the async http API so the desktop keeps running.
    local function fetch(code)
        if not http then message = "HTTP is disabled on this computer."; view = "error"; return end
        pendingUrl = pastebinUrl(code)
        view = "loading"; render()
        if not ctx:hasCapability("content.fetch") then
            message = "This account is not allowed to download packages."; view = "error"; return
        end
        ctx:audit("fetch", pendingUrl)
        http.request(pendingUrl)
        while true do
            local event, url, handle = ctx:pullEvent()
            if event == "http_success" and url == pendingUrl then
                local data = handle.readAll(); handle.close()
                local manifest, decodeErr = Store.decode(data)
                if not manifest then message = decodeErr or "Invalid package."; view = "error"; return end
                local result = Store.validate(manifest)
                if not result.ok then message = result.reason; view = "error"; return end
                descriptor = result
                plan = Store.planInstall(descriptor, registry)
                if not Store.meetsRequirements(descriptor, VERSION) then
                    message = "Needs Qalcom " .. tostring(descriptor.requires.minOs) .. " or newer (you have " .. VERSION .. ")."
                    view = "error"; return
                end
                view = "detail"; return
            elseif event == "http_failure" and url == pendingUrl then
                message = "Download failed: " .. tostring(handle or "connection error"); view = "error"; return
            elseif event == "key" and url == keys.escape then
                ctx:close(); return
            elseif event == "term_resize" or event == "qalcom_tick" then
                render()
            end
        end
    end

    -- === Install ============================================================
    local function performInstall()
        view = "installing"
        progress = { done = 0, total = #plan.writes + #plan.deletes, label = "Preparing..." }
        render()
        for _, file in ipairs(plan.writes) do
            progress.label = file.path
            local dir = fs.getDir(file.path)
            if dir and dir ~= "" then ctx:makeDir("/" .. dir) end
            local ok, reason = ctx:writeFile(file.path, file.content)
            if not ok then message = "Write failed: " .. file.path .. "\n" .. tostring(reason); view = "error"; return end
            progress.done = progress.done + 1; render()
        end
        for _, path in ipairs(plan.deletes) do
            progress.label = "Removing " .. path
            ctx:deletePath(path)
            progress.done = progress.done + 1; render()
        end
        registry = Store.recordInstall(registry, descriptor, pendingUrl or "", os.epoch and os.epoch("utc") or os.time())
        local ok, reason = ctx:writeFile(REGISTRY_PATH, Store.serializeRegistry(registry))
        if not ok then message = "Could not update package registry: " .. tostring(reason); view = "error"; return end
        ctx:audit("install", descriptor.id .. "@" .. descriptor.version)
        message = descriptor.fileCount .. " files written."
        view = "done"
    end

    local function performRemove()
        local removePlan = Store.planRemove(descriptor.id, registry)
        if not removePlan.ok then message = removePlan.reason; view = "error"; return end
        for _, path in ipairs(removePlan.deletes) do ctx:deletePath(path) end
        registry = Store.removeRecord(registry, descriptor.id)
        ctx:writeFile(REGISTRY_PATH, Store.serializeRegistry(registry))
        ctx:audit("remove", descriptor.id)
        plan = { reboot = true }
        message = "Removed. Reboot to update the launcher."
        view = "done"
    end

    -- === Actions ============================================================
    local function activate(action)
        if action == "open" then
            if codeInput:gsub("%s+", "") ~= "" then fetch(codeInput) end
        elseif action == "confirm" then
            if canInstall() then plan = Store.planInstall(descriptor, registry); view = "confirm" end
        elseif action == "install" then performInstall()
        elseif action == "remove" then performRemove()
        elseif action == "back-detail" then view = "detail"
        elseif action == "back-landing" then view = "landing"; descriptor = nil
        elseif action == "reboot" then ctx:managedPower("reboot")
        elseif action == "close" then ctx:close(); return end
        render()
    end

    -- === Startup ============================================================
    loadRegistry()
    if ctx.code and tostring(ctx.code) ~= "" then
        fetch(ctx.code)
    end
    render()

    -- === Event loop =========================================================
    while true do
        local event, value, x, y = ctx:pullEvent()
        if event == "char" then
            if view == "landing" then codeInput = codeInput .. value; render() end
        elseif event == "key" then
            if value == keys.escape then
                if view == "detail" or view == "error" then view = "landing"; descriptor = nil; render()
                elseif view == "confirm" then view = "detail"; render()
                else ctx:close() end
            elseif value == keys.backspace and view == "landing" then
                codeInput = codeInput:sub(1, #codeInput - 1); render()
            elseif value == keys.enter then
                if view == "landing" then activate("open")
                elseif view == "detail" then activate("confirm")
                elseif view == "confirm" then activate("install")
                elseif view == "done" then activate("close") end
            end
        elseif event == "mouse_click" then
            local button = UI.hitButton(buttons, x, y)
            if button and not button.disabled then activate(button.action) end
        elseif event == "term_resize" or event == "qalcom_tick" then
            render()
        end
    end
end
