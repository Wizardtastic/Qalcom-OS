local Network = {}
local Crypto = dofile("/qalcom/lib/crypto.lua")

Network.schemaVersion = 1
Network.protocolVersion = 1
Network.protocol = "qalcom.v1"
Network.defaultChannel = 4242
Network.defaultReplyChannel = 4243
Network.maxNodes = 32
Network.maxNodeId = 48
Network.maxAlias = 48
Network.maxSecret = 96
Network.maxPayloadBytes = 12000
Network.maxEnvelopeAge = 30
Network.maxFutureSkew = 10
Network.maxReplay = 64
Network.maxRequestKind = 48
Network.maxStatusItems = 64
-- Legacy checksum helpers are retained only for source compatibility; the transport rejects legacy envelopes.
Network.authenticationStrength = "HMAC-SHA256 + encrypted stream; host trust and jamming remain out of scope"
Network.maxCounter = 9007199254740991
Network.maxRateWindow = 10
Network.maxRequestsPerWindow = 12
Network.maxAuditEntries = 128
Network.maxPlaintextBytes = 12000

function Network.now()
    if os and os.epoch then
        local ok, value = pcall(os.epoch, "utc")
        if ok and type(value) == "number" then return math.floor(value / 1000) end
    end
    return math.floor((os and os.clock and os.clock()) or 0)
end


local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n|]", " "):sub(1, maximum or 120)
end

local function escape(value)
    return clean(value, 160):gsub("\\", "\\\\"):gsub("|", "\\p")
end

local function unescape(value)
    value = tostring(value or "")
    local result, index = {}, 1
    while index <= #value do
        local character = value:sub(index, index)
        if character == "\\" and index < #value then
            local nextCharacter = value:sub(index + 1, index + 1)
            result[#result + 1] = nextCharacter == "p" and "|" or nextCharacter
            index = index + 2
        else
            result[#result + 1] = character
            index = index + 1
        end
    end
    return table.concat(result)
end

local function split(line)
    local fields, current, escaped = {}, {}, false
    for index = 1, #line do
        local character = line:sub(index, index)
        if escaped then
            current[#current + 1] = "\\" .. character
            escaped = false
        elseif character == "\\" then
            escaped = true
        elseif character == "|" then
            fields[#fields + 1] = unescape(table.concat(current))
            current = {}
        else
            current[#current + 1] = character
        end
    end
    if escaped then current[#current + 1] = "\\" end
    fields[#fields + 1] = unescape(table.concat(current))
    return fields
end

local function number(value, minimum, maximum, fallback)
    local result = tonumber(value)
    if not result then result = fallback end
    result = math.floor(result or minimum)
    if result < minimum then return minimum end
    if result > maximum then return maximum end
    return result
end

local function bool(value, fallback)
    if value == true or value == "true" or value == "1" then return true end
    if value == false or value == "false" or value == "0" then return false end
    return fallback == true
end

local function checksum(seed, text)
    local value = tonumber(seed) or 7919
    text = tostring(text or "")
    for index = 1, #text do
        value = (value * 33 + string.byte(text, index) + index * 17) % 2147483647
        value = (value * 65599 + index) % 2147483647
    end
    return tostring(value)
end

local function stable(value, depth)
    depth = depth or 0
    if depth > 4 then return "<depth>" end
    if value == nil then return "nil" end
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) ~= "table" then return "<" .. type(value) .. ">" end
    local keys = {}
    for key, _ in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = stable(key, depth + 1) .. "=" .. stable(value[key], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function canonical(envelope)
    return table.concat({
        envelope.protocol or "", envelope.version or "", envelope.source or "",
        envelope.destination or "*", envelope.kind or "", envelope.timestamp or "",
        envelope.counter or "", envelope.nonce or "", envelope.ciphertext or "", envelope.tag or "",
        stable(envelope.payload),
    }, "\n")
end

local function encodeValue(value, depth)
    depth = depth or 0
    if depth > 4 then return "s6:<depth>" end
    if value == nil then return "n" end
    if type(value) == "boolean" then return value and "b1" or "b0" end
    if type(value) == "number" then return "d" .. tostring(value) .. ";" end
    if type(value) == "string" then return "s" .. tostring(#value) .. ":" .. value end
    if type(value) ~= "table" then return "s11:<unsupported>" end
    local keys = {}
    for key, _ in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = { "t", tostring(#keys), ":" }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encodeValue(key, depth + 1)
        parts[#parts + 1] = encodeValue(value[key], depth + 1)
    end
    parts[#parts + 1] = "e"
    return table.concat(parts)
end

local function decodeValue(text, position, depth)
    depth = depth or 0
    if depth > 5 or position > #text then return nil, position, "payload depth/position limit" end
    local tag = text:sub(position, position)
    position = position + 1
    if tag == "n" then return nil, position end
    if tag == "b" then return text:sub(position, position) == "1", position + 1 end
    if tag == "d" then
        local finish = text:find(";", position, true)
        if not finish then return nil, position, "number terminator missing" end
        local value = tonumber(text:sub(position, finish - 1))
        if value == nil then return nil, finish + 1, "invalid number" end
        return value, finish + 1
    end
    if tag == "s" then
        local colon = text:find(":", position, true)
        if not colon then return nil, position, "string length missing" end
        local length = tonumber(text:sub(position, colon - 1))
        if not length or length < 0 or length > Network.maxPayloadBytes then return nil, colon + 1, "string length invalid" end
        local first = colon + 1
        local last = first + length - 1
        if last > #text then return nil, first, "string truncated" end
        return text:sub(first, last), last + 1
    end
    if tag == "t" then
        local colon = text:find(":", position, true)
        if not colon then return nil, position, "table count missing" end
        local count = tonumber(text:sub(position, colon - 1))
        if not count or count < 0 or count > 256 then return nil, colon + 1, "table count invalid" end
        local result, nextPosition = {}, colon + 1
        for _ = 1, count do
            local key, afterKey, keyReason = decodeValue(text, nextPosition, depth + 1)
            if keyReason then return nil, afterKey, keyReason end
            local value, afterValue, valueReason = decodeValue(text, afterKey, depth + 1)
            if valueReason or (type(key) ~= "string" and type(key) ~= "number") then return nil, afterValue, valueReason or "table key invalid" end
            result[key] = value
            nextPosition = afterValue
        end
        if text:sub(nextPosition, nextPosition) ~= "e" then return nil, nextPosition, "table terminator missing" end
        return result, nextPosition + 1
    end
    return nil, position, "unknown payload tag"
end

local function serializePayload(payload)
    return encodeValue(payload)
end

local function deserializePayload(value)
    local result, position, reason = decodeValue(value, 1, 0)
    if reason or type(result) ~= "table" or position ~= #value + 1 then return nil end
    return result
end

local function counterNonce(source, counter)
    return tostring(source) .. ":" .. tostring(counter)
end

local function defaultNodeId()
    local id = 0
    if os and os.getComputerID then
        local ok, value = pcall(os.getComputerID)
        if ok then id = value end
    end
    return "computer-" .. tostring(id)
end

function Network.clean(value, maximum)
    return clean(value, maximum)
end

function Network.emptyConfig(nodeId)
    return {
        schemaVersion = Network.schemaVersion,
        enabled = false,
        nodeId = clean(nodeId or defaultNodeId(), Network.maxNodeId),
        nodeName = "Qalcom node",
        channel = Network.defaultChannel,
        replyChannel = Network.defaultReplyChannel,
        protocol = Network.protocol,
    }
end

function Network.normalizeConfig(config, fallbackNodeId)
    config = config or {}
    local result = Network.emptyConfig(fallbackNodeId)
    result.enabled = config.enabled == true
    result.nodeId = clean(config.nodeId or result.nodeId, Network.maxNodeId)
    result.nodeName = clean(config.nodeName or result.nodeName, Network.maxAlias)
    result.channel = number(config.channel, 1, 65535, Network.defaultChannel)
    result.replyChannel = number(config.replyChannel, 1, 65535, Network.defaultReplyChannel)
    result.protocol = clean(config.protocol or Network.protocol, 24)
    if result.protocol == "" then result.protocol = Network.protocol end
    return result
end

function Network.emptyNodes()
    return { schemaVersion = Network.schemaVersion, nodes = {} }
end

function Network.normalizeNode(node, fallbackId)
    node = node or {}
    local state = node.state
    if state ~= "paired" and state ~= "blocked" and state ~= "quarantined" then state = "paired" end
    return {
        id = clean(node.id or fallbackId or "node", Network.maxNodeId),
        alias = clean(node.alias or node.id or fallbackId or "Node", Network.maxAlias),
        secret = clean(node.secret or "", Network.maxSecret),
        role = clean(node.role or "Observer", 40),
        state = state,
        lastSeen = tonumber(node.lastSeen) or 0,
        capabilities = clean(node.capabilities or "", 160),
    }
end

local function validNodeFields(fields)
    return fields[2] and fields[2] ~= ""
        and fields[3] and fields[3] ~= ""
        and fields[4] and #fields[4] >= 16
        and (fields[6] == "paired" or fields[6] == "blocked" or fields[6] == "quarantined")
        and tonumber(fields[7]) ~= nil
end

function Network.parseConfig(text, fallbackNodeId)
    local config = Network.emptyConfig(fallbackNodeId)
    local errorMessage
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "schema" then
                local schema = tonumber(fields[2])
                if schema ~= Network.schemaVersion then errorMessage = "Unsupported network schema" end
            elseif fields[1] == "config" then
                if #fields < 7 then errorMessage = "Malformed network configuration"
                else config = Network.normalizeConfig({ enabled = bool(fields[2], false), nodeId = fields[3], nodeName = fields[4], channel = fields[5], replyChannel = fields[6], protocol = fields[7] }, fallbackNodeId) end
            end
        end
    end
    config.schemaVersion = Network.schemaVersion
    config.error = errorMessage
    return config
end

function Network.serializeConfig(config)
    config = Network.normalizeConfig(config)
    return table.concat({
        "# Qalcom network configuration schema " .. tostring(Network.schemaVersion),
        "schema|" .. tostring(Network.schemaVersion),
        table.concat({ "config", tostring(config.enabled), escape(config.nodeId), escape(config.nodeName), config.channel, config.replyChannel, escape(config.protocol) }, "|"),
    }, "\n") .. "\n"
end

function Network.parseNodes(text)
    local result, seen = Network.emptyNodes(), {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = split(line)
            if fields[1] == "schema" then
                local schema = tonumber(fields[2])
                if schema ~= Network.schemaVersion then result.error = "Unsupported node schema" end
            elseif fields[1] == "node" then
                if #result.nodes >= Network.maxNodes then result.error = "Node limit reached"
                elseif not validNodeFields(fields) then result.error = "Malformed node record"
                else
                    local node = Network.normalizeNode({ id = fields[2], alias = fields[3], secret = fields[4], role = fields[5], state = fields[6], lastSeen = fields[7], capabilities = fields[8] })
                    if node.id == "" or node.secret == "" then result.error = "Malformed node record"
                    elseif seen[node.id] then result.error = "Duplicate node record"
                    else
                        seen[node.id] = true
                        result.nodes[#result.nodes + 1] = node
                    end
                end
            end
        end
    end
    result.schemaVersion = Network.schemaVersion
    if result.error then result.nodes = {} end
    return result
end

function Network.serializeNodes(data)
    data = data or Network.emptyNodes()
    local lines = { "# Qalcom paired node schema " .. tostring(Network.schemaVersion), "schema|" .. tostring(Network.schemaVersion) }
    local nodes = {}
    for index, node in ipairs(data.nodes or {}) do if index <= Network.maxNodes then nodes[#nodes + 1] = Network.normalizeNode(node, "node-" .. tostring(index)) end end
    table.sort(nodes, function(left, right) return left.id < right.id end)
    for _, node in ipairs(nodes) do
        lines[#lines + 1] = table.concat({ "node", escape(node.id), escape(node.alias), escape(node.secret), escape(node.role), node.state, tostring(node.lastSeen), escape(node.capabilities) }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Network.pairNode(data, node)
    data = data or Network.emptyNodes()
    local normalized = Network.normalizeNode(node)
    if normalized.id == "" or #normalized.secret < 16 then return false, "Node ID and pairing secret of at least 16 characters are required" end
    for index, existing in ipairs(data.nodes or {}) do if existing.id == normalized.id then data.nodes[index] = normalized; return true end end
    if #data.nodes >= Network.maxNodes then return false, "Node limit reached" end
    data.nodes[#data.nodes + 1] = normalized
    return true
end

function Network.findNode(data, nodeId)
    for _, node in ipairs((data and data.nodes) or {}) do if node.id == nodeId then return node end end
    return nil
end

function Network.newNonce(now, counter)
    return tostring(math.floor(tonumber(now) or 0)) .. "-" .. tostring(counter or 0)
end

function Network.createEnvelope(config, destination, kind, payload, secret, now, nonce)
    config = Network.normalizeConfig(config)
    local envelope = {
        protocol = config.protocol, version = Network.protocolVersion, source = config.nodeId,
        destination = clean(destination or "", Network.maxNodeId), kind = clean(kind, Network.maxRequestKind),
        timestamp = math.floor(tonumber(now) or 0), nonce = clean(nonce or Network.newNonce(now, 0), 48), payload = Network.boundPayload(payload, Network.maxPayloadBytes),
    }
    envelope.auth = checksum(secret, canonical(envelope))
    return envelope
end

function Network.deriveKey(secret, localId, remoteId, salt)
    return Crypto.hkdf(secret, salt or "qalcom pairing", "qalcom " .. tostring(localId) .. " " .. tostring(remoteId), 32)
end

function Network.nextCounter(state)
    state = state or {}
    local counter = math.floor(tonumber(state.txCounter) or 0) + 1
    if counter > Network.maxCounter then counter = 1 end
    state.txCounter = counter
    return counter
end

function Network.createSecureEnvelope(config, destination, kind, payload, secret, counter, now)
    config = Network.normalizeConfig(config)
    counter = math.max(1, math.min(Network.maxCounter, math.floor(tonumber(counter) or 1)))
    local envelope = {
        protocol = config.protocol, version = Network.protocolVersion, source = config.nodeId,
        destination = clean(destination or "", Network.maxNodeId), kind = clean(kind, Network.maxRequestKind),
        timestamp = math.floor(tonumber(now) or Network.now()), counter = counter,
        nonce = counterNonce(config.nodeId, counter),
    }
    local plaintext = serializePayload(Network.boundPayload(payload, Network.maxPayloadBytes))
    if #plaintext > Network.maxPlaintextBytes then
        plaintext = serializePayload({ truncated = true, reason = "payload exceeds transport limit" })
    end
    local associated = table.concat({ envelope.protocol, envelope.version, envelope.source, envelope.destination, envelope.kind, envelope.timestamp, envelope.counter }, "|")
    local ciphertext, tag = Crypto.seal(secret, envelope.nonce, plaintext, associated)
    envelope.ciphertext = Crypto.hex(ciphertext)
    envelope.tag = Crypto.hex(tag)
    envelope.crypto = "hmac-sha256-stream-v1"
    return envelope
end

function Network.openSecureEnvelope(envelope, secret, expectedProtocol, now, node, replay, localNodeId)
    local ok, reason = Network.validateEnvelope(envelope, expectedProtocol, now, node, replay, localNodeId)
    if not ok then return nil, reason end
    if envelope.crypto ~= "hmac-sha256-stream-v1" then return nil, "Unsupported cryptographic suite" end
    if #envelope.ciphertext > Network.maxPayloadBytes * 2 or #envelope.tag > 64 then return nil, "Encrypted payload exceeds safety limit" end
    local ciphertext = Crypto.unhex(envelope.ciphertext)
    local tag = Crypto.unhex(envelope.tag)
    if not ciphertext or not tag or #ciphertext > Network.maxPlaintextBytes then return nil, "Malformed encrypted payload" end
    local associated = table.concat({ envelope.protocol, envelope.version, envelope.source, envelope.destination, envelope.kind, envelope.timestamp, envelope.counter }, "|")
    local plaintext, openReason = Crypto.open(secret, envelope.nonce, ciphertext, tag, associated)
    if not plaintext then return nil, openReason end
    local payload = deserializePayload(plaintext)
    if type(payload) ~= "table" then return nil, "Payload decode failed" end
    local marked, markReason = Network.markReplay(replay, envelope, now)
    if not marked then return nil, markReason end
    return payload
end

function Network.validateEnvelope(envelope, expectedProtocol, now, node, replay, localNodeId)
    if type(envelope) ~= "table" then return false, "Envelope is not a table" end
    if envelope.protocol ~= (expectedProtocol or Network.protocol) then return false, "Protocol mismatch" end
    if tonumber(envelope.version) ~= Network.protocolVersion then return false, "Protocol version mismatch" end
    if type(envelope.source) ~= "string" or envelope.source == "" then return false, "Source missing" end
    if type(envelope.kind) ~= "string" or envelope.kind == "" then return false, "Message kind missing" end
    if envelope.crypto ~= "hmac-sha256-stream-v1" then return false, "Cryptographic suite required" end
    local timestamp = tonumber(envelope.timestamp)
    if not timestamp then return false, "Timestamp missing" end
    now = tonumber(now) or 0
    if timestamp < now - Network.maxEnvelopeAge then return false, "Envelope expired" end
    if timestamp > now + Network.maxFutureSkew then return false, "Envelope is from the future" end
    if type(envelope.nonce) ~= "string" or envelope.nonce == "" then return false, "Nonce missing" end
    if envelope.counter and tonumber(envelope.counter) == nil then return false, "Counter invalid" end
    if type(node) ~= "table" or node.state ~= "paired" or node.secret == "" then return false, "Node is not paired" end
    if node.id ~= envelope.source then return false, "Unknown source" end
    if type(localNodeId) ~= "string" or localNodeId == "" then return false, "Local destination is required" end
    if type(envelope.destination) ~= "string" or envelope.destination == "" or envelope.destination == "*" then return false, "Destination missing" end
    if envelope.crypto == "hmac-sha256-stream-v1" then
        if envelope.destination ~= localNodeId then return false, "Destination mismatch" end
        if type(envelope.ciphertext) ~= "string" or type(envelope.tag) ~= "string" then return false, "Encrypted payload missing" end
        if envelope.counter == nil or math.floor(tonumber(envelope.counter)) ~= tonumber(envelope.counter) or tonumber(envelope.counter) < 1 or tonumber(envelope.counter) > Network.maxCounter then return false, "Counter invalid" end
        if envelope.nonce ~= counterNonce(envelope.source, tonumber(envelope.counter)) then return false, "Nonce binding failed" end
    else
        return false, "Cryptographic suite required"
    end
    replay = replay or {}
    local source = envelope.source
    if envelope.counter then
        local counter = tonumber(envelope.counter)
        local state = replay[source]
        local highWater = state and state.highWater or 0
        local floor = math.max(0, highWater - Network.maxReplay + 1)
        if counter <= floor or (state and state.seen and state.seen[counter]) then return false, "Replay or expired counter rejected" end
    else
        local replayKey = source .. ":" .. tostring(envelope.nonce)
        if replay[replayKey] then return false, "Replay rejected" end
    end
    return true
end

function Network.markReplay(replay, envelope, now)
    replay = replay or {}
    local source = envelope.source
    now = tonumber(now) or Network.now()
    if envelope.counter then
        local counter = tonumber(envelope.counter)
        local state = replay[source] or { highWater = 0, seen = {}, at = now }
        state.seen = state.seen or {}
        local highWater = tonumber(state.highWater) or 0
        local floor = math.max(0, highWater - Network.maxReplay + 1)
        if counter <= floor or state.seen[counter] then return false, "Replay or expired counter rejected" end
        state.seen[counter] = true
        if counter > highWater then state.highWater = counter end
        state.at = now
        local newFloor = math.max(0, state.highWater - Network.maxReplay + 1)
        for seenCounter, _ in pairs(state.seen) do
            if tonumber(seenCounter) < newFloor then state.seen[seenCounter] = nil end
        end
        replay[source] = state
        return true
    end
    local replayKey = source .. ":" .. tostring(envelope.nonce)
    if replay[replayKey] then return false, "Replay rejected" end
    replay[replayKey] = now
    local count = 0
    for key, value in pairs(replay) do
        if type(value) ~= "table" and now - (tonumber(value) or now) > Network.maxEnvelopeAge then replay[key] = nil else count = count + 1 end
    end
    while count > Network.maxReplay do
        for key, value in pairs(replay) do
            if type(value) ~= "table" then replay[key] = nil; count = count - 1; break end
        end
        if count <= Network.maxReplay then break end
    end
    return true
end

Network.readRequests = { ["system.status"] = true, ["telemetry.snapshot"] = true, ["radar.contacts"] = true, ["assets.summary"] = true }
Network.controlRequests = { ["infrastructure.toggle"] = true, ["infrastructure.safe_state"] = true, ["jobs.pause"] = true }

function Network.validateRequest(payload, kind)
    if type(payload) ~= "table" then return false, "Request payload must be a table" end
    local request = clean(payload.request, 48)
    if kind == "status_request" then
        if not Network.readRequests[request] then return false, "Read request is not allowlisted" end
    elseif kind == "control_request" then
        if not Network.controlRequests[request] then return false, "Control request is not allowlisted" end
        if request == "infrastructure.toggle" and clean(payload.target, 32) == "" then return false, "Control target required" end
    else
        return false, "Unsupported request kind"
    end
    return true
end

function Network.parseState(text)
    local source = tostring(text or "")
    local state = { schemaVersion = Network.schemaVersion, txCounter = 0, rxCounters = {} }
    local sawSchema, sawState = false, false
    if source ~= "" then
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local fields = split(line)
        if fields[1] == "schema" then state.schemaVersion = tonumber(fields[2]) or Network.schemaVersion; sawSchema = true
        elseif fields[1] == "state" then
            if not fields[2] or tonumber(fields[2]) == nil then state.error = "Malformed network state" else state.txCounter = math.max(0, math.floor(tonumber(fields[2]) or 0)); sawState = true end
        elseif fields[1] == "rx" and fields[2] and fields[3] then
            local counter = tonumber(fields[3])
            if counter and counter >= 0 and counter <= Network.maxCounter then
                local window = { highWater = math.floor(counter), seen = {} }
                for token in tostring(fields[4] or ""):gmatch("%d+") do
                    local seenCounter = tonumber(token)
                    if seenCounter and seenCounter >= 0 and seenCounter <= window.highWater then window.seen[seenCounter] = true end
                end
                if next(window.seen) == nil then window.seen[window.highWater] = true end
                state.rxCounters[fields[2]] = window
            end
        end
    end
    end
    if source ~= "" and (not sawSchema or not sawState) then state.error = state.error or "Malformed network state" end
    if state.schemaVersion ~= Network.schemaVersion then state.error = "Unsupported network state schema" end
    return state
end

function Network.serializeState(state)
    state = state or {}
    local lines = {
        "# Qalcom network counter schema " .. tostring(Network.schemaVersion),
        "schema|" .. tostring(Network.schemaVersion),
        "state|" .. tostring(math.max(0, math.floor(tonumber(state.txCounter) or 0))),
    }
    local ids = {}
    for id, counter in pairs(state.rxCounters or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local value = state.rxCounters[id]
        local highWater = type(value) == "table" and value.highWater or value
        local seen = {}
        if type(value) == "table" then
            for counter, accepted in pairs(value.seen or {}) do if accepted then seen[#seen + 1] = math.floor(tonumber(counter) or 0) end end
            table.sort(seen)
        end
        lines[#lines + 1] = "rx|" .. escape(id) .. "|" .. tostring(math.max(0, math.floor(tonumber(highWater) or 0))) .. "|" .. table.concat(seen, ",")
    end
    return table.concat(lines, "\n") .. "\n"
end

function Network.rateLimit(rate, nodeId, now)
    rate = rate or {}
    now = tonumber(now) or 0
    local bucket = rate[nodeId]
    if not bucket or now - bucket.started >= Network.maxRateWindow then
        bucket = { started = now, count = 0 }
        rate[nodeId] = bucket
    end
    bucket.count = bucket.count + 1
    return bucket.count <= Network.maxRequestsPerWindow, bucket.count
end

function Network.requestId(payload)
    return clean(payload and payload.requestId or "", 64)
end

function Network.boundPayload(value, maximum, depth, seen)
    maximum = maximum or Network.maxPayloadBytes
    depth = depth or 0
    seen = seen or {}
    if depth > 4 then return "<depth>" end
    if type(value) == "string" then return value:sub(1, maximum) end
    if type(value) ~= "table" then return value end
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local result, size = {}, 0
    for key, item in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local bounded = Network.boundPayload(item, maximum, depth + 1, seen)
            result[key] = bounded
            size = size + #stable(key) + #stable(bounded)
            if size >= maximum then break end
        end
    end
    seen[value] = nil
    return result
end

return Network
