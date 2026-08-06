local Network = dofile("/qalcom/lib/network.lua")
local Protocol = dofile("/qalcom/lib/protocol.lua")
local Nodes = dofile("/qalcom/lib/nodes.lua")
local Roles = dofile("/qalcom/lib/roles.lua")
local Telemetry = dofile("/qalcom/lib/telemetry.lua")
local Peripherals = dofile("/qalcom/lib/peripherals.lua")
local unpack = table.unpack or unpack

return function(ctx)
    local config = Network.emptyConfig("computer-" .. tostring(os.getComputerID()))
    local nodes = Network.emptyNodes()
    local protocol = Protocol.emptyState()
    local counter = { txCounter = 0, rxCounters = {} }
    local modems = {}
    local lastConfig = ""

    local function persist(path, text)
        if ctx.writeNetworkServiceFile then return ctx:writeNetworkServiceFile(path, text) end
        return false, "Network service persistence unavailable"
    end

    local function load()
        local configText = ctx:readFile("/qalcom/data/network.meta") or ""
        config = Network.parseConfig(configText, "computer-" .. tostring(os.getComputerID()))
        local nodeText = ctx:readFile("/qalcom/data/nodes.meta") or ""
        nodes = Network.parseNodes(nodeText)
        local stateText = ctx:readFile("/qalcom/data/network.state") or ""
        counter = Network.parseState(stateText)
        if counter.error then config.error = config.error or counter.error; config.enabled = false end
        local restoredReplay = {}
        for nodeId, replayState in pairs(counter.rxCounters or {}) do
            if type(replayState) == "table" then
                restoredReplay[nodeId] = { highWater = replayState.highWater or 0, seen = replayState.seen or {}, at = Network.now() }
            else
                restoredReplay[nodeId] = { highWater = replayState or 0, seen = { [replayState or 0] = true }, at = Network.now() }
            end
        end
        local auditText = ctx:readFile("/qalcom/data/network.audit") or ""
        protocol = Protocol.emptyState()
        protocol.replay = restoredReplay
        for line in (auditText .. "\n"):gmatch("(.-)\n") do
            local fields = {}
            for field in tostring(line):gmatch("[^|]+") do fields[#fields + 1] = field end
            if fields[1] == "audit" then
                Protocol.record(protocol, { id = fields[2], source = fields[3], request = fields[4], outcome = fields[5], detail = fields[6] }, tonumber(fields[7]) or 0)
            end
        end
        modems = {}
        if config.enabled and not config.error then
            for _, name in ipairs(ctx:networkModems() or {}) do
                if ctx:modemOpen(name, config.channel) then modems[#modems + 1] = name end
            end
        end
        lastConfig = tostring(configText)
    end

    local function syncReplayState()
        counter.rxCounters = {}
        for nodeId, replayState in pairs(protocol.replay or {}) do
            if type(replayState) == "table" and replayState.highWater then counter.rxCounters[nodeId] = replayState end
        end
        return Network.serializeState(counter)
    end

    local function audit(envelope, requestPayload, request, outcome, detail, now)
        Protocol.record(protocol, { id = Network.requestId(requestPayload), source = envelope and envelope.source, request = request, outcome = outcome, detail = detail }, now)
        persist("/qalcom/data/network.audit", Protocol.auditText(protocol))
        if ctx.audit then ctx:audit("network-" .. tostring(outcome), "source=" .. tostring(envelope and envelope.source) .. " request=" .. tostring(request) .. " " .. tostring(detail or "")) end
    end

    local function send(modem, destination, requestEnvelope, requestPayload, outcome, data, secret, now)
        local responseCounter = Network.nextCounter(counter)
        local response = Protocol.response(config, requestEnvelope, requestPayload, outcome, data, secret, responseCounter, now)
        ctx:modemTransmit(modem, config.replyChannel, requestEnvelope.replyChannel or config.replyChannel, response)
        persist("/qalcom/data/network.state", Network.serializeState(counter))
    end

    local function localStatus()
        local info = ctx:systemInfo()
        return { computerId = info.computerId, label = info.label, role = info.role, peripherals = #info.peripherals, modems = info.modems, jobs = info.jobs and info.jobs.summary }
    end

    local function telemetry()
        local metadata = Peripherals.emptyMetadata()
        metadata = Peripherals.parseMetadata(ctx:peripheralMetadataFile() or "")
        local now = Network.now()
        local devices = Peripherals.inspect(ctx, metadata, now)
        local records = Telemetry.snapshot(ctx, devices, now)
        local contacts = Telemetry.mergeContacts(records, now, 32)
        return { records = records, contacts = contacts, summary = Telemetry.summary(records, contacts) }
    end

    local function safeState()
        local failures, changed = {}, 0
        local profiles = ctx:infrastructureProfiles()
        for _, profile in ipairs(profiles.profiles or {}) do
            if profile.kind == "output" and profile.enabled ~= false then
                local ok, reason = ctx:redstoneWrite(profile.side, profile.safe == true)
                if ok then changed = changed + 1 else failures[#failures + 1] = { id = profile.id, reason = tostring(reason or "failed") } end
            end
        end
        return #failures == 0, { changed = changed, failures = failures }
    end

    local function controlAllowed(node, request)
        if not node or node.state ~= "paired" or not ctx:hasCapability("network.control") then return false end
        if request == "infrastructure.safe_state" then
            return Roles.allows(node.role, "infrastructure.emergency") and Roles.allows(node.role, "network.control") and ctx:hasCapability("infrastructure.emergency")
        end
        return Roles.allows(node.role, "network.control") and Roles.allows(node.role, "infrastructure.control") and ctx:hasCapability("jobs.manage")
    end

    local function handle(event)
        local _, side, channel, replyChannel, envelope = unpack(event)
        if type(envelope) ~= "table" or channel ~= config.channel then return end
        local node = Network.findNode(nodes, envelope.source)
        local now = Network.now()
        if not node then audit(envelope, nil, "unknown", "rejected", "unknown node", now); return end
        local payload, reason = Network.openSecureEnvelope(envelope, node.secret, config.protocol, now, node, protocol.replay, config.nodeId)
        if not payload then audit(envelope, nil, "unknown", "rejected", reason, now); return end
        local authenticatedState = syncReplayState()
        local stateSaved, stateReason = persist("/qalcom/data/network.state", authenticatedState)
        if not stateSaved then audit(envelope, payload, payload.request, "rejected", "Replay state could not be persisted: " .. tostring(stateReason), now); return end
        Nodes.touch(nodes, node.id, now)
        local valid, validation = Protocol.validateRequest(protocol, envelope, payload, now, node, config.nodeId)
        if not valid then audit(envelope, payload, payload.request, "rejected", validation, now); return end
        local modem = side
        if envelope.kind == "status_request" then
            local data
            if payload.request == "system.status" then data = localStatus()
            elseif payload.request == "telemetry.snapshot" or payload.request == "assets.summary" then data = telemetry()
            elseif payload.request == "radar.contacts" then data = { contacts = telemetry().contacts } end
            audit(envelope, payload, payload.request, "accepted", "read-only", now)
            send(modem, envelope.source, envelope, payload, "success", data or {}, node.secret, now)
        elseif envelope.kind == "control_request" then
            if not controlAllowed(node, payload.request) then
                audit(envelope, payload, payload.request, "denied", "node role lacks control policy", now)
                send(modem, envelope.source, envelope, payload, "denied", { reason = "control policy denied" }, node.secret, now)
                return
            end
            local ok, data
            if payload.request == "infrastructure.safe_state" then ok, data = safeState()
            elseif payload.request == "jobs.pause" then ok, data = ctx:disableAutomationJobs()
            else ok, data = false, { reason = "Only safe-state and job pause are enabled" } end
            audit(envelope, payload, payload.request, ok and "success" or "failed", tostring(data and data.reason or "completed"), now)
            send(modem, envelope.source, envelope, payload, ok and "success" or "failed", data or {}, node.secret, now)
        end
        persist("/qalcom/data/network.state", syncReplayState())
        persist("/qalcom/data/nodes.meta", Network.serializeNodes(nodes))
    end

    load()
    while true do
        local event = { ctx:pullEvent() }
        if event[1] == "modem_message" and config.enabled and not config.error then
            handle(event)
        elseif event[1] == "qalcom_network_reload" or event[1] == "qalcom_tick" then
            local text = ctx:readFile("/qalcom/data/network.meta") or ""
            if text ~= lastConfig or event[1] == "qalcom_network_reload" then load() end
        elseif event[1] == "peripheral" or event[1] == "peripheral_detach" then
            load()
        end
    end
end
