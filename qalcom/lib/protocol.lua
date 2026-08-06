local Protocol = {}
local Network = dofile("/qalcom/lib/network.lua")

Protocol.schemaVersion = 1
Protocol.maxAudit = 128
Protocol.maxResponse = 12000

local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n|]", " "):sub(1, maximum or 120)
end

function Protocol.emptyState()
    return { audit = {}, rate = {}, replay = {}, requests = {} }
end

function Protocol.record(state, entry, now)
    state = state or Protocol.emptyState()
    local audit = state.audit
    audit[#audit + 1] = {
        id = clean(entry and entry.id, 64),
        source = clean(entry and entry.source, 48),
        request = clean(entry and entry.request, 48),
        outcome = clean(entry and entry.outcome, 24),
        detail = clean(entry and entry.detail, 120),
        at = tonumber(now) or 0,
    }
    while #audit > Protocol.maxAudit do table.remove(audit, 1) end
    return state
end

function Protocol.validateRequest(state, envelope, payload, now, node, localNodeId)
    local requestId = Network.requestId(payload)
    if requestId == "" then return false, "Request ID required" end
    if state.requests[requestId] then return false, "Duplicate request ID" end
    local requestKind = envelope.kind
    local valid, reason = Network.validateRequest(payload, requestKind)
    if not valid then return false, reason end
    local rateAllowed, count = Network.rateLimit(state.rate, envelope.source, now)
    if not rateAllowed then return false, "Per-node rate limit exceeded" end
    state.requests[requestId] = { at = tonumber(now) or 0, source = envelope.source, count = count }
    while true do
        local removed = false
        for id, item in pairs(state.requests) do
            if (tonumber(now) or 0) - (tonumber(item.at) or 0) > Network.maxEnvelopeAge then state.requests[id] = nil; removed = true; break end
        end
        if not removed then break end
    end
    return true
end

function Protocol.response(config, requestEnvelope, requestPayload, outcome, payload, secret, counter, now)
    return Network.createSecureEnvelope(config, requestEnvelope.source, "response", {
        requestId = Network.requestId(requestPayload),
        outcome = clean(outcome, 24),
        data = Network.boundPayload(payload or {}, Protocol.maxResponse),
    }, secret, counter, now)
end

function Protocol.auditText(state)
    local lines = { "# Qalcom network audit schema " .. tostring(Protocol.schemaVersion) }
    for _, entry in ipairs((state and state.audit) or {}) do
        lines[#lines + 1] = table.concat({
            "audit", clean(entry.id, 64), clean(entry.source, 48), clean(entry.request, 48),
            clean(entry.outcome, 24), clean(entry.detail, 120), tostring(entry.at or 0),
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

return Protocol
