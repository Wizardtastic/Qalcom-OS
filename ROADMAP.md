# Qalcom OS Roadmap

Qalcom OS is a Windows-inspired ComputerCraft: Tweaked operating environment built entirely from standard CC:T Lua APIs. It is a replacement userland and desktop running above the CC:T host, not a replacement for the Java-side firmware.

This roadmap is intentionally incremental. Each milestone should deliver one coherent capability, remain usable on its own, and be validated on an actual CC:T computer before the next milestone begins.

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

## 0.1.9 — Desktop lifecycle hardening

## 0.1.9 — Desktop lifecycle hardening

**Goal:** Finish the local desktop foundation before introducing permissions.

- Improve task cleanup for crashed, stopped, minimized, and session-invalid applications.
- Add clearer process details and safe manual restart limits.
- Improve log rotation/pruning so large logs do not cause unnecessary repeated work.
- Add a desktop-level safe shutdown/reboot confirmation flow.
- Add more reliable resize behavior for all built-in applications.
- Add a recovery-only diagnostic page for task failures and recent boot stages.

**Exit criteria:** Repeated login/logout, app failure, resize, and recovery cycles do not leave stale windows, stale tasks, or unusable settings behind.

## 0.2.0 — Capability vocabulary and trusted app manifests

**Goal:** Define permissions before third-party apps or remote operations exist.

- Create a capability vocabulary:
  - `fs.read`
  - `fs.write`
  - `peripheral.read`
  - `peripheral.control`
  - `redstone.read`
  - `redstone.control`
  - `network.send`
  - `network.receive`
  - `system.reboot`
  - `system.shutdown`
- Add application manifests that declare requested capabilities.
- Classify built-in applications as trusted and identify undeclared access.
- Add a capability inspection view in Control Center or Settings.
- Add a security audit log for login, recovery, configuration, and capability decisions.
- Document that capability checks are an application policy layer, not an unbreakable CC:T sandbox.

**Exit criteria:** Every built-in app has a documented capability profile and the OS can display requested versus approved capabilities without breaking existing apps.

## 0.2.1 — Roles and approval policy

**Goal:** Separate identity from permission decisions.

- Add local roles such as Administrator, Operator, Observer, Automation service, and Restricted guest.
- Add role persistence and migration for existing administrator accounts.
- Add a policy table mapping roles to capabilities.
- Add explicit approval dialogs for sensitive actions.
- Add audit entries for approvals, denials, and policy changes.
- Keep account management local and document its non-cryptographic limitations.

**Exit criteria:** A user’s role can be inspected, sensitive built-in actions can be approved or denied, and all decisions are logged.

## 0.2.2 — Capability-aware application context

**Goal:** Connect the policy model to Qalcom’s app lifecycle without pretending to sandbox globals.

- Pass approved capabilities through application contexts.
- Add reusable checks for Qalcom-managed filesystem, peripheral, redstone, and system actions.
- Make built-in apps use the managed checks where practical.
- Show a useful denial message instead of silently failing.
- Add a Safe Mode policy that disables sensitive managed actions.
- Document that trusted Lua code still has normal CC:T global access until a stronger boundary exists.

**Exit criteria:** New Qalcom-managed features consistently check capabilities, and denied actions are visible in the UI and audit log.

## 0.2.3 — Peripheral inventory and inspection

**Goal:** Read and understand local devices before controlling them.

- Add a Peripheral Manager application.
- Discover attached peripherals defensively and refresh on attach/detach events.
- Display type, side/name, available methods, and basic status where safe.
- Add user-defined aliases for devices.
- Add persistent blocklists and trusted-device markers.
- Keep inspection read-only in this milestone.

**Exit criteria:** Operators can identify local peripherals and their status without issuing control commands.

## 0.2.4 — Redstone and local device controls

**Goal:** Add narrowly scoped manual control with safeguards.

- Add named redstone inputs and outputs.
- Add explicit on/off controls with confirmation for important outputs.
- Add timed pulses with bounded durations.
- Add an emergency all-off action for Qalcom-managed outputs.
- Log every control action with user, device, value, and timestamp.
- Respect device blocklists and role capabilities.

**Exit criteria:** Manual controls are allowlisted, reversible where possible, auditable, and safe when a peripheral disappears.

## 0.2.5 — Local jobs and structured automation

**Goal:** Automate local actions without executing arbitrary Lua strings.

- Add a local job scheduler with named jobs.
- Support structured triggers such as timer, redstone input, peripheral attach, and manual run.
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

## 0.3.0 — Network and modem foundation

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

## 0.4.0 — Defense telemetry foundation

**Goal:** Build a read-only command center before adding response actions.

- Add a dashboard for connected node and device telemetry.
- Add configurable panels for inventory, power, reactor, turtle, door, and alarm status where supported by installed mods/devices.
- Add timestamps, stale-data indicators, and source identity.
- Add historical incident/event timeline using bounded local storage.
- Keep all panels read-only.

**Exit criteria:** The dashboard clearly distinguishes current, stale, missing, and untrusted telemetry.

## 0.4.1 — Fleet and logistics views

**Goal:** Organize defensive assets without issuing movement or attack commands.

- Add turtle/fleet inventory and health views.
- Add named locations and route metadata.
- Add logistics and storage status panels.
- Add power and fuel warnings.
- Add node/device grouping and filters.

**Exit criteria:** Operators can locate and assess defensive resources from the dashboard without unsafe automatic action.

## 0.4.2 — Manual defensive response

**Goal:** Add carefully confirmed response actions.

- Add manual door, barrier, alarm, and lockdown controls.
- Require role permission and explicit confirmation for high-impact actions.
- Add all-off/unlock recovery actions where safe and supported.
- Record operator, target, old state, new state, and result.
- Add response cooldowns and duplicate-command protection.

**Exit criteria:** Defensive actions are explicit, auditable, reversible where possible, and unavailable to unauthorized roles.

## 0.4.3 — Incident response and automation safety

**Goal:** Coordinate defensive actions without creating an uncontrolled autonomous system.

- Add incident records with severity, source, timeline, and acknowledgement state.
- Add response playbooks built from structured allowlisted actions.
- Add dry-run previews before executing playbooks.
- Add automation failure safe mode and global emergency stop.
- Require operator acknowledgement for destructive or world-changing actions.

**Exit criteria:** Incidents can be acknowledged, investigated, and resolved with bounded playbooks and clear emergency escape paths.

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
- Capability declarations and policy decisions
- Window geometry and compact layouts
- Event routing and session invalidation
- Peripheral attach/detach behavior
- Job validation, retries, timeouts, and emergency stop
- Network envelope validation, replay rejection, expiry, and rate limits
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

## Explicit non-goals

- No arbitrary remote Lua execution
- No unrestricted remote `shell.run` or `os.run`
- No unrestricted remote `peripheral.call`
- No claim that local login or pairing is cryptographically secure without a suitable CC:T-compatible design
- No third-party app store before capability and trust work
- No complex multi-user desktop before the local foundation is stable
- No autonomous destructive or offensive behavior
- No modification of the CC:T Java host or firmware in this project
- No assumption that a Lua coroutine is a secure process sandbox
