# Qalcom Mail — Relay-Server Design & Implementation Plan

**Target version:** `0.6.0` (Mail milestone)
**Depends on:** the existing networking pack — `network.lua` (secure transport), `protocol.lua`, `nodes.lua`, `crypto.lua`, and the `network_service` model. Mail is an additive pack, like the networking and war packs.

## What we're building

A store-and-forward email system for Qalcom computers. A computer composes a message (with optional file attachments), addressed to another computer, and hands it to a **relay** — a dedicated, always-loaded "post office" computer that holds mail until the recipient comes online and collects it. Recipients keep an inbox; senders keep a sent box and an outbox of undelivered mail. The relay also hosts the **address map**: the directory of who is reachable at what address.

This is the *relay* model (chosen over online-only direct delivery) precisely because ComputerCraft computers only run while their chunk is loaded. A recipient that is unloaded is unreachable, so a persistent relay is what makes delivery reliable and asynchronous — real email semantics rather than instant messaging.

## Why Qalcom is already most of the way there

The networking pack was built for exactly this shape of problem and even anticipates the extension. Concretely:

- **Authenticated, encrypted transport.** `Network.createSecureEnvelope` / `openSecureEnvelope` bind protocol, source, destination, kind, timestamp, counter, and nonce under HMAC-SHA256 + an encrypted stream, with replay windows (`markReplay`), age/skew checks, and per-node rate limiting (`Network.rateLimit`, 12 requests / 10 s). Mail reuses this verbatim.
- **A pairing directory = the address book.** `nodes.meta` already stores paired nodes with an ID, alias, shared secret (≥16 chars), role, and last-seen. That is the seed of the email map.
- **A background service pattern.** `network_service.lua` is a hidden `function(ctx)` that owns the modem, opens a channel, and dispatches inbound envelopes by `envelope.kind`. Mail adds an analogous service.
- **Kind-based dispatch with allowlists.** The transport already routes on `envelope.kind` and checks request names against `Network.readRequests` / `controlRequests`. The code notes control kinds "exist for future expansion." Mail is that expansion: a new kind plus a new allowlist.
- **HKDF for key separation.** `crypto.lua` exposes `Crypto.hkdf`, so mail can derive its own key from an existing pairing without re-pairing (see "Reusing pairings safely").

So the new work is additive and well-bounded: a pure mail-logic module, one new envelope kind, a mail service (client + relay halves), a Mail app, and the mailbox/attachment stores.

## Design decisions fixed for this version

- **Relay store-and-forward**, star topology: every client pairs with the relay; clients do not pair with each other. Within the `maxNodes = 32` pairing limit that is 31 mailboxes per relay (federation of multiple relays is future work).
- **Poll-based collection.** The relay never pushes; recipients poll it when online. Near-real-time while a recipient is running and polling, delayed otherwise — the correct model for unloaded computers.
- **Its own channel and transport state.** Mail runs on a dedicated channel pair (default `4244` / `4245`) with its own counter/replay state, so it never entangles with the telemetry service on `4242`.
- **Transport-encrypted to the relay (not end-to-end).** The relay decrypts to route and store, so it can read mail — exactly like a real mail server. End-to-end encryption between correspondents is noted as future hardening.
- **Attachments are quarantined data, never code.** Received files land under `/qalcom/mail/…`, are checksum-verified, and are never executed — reusing the Software Center's path-allowlist and SHA-256 approach.

## Addressing and the email map

An address is `alias@relay`, where `alias` is the mailbox name a node registered with the relay. Internally every mailbox is keyed by the node's stable ID; the alias is a friendly label. The relay owns the authoritative map (`nodeId ↔ alias`), because the star topology makes it the one computer everybody talks to.

- Clients discover addresses with a `mail.lookup` request to the relay (by alias or a full listing, subject to the relay's policy).
- A node claims its alias at pairing time or via a `mail.register` request; the relay rejects duplicates.
- The map is a bounded `mail.map` file on the relay following the existing `.meta` line format.

## Message format and chunking

The 12 KB envelope cap (`Network.maxPayloadBytes = 12000`) is the defining constraint. A mail message is therefore split into envelope-sized chunks and reassembled.

A logical message (before chunking):

```lua
{
  id = "<sender>-<counter>-<nonce8>",   -- globally unique message id
  from = "alice@relay",
  to = "bob@relay",
  subject = "...",
  body = "...",                          -- plain text
  at = 1712345678901,                    -- os.epoch("utc")
  attachments = {                        -- metadata only; bytes travel as chunks
    { name = "report.lua", size = 4096, sha256 = "<hex>", parts = 1 },
  },
}
```

The sender's mail service serializes the message + attachment bytes and splits the stream into parts that each fit an envelope with headroom for envelope overhead (target ≤ ~10.5 KB of payload per chunk):

```lua
{ request = "mail.deposit", msgId = "...", to = "bob", seq = 1, total = 3,
  requestId = "...", data = "<chunk bytes>" }
```

The relay stores chunks under the recipient's mailbox and only considers a message deliverable once all `total` chunks arrive (`seq` 1..total). The recipient polls, pulls the chunks, verifies each attachment's SHA-256 after reassembly, and writes the message to its inbox. Practical guidance: text mail is one or two chunks; a modest attachment is a handful; large files are slow over modems, so a per-message attachment cap (e.g. a few hundred KB) is enforced and surfaced in the UI.

## The relay (server half)

A computer becomes a relay by setting `mail.relay = true` in its mail config. The relay:

1. **Accepts deposits.** On a `mail.deposit` chunk from a paired node, validate (envelope auth, replay, rate limit, per-mailbox quota, TTL), then append the chunk to the recipient's spool. Respond with an ack once the full message is present.
2. **Serves polls.** On `mail.poll` from a node, return the list of complete messages queued for that node (headers first, then chunked bodies on `mail.fetch`), oldest first, bounded per response.
3. **Honors acks.** On `mail.ack` with delivered message IDs, delete them from the spool.
4. **Answers the directory.** `mail.register` / `mail.lookup` maintain and read `mail.map`.
5. **Enforces limits.** Per-mailbox message count and byte quota, per-message size cap, message TTL (spooled mail expires), and the transport's existing per-node rate limit. A full mailbox rejects new deposits with a clear outcome the sender records in its outbox.

Relay storage (bounded, `.meta`/log conventions):

- `/qalcom/data/mail.spool` — queued messages/chunks keyed by recipient (or a `mail/spool/<node>/` tree for larger volumes).
- `/qalcom/data/mail.map` — the alias ↔ nodeId directory.
- `/qalcom/data/mail.relay.audit` — deposits, polls, acks, rejections.

The relay must be kept chunkloaded in-game (a chunk-loader block, mod-dependent). That is the operational cost of the relay model and is called out for operators.

## The client (every computer)

The client half of the mail service:

- **Drains the outbox.** New mail is written to `/qalcom/data/mail.outbox` by the Mail app; the service chunks it and deposits to the relay, moving it to `mail.sent` on ack (or leaving it queued with a retry/backoff and a visible "undelivered" state).
- **Polls for inbox.** On a timer (and on demand), `mail.poll` the relay; fetch and reassemble complete messages; verify attachment checksums; write to `/qalcom/data/mail.inbox`; save attachment bytes under `/qalcom/mail/<msgId>/<name>`; then `mail.ack`.
- **Never blocks the desktop.** Like the store's fetch, all modem I/O is event-driven inside the service loop; the Mail app only ever touches local files.

Client storage:

- `/qalcom/data/mail.inbox`, `/qalcom/data/mail.sent`, `/qalcom/data/mail.outbox` — bounded mailbox stores (read/unread, timestamps, threading by `id`/`subject`).
- `/qalcom/mail/<msgId>/…` — quarantined attachment files (never executed).
- `/qalcom/data/mail.meta` — mail config (enabled, relay address, this node's alias, `mail.relay` flag, channel).
- `/qalcom/data/mail.state` — mail's own transmit counter and replay windows (separate from `network.state`).

## Transport extension

Minimal, mirroring the existing status/control split:

- Add an envelope kind `"mail_request"` and `Network.mailRequests = { ["mail.deposit"]=true, ["mail.poll"]=true, ["mail.fetch"]=true, ["mail.ack"]=true, ["mail.register"]=true, ["mail.lookup"]=true }`.
- Extend `Network.validateRequest(payload, kind)` to handle `kind == "mail_request"` against `mailRequests` (plus per-request field checks: `mail.deposit` needs `to`, `msgId`, `seq`, `total`, `data`).
- Reuse `Protocol.validateRequest` (request-ID dedupe, rate limit, replay) and `Protocol.response` unchanged.
- Everything else — envelopes, counters, replay, bounds, audit — is reused as-is.

### Reusing pairings safely

To let a node that is already paired (for telemetry) also do mail without re-pairing, derive a distinct mail key from the shared secret rather than reusing it directly:

```
mailSecret = Crypto.hkdf(nodeSecret, salt, "qalcom mail", 32)
```

This gives cryptographic separation between the telemetry channel and the mail channel from one pairing, so an envelope can never be replayed across purposes. Alternatively, mail can maintain entirely separate pairings; the HKDF route is preferred for one-time pairing UX.

## The Mail app (UI)

A new `qalcom/apps/mail.lua`, registered in the kernel like the Software Center, following the `Screen.app` pattern. Views:

- **Inbox** — list with unread markers, sender, subject, time; open to read.
- **Read** — headers, body, and an attachments row with a **Save** action (writes from the quarantine to a user-chosen folder via the managed filesystem).
- **Compose** — `To` (alias, with `mail.lookup` autocomplete), `Subject`, `Body`, and **Attach** (pick a file via the Explorer/file picker). Send writes to the outbox and returns.
- **Sent / Outbox** — sent history and pending/undelivered mail with retry state.
- **Relay admin** (only when `mail.relay = true`) — mailbox directory, spool sizes, quotas, and recent relay audit.

The app is pure UI over the local mailbox files; the service does all networking. This keeps the app testable and the transport in one place.

## Capabilities and roles

New capabilities in `capabilities.lua`, gated by role and blocked in Safe Mode like the other network capabilities:

- `mail.send` — compose and deposit mail;
- `mail.receive` — poll and read mail;
- `mail.relay` — operate a relay (accept/serve/spool).

Grant `mail.send`/`mail.receive` to the roles that already hold `network.receive` (Administrator, Commander, operations/engineer/observer as appropriate); restrict `mail.relay` to Administrator. The Mail app's manifest declares `fs.read`, `fs.write`, `mail.send`, `mail.receive` (and `mail.relay` when operating a relay). The mail service declares the network + mail capabilities it uses.

## File-by-file change list

**New files**

- `qalcom/lib/mail.lua` — pure mail core: message struct + validation, address parsing (`alias@relay`), mailbox store serialize/parse (inbox/sent/outbox), chunk/reassemble, attachment quarantine-path + checksum, relay spool management, quotas/TTL, directory (`mail.map`) helpers. Unit-tested in `tests/pure_test.lua`.
- `qalcom/apps/mail.lua` — the Mail app (compose/inbox/read/sent/outbox/relay-admin).
- `qalcom/apps/mail_service.lua` — hidden background service: client (outbox drain + poll loop) and relay (deposit/serve/ack/spool) halves, owning the mail channel.
- `MAIL.md` — operator/user guide (setting up a relay, pairing, addressing, limits, security).

**Edited files**

- `qalcom/lib/network.lua` — add the `mail_request` kind handling and `Network.mailRequests`; add mail channel defaults (`4244`/`4245`); optional `Network.maxMailBytes` chunk target.
- `qalcom/lib/capabilities.lua` — add `mail.send` / `mail.receive` / `mail.relay` names, descriptions, Safe-Mode blocks, and the `mail` + `mail_service` app manifests.
- `qalcom/lib/roles.lua` — grant the mail capabilities to the appropriate roles.
- `qalcom/kernel/init.lua` — register `mail` in `APP_PATHS` / `APP_META` / `APP_CATEGORIES` / launcher; start `mail_service` after login like `network_service`; expose the ctx helpers the mail service needs (modem transmit/open on the mail channel, mail-file persistence) mirroring the network-service helpers.
- `qalcom/apps/network.lua` (or a Mail settings view) — configure `mail.meta` (enable, relay address, alias, `mail.relay`).
- `install.lua` — add the mail files to the `NETWORK` pack (they depend on the transport), or a new optional `MAIL` pack.
- `tests/pure_test.lua` — mail-core cases (below).
- `qalcom/version.lua` — bump to `0.6.0`.

## Testing

Pure, `textutils`-free logic in `mail.lua` mirrors how `store.lua`/`network.lua` are tested under the bare-Lua harness:

- Address parse/format (`alias@relay`, invalid forms).
- Message serialize → chunk → reassemble round-trip, including a multi-chunk attachment and a dropped/duplicate chunk.
- Attachment checksum verify + tamper rejection (reuse `Crypto`).
- Mailbox store round-trip (inbox/sent/outbox), read/unread, bounded truncation.
- Relay spool: enqueue, per-mailbox quota + TTL eviction, poll ordering (oldest first), ack removal.
- Directory (`mail.map`) register/lookup, duplicate-alias rejection.
- `Network.validateRequest` accepts `mail_request` allowlisted names and rejects others, with field checks.

In-game validation is still required for the modem/channel/replay behaviour and the always-loaded relay, per `TESTING.md`.

## Milestones

1. **Pure mail core** (`lib/mail.lua`) + tests: messages, chunking, mailbox stores, spool, directory, checksums. No networking.
2. **Transport extension**: `mail_request` kind + `mailRequests` allowlist + field validation, with tests.
3. **Mail service**: client half (outbox drain, poll, inbox write, attachment quarantine) against a relay; HKDF key derivation; state/replay isolation on the mail channel.
4. **Relay half**: spool, quotas, TTL, directory, acks; `mail.relay` config.
5. **Mail app** + kernel registration + capabilities/roles + config UI.
6. **Docs + end-to-end**: `MAIL.md`, a two-node + relay in-game checklist, README updates.

## Flagged trade-offs and constraints

- **The relay must stay chunkloaded.** That is the whole point of the model, and the operational cost: the post-office computer needs a chunk loader (mod-dependent) to receive and hold mail while correspondents are away.
- **12 KB per envelope.** Attachments are chunked; large files are slow and bounded by a per-message cap. This is a hard transport limit, not a policy choice.
- **The relay can read mail** (transport-encrypted, not end-to-end). Fine for a trusted post office; end-to-end encryption between correspondents (double-encryption with a recipient key) is the future-hardening path.
- **Star topology, ≤ 31 mailboxes per relay** (the `maxNodes = 32` pairing limit, minus the relay). Multiple federated relays would scale further and are out of scope here.
- **Poll-based latency.** Delivery to an online, polling recipient is near-real-time; an offline recipient gets mail on its next poll. No delivery is possible while neither the relay nor recipient is loaded.
- **Modem choice.** An ender modem (unlimited range) is recommended for a base-wide post office; wireless modems impose range limits, wired modems require cabling.
- **Trust and abuse.** Only paired nodes can deposit, and the relay enforces quotas, TTL, and rate limits — so spam is naturally bounded by the pairing model. An open (unpaired) address map would be friendlier but would need separate anti-abuse work.
