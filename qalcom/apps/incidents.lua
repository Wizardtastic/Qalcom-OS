local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Incidents = dofile("/qalcom/lib/incidents.lua")

return function(ctx)
    local data = Incidents.empty()
    local selected = 1
    local status = "Structured incident coordination; actions require operator approval"
    local tab = "incidents"
    local preview = nil

    local function now()
        if os.epoch then
            local ok, value = pcall(os.epoch, "utc")
            if ok and value then return math.floor(value / 1000) end
        end
        return math.floor(os.clock())
    end

    local function load()
        data = Incidents.parse(ctx:readFile("/qalcom/data/incidents.meta") or "")
        selected = math.max(1, math.min(selected, math.max(1, #data.incidents)))
        preview = nil
    end

    local function save()
        local ok, reason = ctx:writeIncidentData(data)
        status = ok and "Incident records saved" or (reason or "Unable to save incident records")
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, start = Screen.begin(ctx.win, "Incident Response", nil, { ui = UI })
        UI.text(ctx.win, 2, start, status, UI.colors.muted, UI.colors.surface, width - 3)
        local row, footer = start + 1, height + 1
        local function line(label, value, color)
            if row >= footer then return end
            UI.listRow(ctx.win, 2, row, width - 3, label, tostring(value or "-"), false, { split = math.floor(width * .46), valueColor = color or UI.colors.text, background = UI.colors.surface })
            row = row + 1
        end
        line("Open", #data.incidents, UI.colors.accent)
        line("View", tab == "incidents" and "incident records" or "dry-run playbook preview")
        if row < footer then row = row + 1 end
        if tab == "incidents" then
            if row < footer then UI.sectionHeader(ctx.win, 2, row, width - 3, "Incidents", { background = colors.yellow, foreground = colors.black }); row = row + 1 end
            for index, item in ipairs(data.incidents) do
                if row >= footer then break end
                local active = index == selected
                UI.listRow(ctx.win, 2, row, width - 3, (active and "> " or "  ") .. item.title, item.severity .. "/" .. item.state, active, { activeBackground = UI.colors.accentLight, activeForeground = colors.white, background = UI.colors.surface })
                row = row + 1
            end
            local item = data.incidents[selected]
            if item and row < footer then
                row = row + 1
                line("Source", item.source)
                line("Faction", item.faction)
                line("Asset", item.asset)
                line("Timeline", #item.timeline)
                line("Actions", "A acknowledge  P preview  S save", UI.colors.warning)
            elseif row < footer then
                UI.text(ctx.win, 3, row, "No incidents. Create records through a trusted local workflow.", UI.colors.muted, UI.colors.surface, width - 5)
            end
        else
            if row < footer then UI.sectionHeader(ctx.win, 2, row, width - 3, "Dry-run playbook", { background = colors.yellow, foreground = colors.black }); row = row + 1 end
            if preview then
                line("Playbook", preview.playbook)
                line("Dry run", preview.dryRun and "yes; nothing executed" or "no")
                for _, action in ipairs(preview.actions) do line("Action", action.action .. " / " .. (action.allowed and "allowed" or "blocked")) end
                if preview.reason then line("Reason", preview.reason, UI.colors.warning) end
            elseif row < footer then
                UI.text(ctx.win, 3, row, "Select an incident and press P to preview lockdown/alarm/evacuation.", UI.colors.muted, UI.colors.surface, width - 5)
            end
        end
        if row < footer then UI.text(ctx.win, 2, footer, "Up/Down select  A acknowledge  P preview  Tab view  S save  R refresh  Esc close", UI.colors.muted, UI.colors.surface, width - 3) end
    end

    load()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(math.max(1, #data.incidents), selected + 1); render()
            elseif value == keys.tab then tab = tab == "incidents" and "preview" or "incidents"; render()
            elseif value == keys.a then
                local item = data.incidents[selected]
                if item then
                    local ok, reason = Incidents.setState(data, item.id, "acknowledged", ctx.user or "operator", now())
                    status = ok and "Incident acknowledged" or (reason or "Acknowledgement failed")
                    save(); render()
                end
            elseif value == keys.p then
                local item = data.incidents[selected]
                if item then
                    local ok, result = Incidents.preview(item.severity == "critical" and "lockdown" or "alarm", { ["infrastructure.safe_state"] = ctx:hasCapability("infrastructure.emergency"), ["jobs.pause"] = ctx:hasCapability("jobs.manage") })
                    preview = ok and result or nil
                    status = ok and "Dry-run generated; no action executed" or tostring(result)
                    tab = "preview"
                    render()
                end
            elseif value == keys.s then save(); render()
            elseif value == keys.r then load(); status = "Incident records refreshed"; render()
            elseif value == keys.escape then ctx:close() end
        elseif event == "term_resize" or event == "qalcom_tick" then render()
        end
    end
end
