local Incidents = {}

Incidents.schemaVersion = 1
Incidents.maxIncidents = 64
Incidents.maxTimeline = 16
Incidents.maxText = 96
Incidents.severities = { low = true, medium = true, high = true, critical = true }
Incidents.states = { open = true, acknowledged = true, resolved = true, cancelled = true }
Incidents.playbooks = {
    alarm = { "infrastructure.safe_state" },
    lockdown = { "infrastructure.safe_state", "jobs.pause" },
    evacuation = { "infrastructure.safe_state" },
}

local function clean(value, maximum)
    return tostring(value or ""):gsub("[\r\n|]", " "):sub(1, maximum or Incidents.maxText)
end

local function number(value, fallback)
    local result = tonumber(value)
    return result and math.floor(result) or fallback or 0
end

function Incidents.empty()
    return { schemaVersion = Incidents.schemaVersion, incidents = {} }
end

function Incidents.normalize(item, fallbackId)
    item = item or {}
    local severity = Incidents.severities[item.severity] and item.severity or "medium"
    local state = Incidents.states[item.state] and item.state or "open"
    local incident = {
        id = clean(item.id or fallbackId or "incident", 32),
        title = clean(item.title or "Untitled incident", 64),
        severity = severity,
        state = state,
        source = clean(item.source or "operator", 48),
        faction = clean(item.faction or "unknown", 40),
        asset = clean(item.asset or "unknown", 48),
        created = number(item.created),
        updated = number(item.updated, number(item.created)),
        acknowledgedBy = clean(item.acknowledgedBy or "", 32),
        timeline = {},
    }
    for index, event in ipairs(item.timeline or {}) do
        if index > Incidents.maxTimeline then break end
        incident.timeline[#incident.timeline + 1] = {
            at = number(event.at), actor = clean(event.actor, 32),
            action = clean(event.action, 40), detail = clean(event.detail, 96),
        }
    end
    return incident
end

function Incidents.add(data, item, now)
    data = data or Incidents.empty()
    local normalized = Incidents.normalize(item, "incident-" .. tostring(#data.incidents + 1))
    normalized.created = normalized.created ~= 0 and normalized.created or number(now)
    normalized.updated = normalized.created
    for _, existing in ipairs(data.incidents) do
        if existing.id == normalized.id then return false, "Incident already exists" end
    end
    if #data.incidents >= Incidents.maxIncidents then return false, "Incident limit reached" end
    data.incidents[#data.incidents + 1] = normalized
    return true, normalized
end

function Incidents.find(data, id)
    for _, item in ipairs((data and data.incidents) or {}) do if item.id == id then return item end end
end

function Incidents.append(data, id, actor, action, detail, now)
    local incident = Incidents.find(data, id)
    if not incident then return false, "Incident not found" end
    if #incident.timeline >= Incidents.maxTimeline then table.remove(incident.timeline, 1) end
    incident.timeline[#incident.timeline + 1] = { at = number(now), actor = clean(actor, 32), action = clean(action, 40), detail = clean(detail, 96) }
    incident.updated = number(now)
    return true, incident
end

function Incidents.setState(data, id, state, actor, now)
    if not Incidents.states[state] then return false, "Invalid incident state" end
    local incident = Incidents.find(data, id)
    if not incident then return false, "Incident not found" end
    incident.state = state
    if state == "acknowledged" then incident.acknowledgedBy = clean(actor, 32) end
    return Incidents.append(data, id, actor, "state", state, now)
end

function Incidents.preview(playbook, context)
    local actions = Incidents.playbooks[playbook]
    if not actions then return false, "Unknown playbook" end
    local result = { playbook = playbook, dryRun = true, actions = {}, blocked = false, reason = nil }
    for _, action in ipairs(actions) do
        local allowed = not context or context[action] ~= false
        result.actions[#result.actions + 1] = { action = action, allowed = allowed, reversible = action ~= "jobs.pause" }
        if not allowed then result.blocked = true; result.reason = "Policy denied: " .. action end
    end
    return true, result
end

function Incidents.serialize(data)
    data = data or Incidents.empty()
    local lines = { "# Qalcom incident schema " .. tostring(Incidents.schemaVersion), "schema|" .. tostring(Incidents.schemaVersion) }
    for index, source in ipairs(data.incidents or {}) do
        if index <= Incidents.maxIncidents then
            local item = Incidents.normalize(source, "incident-" .. tostring(index))
            lines[#lines + 1] = table.concat({ "incident", clean(item.id, 32), clean(item.title, 64), item.severity, item.state, clean(item.source, 48), clean(item.faction, 40), clean(item.asset, 48), item.created, item.updated, clean(item.acknowledgedBy, 32) }, "|")
            for _, event in ipairs(item.timeline) do
                lines[#lines + 1] = table.concat({ "event", item.id, event.at, clean(event.actor, 32), clean(event.action, 40), clean(event.detail, 96) }, "|")
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function Incidents.parse(text)
    local result, current = Incidents.empty(), {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = {}
            for value in line:gmatch("[^|]+") do fields[#fields + 1] = value end
            if fields[1] == "schema" then result.schemaVersion = tonumber(fields[2]) or Incidents.schemaVersion
            elseif fields[1] == "incident" and #result.incidents < Incidents.maxIncidents then
                local item = Incidents.normalize({ id = fields[2], title = fields[3], severity = fields[4], state = fields[5], source = fields[6], faction = fields[7], asset = fields[8], created = fields[9], updated = fields[10], acknowledgedBy = fields[11] })
                if not current[item.id] then result.incidents[#result.incidents + 1] = item; current[item.id] = item end
            elseif fields[1] == "event" and current[fields[2]] then
                Incidents.append(result, fields[2], fields[4], fields[5], fields[6], fields[3])
            end
        end
    end
    if result.schemaVersion ~= Incidents.schemaVersion then result.error = "Unsupported incident schema"; result.incidents = {} end
    return result
end

return Incidents
