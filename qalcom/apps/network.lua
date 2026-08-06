local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")
local Network = dofile("/qalcom/lib/network.lua")
local Nodes = dofile("/qalcom/lib/nodes.lua")

return function(ctx)
    local config = Network.emptyConfig("computer-unknown")
    local nodes = Network.emptyNodes()
    local modems = {}
    local selected = 1
    local status = "Encrypted transport is opt-in; encryption cannot prevent jamming"
    local editing = false
    local input = ""
    local editField = nil
    local tab = "nodes"
    local auditLines = {}

    local function readAudit()
        local text = ctx:readFile("/qalcom/data/network.audit") or ""
        auditLines = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if line ~= "" and line:sub(1, 1) ~= "#" then auditLines[#auditLines + 1] = line:sub(1, 100) end
        end
        while #auditLines > 8 do table.remove(auditLines, 1) end
    end

    local function load()
        local configText = ctx:readFile("/qalcom/data/network.meta")
        config = Network.parseConfig(configText or "", "computer-" .. tostring(os.getComputerID()))
        local nodeText = ctx:readFile("/qalcom/data/nodes.meta")
        nodes = Network.parseNodes(nodeText or "")
        modems = {}
        for _, name in ipairs(ctx:peripheralNames() or {}) do
            if ctx:peripheralType(name) == "modem" then
                modems[#modems + 1] = { name = name, methods = ctx:peripheralMethods(name) or {} }
            end
        end
        readAudit()
        selected = math.max(1, math.min(selected, math.max(1, #nodes.nodes)))
    end

    local function saveConfig()
        local ok, reason = ctx:writeNetworkConfig(config)
        status = ok and "Configuration saved; reload service to apply" or (reason or "Configuration save failed")
        if ok then os.queueEvent("qalcom_network_reload") end
    end

    local function saveNodes()
        local ok, reason = ctx:writeNetworkNodes(nodes)
        status = ok and "Node trust state saved" or (reason or "Node state save failed")
        if ok then os.queueEvent("qalcom_network_reload") end
    end

    local function render()
        local width, height = ctx.win.getSize()
        local _, _, start = Screen.begin(ctx.win, "Network Operations", nil, { ui = UI })
        UI.text(ctx.win, 2, start, editing and ("Edit " .. tostring(editField) .. ": " .. input .. "_") or status, UI.colors.muted, UI.colors.surface, width - 3)
        local row = start + 1
        local footer = height + 1
        local function line(label, value, color)
            if row >= footer then return end
            UI.listRow(ctx.win, 2, row, width - 3, label, tostring(value or "-"), false, {
                split = math.floor(width * 0.48), valueColor = color or UI.colors.text, background = UI.colors.surface,
            })
            row = row + 1
        end
        line("Cipher suite", "HMAC-SHA256 stream + authenticated tag", UI.colors.accent)
        line("Transport", config.enabled and "enabled (jamming still possible)" or "disabled", config.enabled and UI.colors.warning or UI.colors.muted)
        line("Node", config.nodeId)
        line("Channel", tostring(config.channel) .. " / replies " .. tostring(config.replyChannel))
        line("Modems", #modems, #modems > 0 and UI.colors.success or UI.colors.warning)
        line("View", tab == "nodes" and "trusted nodes" or "recent audit")
        if row < footer then row = row + 1 end
        if tab == "nodes" then
            if row < footer then UI.sectionHeader(ctx.win, 2, row, width - 3, "Trusted nodes", { background = colors.yellow, foreground = colors.black }); row = row + 1 end
            if #nodes.nodes == 0 and row < footer then
                UI.text(ctx.win, 3, row, "No nodes enrolled; pairing requires an explicit local record.", UI.colors.muted, UI.colors.surface, width - 5)
            else
                for index, node in ipairs(nodes.nodes) do
                    if row >= footer then break end
                    local active = index == selected
                    local label = (active and "> " or "  ") .. node.alias
                    UI.listRow(ctx.win, 2, row, width - 3, label, node.state, active, {
                        activeBackground = UI.colors.accentLight, activeForeground = colors.white, background = UI.colors.surface,
                    })
                    row = row + 1
                end
                local node = nodes.nodes[selected]
                if node and row < footer then
                    row = row + 1
                    line("Selected ID", node.id)
                    line("Role", node.role)
                    line("Last seen", node.lastSeen)
                    line("Trust action", "B block  Q quarantine  A approve", UI.colors.warning)
                end
            end
        else
            if row < footer then UI.sectionHeader(ctx.win, 2, row, width - 3, "Recent authenticated request audit", { background = colors.yellow, foreground = colors.black }); row = row + 1 end
            for index = #auditLines, 1, -1 do
                if row >= footer then break end
                UI.text(ctx.win, 3, row, auditLines[index], UI.colors.text, UI.colors.surface, width - 5)
                row = row + 1
            end
        end
        if row < footer then
            UI.text(ctx.win, 2, footer, "Tab audit  E node  C channel  P reply  S save  D toggle  R refresh  Esc close", UI.colors.muted, UI.colors.surface, width - 3)
        end
    end

    load()
    render()
    while true do
        local event, value = ctx:pullEvent()
        if editing then
            if event == "char" or event == "paste" then
                input = input .. tostring(value or ""):sub(1, 48 - #input)
                render()
            elseif event == "key" then
                if value == keys.backspace then input = input:sub(1, math.max(0, #input - 1)); render()
                elseif value == keys.escape then editing = false; render()
                elseif value == keys.enter then
                    if editField == "node" then config.nodeId = Network.clean(input, Network.maxNodeId)
                    elseif editField == "channel" then config.channel = tonumber(input) or config.channel
                    elseif editField == "reply" then config.replyChannel = tonumber(input) or config.replyChannel end
                    editing = false; status = "Configuration staged; press S to save"; render()
                end
            end
        elseif event == "key" then
            if value == keys.up then selected = math.max(1, selected - 1); render()
            elseif value == keys.down then selected = math.min(math.max(1, #nodes.nodes), selected + 1); render()
            elseif value == keys.tab then tab = tab == "nodes" and "audit" or "nodes"; render()
            elseif value == keys.r then load(); status = "Network inventory refreshed"; render()
            elseif value == keys.s then if tab == "nodes" then saveNodes() else saveConfig() end; render()
            elseif value == keys.d then config.enabled = not config.enabled; status = "Transport staged; press S to save"; render()
            elseif value == keys.e then editField = "node"; input = config.nodeId; editing = true; render()
            elseif value == keys.c then editField = "channel"; input = tostring(config.channel); editing = true; render()
            elseif value == keys.p then editField = "reply"; input = tostring(config.replyChannel); editing = true; render()
            elseif value == keys.b or value == keys.q or value == keys.a then
                local node = nodes.nodes[selected]
                if node then
                    local target = value == keys.b and "blocked" or value == keys.q and "quarantined" or "paired"
                    local ok, reason = Nodes.setState(nodes, node.id, target)
                    status = ok and ("Node marked " .. target .. "; press S") or (reason or "Trust update failed")
                    render()
                end
            elseif value == keys.escape then ctx:close() end
        elseif event == "peripheral" or event == "peripheral_detach" or event == "term_resize" or event == "qalcom_tick" then
            load(); render()
        end
    end
end
