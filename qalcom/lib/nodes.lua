local Nodes = {}
local Network = dofile("/qalcom/lib/network.lua")

Nodes.maxPairCode = 12
Nodes.maxCapabilities = 160

local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n|]", " "):sub(1, maximum or 120)
end

local function codeValue(value)
    local number = math.floor(tonumber(value) or 0) % 1000000
    return string.format("%06d", number)
end

function Nodes.newPairing(nodeId, now, entropy)
    local seed = math.floor((tonumber(now) or 0) * 1000 + (tonumber(entropy) or 0))
    local code = codeValue(seed * 7919 + 104729)
    local secret = clean(code .. ":" .. tostring(seed) .. ":" .. tostring(nodeId), Network.maxSecret)
    return { nodeId = clean(nodeId, Network.maxNodeId), code = code, secret = secret, expires = (tonumber(now) or 0) + 120 }
end

function Nodes.acceptPairing(data, pairing, alias, role, capabilities, now, enteredCode)
    if type(pairing) ~= "table" or tostring(enteredCode or "") ~= tostring(pairing.code or "") then return false, "Pairing code mismatch" end
    if tonumber(pairing.expires) < (tonumber(now) or 0) then return false, "Pairing expired" end
    local node = Network.normalizeNode({
        id = pairing.nodeId,
        alias = alias or pairing.nodeId,
        secret = pairing.secret,
        role = role or "Observer",
        state = "paired",
        lastSeen = now,
        capabilities = clean(capabilities, Nodes.maxCapabilities),
    })
    return Network.pairNode(data, node), node
end

function Nodes.setState(data, nodeId, state)
    if state ~= "paired" and state ~= "blocked" and state ~= "quarantined" then return false, "Invalid node state" end
    local node = Network.findNode(data, nodeId)
    if not node then return false, "Node not found" end
    node.state = state
    return true
end

function Nodes.touch(data, nodeId, now)
    local node = Network.findNode(data, nodeId)
    if not node then return false, "Node not found" end
    node.lastSeen = tonumber(now) or 0
    return true
end

return Nodes
