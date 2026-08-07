# Qalcom OS 0.4.7

Qalcom OS is a clean, Windows-inspired desktop environment for ComputerCraft: Tweaked. This milestone runs entirely inside CC:T and does not require a Minecraft mod or CraftOS modification.

## Install

Copy the repository contents to the root of a CC:T computer so the layout looks like this:

```text
/startup.lua
/qalcom/kernel/init.lua
/qalcom/lib/ui.lua
/qalcom/lib/ui/animation.lua
/qalcom/lib/ui/hit.lua
/qalcom/lib/ui/screen.lua
/qalcom/lib/config.lua
/qalcom/lib/auth.lua
/qalcom/version.lua
/qalcom/apps/terminal.lua
/qalcom/apps/explorer.lua
/qalcom/apps/monitor.lua
/qalcom/apps/settings.lua
/qalcom/apps/account.lua
/qalcom/apps/editor.lua
/qalcom/apps/dialog.lua
/qalcom/apps/control.lua
/qalcom/apps/logs.lua
/qalcom/apps/recovery.lua
/qalcom/apps/diagnostics.lua
/qalcom/lib/system.lua
/qalcom/lib/pure.lua
/qalcom/lib/capabilities.lua
/qalcom/lib/roles.lua
/qalcom/lib/managed.lua
/qalcom/lib/peripherals.lua
/qalcom/lib/infrastructure.lua
/qalcom/lib/jobs.lua
/qalcom/apps/peripherals.lua
/qalcom/apps/jobs.lua
/qalcom/apps/jobs_service.lua
/qalcom/apps/infrastructure.lua
/qalcom/lib/network.lua
/qalcom/lib/crypto.lua
/qalcom/lib/protocol.lua
/qalcom/lib/nodes.lua
/qalcom/lib/telemetry.lua
/qalcom/lib/cannon.lua
/qalcom/apps/network.lua
/qalcom/apps/network_service.lua
/qalcom/apps/telemetry.lua
/qalcom/apps/cannon.lua
/qalcom/lib/incidents.lua
/qalcom/apps/incidents.lua
/qalcom/lib/calculator.lua
/qalcom/apps/calculator.lua
/qalcom/apps/capabilities.lua
```

Reboot the computer. Qalcom starts through `/startup.lua`, shows the first-run account setup, and will enter a small recovery prompt if the kernel fails to load. When upgrading from 0.1.10, copy the updated `/qalcom/kernel/init.lua`, `/qalcom/lib/ui.lua`, `/qalcom/lib/ui/animation.lua`, `/qalcom/lib/ui/hit.lua`, `/qalcom/lib/config.lua`, `/qalcom/apps/settings.lua`, `/qalcom/lib/capabilities.lua`, `/qalcom/lib/roles.lua`, `/qalcom/lib/managed.lua`, `/qalcom/lib/peripherals.lua`,`/qalcom/lib/infrastructure.lua`, `/qalcom/lib/jobs.lua`, `/qalcom/lib/calculator.lua`, `/qalcom/apps/calculator.lua`, `/qalcom/apps/capabilities.lua`, `/qalcom/apps/peripherals.lua`, `/qalcom/apps/infrastructure.lua`, `/qalcom/apps/jobs.lua`, `/qalcom/apps/jobs_service.lua`, `/qalcom/lib/network.lua`, `/qalcom/lib/crypto.lua`, `/qalcom/lib/protocol.lua`, `/qalcom/lib/nodes.lua`, `/qalcom/lib/telemetry.lua`, `/qalcom/lib/incidents.lua`, `/qalcom/apps/network.lua`, `/qalcom/apps/network_service.lua`, `/qalcom/apps/telemetry.lua`, `/qalcom/apps/incidents.lua`, and `/qalcom/version.lua` files. Configuration schema migration runs automatically, including the Reduced motion preference; account data in `/qalcom/data/accounts` is preserved.

## Controls

- Qalcom requires a terminal at least 30 columns wide and 14 rows tall.
- Sign in at boot; the first boot creates a local administrator account.
- Click the green **Q** button at the bottom-left to open the Windows-style Start menu above the taskbar; type in its search bar to find programs, or choose from recently used apps below it. Use Up/Down and Enter while it is open.
- Taskbar applications use compact icons immediately after the green Q button; they are left-aligned, and the active app is marked with a subtle light-blue underline. Hover with the mouse to see the application name.
- Window headers are yellow with white bodies; click the left-side `x` to close, `-` to minimize, and `+` to expand/restore. Click the remaining header area to drag.
- Built-in apps share the native graphics system: yellow section headers, gray keycaps/buttons, compact list rows, status badges, meters, cards, and clean content-first layouts. The shared primitives live in `/qalcom/lib/ui.lua` and `/qalcom/lib/ui/screen.lua`.
- Click an active taskbar icon to minimize its window; click it again to restore it, or click another app icon to focus that window. Hovering still shows the app name.
- Click a window title bar to focus it.
- Click `x` in a title bar to close an application.
- Use `Alt+Tab` to switch windows and `Alt+F4` to close the focused window.
- Use terminal Tab completion and left/right cursor navigation.
- In File Explorer: Enter opens folders/text files, N creates a folder, D deletes with confirmation, C/V copies and pastes.
- Use Ctrl+S in the text viewer to save changes.
- Terminal supports keyboard input, command history, and basic filesystem commands.
- File Explorer supports mouse selection, keyboard navigation, opening directories, and refresh.
- System Monitor is available from Start and reports peripheral/modem status; it does not launch automatically.
- Open **Control Center** from Start to inspect processes, memory, storage, services, automation activity, and declared capability profiles.
- Open **Network Operations** from Start to inspect modem hardware, opt-in encrypted transport, trusted-node state, and recent authenticated-request audit. Encryption authenticates and hides messages in transit but cannot prevent radio/game-level jamming or protect a compromised computer.
- Open **Operations Telemetry** from Start to inspect normalized read-only radar, Aeronautics, CBC, and Create: Propulsion candidates, health, stale/degraded state, and bounded contacts. It never controls a device.
- Open **CBC Fire Control** from Start to select one or more verified CC:CBC mounts, choose world coordinates or a radar contact, calculate per-cannon yaw/pitch, explicitly confirm aiming, and explicitly confirm a short fire pulse. The app refuses unaligned/unassembled mounts, applies a cooldown, audits every action, and never fires automatically.
- Open **Recovery → Disable all automation jobs** to pause every persisted job and reload the hidden scheduler safely.
- In **Automation Jobs**, press I to export validated definitions to `/qalcom/data/jobs.export`, or O to import that file after validation. Runtime state shows running, retrying, blocked, failed, or successful jobs with bounded attempt counts and failure details.
- Open **Peripheral Manager** from Start to inspect attached devices, adapter health, safe status, and normalized radar contacts. Press A to edit an alias, B to block, T to mark trusted, S to save staged metadata, and R to refresh; it is read-only.
- Open **Infrastructure Controls** from Start to inspect named redstone inputs/outputs. Press Enter for a confirmed toggle, P for a bounded confirmed pulse, E for confirmed emergency safe-state, S to save profiles, and I to refresh state.
- Open **Automation Jobs** from Start to manage validated local jobs. Jobs use structured data only: N creates one, Enter runs it, Space pauses/resumes it, D enables/disables it, S saves, R refreshes, and E pauses all jobs as an emergency stop.
- Open **Calculator** from Start for a compact four-column calculator inspired by the supplied retro reference. Use the mouse or keyboard digits/operators; Enter evaluates, Backspace erases, and Escape closes it.
- Open **Capabilities** from Start to inspect built-in application manifests, role decisions, and the capability policy audit stream.
- Open **Recovery** from Start to clear notifications, reset the theme, toggle Safe Mode, restore Qalcom defaults, view diagnostics, or open the system log.
- In **Settings**, select Safe Mode, Log retention, or Reduced motion and press Enter to change them. Restore defaults to reset Qalcom settings without deleting accounts.
- In **System Log**, press F to cycle through all, failure, and login entries.
- In **Automation Jobs**, use C to cycle triggers, A to cycle structured actions, L to edit a label, T to set an infrastructure target, and V to set a timer/redstone trigger value.
- Open **System Log** from Start to inspect recent Qalcom events and errors.
- Crashed applications remain visible with a recovery screen; select them in Control Center and press R to restart.
- The kernel forwards timer, alarm, redstone, peripheral, disk, modem, and rednet events to trusted applications.

## Included applications

- **Terminal**: `help`, `ls`, `cd`, `cat`, `pwd`, `id`, `label`, `time`, `whoami`, `version`, `mkdir`, `rm`, `cp`, `mv`, `touch`, `view`, `logout`, `about`, `reboot`, `shutdown`.
- **File Explorer**: Browse the local CC:T filesystem.
- **System Monitor**: Computer identity, memory, terminal size, peripherals, and modem count. Launch it from Start when needed; it is not a boot service.
- **Control Center**: Process states, crash visibility, restart actions, memory, free space, and service information.
- **Recovery**: Local recovery actions and access to diagnostics/logs.
- **Diagnostics**: Scrollable boot-stage and recent-crash details.
- **System Log**: Scrollable recent system events with failure/login filtering and retention limits.
- **Settings**: Edit the computer label, change themes, toggle Safe Mode, view settings categories, and adjust log retention.
- **Account**: View the current session and local war-server role; Administrators can manage account roles, and all users can sign out.
- **Text Viewer**: View and edit local text, Lua, and log files.
- **Calculator**: Perform basic arithmetic with a screenshot-inspired display and keypad.
- **Network Operations**: Configure opt-in encrypted transport, inspect trusted nodes, block/quarantine nodes, and review bounded request audit history.
- **Incident Response**: Acknowledge structured incidents and preview bounded alarm/lockdown playbooks in dry-run mode; no playbook action executes automatically.
- **CBC Fire Control**: Select verified `cannon_mount`/`compact_cannon_mount` peripherals, use clickable coordinate fields and visible coordinate/radar/action buttons, calculate geometric line-of-sight aim from coordinate or fresh radar-contact positions, explicitly confirm aiming and firing, and automatically clear the fire signal after a bounded pulse. Ambiguous contacts are rejected. It does not calculate ballistic trajectories; projectile/ammunition behavior must be validated in the target modpack.
- **Operations Telemetry**: Inspect normalized read-only radar, Aeronautics, CBC, and Create: Propulsion telemetry and bounded contacts. CC:CBC `cannon_mount`/`compact_cannon_mount` devices show assembly, current/target yaw and pitch, shaft speeds, and mount position from `getInfo()`; ammunition and firing readiness remain explicitly unknown because CC:CBC does not expose them in that method.
- **Encrypted Network Service**: Hidden kernel service for authenticated status and defensive safe-state/job-pause requests only.

## Version 0.4.7

This release delivers the currently safe, implementable roadmap slice: authenticated encrypted datagrams, persisted transmit/receive counters, trust-state operations, read-only telemetry, verified CC:CBC cannon-mount state, bounded defensive requests, and structured incident dry-runs. Full pairing UX, fleet/logistics dashboards, and playbook execution remain explicitly partial or deferred. Pairing still requires an explicit local node record or separate trusted enrollment channel; no secret is generated from an unauthenticated network message.



Qalcom retains the capability policy layer from 0.2.0, role approvals from 0.2.1, and managed application context from 0.2.2. Trusted Lua still has normal CC:T globals, so this is not a secure sandbox. The native Windows-like UI foundation from 0.1.10 remains active.

The 0.2.3 milestone added a read-only Peripheral Manager. It defensively discovers attached devices, refreshes on attach/detach events, reports names/sides/types/methods and safe status methods, identifies Aeronautics, Create: Big Cannons, Create: Propulsion, Create Radar, and Create Aero Radar through capability discovery rather than fixed names, and exposes a versioned adapter health contract. Radar results are normalized into bounded, timestamped, confidence-aware contact records with explicitly unverified or ambiguous identity. Operators can persist aliases, blocklists, and trusted-device markers in `/qalcom/data/peripherals.meta`; no device control is exposed.

The 0.2.4 milestone adds local Infrastructure Controls. Operators can define named redstone input/output profiles in `/qalcom/data/infrastructure.meta` (or press N to add a starter output), inspect live state, require confirmation for output changes, issue pulses bounded by global and profile limits, and set enabled outputs to their configured safe state through a confirmed emergency action. Every write, cancellation, failure, pulse completion, and safe-state attempt is audited. Blocklisted or unavailable profiles fail closed; only local/base zones are controllable in this milestone; Safe Mode preserves read-only state inspection but blocks output writes and profile persistence. N creates a starter output; profile labels, sides, zones, and safe-state fields can be adjusted in the documented metadata record before saving.

The 0.2.5 milestone added **Automation Jobs**. Jobs are persisted as validated records in `/qalcom/data/jobs.meta`, with bounded run history in `/qalcom/data/jobs.history`. A hidden kernel-launched service continues scheduling after the UI closes; the application provides creation, observation, editing, pause/disable, and emergency-stop controls. Jobs support manual, timer, and redstone-input triggers and can perform only structured infrastructure toggles or safe-state actions. Jobs enforce capability checks, cooldowns, bounded retries/history, pause/disable controls, and Safe Mode blocking; they never evaluate Lua strings or invoke arbitrary peripheral methods. Peripheral-attach and radar-contact triggers remain deferred.

The 0.2.6 milestone added automation observability and recovery. The 0.3.0–0.4.7 milestones add authenticated encrypted operations, telemetry, bounded defensive response, structured incident coordination, verified CC:CBC cannon-mount telemetry, operator-confirmed CBC Fire Control, and a mouse-first interactive targeting workflow. Fire Control uses geometric line-of-sight angles only; it does not claim a ballistic firing solution.
 Network configuration, modem inventory, trusted-node state, HMAC-SHA256 authenticated encryption, persistent counters, replay rejection, allowlisted request kinds, bounded payloads, rate limits, and audit records are implemented in `/qalcom/lib/network.lua`, `/qalcom/lib/crypto.lua`, `/qalcom/lib/protocol.lua`, and `/qalcom/lib/nodes.lua`. Telemetry normalizes discovered Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar candidates into bounded health/status/contact records and remains read-only. Incident Response stores bounded records and offers dry-run previews only.

Persistent 0.4.7 records are optional `/qalcom/data/network.meta` (local modem configuration), `/qalcom/data/nodes.meta` (explicitly enrolled nodes), `/qalcom/data/network.state` (counter/replay state), `/qalcom/data/network.audit` (bounded request audit), and `/qalcom/data/incidents.meta` (bounded incident records); malformed records fail closed. Research boundary: CC:Tweaked provides the modem/peripheral primitives, but the target Create mods do not all expose the same native CC API. Create Radar/Create Aero Radar support is not assumed without an in-game bridge. Create Aeronautics telemetry/control is expected through a separately installed bridge such as Create: Avionics where present. CBC control/telemetry may be exposed by CC:CBC or another server-approved peripheral addon. Qalcom discovers methods at runtime, calls only its small read allowlist, reports unknown/stale/degraded/unavailable state, and never turns radar observations into targeting or firing authority. CC:CBC standard `cannon_mount` and compact `compact_cannon_mount` peripherals are read through the verified `getInfo()` method only; `fire`, `assemble`, computer-control, and aiming methods are never called. The network transport uses pure-Lua SHA-256/HMAC-SHA256, HKDF-derived encryption/authentication keys, authenticated stream encryption, persistent transmit and receive counters, replay checks, rate limits, and authenticated associated data. It still cannot prevent RF/game-level jamming/interference, protect a compromised CC:T host or copied secret, guarantee clock availability, or guarantee constant-time side-channel resistance; those limitations are explicit.

Managed peripheral reads use an allowlist of known read-only methods and reject arbitrary method invocation. Absent or failing peripherals are reported as degraded device state and do not prevent Qalcom from booting.

Infrastructure profile records use `profile|id|label|kind|side|safe|confirm|zone|maxPulse|enabled|blocked` fields. Only local/base zones are controllable in 0.2.4; other zones remain inspectable but fail closed until a future server-aware zone adapter exists.

Run `lua tests/pure_test.lua` when a local Lua interpreter is available. This covers only CC:T-independent helpers; complete the in-game checklist in [TESTING.md](TESTING.md) as well.

The complete future roadmap is preserved in [ROADMAP.md](ROADMAP.md). See [TESTING.md](TESTING.md) for manual validation and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for milestone completion requirements.

## Design boundary

Qalcom replaces the default CraftOS user experience after the CC:T host and BIOS have loaded. It intentionally uses only standard CC:T Lua APIs, including `term`, `window`, `fs`, `peripheral`, and the event system. It is not a replacement for the Java-side CC:T firmware.

Safe Mode limits the launcher to recovery, logs, terminal, settings, the read-only Peripheral Manager, Operations Telemetry, Incident Response, Network Operations diagnostics, Infrastructure Controls, and Automation Jobs for troubleshooting, closes disallowed desktop apps when the setting takes effect, and blocks sensitive managed writes, redstone/infrastructure controls, job management/execution, label changes, power actions, and network transport. Read-only managed inspection remains available where the app is allowed. The Network Operations app provides explicit opt-in encrypted transport, trust-state management, replay protection, request limits, and audit visibility. The hidden service handles only authenticated allowlisted status and narrowly bounded safe-state/job-pause requests. Incident Response provides acknowledgement and dry-run previews. There is no arbitrary remote execution, remote peripheral call, autonomous firing, autonomous radar engagement, launch, movement, or propulsion actuation. CBC firing is available only through the local Fire Control app with role authorization, explicit aim/fire confirmation, alignment checks, a bounded pulse, cooldown, and audit logging.

Built-in applications are trusted and currently execute with the normal CC:T global APIs. Login credentials are stored locally in `/qalcom/data/accounts`; the included digest is a lightweight local deterrent, not cryptographic protection. Anyone with CraftOS recovery or server/file access can bypass it. Qalcom's process model provides lifecycle and UI isolation, not a security sandbox; third-party applications should not be installed until a capability-based service boundary is added.
