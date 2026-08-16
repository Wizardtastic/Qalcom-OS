--[[ Qalcom Mail logic ----------------------------------------------------------
    Pure, side-effect-free core for the relay email system. Owns the mail data
    contracts: address parsing, message wire encoding + chunking, the local
    mailbox stores (inbox/sent/outbox), the relay spool, the alias directory,
    and attachment quarantine paths + checksums.

    Everything here is plain Lua so tests/pure_test.lua can exercise it under a
    bare interpreter. Two serialization styles are used deliberately:
      * raw-byte data (message blobs, chunks, the spool) uses length-prefixed
        "netstrings" (`<len>:<bytes>`), which are safe for arbitrary bytes;
      * text metadata (mailboxes, directory) uses a line format with a
        newline-preserving escape, mirroring network.lua's conventions.
    Only crypto (SHA-256 for attachment integrity) is required, loaded through a
    candidate-path loader so this works on a CC:T computer and from the repo root.
------------------------------------------------------------------------------]]

local Mail = {}
Mail.schemaVersion = 1

-- Bounds. maxChunkBytes leaves headroom under the transport's 12000-byte
-- envelope payload cap for envelope overhead.
Mail.maxChunkBytes      = 10500
Mail.maxSubject         = 128
Mail.maxBody            = 8000
Mail.maxAttachments     = 8
Mail.maxAttachmentBytes = 262144   -- 256 KiB per attachment
Mail.maxMessageBytes    = 300000   -- ~300 KiB total encoded message
Mail.maxMailboxMessages = 200      -- bounded local store
Mail.maxSpoolMessages   = 64       -- per mailbox on the relay
Mail.maxSpoolBytes      = 1048576  -- 1 MiB per mailbox on the relay
Mail.defaultTtl         = 7 * 24 * 3600 * 1000  -- 7 days, in ms (os.epoch scale)
Mail.attachmentRoot     = "/qalcom/mail/"

Mail.maxAlias = 32
Mail.maxRelay = 48

-- === Dependency loading =====================================================
local function loadModule(name)
    local candidates = { "qalcom/lib/" .. name, "../qalcom/lib/" .. name, "/qalcom/lib/" .. name }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    return nil
end
local Crypto = loadModule("crypto.lua")
Mail.cryptoAvailable = Crypto ~= nil

-- === Small utilities ========================================================
local function isNonEmptyString(value) return type(value) == "string" and value ~= "" end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function Mail.checksum(bytes)
    if not Crypto then return nil end
    return Crypto.hex(Crypto.sha256(tostring(bytes or "")))
end

-- Newline-preserving escape for the line-based text stores (mailboxes,
-- directory, config). Netstring framing is used separately for raw bytes.
local function esc(value)
    return tostring(value or "")
        :gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function unesc(value)
    return (tostring(value or ""):gsub("\\(.)", function(character)
        if character == "p" then return "|" end
        if character == "n" then return "\n" end
        if character == "r" then return "\r" end
        if character == "\\" then return "\\" end
        return character
    end))
end

local function splitFields(line)
    local fields = {}
    for field in (line .. "|"):gmatch("(.-)|") do fields[#fields + 1] = unesc(field) end
    return fields
end

-- === Addresses ==============================================================

function Mail.formatAddress(alias, relay)
    return tostring(alias or "") .. "@" .. tostring(relay or "")
end

-- Parse "alias@relay" into its parts, or nil + reason. A bare "alias" (no @) is
-- returned with relay = nil so callers can apply a default relay.
function Mail.parseAddress(address)
    if not isNonEmptyString(address) then return nil, "empty address" end
    local alias, relay = address:match("^([^@]+)@(.+)$")
    if not alias then alias, relay = address, nil end
    if alias:match("^[%w_%-%.]+$") == nil or #alias > Mail.maxAlias then
        return nil, "invalid alias: " .. tostring(alias)
    end
    if relay ~= nil and (relay:match("^[%w_%-%.]+$") == nil or #relay > Mail.maxRelay) then
        return nil, "invalid relay: " .. tostring(relay)
    end
    return { alias = alias, relay = relay }
end

function Mail.messageId(source, counter, nonce)
    return (tostring(source or "node"):gsub("[^%w_%-%.]", "_"))
        .. "-" .. tostring(counter or 0)
        .. "-" .. (tostring(nonce or ""):gsub("[^%w]", ""):sub(1, 12))
end

-- === Message validation =====================================================

function Mail.newMessage(fields)
    fields = fields or {}
    local message = {
        id = fields.id,
        from = fields.from,
        to = fields.to,
        subject = fields.subject or "",
        body = fields.body or "",
        at = fields.at or 0,
        attachments = {},
    }
    for _, attachment in ipairs(fields.attachments or {}) do
        message.attachments[#message.attachments + 1] = {
            name = attachment.name,
            data = attachment.data,
            size = attachment.size,
            sha256 = attachment.sha256,
        }
    end
    local ok, reason = Mail.validateMessage(message)
    if not ok then return nil, reason end
    return message
end

function Mail.validateMessage(message)
    if type(message) ~= "table" then return false, "message is not a table" end
    if not isNonEmptyString(message.from) then return false, "message has no sender" end
    if not isNonEmptyString(message.to) then return false, "message has no recipient" end
    if type(message.subject) ~= "string" or #message.subject > Mail.maxSubject then
        return false, "subject missing or too long"
    end
    if type(message.body) ~= "string" or #message.body > Mail.maxBody then
        return false, "body missing or too long"
    end
    local attachments = message.attachments or {}
    if #attachments > Mail.maxAttachments then return false, "too many attachments" end
    local total = #message.body
    for index, attachment in ipairs(attachments) do
        if not isNonEmptyString(attachment.name) then return false, "attachment #" .. index .. " has no name" end
        if attachment.data ~= nil then
            if type(attachment.data) ~= "string" then return false, "attachment data must be a string" end
            if #attachment.data > Mail.maxAttachmentBytes then return false, "attachment too large: " .. attachment.name end
            total = total + #attachment.data
        end
    end
    if total > Mail.maxMessageBytes then return false, "message exceeds total size limit" end
    return true
end

-- === Client helpers =========================================================

-- Staging area for outgoing attachments (bytes the app writes at compose time
-- and the service reads at send time), kept separate from received mail.
Mail.outboxRoot = "/qalcom/mail/outbox/"

function Mail.outboxAttachmentPath(messageId, name)
    return Mail.outboxRoot .. Mail.sanitizeName(messageId) .. "/" .. Mail.sanitizeName(name)
end

-- Derive a channel-specific mail key from a node's pairing secret so mail and
-- telemetry never share key material and an envelope cannot be replayed across
-- purposes. The salt is order-independent so the client and relay derive the
-- same key regardless of which side computes it. Falls back to the raw secret
-- only if crypto is unavailable.
function Mail.deriveMailKey(secret, idA, idB)
    if not Crypto then return tostring(secret or "") end
    local a, b = tostring(idA or ""), tostring(idB or "")
    if a > b then a, b = b, a end
    return Crypto.hkdf(tostring(secret or ""), a .. "|" .. b, "qalcom mail", 32)
end

-- Build the ordered mail.deposit request payloads for a message blob. The
-- service adds the per-request id and counter before sealing each one. `meta`
-- carries { from, at } so the relay can summarise a message for a poll without
-- decoding its payload.
function Mail.buildDeposits(messageId, to, blob, maxBytes, meta)
    meta = meta or {}
    local parts = Mail.split(blob, maxBytes)
    local deposits = {}
    for seq, data in ipairs(parts) do
        deposits[seq] = {
            request = "mail.deposit", to = to, msgId = messageId,
            from = meta.from, at = meta.at, seq = seq, total = #parts, data = data,
        }
    end
    return deposits
end

-- Turn a freshly decoded message into an inbox record (unread, no bytes).
function Mail.inboxRecordFrom(message)
    return {
        id = message.id, from = message.from, to = message.to,
        subject = message.subject or "", body = message.body or "", at = message.at or 0,
        unread = true, state = "unread", attachments = message.attachments or {},
    }
end

-- === Mail configuration (mail.meta) =========================================

function Mail.emptyConfig()
    return { schemaVersion = Mail.schemaVersion, enabled = false, relay = "", alias = "", isRelay = false, channel = 4244 }
end

function Mail.parseConfig(text)
    local config = Mail.emptyConfig()
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = splitFields(line)
            local tag = fields[1]
            if tag == "enabled" then config.enabled = fields[2] == "1"
            elseif tag == "relay" then config.relay = fields[2] or ""
            elseif tag == "alias" then config.alias = fields[2] or ""
            elseif tag == "isRelay" then config.isRelay = fields[2] == "1"
            elseif tag == "channel" then config.channel = tonumber(fields[2]) or 4244 end
        end
    end
    return config
end

function Mail.serializeConfig(config)
    config = config or Mail.emptyConfig()
    return table.concat({
        "# Qalcom mail config schema " .. tostring(Mail.schemaVersion),
        "schema|" .. tostring(Mail.schemaVersion),
        "enabled|" .. (config.enabled and "1" or "0"),
        "relay|" .. esc(config.relay or ""),
        "alias|" .. esc(config.alias or ""),
        "isRelay|" .. (config.isRelay and "1" or "0"),
        "channel|" .. tostring(math.floor(tonumber(config.channel) or 4244)),
    }, "\n") .. "\n"
end

-- === Netstring framing (binary-safe) ========================================
local function nsWrite(parts, value)
    value = tostring(value or "")
    parts[#parts + 1] = #value .. ":" .. value
end

local function nsRead(str, pos)
    local colon = str:find(":", pos, true)
    if not colon then return nil end
    local lenText = str:sub(pos, colon - 1)
    if lenText:match("^%d+$") == nil then return nil end
    local length = tonumber(lenText)
    local start = colon + 1
    local finish = start + length - 1
    if finish > #str then return nil end
    return str:sub(start, finish), finish + 1
end

-- Encode a message (with attachment bytes) into a single wire blob. Attachment
-- content is carried inline; each is tagged with its SHA-256 for verification.
function Mail.encodeMessage(message)
    local parts = {}
    nsWrite(parts, "MAILv1")
    nsWrite(parts, message.id or "")
    nsWrite(parts, message.from or "")
    nsWrite(parts, message.to or "")
    nsWrite(parts, message.subject or "")
    nsWrite(parts, tostring(message.at or 0))
    nsWrite(parts, message.body or "")
    local attachments = message.attachments or {}
    nsWrite(parts, tostring(#attachments))
    for _, attachment in ipairs(attachments) do
        local data = attachment.data or ""
        nsWrite(parts, attachment.name or "")
        nsWrite(parts, tostring(#data))
        nsWrite(parts, Mail.checksum(data) or "")
        nsWrite(parts, data)
    end
    return table.concat(parts)
end

-- Decode a wire blob into a message (metadata only, with attachment
-- name/size/sha256) plus a map of attachment name -> bytes. Verifies each
-- attachment checksum; returns nil + reason on any corruption.
function Mail.decodeMessage(blob)
    if type(blob) ~= "string" then return nil, "blob is not a string" end
    local pos = 1
    local function take() local v; v, pos = nsRead(blob, pos); return v end
    if take() ~= "MAILv1" then return nil, "not a Qalcom message" end
    local message = { attachments = {} }
    message.id = take(); message.from = take(); message.to = take()
    message.subject = take(); local at = take(); message.body = take()
    if message.body == nil or at == nil then return nil, "truncated message header" end
    message.at = tonumber(at) or 0
    local countText = take()
    local count = tonumber(countText)
    if not count then return nil, "bad attachment count" end
    local data = {}
    for index = 1, count do
        local name = take()
        local sizeText = take()
        local sum = take()
        local bytes = take()
        if bytes == nil then return nil, "truncated attachment #" .. index end
        if Mail.cryptoAvailable and Mail.checksum(bytes) ~= sum then
            return nil, "attachment checksum mismatch: " .. tostring(name)
        end
        message.attachments[index] = { name = name, size = #bytes, sha256 = sum }
        data[name] = bytes
    end
    return message, data
end

-- === Chunking ===============================================================

function Mail.split(blob, maxBytes)
    maxBytes = maxBytes or Mail.maxChunkBytes
    blob = tostring(blob or "")
    local parts = {}
    if #blob == 0 then return { "" } end
    local index = 1
    while index <= #blob do
        parts[#parts + 1] = blob:sub(index, index + maxBytes - 1)
        index = index + maxBytes
    end
    return parts
end

-- Reassemble a blob from a seq -> data map. Returns nil until every part
-- 1..total is present, so a dropped chunk simply defers completion and a
-- duplicate chunk is harmless (same key).
function Mail.joinParts(chunks, total)
    chunks = chunks or {}
    local count = total
    if not count then
        count = 0
        for seq in pairs(chunks) do if seq > count then count = seq end end
    end
    local ordered = {}
    for seq = 1, count do
        if chunks[seq] == nil then return nil end
        ordered[seq] = chunks[seq]
    end
    return table.concat(ordered)
end

-- === Attachment quarantine paths ============================================

function Mail.sanitizeName(name)
    name = tostring(name or "")
    name = name:gsub("[/\\]", "_"):gsub("%.%.", "_"):gsub("[^%w%._%-]", "_")
    if name == "" then name = "file" end
    return name:sub(1, 64)
end

-- Attachments are always written under a per-message quarantine directory and
-- are never executed by the mail system.
function Mail.attachmentPath(messageId, name)
    return Mail.attachmentRoot .. Mail.sanitizeName(messageId) .. "/" .. Mail.sanitizeName(name)
end

-- === Mailbox store (inbox / sent / outbox) ==================================

function Mail.newMailbox() return { schemaVersion = Mail.schemaVersion, messages = {} } end

-- record: { id, from, to, subject, body, at, unread, state, attachments={{name,size,sha256}} }
function Mail.addMessage(mailbox, record)
    mailbox.messages = mailbox.messages or {}
    -- Replace an existing record with the same id rather than duplicating.
    for index, existing in ipairs(mailbox.messages) do
        if existing.id == record.id then mailbox.messages[index] = record; return mailbox end
    end
    mailbox.messages[#mailbox.messages + 1] = record
    while #mailbox.messages > Mail.maxMailboxMessages do table.remove(mailbox.messages, 1) end
    return mailbox
end

function Mail.findMessage(mailbox, id)
    for _, record in ipairs(mailbox.messages or {}) do
        if record.id == id then return record end
    end
    return nil
end

function Mail.markRead(mailbox, id, read)
    local record = Mail.findMessage(mailbox, id)
    if record then record.unread = read == false and true or false end
    return record ~= nil
end

function Mail.setState(mailbox, id, state)
    local record = Mail.findMessage(mailbox, id)
    if record then record.state = state end
    return record ~= nil
end

function Mail.removeMessage(mailbox, id)
    for index, record in ipairs(mailbox.messages or {}) do
        if record.id == id then table.remove(mailbox.messages, index); return true end
    end
    return false
end

function Mail.serializeMailbox(mailbox)
    local lines = { "# Qalcom mailbox schema " .. tostring(Mail.schemaVersion) }
    for _, record in ipairs((mailbox and mailbox.messages) or {}) do
        lines[#lines + 1] = table.concat({
            "msg", esc(record.id), esc(record.from), esc(record.to),
            tostring(math.floor(tonumber(record.at) or 0)),
            record.unread and "1" or "0",
            esc(record.state or ""),
        }, "|")
        lines[#lines + 1] = "subj|" .. esc(record.id) .. "|" .. esc(record.subject or "")
        lines[#lines + 1] = "body|" .. esc(record.id) .. "|" .. esc(record.body or "")
        for _, attachment in ipairs(record.attachments or {}) do
            lines[#lines + 1] = table.concat({
                "att", esc(record.id), esc(attachment.name),
                tostring(math.floor(tonumber(attachment.size) or 0)),
                esc(attachment.sha256 or ""),
            }, "|")
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function Mail.parseMailbox(text)
    local mailbox = Mail.newMailbox()
    local index = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = splitFields(line)
            local tag = fields[1]
            if tag == "msg" and isNonEmptyString(fields[2]) then
                local record = {
                    id = fields[2], from = fields[3], to = fields[4],
                    at = tonumber(fields[5]) or 0,
                    unread = fields[6] == "1",
                    state = fields[7] ~= "" and fields[7] or nil,
                    subject = "", body = "", attachments = {},
                }
                mailbox.messages[#mailbox.messages + 1] = record
                index[record.id] = record
            elseif tag == "subj" and index[fields[2]] then
                index[fields[2]].subject = fields[3] or ""
            elseif tag == "body" and index[fields[2]] then
                index[fields[2]].body = fields[3] or ""
            elseif tag == "att" and index[fields[2]] then
                local record = index[fields[2]]
                record.attachments[#record.attachments + 1] = {
                    name = fields[3], size = tonumber(fields[4]) or 0, sha256 = fields[5],
                }
            end
        end
    end
    return mailbox
end

-- === Alias directory (relay-hosted) =========================================

function Mail.newDirectory() return { schemaVersion = Mail.schemaVersion, byAlias = {}, byNode = {} } end

-- Bind an alias to a node id. Rejects an alias already owned by a different node.
function Mail.registerAlias(directory, alias, nodeId)
    if not isNonEmptyString(alias) or not isNonEmptyString(nodeId) then return false, "alias and node id required" end
    local parsed = Mail.parseAddress(alias)
    if not parsed then return false, "invalid alias" end
    local existing = directory.byAlias[alias]
    if existing and existing ~= nodeId then return false, "alias already registered" end
    -- One alias per node: drop any previous alias this node held.
    local previous = directory.byNode[nodeId]
    if previous and previous ~= alias then directory.byAlias[previous] = nil end
    directory.byAlias[alias] = nodeId
    directory.byNode[nodeId] = alias
    return true
end

function Mail.lookup(directory, alias) return directory and directory.byAlias[alias] or nil end
function Mail.aliasFor(directory, nodeId) return directory and directory.byNode[nodeId] or nil end

function Mail.serializeDirectory(directory)
    local lines = { "# Qalcom mail directory schema " .. tostring(Mail.schemaVersion) }
    for _, alias in ipairs(sortedKeys(directory and directory.byAlias)) do
        lines[#lines + 1] = "map|" .. esc(alias) .. "|" .. esc(directory.byAlias[alias])
    end
    return table.concat(lines, "\n") .. "\n"
end

function Mail.parseDirectory(text)
    local directory = Mail.newDirectory()
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = splitFields(line)
            if fields[1] == "map" and isNonEmptyString(fields[2]) and isNonEmptyString(fields[3]) then
                directory.byAlias[fields[2]] = fields[3]
                directory.byNode[fields[3]] = fields[2]
            end
        end
    end
    return directory
end

-- === Relay spool ============================================================
-- spool.mailboxes[recipient].messages[msgId] = { from, to, at, total, bytes,
--   chunks = { [seq] = data } }

function Mail.newSpool() return { schemaVersion = Mail.schemaVersion, mailboxes = {} } end

local function mailboxFor(spool, recipient)
    spool.mailboxes = spool.mailboxes or {}
    spool.mailboxes[recipient] = spool.mailboxes[recipient] or { messages = {}, bytes = 0 }
    return spool.mailboxes[recipient]
end

local function messageComplete(message)
    if not message.total then return false end
    for seq = 1, message.total do if message.chunks[seq] == nil then return false end end
    return true
end

-- Deposit one chunk. Returns a status: "accepted" (stored, incomplete),
-- "complete" (final chunk arrived), "duplicate" (already had it), or "quota"
-- (mailbox full). `chunk` = { msgId, from, to, at, seq, total, data }.
function Mail.spoolDeposit(spool, recipient, chunk)
    if not isNonEmptyString(recipient) then return false, "recipient required" end
    if not chunk or not isNonEmptyString(chunk.msgId) then return false, "msgId required" end
    local seq, total = tonumber(chunk.seq), tonumber(chunk.total)
    if not seq or not total or seq < 1 or seq > total then return false, "bad chunk sequence" end
    local mailbox = mailboxFor(spool, recipient)
    local message = mailbox.messages[chunk.msgId]
    local data = tostring(chunk.data or "")

    if not message then
        if Mail.spoolCount(spool, recipient) >= Mail.maxSpoolMessages then return true, "quota" end
        if mailbox.bytes + #data > Mail.maxSpoolBytes then return true, "quota" end
        message = { from = chunk.from, to = chunk.to, at = tonumber(chunk.at) or 0, total = total, chunks = {}, bytes = 0 }
        mailbox.messages[chunk.msgId] = message
    end
    if message.chunks[seq] ~= nil then return true, "duplicate" end
    if mailbox.bytes + #data > Mail.maxSpoolBytes then
        if not messageComplete(message) then mailbox.messages[chunk.msgId] = nil end
        return true, "quota"
    end
    message.chunks[seq] = data
    message.bytes = message.bytes + #data
    mailbox.bytes = mailbox.bytes + #data
    return true, messageComplete(message) and "complete" or "accepted"
end

function Mail.spoolCount(spool, recipient)
    local mailbox = spool.mailboxes and spool.mailboxes[recipient]
    if not mailbox then return 0 end
    local count = 0
    for _ in pairs(mailbox.messages) do count = count + 1 end
    return count
end

-- Summaries of complete messages waiting for a recipient, oldest first.
function Mail.spoolReady(spool, recipient)
    local mailbox = spool.mailboxes and spool.mailboxes[recipient]
    local ready = {}
    if not mailbox then return ready end
    for _, id in ipairs(sortedKeys(mailbox.messages)) do
        local message = mailbox.messages[id]
        if messageComplete(message) then
            ready[#ready + 1] = { msgId = id, from = message.from, at = message.at, total = message.total, bytes = message.bytes }
        end
    end
    table.sort(ready, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.msgId < b.msgId end)
    return ready
end

-- The ordered chunk list for a complete message (for mail.fetch), or nil.
function Mail.spoolChunks(spool, recipient, msgId)
    local mailbox = spool.mailboxes and spool.mailboxes[recipient]
    local message = mailbox and mailbox.messages[msgId]
    if not message or not messageComplete(message) then return nil end
    local parts = {}
    for seq = 1, message.total do parts[seq] = message.chunks[seq] end
    return parts
end

function Mail.spoolAck(spool, recipient, msgId)
    local mailbox = spool.mailboxes and spool.mailboxes[recipient]
    local message = mailbox and mailbox.messages[msgId]
    if not message then return false end
    mailbox.bytes = math.max(0, mailbox.bytes - (message.bytes or 0))
    mailbox.messages[msgId] = nil
    return true
end

-- Drop messages older than ttl (based on the message timestamp). Returns the
-- number evicted.
function Mail.spoolEvict(spool, now, ttl)
    ttl = ttl or Mail.defaultTtl
    now = tonumber(now) or 0
    local evicted = 0
    for _, mailbox in pairs(spool.mailboxes or {}) do
        for id in pairs(mailbox.messages) do
            local message = mailbox.messages[id]
            if now - (tonumber(message.at) or 0) > ttl then
                mailbox.bytes = math.max(0, mailbox.bytes - (message.bytes or 0))
                mailbox.messages[id] = nil
                evicted = evicted + 1
            end
        end
    end
    return evicted
end

-- Persist the spool. Raw chunk bytes force netstring framing; the whole file is
-- one netstring stream so it is binary-safe.
function Mail.serializeSpool(spool)
    local parts = {}
    nsWrite(parts, "SPOOLv" .. tostring(Mail.schemaVersion))
    local recipients = sortedKeys(spool and spool.mailboxes)
    nsWrite(parts, tostring(#recipients))
    for _, recipient in ipairs(recipients) do
        local mailbox = spool.mailboxes[recipient]
        nsWrite(parts, recipient)
        local ids = sortedKeys(mailbox.messages)
        nsWrite(parts, tostring(#ids))
        for _, id in ipairs(ids) do
            local message = mailbox.messages[id]
            nsWrite(parts, id)
            nsWrite(parts, message.from or "")
            nsWrite(parts, message.to or "")
            nsWrite(parts, tostring(message.at or 0))
            nsWrite(parts, tostring(message.total or 0))
            local present = {}
            for seq = 1, (message.total or 0) do if message.chunks[seq] ~= nil then present[#present + 1] = seq end end
            nsWrite(parts, tostring(#present))
            for _, seq in ipairs(present) do
                nsWrite(parts, tostring(seq))
                nsWrite(parts, message.chunks[seq])
            end
        end
    end
    return table.concat(parts)
end

function Mail.parseSpool(text)
    local spool = Mail.newSpool()
    if type(text) ~= "string" or text == "" then return spool end
    local pos = 1
    local function take() local v; v, pos = nsRead(text, pos); return v end
    if take() ~= "SPOOLv" .. tostring(Mail.schemaVersion) then return spool end
    local recipientCount = tonumber(take() or "")
    if not recipientCount then return spool end
    for _ = 1, recipientCount do
        local recipient = take()
        local messageCount = tonumber(take() or "")
        if not recipient or not messageCount then return spool end
        local mailbox = mailboxFor(spool, recipient)
        for _ = 1, messageCount do
            local id = take()
            local from = take(); local to = take(); local at = take(); local total = take()
            local presentCount = tonumber(take() or "")
            if not id or not presentCount then return spool end
            local message = { from = from, to = to, at = tonumber(at) or 0, total = tonumber(total) or 0, chunks = {}, bytes = 0 }
            for _ = 1, presentCount do
                local seq = tonumber(take() or "")
                local data = take()
                if not seq or data == nil then return spool end
                message.chunks[seq] = data
                message.bytes = message.bytes + #data
            end
            mailbox.messages[id] = message
            mailbox.bytes = mailbox.bytes + message.bytes
        end
    end
    return spool
end

return Mail
