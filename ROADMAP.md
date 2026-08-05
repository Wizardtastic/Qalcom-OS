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
- The exact peripheral names, methods, block entities, and addon APIs are server-specific. Integration work must use an adapter layer and capability discovery instead of hard-coded assumptions throughout the desktop.

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

- Deferred to 0.2.2+: broader capability-aware service boundaries and managed enforcement for filesystem, peripheral, redstone, and system actions.
- Deferred to 0.2.3+: peripheral inventory and safe device inspection.

**Implementation status:** Every built-in app has a documented capability profile and the OS can display declared capabilities without changing existing app behavior. The audit stream is bounded and the capability layer does not claim to sandbox trusted Lua. Role approvals now begin in 0.2.1 for managed power requests; broader enforcement remains deferred.

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

**Deferred:** Broader managed filesystem/peripheral/redstone enforcement and multi-user administration remain in 0.2.2+. Role changes are exposed only through the Administrator-gated, audited Account workflow.

**Exit criteria:** A user’s role can be inspected, sensitive built-in actions can be approved or denied, and all decisions are logged. Manual CC:T validation remains required before this milestone is considered fully validated.

## 0.2.2 — Capability-aware application context

**Goal:** Connect the policy model to Qalcom’s app lifecycle without pretending to sandbox globals.

- Pass approved capabilities through application contexts.
- Add reusable checks for Qalcom-managed filesystem, peripheral, redstone, and system actions.
- Make built-in apps use the managed checks where practical.
- Show a useful denial message instead of silently failing.
- Add a Safe Mode policy that disables sensitive managed actions.
- Document that trusted Lua code still has normal CC:T global access until a stronger boundary exists.

**Exit criteria:** New Qalcom-managed features consistently check capabilities, and denied actions are visible in the UI and audit log.

## 0.2.3 — Peripheral and mod-device inventory

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

**Exit criteria:** Operators can identify local mod devices and their status without issuing control commands, each discovered integration reports a compatible adapter contract and health state, radar contacts are safely normalized without claiming certainty, and an absent integration does not prevent Qalcom from booting.

## 0.2.4 — Local base and infrastructure controls

**Goal:** Add narrowly scoped manual control for local bases and support systems before controlling vehicles or artillery.

- Add named redstone inputs and outputs for doors, alarms, lights, pumps, loaders, and other server-approved infrastructure.
- Add explicit on/off controls with confirmation for important outputs.
- Add timed pulses with bounded durations.
- Add an emergency all-off or safe-state action for Qalcom-managed infrastructure.
- Log every control action with user, device, value, and timestamp.
- Respect device blocklists, war-server zones, and role capabilities.
- Do not add firing, launch, propulsion, or movement controls in this milestone.

**Exit criteria:** Manual infrastructure controls are allowlisted, reversible where possible, auditable, and safe when a peripheral disappears.

## 0.2.5 — Local jobs and structured automation

**Goal:** Automate local actions without executing arbitrary Lua strings.

- Add a local job scheduler with named jobs.
- Support structured triggers such as timer, redstone input, peripheral attach, radar contact, and manual run.
- Add retry limits, cooldowns, timeouts, and execution history.
- Add pause, resume, disable, and emergency-stop controls.
- Add per-job capability declarations.
- Store actions as validated data structures rather than arbitrary code.

**Exit criteria:** A small automation job can be created, observed, stopped, and recovered without unrestricted script execution.

## 0.2.6 — Automation observability and recovery

**Goal:** Make local automation dependable before networking it.

- Add job status to Control Center.
- Add structured job logs and failure reasons.
- Add retry/backoff visibility.
- Add safe fallback behavior when a target peripheral disappears.
- Add import/export of validated job definitions.
- Add recovery tools for disabling all automation jobs.

**Exit criteria:** Failed jobs are diagnosable, bounded, and recoverable from the desktop or CraftOS recovery path.

## 0.3.0 — Network and modem foundation for the war server

**Goal:** Discover network hardware without accepting remote commands yet.

- Add a Network Manager application.
- Discover modems and expose side/type/status information.
- Add channel and protocol configuration with validation.
- Define a Qalcom node identity and protocol version.
- Add local-only network diagnostics and traffic counters.
- Keep remote control disabled by default.

**Exit criteria:** Network hardware can be configured and observed locally, but no remote request can change the computer.

## 0.3.1 — Pairing and node enrollment

**Goal:** Establish explicit trust between Qalcom computers.

- Add pairing codes or another in-game enrollment flow.
- Store node records with names, identities, roles, and capabilities.
- Add approve, revoke, block, and quarantine actions.
- Log enrollment and trust changes.
- Reject unknown nodes before command handling.

**Exit criteria:** Two Qalcom nodes can be paired, inspected, revoked, and safely re-paired without implicit trust.

## 0.3.2 — Authenticated read-only operations

**Goal:** Begin remote operations with status queries only.

- Define signed or otherwise authenticated request envelopes supported by CC:T constraints.
- Add request IDs, timestamps/expiry, nonces, and replay rejection.
- Permit only a small allowlist of read-only status requests.
- Add response size and rate limits.
- Add a network audit view for accepted and rejected requests.

**Exit criteria:** Remote status requests are authenticated, bounded, auditable, and cannot execute arbitrary Lua or change device state.

## 0.3.3 — Authenticated control operations

**Goal:** Expand remote access only to explicitly approved actions.

- Add allowlisted commands for selected redstone, peripheral, and job actions.
- Require node and user capabilities for every command.
- Require confirmation for high-impact actions.
- Add idempotency handling and clear failure responses.
- Add per-node rate limits, quarantine, and emergency network disable.
- Never expose unrestricted `shell.run`, `os.run`, `peripheral.call`, or remote Lua execution.

**Exit criteria:** Every remote command is typed, validated, authorized, logged, and safely rejected when malformed or unauthorized.

## 0.3.4 — Network operations console

**Goal:** Make authenticated operations manageable from one desktop.

- Add node list, health, capabilities, alerts, and recent activity.
- Add request history with filtering and correlation by request ID.
- Add operator acknowledgement for alerts.
- Add network Safe Mode and local emergency disconnect.
- Add recovery documentation for lost pairing or compromised nodes.

**Exit criteria:** Operators can understand and control the trust boundary without relying on raw terminal commands.

## 0.4.0 — Modded war-server telemetry foundation

**Goal:** Build a read-only command center for the target modpack before adding combat or movement actions.

- Add adapter-backed dashboards for Aeronautics vehicles and airships, CBC artillery, and Create: Propulsion systems.
- Add configurable panels for radar status, scan coverage, contact tracks, vehicle identity, assembly health, docking, power, fuel, propulsion readiness, cannon readiness, ammunition, loaders, depots, alarms, and base infrastructure where supported.
- Add radar contact age, confidence, source identity, position uncertainty, scan coverage gaps, and correlation history alongside timestamps, stale-data indicators, mod/integration version, and adapter failure reasons.
- Add map-oriented overlays and bounded historical incident/combat-event timelines, while respecting faction and protected-zone visibility rules.
- Keep all mod panels and controls read-only.

**Exit criteria:** The command center clearly distinguishes current, stale, missing, damaged, unavailable, and untrusted telemetry for every supported integration, and radar displays never present an unverified contact as a confirmed hostile target.

## 0.4.1 — Fleet, artillery, and logistics views

**Goal:** Organize war-server assets and supply chains without issuing movement, firing, or propulsion commands.

- Add radar-derived air, land, and naval contact views, with explicit unknown/friendly/claimed/unverified states.
- Add Aeronautics fleet inventory, crew/seat status where available, vehicle health, docking, and named-location views.
- Add CBC cannon inventory, loading state, barrel/readiness state, ammunition stock, and maintenance warnings.
- Add Create: Propulsion engine, fuel/energy, assembly, route, and mechanical readiness panels where exposed.
- Add Create Diesel Generators and Create Nuclear power/fuel/heat telemetry where safely exposed.
- Add Create Railways, trains, depots, and supply-route status where exposed.
- Add logistics and storage status for ammunition, fuel, components, and repair supplies.
- Add power, fuel, ammunition, communication, radar coverage, and sensor-health warnings.
- Add asset grouping, faction/base/protected-zone filters, and operator-defined routes and locations.

**Exit criteria:** Operators can locate and assess vehicles, artillery, propulsion systems, and supplies without unsafe automatic action.

## 0.4.2 — Manual defensive and infrastructure response

**Goal:** Add carefully confirmed response actions while keeping combat actions behind a separate approval boundary.

- Add manual door, barrier, alarm, lockdown, docking, and infrastructure controls.
- Add safe-state or emergency-stop actions for Qalcom-managed propulsion and base systems where supported.
- Add operator-confirmed radar mute, scan pause, or sensor-isolation actions only where the mod exposes a safe, reversible interface.
- Keep radar-guided targeting, CBC firing, TACZ actions, and Aeronautics movement/flight commands disabled by default until their dedicated approval and safety model is complete.
- Require role permission and explicit confirmation for every high-impact action.
- Add all-off, unlock, and recovery actions where safe and supported.
- Record operator, target, old state, new state, request ID, and result.
- Add response cooldowns, duplicate-command protection, and zone restrictions.

**Exit criteria:** Defensive and infrastructure actions are explicit, auditable, reversible where possible, and unavailable to unauthorized roles.

## 0.4.3 — Incident response and combat-system safety

**Goal:** Coordinate war-server incidents without creating an uncontrolled autonomous combat system.

- Add incident records with severity, faction/base/asset source, timeline, and acknowledgement state.
- Add response playbooks built from structured, allowlisted actions for alarms, lockdowns, logistics, evacuation, and safe-state procedures.
- Add dry-run previews before executing playbooks.
- Add adapter health monitoring and a clear degraded-mode experience when Aeronautics, CBC, Create: Propulsion, Create Radar, or Create Aero Radar is unavailable.
- Correlate radar contacts with faction, territory, vehicle, and incident records without treating correlation as identification or authorization.
- Add automation failure safe mode and a global emergency stop.
- Require operator acknowledgement for destructive, combat-related, or world-changing actions.
- Defer any radar-guided targeting, CBC firing, TACZ control, Aeronautics flight/movement, or Create: Propulsion actuation to a later milestone with server-specific rules, two-person approval where appropriate, and a dedicated manual CC:T test plan.

**Exit criteria:** Incidents can be acknowledged, investigated, and resolved with bounded playbooks, clear emergency escape paths, and no accidental autonomous combat behavior.

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
