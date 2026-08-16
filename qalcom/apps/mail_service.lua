--[[ Qalcom Mail service (client half) ------------------------------------------
    Hidden background service that owns the mail channel and moves mail between
    this computer and its relay. It never blocks the desktop: all modem I/O is
    event-driven inside this coroutine, and the Mail app only ever touches the
    local mailbox files this service reads and writes.

    Client responsibilities (this milestone):
      * drain /qalcom/data/mail.outbox: encode + chunk each message and deposit
        it to the relay, moving delivered mail to mail.sent;
      * poll the relay, fetch + reassemble waiting mail, verify attachment
        checksums, quarantine attachment bytes under /qalcom/mail/, write
        mail.inbox, then ack.

    The relay (server) half is added in the next milestone; a computer with
    mail.isRelay set is otherwise handled there.

    All transport (secure envelopes, counters, replay, rate limits) is reused
    from network.lua; mail runs on its own channel with its own state so it
    never entangles with the telemetry service.
------------------------------------------------------------------------------]]

local Network = dofile("/qalcom/lib/network.lua")
local Protocol = dofile("/qalcom/lib/protocol.lua")
local Mail = dofile("/qalcom/lib/mail.lua")

return function(ctx)
    local nodeId = "computer-" .. tostring(os.getComputerID())

    local FILES = {
        config = "/qalcom/data/mail.meta",
        state  = "/qalcom/data/mail.state",
        outbox = "/qalcom/data/mail.outbox",
        inbox  = "/qalcom/data/mail.inbox",
        sent   = "/qalcom/data/mail.sent",
        spool  = "/qalcom/data/mail.spool",   -- relay only
        map    = "/qalcom/data/mail.map",     -- relay only
    }

    local mailConfig = Mail.emptyConfig()
    local transport = Network.emptyConfig(nodeId)
    local nodes = Network.emptyNodes()
    local state = { txCounter = 0, rxCounters = {} }
    local replay = {}
    local modems = {}
    local relayNode, relaySecret
    local busy = false

    -- Relay (server) state.
    local spool = Mail.newSpool()
    local directory = Mail.newDirectory()
    local relayProto = Protocol.emptyState()
    local ticks = 0

    local function persist(path, text)
        local ok = ctx:writeFile(path, text)
        return ok == true
    end

    -- Fold the live replay windows back into the persisted counter state.
    local function syncReplayState()
        state.rxCounters = {}
        for id, window in pairs(replay) do
            if type(window) == "table" and window.highWater then state.rxCounters[id] = window end
        end
        return Network.serializeState(state)
    end

    local function load()
        mailConfig = Mail.parseConfig(ctx:readFile(FILES.config) or "")
        nodes = Network.parseNodes(ctx:readFile("/qalcom/data/nodes.meta") or "")
        state = Network.parseState(ctx:readFile(FILES.state) or "")
        if state.error then state = { txCounter = 0, rxCounters = {} } end
        replay = {}
        for id, window in pairs(state.rxCounters or {}) do
            if type(window) == "table" then
                replay[id] = { highWater = window.highWater or 0, seen = window.seen or {}, at = Network.now() }
            else
                replay[id] = { highWater = window or 0, seen = { [window or 0] = true }, at = Network.now() }
            end
        end

        transport = Network.emptyConfig(nodeId)
        transport.protocol = Network.protocol
        transport.channel = mailConfig.channel or Network.mailChannel
        transport.replyChannel = Network.mailReplyChannel

        relayNode = (mailConfig.relay ~= "") and Network.findNode(nodes, mailConfig.relay) or nil
        relaySecret = relayNode and Mail.deriveMailKey(relayNode.secret, nodeId, relayNode.id) or nil

        -- Relay-side stores.
        if mailConfig.isRelay then
            spool = Mail.parseSpool(ctx:readFile(FILES.spool) or "")
            directory = Mail.parseDirectory(ctx:readFile(FILES.map) or "")
            relayProto = Protocol.emptyState()
        end

        -- Open the mail channels for receiving. A client hears responses on the
        -- reply channel; a relay hears requests on the main channel. Opening both
        -- lets a self-hosting node act as client and relay. Transmit needs no open.
        modems = {}
        if mailConfig.enabled and (mailConfig.isRelay or relayNode) then
            for _, name in ipairs(ctx:networkModems() or {}) do
                local a = ctx:modemOpen(name, transport.channel)
                local b = ctx:modemOpen(name, transport.replyChannel)
                if a or b then modems[#modems + 1] = name end
            end
        end
    end

    -- Send a mail request to the relay and wait for its authenticated response,
    -- correlated by request id. Returns the response payload, or nil + reason.
    local function request(payload, timeout)
        if not relayNode or not relaySecret or #modems == 0 then return nil, "mail transport unavailable" end
        local counter = Network.nextCounter(state)
        payload.requestId = nodeId .. "-" .. counter
        local envelope = Network.createSecureEnvelope(transport, relayNode.id, "mail_request", payload, relaySecret, counter, Network.now())
        persist(FILES.state, Network.serializeState(state))

        local sent = false
        for _, modem in ipairs(modems) do
            if ctx:modemTransmit(modem, transport.channel, transport.replyChannel, envelope) then sent = true end
        end
        if not sent then return nil, "no modem" end

        local timer = os.startTimer(timeout or 3)
        while true do
            local event = { ctx:pullEvent() }
            local name = event[1]
            if name == "modem_message" then
                local channel, response = event[3], event[5]
                if channel == transport.replyChannel and type(response) == "table" then
                    local reply = Network.openSecureEnvelope(response, relaySecret, transport.protocol, Network.now(), relayNode, replay, nodeId)
                    if reply and reply.requestId == payload.requestId then
                        persist(FILES.state, syncReplayState())
                        return reply
                    end
                end
            elseif name == "timer" and event[2] == timer then
                return nil, "timeout"
            elseif name == "qalcom_session_invalid" then
                return nil, "session ended"
            end
        end
    end

    local function makeDirFor(path)
        local dir = fs.getDir(path)
        if dir and dir ~= "" and dir ~= "/" then ctx:makeDir("/" .. dir) end
    end

    local function loadOutgoingAttachments(record)
        local attachments = {}
        for _, meta in ipairs(record.attachments or {}) do
            local bytes = ctx:readFile(Mail.outboxAttachmentPath(record.id, meta.name))
            if not bytes then return nil, "attachment missing: " .. tostring(meta.name) end
            attachments[#attachments + 1] = { name = meta.name, data = bytes }
        end
        return attachments
    end

    -- Deposit one outbox message. Returns true on delivery, or false + reason.
    local function deliver(record)
        local attachments, reason = loadOutgoingAttachments(record)
        if not attachments then return false, reason end
        local message, buildReason = Mail.newMessage({
            id = record.id, from = record.from, to = record.to, subject = record.subject,
            body = record.body, at = record.at, attachments = attachments,
        })
        if not message then return false, buildReason end
        -- Address the relay by the recipient's bare alias (the relay resolves it
        -- to a mailbox); accept either "bob" or "bob@relay" in the record.
        local parsed = Mail.parseAddress(record.to)
        local toAlias = (parsed and parsed.alias) or record.to
        local blob = Mail.encodeMessage(message)
        local deposits = Mail.buildDeposits(record.id, toAlias, blob, Mail.maxChunkBytes, { from = record.from, at = record.at })
        for _, payload in ipairs(deposits) do
            local reply, requestReason = request(payload)
            if not reply then return false, requestReason or "no response" end
            if reply.outcome ~= "success" then return false, tostring(reply.outcome) end
        end
        return true
    end

    local function drainOutbox()
        local outbox = Mail.parseMailbox(ctx:readFile(FILES.outbox) or "")
        if #outbox.messages == 0 then return end
        local sentbox = Mail.parseMailbox(ctx:readFile(FILES.sent) or "")
        local remaining = {}
        local changed = false
        local transportDown = false
        for _, record in ipairs(outbox.messages) do
            if transportDown then
                remaining[#remaining + 1] = record
            else
                local ok, reason = deliver(record)
                if ok then
                    record.state = "sent"; record.unread = false
                    Mail.addMessage(sentbox, record)
                    for _, meta in ipairs(record.attachments or {}) do
                        ctx:deletePath(Mail.outboxAttachmentPath(record.id, meta.name))
                    end
                    changed = true
                    if ctx.audit then ctx:audit("mail-sent", record.id .. " -> " .. tostring(record.to)) end
                else
                    record.state = "pending"
                    remaining[#remaining + 1] = record
                    -- A transport failure means the relay is unreachable; stop and
                    -- retry the whole batch next cycle rather than timing out on each.
                    if reason == "timeout" or reason == "no modem" or reason == "mail transport unavailable" then
                        transportDown = true
                    end
                    if ctx.audit then ctx:audit("mail-deferred", record.id .. " " .. tostring(reason)) end
                end
            end
        end
        outbox.messages = remaining
        if changed then persist(FILES.sent, Mail.serializeMailbox(sentbox)) end
        persist(FILES.outbox, Mail.serializeMailbox(outbox))
    end

    local function collectInbox()
        local reply = request({ request = "mail.poll" })
        if not reply or reply.outcome ~= "success" then return end
        local ready = (reply.data and reply.data.messages) or {}
        if #ready == 0 then return end
        local inbox = Mail.parseMailbox(ctx:readFile(FILES.inbox) or "")
        local changed = false
        for _, summary in ipairs(ready) do
            local total = tonumber(summary.total) or 0
            local chunks, complete = {}, total > 0
            for seq = 1, total do
                local fetched = request({ request = "mail.fetch", msgId = summary.msgId, seq = seq })
                if fetched and fetched.outcome == "success" and fetched.data and type(fetched.data.chunk) == "string" then
                    chunks[seq] = fetched.data.chunk
                else
                    complete = false
                    break
                end
            end
            local blob = complete and Mail.joinParts(chunks, total) or nil
            if blob then
                local message, data = Mail.decodeMessage(blob)
                if message then
                    local saved = true
                    for name, bytes in pairs(data or {}) do
                        local path = Mail.attachmentPath(message.id, name)
                        makeDirFor(path)
                        if not ctx:writeFile(path, bytes) then saved = false end
                    end
                    if saved then
                        Mail.addMessage(inbox, Mail.inboxRecordFrom(message))
                        changed = true
                        request({ request = "mail.ack", msgId = message.id })
                        if ctx.audit then ctx:audit("mail-received", message.id .. " <- " .. tostring(message.from)) end
                    end
                end
            end
        end
        if changed then persist(FILES.inbox, Mail.serializeMailbox(inbox)) end
    end

    -- === Relay (server) half ===============================================

    local function persistSpool() persist(FILES.spool, Mail.serializeSpool(spool)) end
    local function persistDirectory() persist(FILES.map, Mail.serializeDirectory(directory)) end

    -- Resolve a deposit's `to` field to a mailbox key: a registered alias, or a
    -- paired node id addressed directly. Unknown recipients are refused.
    local function resolveRecipient(to)
        local viaAlias = Mail.lookup(directory, to)
        if viaAlias then return viaAlias end
        if Network.findNode(nodes, to) then return to end
        return nil
    end

    -- Seal and transmit a response to a request, using the same derived key.
    local function respond(requestEnvelope, requestPayload, secret, outcome, data)
        local counter = Network.nextCounter(state)
        local response = Protocol.response(transport, requestEnvelope, requestPayload, outcome, data or {}, secret, counter, Network.now())
        for _, modem in ipairs(modems) do
            ctx:modemTransmit(modem, transport.replyChannel, requestEnvelope.replyChannel or transport.replyChannel, response)
        end
        persist(FILES.state, Network.serializeState(state))
    end

    -- Handle one inbound mail request. No-op unless this computer is a relay.
    local function serve(event)
        if not mailConfig.isRelay then return end
        local channel, envelope = event[3], event[5]
        if channel ~= transport.channel or type(envelope) ~= "table" then return end

        local node = Network.findNode(nodes, envelope.source)
        if not node then return end   -- only paired nodes may use the relay
        local secret = Mail.deriveMailKey(node.secret, node.id, transport.nodeId)
        local now = Network.now()
        local payload = Network.openSecureEnvelope(envelope, secret, transport.protocol, now, node, replay, transport.nodeId)
        if not payload then return end
        persist(FILES.state, syncReplayState())

        local valid = Protocol.validateRequest(relayProto, envelope, payload, now, node, transport.nodeId)
        if not valid then return end

        local request = payload.request
        if request == "mail.deposit" then
            local recipient = resolveRecipient(payload.to)
            if not recipient then respond(envelope, payload, secret, "unknown-recipient"); return end
            local _, status = Mail.spoolDeposit(spool, recipient, {
                msgId = payload.msgId, from = payload.from or envelope.source, to = payload.to,
                at = payload.at, seq = payload.seq, total = payload.total, data = payload.data,
            })
            persistSpool()
            respond(envelope, payload, secret, status == "quota" and "quota" or "success", { status = status })
        elseif request == "mail.poll" then
            respond(envelope, payload, secret, "success", { messages = Mail.spoolReady(spool, envelope.source) })
        elseif request == "mail.fetch" then
            local chunks = Mail.spoolChunks(spool, envelope.source, payload.msgId)
            local seq = tonumber(payload.seq) or 1
            if chunks and chunks[seq] then
                respond(envelope, payload, secret, "success", { chunk = chunks[seq], seq = seq })
            else
                respond(envelope, payload, secret, "not-found")
            end
        elseif request == "mail.ack" then
            local removed = Mail.spoolAck(spool, envelope.source, payload.msgId)
            persistSpool()
            respond(envelope, payload, secret, removed and "success" or "not-found")
        elseif request == "mail.register" then
            local ok, reason = Mail.registerAlias(directory, payload.alias, envelope.source)
            if ok then persistDirectory() end
            respond(envelope, payload, secret, ok and "success" or "conflict", { reason = reason })
        elseif request == "mail.lookup" then
            respond(envelope, payload, secret, "success", { alias = payload.alias, nodeId = Mail.lookup(directory, payload.alias) or "" })
        end
    end

    -- Expire spooled mail past its TTL (throttled to run occasionally). Message
    -- timestamps and the TTL are in milliseconds (os.epoch scale), so eviction
    -- must compare against a millisecond clock, not Network.now() (seconds).
    local function nowMillis()
        if os.epoch then local ok, value = pcall(os.epoch, "utc"); if ok then return value end end
        return Network.now() * 1000
    end
    local function evict()
        if not mailConfig.isRelay then return end
        if Mail.spoolEvict(spool, nowMillis(), Mail.defaultTtl) > 0 then persistSpool() end
    end

    -- One send+receive cycle, guarded against overlap and never allowed to crash
    -- the service.
    local function flush()
        if busy or not mailConfig.enabled or not relayNode then return end
        busy = true
        local ok, err = pcall(function()
            drainOutbox()
            collectInbox()
        end)
        busy = false
        if not ok and ctx.audit then ctx:audit("mail-error", tostring(err)) end
    end

    load()
    while true do
        local event = { ctx:pullEvent() }
        local name = event[1]
        if name == "modem_message" then
            -- Relay: answer inbound mail requests. Inert on a non-relay node.
            local ok, err = pcall(serve, event)
            if not ok and ctx.audit then ctx:audit("mail-relay-error", tostring(err)) end
        elseif name == "qalcom_mail_flush" then
            load()
            flush()
        elseif name == "qalcom_tick" then
            flush()
            ticks = ticks + 1
            if mailConfig.isRelay and ticks % 60 == 0 then
                local ok, err = pcall(evict)
                if not ok and ctx.audit then ctx:audit("mail-relay-error", tostring(err)) end
            end
        elseif name == "qalcom_network_reload" or name == "peripheral" or name == "peripheral_detach" then
            load()
        end
    end
end
