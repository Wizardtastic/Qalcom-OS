# Qalcom OS Roadmap

Qalcom OS is a Windows-inspired ComputerCraft: Tweaked command-and-control environment for a modded Minecraft war server. The server uses **Aeronautics** for vehicles and airships, **Create: Big Cannons (CBC)** for artillery, and **Create: Propulsion** for propulsion and mechanical systems. Qalcom provides the in-world terminals, permissions, telemetry, logistics views, and carefully allowlisted controls needed to operate those systems; it does not replace the CC:T host, the installed mods, or their normal game mechanics.

The roadmap is intentionally incremental. Each milestone should deliver one coherent capability, remain usable on its own, and be validated on an actual CC:T computer in the target modpack before the next milestone begins. Mod integrations must be defensive and observable by default: Qalcom should never invent mod APIs, bypass server protections, or expose unrestricted remote Lua or arbitrary peripheral calls.

## War-server product goals

- Give commanders a reliable picture of radar contacts, vehicles, artillery, propulsion infrastructure, supplies, power, territory, and alerts.
- Turn radar detections into understandable contact tracks without making radar an automatic weapons authority.
- Separate strategic visibility from high-impact controls such as firing, launching, movement, lockdowns, and demolition.
- Make every sensitive action role-gated, explicitly confirmed, rate-limited, and auditable.
- Treat Aeronautics, CBC, and Create: Propulsion as optional integrations discovered at runtime, with graceful degradation when a mod, block, peripheral, or addon is absent.
- Keep the system useful during a conflict: stale data, damaged links, missing peripherals, and server restarts must be visible rather than silently treated as healthy.

## Target modpack assumptions

- **Aeronautics:** vehicle and airship state, assemblies, controls, docking, navigation, and flight-related telemetry where exposed through supported peripherals or server-side bridges.
- **CBC / Create: Big Cannons:** cannon inventory, loading and readiness state, ammunition logistics, targeting metadata, and firing controls only where the server explicitly exposes a safe, allowlisted interface.
- **Create: Propulsion:** propulsion assemblies, engines, fuel or energy status, mechanical readiness, and transport/logistics telemetry where available.
- **Create Radar:** radar blocks, scans, contacts, range/status, and detection events where exposed through CC:T or a supported peripheral bridge.
- **Create Aero Radar:** the Aeronautics-oriented radar integration for aerial/physics-vehicle detection and radar-assisted tracking where its server-side interface exposes those capabilities.
- **Supporting vehicle and combat systems:** Create Aeronautics/Aeroworks, Sable and CC:Sable, Create Submarine, Drive-By-Wire, CBC Compact Mount, CBC Military Supplement, TACZ with aero compatibility, and RHA armor/projectile mods.
- **Supporting server operations:** FTB Teams, FTB Chunks, FTB Essentials, FTB Quests, Warring Nations, Region Guard, Xaero's maps, Simple Voice Chat, admin tickets, and player-revive/medical systems.
- **Supporting industrial/logistics systems:** Create Diesel Generators, Create Nuclear, Create Railways/Railways, Create Threaded Trains, Create Tweaked Controllers, Create Addition, Storage Drawers, Sophisticated Backpacks, and Create-linked storage/transport blocks.
- The exact peripheral names, methods, block entities, and addon APIs are server-specific. Integration work must use an adapter layer and capability discovery instead of hard-coded assumptions throughout the desktop. Verified CC:CBC references: [CC:CBC API README](https://github.com/Drakon7009/CC-CBC/blob/main/README.md) and [CC:CBC developer integration contract](https://github.com/Drakon7009/CC-CBC/blob/main/DEVELOPER_INTEGRATION.md).

## Integration boundary

Qalcom is an operations layer, not a replacement for the mods' physics, permissions, radar rules, or combat rules. A mod adapter may read state or request a narrowly defined action, but the server and the mod remain authoritative. Every adapter must report its availability, API version, supported operations, stale-data state, and failure reason. Radar contacts are observations, not proof of hostile intent, ownership, or a valid firing solution. No milestone may depend on arbitrary `peripheral.call`, remote Lua execution, or an undocumented command path.

## Confirmed modpack integration profile

The target instance is Minecraft 1.21.1 on NeoForge and includes the following Qalcom-relevant integration points. This inventory is the planning baseline, not proof that a mod exposes a ComputerCraft peripheral, compatible API, or the capabilities suggested by its name. The actual peripheral names, exposed methods, permissions, and cross-mod behavior must be inspected in-game before implementation; each item below is a verification target unless explicitly marked otherwise.

- **Computer and bridge layer:** CC:Tweaked 1.120.0, CC:CBC, CC:Sable, CC:Graphics, and KubeJS. Verify which peripheral types and read-only methods are actually exposed. These may make programmable consoles and server-specific bridge scripts possible, but do not make arbitrary Lua or KubeJS execution an acceptable Qalcom feature.
- **Vehicles and movement:** Create Aeronautics bundled 1.3.0, Aeroworks, Sable, Create Propulsion 1.1.5, Drive-By-Wire, Create Submarine, Create Aeronautics transmission/linkage and sail addons, and Sable hose connectors.
- **Artillery and weapons:** Create Big Cannons 5.11.7, CBC Military Supplement, CBC Compact Mount, TACZ, TACZ Aero Compat, TACZ C, TACZ Armor, RHA/RHA Plus, and the projectile library.
- **Detection and mapping:** Create Radar 0.4.9.4, Create Aero Radar 0.1.1, Xaero's Minimap/World Map, and FTB Xaero compatibility. Radar is a first-class candidate Qalcom sensor source; verify whether it can expose scans, contacts, tracks, alerts, or map coordinates, then prioritize read-only contacts and map overlays before any control workflow is considered.
- **Factions and territory:** Warring Nations, FTB Teams, FTB Chunks, Region Guard, Team RTP, FTB Quests, and FTB Essentials. These should inform identity, faction/territory context, protected-zone rules, and operator workflows without allowing Qalcom to bypass server ownership or claims.
- **Industry and logistics:** Create 6.0.10, Create Addition, Create Diesel Generators, Create Nuclear, Create Railways, Create Threaded Trains, Create Tweaked Controllers, Create Cobblestone, Create BB, Storage Drawers, Sophisticated Backpacks, and related Create transport addons. Verify which devices can provide telemetry; treat power, fuel, manufacturing, ammunition, and supply-route views as planned integration targets rather than guaranteed APIs.
- **Field operations:** Simple Voice Chat, Create-linked communications/controls, First Aid, player revive, admin tickets, and other support systems. Qalcom may link incidents to communications and recovery workflows, but must not impersonate players or silently alter medical/admin state.

The profile intentionally separates direct integrations from libraries, performance mods, and decorative content. Version-specific behavior must be recorded by the adapter health view rather than assumed from a jar filename. The first implementation task for each integration is an in-game capability probe and compatibility record, not a hard-coded control path.

## Release policy

- Increment `/qalcom/version.lua` after every major milestone.
- Keep user-facing version text sourced from that file.
- Keep each release narrowly scoped; defer cross-cutting features until their foundations are stable.
- Keep all remote control allowlisted and authenticated.
- Never expose arbitrary remote Lua execution as a default feature.
- Preserve a recovery path to CraftOS at every stage.
- Validate every release on an actual CC:T computer because the project has no local CC:T runtime.
- Do not describe CC:T Lua process isolation as a secure sandbox.

## Completed: 0.1.2 — Login and sessions

- First-run local administrator setup
- Username/password login screen
- Password masking and confirmation
- Local account persistence at `/qalcom/data/accounts`
- Lightweight password digest with documented non-cryptographic limitations
- Login attempt delay
- Session identity on the desktop
- Account application and logout flow
- Malformed account record filtering
- Compact login layout for smaller supported terminals

## Completed: 0.1.3 — Everyday usability

- Reliable title-bar dragging and z-order handling
- Minimize, restore, close, Alt+Tab, and Alt+F4 controls
- Start launcher with keyboard navigation
- Terminal cursor editing, history, completion, and filesystem commands
- Explorer browsing, folders, copy/paste, and confirmed deletion
- Text viewer/editor with Ctrl+S
- Reusable confirmation dialogs and notifications

## Completed: 0.1.4 — Stability and system polish

- Clear process states and in-window crash screens
- Control Center restart action for failed processes
- Service metadata and expanded system information
- Process age, event count, last-event age, and restart diagnostics
- Defensive peripheral and memory reporting compatible with CC:T

## Completed: 0.1.5 — Recovery and session stability

- Session-generation IDs and stale event rejection
- Context helpers for session validity and app-scoped logs
- System Log application with scrolling and refresh
- Recovery application with notification clearing, theme reset, and log access
- Recovery and System Log launcher entries

## Completed: 0.1.6 — Supervision and settings polish

- Watchdog visibility for slow application event handlers
- Diagnostic-only watchdog behavior; no automatic task termination
- Service/application labels retained in Control Center
- Configurable log retention between 50 and 1000 lines
- System Log filters for all, failure, and login entries
- Safe Mode setting that limits the launcher to recovery tools
- Safe Mode toggle in Recovery and Settings
- Categorized Settings overview
- Theme reset and safe troubleshooting workflow

## Completed: 0.1.7 — Test and documentation foundation

**Goal:** Make future changes safer without adding new operational powers.

- Added a small offline-friendly test harness for pure Lua helpers.
- Added pure checks for account record validation, path normalization, settings clamping, log retention, and window geometry.
- Added manual CC:T test checklists for login, logout, Safe Mode, app crashes, resizing, and recovery.
- Documented installation validation, migration expectations, and recovery to CraftOS.
- Added a release checklist requiring version, README, roadmap, and in-game validation updates.

**Exit criteria met:** Core pure logic now has repeatable helper checks and a fresh installation can be validated from the documentation. Application lifecycle behavior still requires the manual CC:T checklist; the offline tests are not a replacement for in-game validation.

## Completed: 0.1.8 — Configuration and migration stability

**Goal:** Make persistent settings safe to evolve.

- Added a configuration schema/version marker.
- Added defaults and migration handling for missing and legacy setting names.
- Added Settings and Recovery actions to restore Qalcom defaults without deleting user accounts.
- Validated and clamped persisted values before applying them.
- Recorded migrations and configuration changes in the system log.
- Improved compact Settings navigation and separated editable controls from informational categories.

**Exit criteria met:** Older settings load safely, invalid values fall back to defaults, and resetting configuration preserves account data.

## Completed: 0.1.9 — Desktop lifecycle hardening

**Goal:** Finish the local desktop foundation before introducing permissions.

- Added explicit task cleanup for crashed, stopped, minimized, and session-invalid applications.
- Added bounded manual restart attempts and restart-lock diagnostics.
- Reduced repeated log-file rewrites by appending and pruning only after growth thresholds.
- Added confirmation handling for terminal reboot and shutdown requests.
- Added a scrollable Diagnostics application for boot stages, PIDs, crash reasons, and restart counts.
- Hardened compact recovery/settings behavior for supported terminal sizes.

**Exit criteria met:** Task cleanup, bounded recovery, power confirmation, diagnostics, and log maintenance are implemented; full repeated-cycle validation remains part of the manual CC:T checklist.

## Implemented — validation pending: 0.1.10 — Native UI foundation

**Goal:** Improve the desktop presentation without adding external dependencies or changing Qalcom's kernel ownership boundaries.

- Added a backward-compatible native UI layer with semantic colors, reusable cards, headers, title bars, status badges, and safe clipping.
- Added lightweight character-cell shadows and desktop/taskbar composition helpers.
- Added a Qalcom-owned animation manager with bounded easing functions, cancellable transitions, and a reduced-motion setting.
- Added schema migration for the reduced-motion preference while preserving accounts and existing settings.
- Applied the new visual primitives to the desktop shell, centered taskbar, floating Start menu, windows, dialogs, and notification slide-in behavior.
- Added shared screen scaffolding and migrated login, Settings, Recovery, Control Center, Diagnostics, Monitor, System Log, Explorer, Terminal, Account, and Editor to the common visual language.

**Implementation status:** The native foundation loads without external dependencies, existing input behavior remains compatible, and animation is driven by the kernel's timer loop rather than a second event loop. The manual CC:T checklist remains required before this milestone is considered fully validated, especially for compact terminals, resize behavior, and performance.

**Not in scope:** Dirty-region optimization, third-party UI libraries, capability enforcement, or changing the process/event architecture. Further visual polish and specialized widgets can continue in later 0.1.x patches.

## Implemented — validation pending: 0.2.0 — Capability vocabulary and trusted app manifests

**Goal:** Define permissions before third-party apps or remote operations exist.

- Added a versioned capability catalog and trusted built-in application manifests.
- Added a read-only Capabilities inspector reachable from Start.
- Added capability metadata and inspection helpers to application contexts.
- Added bounded capability audit logging for launches, logins, denials, and inspections.
- Kept the policy explicitly advisory because trusted CC:T Lua is not sandboxed.

- Completed in 0.2.2: capability-aware service boundaries and managed enforcement for filesystem, peripheral, redstone, and system actions used by Qalcom-managed paths.
- Deferred to 0.2.3+: peripheral inventory and safe device inspection.

**Implementation status:** Every built-in app has a documented capability profile and the OS can display declared capabilities without changing existing app behavior. The audit stream is bounded and the capability layer does not claim to sandbox trusted Lua. Role approvals begin in 0.2.1, and 0.2.2 adds the first managed service boundary for built-in applications.

**Exit criteria:** Every built-in app has a documented capability profile and the OS can display declared capabilities without breaking existing apps. Manual CC:T validation remains required before this milestone is considered fully validated.

## Implemented — validation pending: 0.2.1 — War-server roles and approval policy

**Goal:** Separate player identity from permission decisions for a conflict-oriented server.

- Added local roles: Administrator, Commander, Operations officer, Artillery officer, Engineer, Logistics officer, Observer, Automation service, and Restricted guest.
- Added role persistence and migration for existing administrator accounts; an account with no legacy role maps to Administrator only for the first account, later role-less accounts map to Observer, and malformed explicit roles fall back to Observer.
- Added a policy table intersecting role permissions with declared built-in capabilities.
- Added explicit approval dialogs for the existing reboot/shutdown sensitive actions and Administrator-only role changes.
- Added audited role administration with protection against removing the last Administrator.
- Kept account management local and documented its non-cryptographic limitations.

**Implementation status:** Active accounts carry a versioned role, the Account/Settings/Capabilities/Control Center views expose it, Administrator accounts can manage roles through an explicit confirmation flow, and managed power requests are role-checked before confirmation. The last Administrator cannot be removed. Only these existing managed paths are enforced in this milestone; filesystem, peripheral, redstone, and network enforcement is deferred to 0.2.2. The policy remains advisory for trusted Lua and does not sandbox CC:T globals.

**Deferred:** Mod-device inventory, redstone control UI, and broader multi-user administration remain in 0.2.3+. Role changes are exposed only through the Administrator-gated, audited Account workflow.

**Exit criteria:** A user’s role can be inspected, sensitive built-in actions can be approved or denied, and all decisions are logged. Manual CC:T validation remains required before this milestone is considered fully validated.

## Implemented — validation pending: 0.2.2 — Capability-aware application context

**Goal:** Connect the policy model to Qalcom’s app lifecycle without pretending to sandbox globals.

- Pass approved capabilities through application contexts, including Safe Mode-aware decisions.
- Added reusable checks in `/qalcom/lib/managed.lua` for Qalcom-managed filesystem, peripheral, redstone, label, and power actions.
- Migrated Terminal, Explorer, Editor, Logs, Settings, Monitor, Control Center, and Capabilities to use managed helpers where practical.
- Show useful denial messages and notifications instead of silently failing; denials are bounded-audit entries.
- Added a Safe Mode policy that disables sensitive managed writes, controls, label changes, and power actions while preserving permitted read-only inspection.
- Documented that trusted Lua code still has normal CC:T global access until a stronger boundary exists.

**Implementation status:** The kernel now exposes approved capability metadata and managed context methods. Built-in applications route their Qalcom-controlled filesystem, peripheral, label, and power operations through those methods. Safe Mode is enforced by the shared policy decision layer, and denied managed operations notify the operator and write an audit entry. Redstone wrappers are available through the managed Infrastructure Controls app; output writes remain allowlisted, role-gated, explicitly confirmed where configured, and audited. Core settings/account persistence remains a kernel/recovery service path rather than an app-controlled filesystem operation; it is not presented as third-party capability enforcement.

**Exit criteria:** New Qalcom-managed features consistently check capabilities, and denied actions are visible in the UI and audit log. Manual CC:T validation remains required before this milestone is considered fully validated.

**Deferred:** Peripheral inventory applications, mod-device adapters, redstone control UI, and stronger process/security isolation remain future work. Trusted built-in Lua still has normal CC:T globals; this is not a secure sandbox.

## Implemented — validation pending: 0.2.3 — Peripheral and mod-device inventory

**Goal:** Read and understand local devices before controlling war-server systems.

- Add a Peripheral Manager application.
- Discover attached peripherals defensively and refresh on attach/detach events.
- Display type, side/name, available methods, and basic status where safe.
- Identify Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar devices through capability discovery rather than fixed names.
- Define a versioned adapter contract for availability, API compatibility, supported read operations, stale-data state, and failure reporting.
- Normalize radar scans into bounded contact records with source, timestamp, position/heading when available, confidence, age, and unknown/ambiguous identity.
- Add user-defined aliases for vehicles, cannons, propulsion systems, radars, depots, and sensors.
- Add persistent blocklists and trusted-device markers.
- Keep inspection read-only in this milestone.

**Implementation status:** The Peripheral Manager performs defensive attach/detach-aware discovery, uses allowlisted read-only managed calls, reports a versioned adapter contract and degraded state, normalizes bounded radar contacts, and persists aliases, blocklists, and trusted markers. It never exposes device control commands. Manual CC:T validation remains required.

**Exit criteria:** Operators can identify local mod devices and their status without issuing control commands, each discovered integration reports a compatible adapter contract and health state, radar contacts are safely normalized without claiming certainty, and an absent integration does not prevent Qalcom from booting.

## Implemented — validation pending: 0.2.4 — Local base and infrastructure controls

**Goal:** Add narrowly scoped manual control for local bases and support systems before controlling vehicles or artillery.

- Add named redstone inputs and outputs for doors, alarms, lights, pumps, loaders, and other server-approved infrastructure.
- Add explicit on/off controls with confirmation for important outputs.
- Add timed pulses with bounded durations.
- Add an emergency all-off or safe-state action for Qalcom-managed infrastructure.
- Log every control action with user, device, value, and timestamp.
- Respect device blocklists, war-server zones, and role capabilities.
- Do not add firing, launch, propulsion, or movement controls in this milestone.

**Implementation status:** Infrastructure Controls now provides versioned named redstone profiles, read-only live state, confirmed output toggles, globally and per-profile bounded pulses, emergency safe-state, audit entries, blocklist checks, role/capability checks, and graceful offline behavior. It does not issue peripheral, vehicle, artillery, propulsion, or network commands. Manual CC:T validation remains required.

**Exit criteria:** Manual infrastructure controls are allowlisted, reversible where possible, auditable, and safe when a peripheral disappears.

## Implemented — validation pending: 0.2.5 — Local jobs and structured automation

**Goal:** Automate local actions without executing arbitrary Lua strings.

- Added a local kernel-launched job service and an Automation Jobs application.
- Supports structured manual, timer, and redstone-input triggers; peripheral/radar triggers remain deferred.
- Added bounded retry limits, cooldowns, validated timeout fields, and persisted execution history.
- Added pause, resume, disable, and emergency-stop controls.
- Added jobs.manage plus infrastructure capability intersection checks and Safe Mode blocking.
- Stores actions as validated data structures rather than arbitrary code.

**Implementation status:** Jobs are persisted in `/qalcom/data/jobs.meta` with bounded `/qalcom/data/jobs.history`; the hidden service continues scheduling after the UI closes, validates side transitions, applies cooldowns/retries, and fails closed on unavailable infrastructure. Manual CC:T validation remains required.

**Exit criteria:** A small automation job can be created, observed, stopped, and recovered without unrestricted script execution.

## Implemented — validation pending: 0.2.6 — Automation observability and recovery

**Goal:** Make local automation dependable before networking it.

- Added job status summaries to Control Center.
- Added bounded structured runtime status in `/qalcom/data/jobs.status`, including failure reasons and retry state.
- Added bounded exponential retry/backoff scheduling so retries do not block the desktop event loop.
- Added blocked fallback behavior when a target infrastructure profile disappears or becomes unavailable.
- Added validated import/export through `/qalcom/data/jobs.export`.
- Added Recovery tooling to pause all persisted automation jobs and reload the hidden service.

**Implementation status:** Local jobs now expose live runtime state, bounded retry timing, explicit target-unavailable failures, validated definition transfer, and a recovery stop path. Manual CC:T validation remains required.

**Exit criteria:** Failed jobs are diagnosable, bounded, and recoverable from the desktop or CraftOS recovery path.

## Implemented — validation pending: 0.3.0 — Network and modem foundation for the war server

**Goal:** Discover network hardware without accepting remote commands yet.

**Implementation status:** Network Manager and the `/qalcom/lib/network.lua` protocol module now discover modem peripherals, persist validated local configuration and enrolled-node records, define versioned compatibility envelopes with expiry/future-skew checks and replay rejection, bound payloads, and allowlist read/control request names for future milestones. The initial compatibility checksum has been superseded by pure-Lua HMAC-SHA256 authenticated encryption, persistent counters, replay protection, request rate limits, and authenticated associated data. Transport remains explicit opt-in and cannot prevent RF/game-level jamming. Operations Telemetry adds a read-only adapter-backed view over discovered Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar candidates. Mod APIs remain runtime-discovered and uncertain until verified in the target instance.

- Added a Network Manager application.
- Discover modems and expose side/type/status information.
- Added channel and protocol configuration with validation.
- Defined a Qalcom node identity and protocol version.
- Added local-only network configuration/inventory diagnostics and bounded protocol helpers; modem channel opening and traffic counters remain deferred until authenticated transport is designed.
- Kept remote control disabled by default.
- Added read-only normalized telemetry for mod candidates; no firing, movement, propulsion, or radar-guided action.

**Exit criteria:** Network hardware can be configured and observed locally, but no remote request can change the computer. Manual CC:T validation remains required.

## Partially implemented — validation pending: 0.3.1 — Pairing and node enrollment

**Goal:** Establish explicit trust between Qalcom computers.

- Trusted node enrollment is available through validated local node records; a user-mediated pairing-code exchange is still required before an unauthenticated node can be trusted.
- Store node records with names, identities, roles, and capabilities.
- Add approve, revoke, block, and quarantine actions.
- Log enrollment and trust changes.
- Reject unknown nodes before command handling.

**Exit criteria:** Two Qalcom nodes can be paired, inspected, revoked, and safely re-paired without implicit trust.

## Implemented — validation pending: 0.3.2 — Authenticated read-only operations

**Goal:** Begin remote operations with status queries only.

- Implement pure-Lua SHA-256/HMAC-SHA256 authenticated encrypted envelopes with HKDF-derived keys and associated-data authentication.
- Add request IDs, timestamps/expiry, nonces, and replay rejection.
- Permit only a small allowlist of read-only status requests.
- Add response size and rate limits.
- Add a network audit view for accepted and rejected requests.

**Exit criteria:** Remote status requests are authenticated, bounded, auditable, and cannot execute arbitrary Lua or change device state.

## Partially implemented — validation pending: 0.3.3 — Authenticated control operations

**Goal:** Expand remote access only to explicitly approved actions.

- Implement allowlisted infrastructure safe-state and structured job-pause requests; high-impact device, vehicle, propulsion, cannon, and weapon commands remain unavailable.
- Require node and user capabilities for every command.
- Require confirmation for high-impact actions.
- Add idempotency handling and clear failure responses.
- Add per-node rate limits, quarantine, and emergency network disable.
- Never expose unrestricted `shell.run`, `os.run`, `peripheral.call`, or remote Lua execution.

**Exit criteria:** Every remote command is typed, validated, authorized, logged, and safely rejected when malformed or unauthorized.

## Implemented — validation pending: 0.3.4 — Network operations console

**Goal:** Make authenticated operations manageable from one desktop.

- Add Network Operations node list, trust state, modem status, cipher status, and bounded audit history.
- Add request history with filtering and correlation by request ID.
- Add operator acknowledgement for alerts.
- Add network Safe Mode and local emergency disconnect.
- Add recovery documentation for lost pairing or compromised nodes.

**Exit criteria:** Operators can understand and control the trust boundary without relying on raw terminal commands.

## Partially implemented — validation pending: 0.4.0 — Modded war-server telemetry foundation

**Goal:** Build a read-only command center for the target modpack before adding combat or movement actions.

- Add adapter-backed read-only telemetry records for Aeronautics vehicles and airships, CBC artillery, Create: Propulsion systems, radar, and Aero Radar candidates.
- Add configurable panels for radar status, scan coverage, contact tracks, vehicle identity, assembly health, docking, power, fuel, propulsion readiness, cannon readiness, ammunition, loaders, depots, alarms, and base infrastructure where supported.
- Add radar contact age, confidence, source identity, position uncertainty, scan coverage gaps, and correlation history alongside timestamps, stale-data indicators, mod/integration version, and adapter failure reasons.
- Add map-oriented overlays and bounded historical incident/combat-event timelines, while respecting faction and protected-zone visibility rules.
- Keep all mod panels and controls read-only.

**Exit criteria:** The command center clearly distinguishes current, stale, missing, damaged, unavailable, and untrusted telemetry for every supported integration, and radar displays never present an unverified contact as a confirmed hostile target.

## Partially implemented — validation pending: 0.4.1 — Fleet, artillery, and logistics views

**Goal:** Organize war-server assets and supply chains without issuing movement, firing, or propulsion commands.

- Add bounded radar-derived contact records with explicit unknown/friendly/claimed/unverified states and uncertainty-preserving telemetry views.
- Add Aeronautics fleet inventory, crew/seat status where available, vehicle health, docking, and named-location views.
- CC:CBC read-only cannon-mount telemetry is implemented for standard `cannon_mount` and compact `compact_cannon_mount` peripherals through the verified `getInfo()` method: assembly, current/target yaw and pitch, shaft speeds, and mount position are normalized. `getInfo()` does not expose ammunition, propellant, barrel temperature, or firing readiness, so those remain unknown until a separate verified read-only bridge exists.
- Add CBC cannon inventory, loading state, barrel/readiness state, ammunition stock, and maintenance warnings where a server-approved bridge exposes them; do not infer these fields from CC:CBC `getInfo()`.
- Added a dedicated local CBC Fire Control app. It supports multi-mount selection, world-coordinate targets, radar-contact targets with positions, per-mount yaw/pitch planning, explicit aim confirmation, explicit fire confirmation, alignment/assembly checks, bounded fire pulses, cooldowns, stop controls, and audit records. It does not autonomously select targets or fire.
- Add Create: Propulsion engine, fuel/energy, assembly, route, and mechanical readiness panels where exposed.
- Add Create Diesel Generators and Create Nuclear power/fuel/heat telemetry where safely exposed.
- Add Create Railways, trains, depots, and supply-route status where exposed.
- Add logistics and storage status for ammunition, fuel, components, and repair supplies.
- Add power, fuel, ammunition, communication, radar coverage, and sensor-health warnings.
- Add asset grouping, faction/base/protected-zone filters, and operator-defined routes and locations.

**Exit criteria:** Operators can locate and assess vehicles, artillery, propulsion systems, and supplies without unsafe automatic action.

## Partially implemented — validation pending: 0.4.2 — Manual defensive and infrastructure response

**Goal:** Add carefully confirmed response actions while keeping combat actions behind a separate approval boundary.

- Reuse the existing local infrastructure controls and expose only authenticated safe-state/job-pause requests; incident playbooks are preview-only until each action has a dedicated confirmation path.
- Add safe-state or emergency-stop actions for Qalcom-managed propulsion and base systems where supported.
- Add operator-confirmed radar mute, scan pause, or sensor-isolation actions only where the mod exposes a safe, reversible interface.
- Keep radar-guided targeting, CBC firing, TACZ actions, and Aeronautics movement/flight commands disabled by default until their dedicated approval and safety model is complete.
- Require role permission and explicit confirmation for every high-impact action.
- Add all-off, unlock, and recovery actions where safe and supported.
- Record operator, target, old state, new state, request ID, and result.
- Add response cooldowns, duplicate-command protection, and zone restrictions.

**Exit criteria:** Defensive and infrastructure actions are explicit, auditable, reversible where possible, and unavailable to unauthorized roles.

## Partially implemented — validation pending: 0.4.3 — Incident response and combat-system safety

**Goal:** Coordinate war-server incidents without creating an uncontrolled autonomous combat system.

- Add bounded incident records with severity, faction/base/asset source, timeline, and acknowledgement state.
- Add structured, allowlisted alarm/lockdown/evacuation playbook dry-run previews; execution remains operator-mediated and no combat action is autonomous.
- Add dry-run previews before any future playbook execution.
- Add adapter health monitoring and a clear degraded-mode experience when Aeronautics, CBC, Create: Propulsion, Create Radar, or Create Aero Radar is unavailable.
- Correlate radar contacts with faction, territory, vehicle, and incident records without treating correlation as identification or authorization.
- Add automation failure safe mode and a global emergency stop.
- Require operator acknowledgement for destructive, combat-related, or world-changing actions.
- Defer any radar-guided targeting, CBC firing, TACZ control, Aeronautics flight/movement, or Create: Propulsion actuation to a later milestone with server-specific rules, two-person approval where appropriate, and a dedicated manual CC:T test plan.

**Exit criteria:** Incidents can be acknowledged, investigated, and resolved with bounded playbooks, clear emergency escape paths, and no accidental autonomous combat behavior.

## Partially implemented — validation pending: 0.4.6 — CBC Fire Control

**Goal:** Permit explicitly authorized operators to aim and fire selected CBC mounts without creating autonomous or unrestricted remote weapons control.

- Use the verified CC:CBC `setComputerControl`, `setTargetAngles`, and level-triggered `fire(boolean)` methods only through the dedicated app.
- Support one or more selected `cannon_mount` or `compact_cannon_mount` peripherals.
- Accept explicit world coordinates or a normalized radar contact that includes a position.
- Calculate independent geometric line-of-sight yaw/pitch per mount from its `getInfo()` position, with configurable yaw offset and pitch sign for the server’s mount orientation; ballistic solutions remain out of scope until projectile/ammunition data is verified.
- Require verified mount telemetry, explicit aim confirmation, explicit fire confirmation, assembly and angular-alignment checks, bounded fire pulses, cooldowns, stop controls, and audit records.
- Never fire merely because a radar contact exists. Radar contacts remain observations and require operator selection and confirmation.
- Keep ammunition, propellant, barrel condition, and true ballistic readiness unknown unless a separate server-approved read-only bridge exposes them.

**Validation status:** Source-level implementation is complete; target CC:T/modpack validation is required before use. Test angle conventions with inert mounts and a non-loaded range before enabling any live firing. The current planner is geometric line-of-sight only, not a ballistic solver.

## Partially implemented — validation pending: 0.4.5 — Verified CC:CBC cannon-mount telemetry

**Goal:** Use the documented CC:CBC peripheral safely to improve artillery visibility without enabling combat control.

- Verified the CC:CBC `cannon_mount` API and the compact-mount addon’s `compact_cannon_mount` API.
- Added runtime discovery and a strict `getInfo()` probe for read-only cannon telemetry.
- Normalized assembly state, current/target yaw and pitch, shaft speeds, and mount position.
- Bounded the returned table to documented scalar fields and reject weak/ambiguous probes.
- Kept `fire`, `assemble`, `setComputerControl`, `setTargetAngles`, `setTargetYaw`, and `setTargetPitch` outside the managed read allowlist and never invoke them.
- Clearly report ammunition, propellant, barrel/readiness, and maintenance data as unavailable because they are not part of the verified `getInfo()` contract.
- Added UI detail, pure helper coverage, source references, and an in-game CC:T checklist.

**Validation status:** Source-level validation is complete; target CC:T/modpack validation remains pending. The next safe extension is a separate server-approved read-only bridge for ammunition/loading data, not a guessed CC:CBC method.

## Cross-release quality requirements

### Versioning

- Centralize the version in `/qalcom/version.lua`.
- Remove stale hard-coded versions from user-facing apps and docs.
- Include a migration note for every release that changes persistent data.

### Testing

Maintain lightweight checks for:

- Path handling and filesystem safety
- Account validation and role persistence
- Settings defaults and migration
- Capability declarations and war-server policy decisions
- Window geometry and compact layouts
- Event routing and session invalidation
- Peripheral attach/detach behavior and mod-adapter discovery
- Job validation, retries, timeouts, and emergency stop
- Network envelope validation, replay rejection, expiry, and rate limits
- Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar adapter discovery, stale-data handling, and safe failure
- Radar contact normalization, uncertainty, deduplication, track expiry, and scan-coverage gaps
- Asset, ammunition, propulsion, power, territory, and logistics state validation
- Recovery behavior and bounded log growth

Every milestone also needs an in-game manual checklist because no local CC:T runtime is available.

### Documentation

Every release documents:

- New files and installation changes
- Controls and commands
- Persistent-data migrations
- Recovery instructions
- Capability and security implications
- Network protocol changes, if any
- Known CC:T and installed-mod limitations

### Performance and reliability

Monitor and constrain:

- Event queue size
- Application count and window count
- Memory and terminal size limitations
- Log growth and filesystem writes
- Long-running filesystem or peripheral operations
- Job frequency and retry volume
- Network message size, rate, and retention
- Radar scan frequency, contact count, track retention, map-overlay density, and alert fan-out

## Explicit non-goals

- No arbitrary remote Lua execution
- No unrestricted remote `shell.run` or `os.run`
- No unrestricted remote `peripheral.call`
- No claim that local login or pairing is cryptographically secure without a suitable CC:T-compatible design
- No third-party app store before capability and trust work
- No complex multi-user desktop before the local foundation is stable
- No autonomous destructive or offensive behavior; combat-system controls require a separate, explicit approval design
- No autonomous radar-to-targeting, radar-to-firing, or radar-to-engagement loop
- No assumption that Aeronautics, CBC, Create: Propulsion, Create Radar, or Create Aero Radar APIs are identical across server modpacks or versions
- No modification of the CC:T Java host or firmware in this project
- No assumption that a Lua coroutine is a secure process sandbox
