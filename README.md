# Qalcom OS 0.2.5

Qalcom OS is a clean, Windows-inspired desktop environment for ComputerCraft: Tweaked. This milestone runs entirely inside CC:T and does not require a Minecraft mod or CraftOS modification.

## Install

Copy the repository contents to the root of a CC:T computer so the layout looks like this:

```text
/startup.lua
/qalcom/kernel/init.lua
/qalcom/lib/ui.lua
/qalcom/lib/ui/animation.lua
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
/qalcom/apps/capabilities.lua
```

Reboot the computer. Qalcom starts through `/startup.lua`, shows the first-run account setup, and will enter a small recovery prompt if the kernel fails to load. When upgrading from 0.1.10, copy the updated `/qalcom/kernel/init.lua`, `/qalcom/lib/ui.lua`, `/qalcom/lib/ui/animation.lua`, `/qalcom/lib/config.lua`, `/qalcom/apps/settings.lua`, `/qalcom/lib/capabilities.lua`, `/qalcom/lib/roles.lua`, `/qalcom/lib/managed.lua`, `/qalcom/lib/peripherals.lua`,`/qalcom/lib/infrastructure.lua`, `/qalcom/lib/jobs.lua`, `/qalcom/apps/capabilities.lua`, `/qalcom/apps/peripherals.lua`, `/qalcom/apps/infrastructure.lua`, `/qalcom/apps/jobs.lua`, `/qalcom/apps/jobs_service.lua`, and `/qalcom/version.lua` files. Configuration schema migration runs automatically, including the Reduced motion preference; account data in `/qalcom/data/accounts` is preserved.

## Controls

- Qalcom requires a terminal at least 30 columns wide and 14 rows tall.
- Sign in at boot; the first boot creates a local administrator account.
- Click the green **Q** button at the bottom-left to open the Windows-style Start menu above the taskbar; type in its search bar to find programs, or choose from recently used apps below it. Use Up/Down and Enter while it is open.
- Taskbar applications use compact icons immediately after the green Q button; they are left-aligned, and the active app is marked with a subtle light-blue underline. Hover with the mouse to see the application name.
- Click `-` in a window title bar to minimize it; click its taskbar button to restore it.
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
- Open **Control Center** from Start to inspect processes, memory, storage, services, and declared capability profiles.
- Open **Peripheral Manager** from Start to inspect attached devices, adapter health, safe status, and normalized radar contacts. Press A to edit an alias, B to block, T to mark trusted, S to save staged metadata, and R to refresh; it is read-only.
- Open **Infrastructure Controls** from Start to inspect named redstone inputs/outputs. Press Enter for a confirmed toggle, P for a bounded confirmed pulse, E for confirmed emergency safe-state, S to save profiles, and I to refresh state.
- Open **Automation Jobs** from Start to manage validated local jobs. Jobs use structured data only: N creates one, Enter runs it, Space pauses/resumes it, D enables/disables it, S saves, R refreshes, and E pauses all jobs as an emergency stop.
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

## Version 0.2.5

Qalcom retains the capability policy layer from 0.2.0, role approvals from 0.2.1, and managed application context from 0.2.2. Trusted Lua still has normal CC:T globals, so this is not a secure sandbox. The native Windows-like UI foundation from 0.1.10 remains active.

The 0.2.3 milestone added a read-only Peripheral Manager. It defensively discovers attached devices, refreshes on attach/detach events, reports names/sides/types/methods and safe status methods, identifies Aeronautics, Create: Big Cannons, Create: Propulsion, Create Radar, and Create Aero Radar through capability discovery rather than fixed names, and exposes a versioned adapter health contract. Radar results are normalized into bounded, timestamped, confidence-aware contact records with explicitly unverified or ambiguous identity. Operators can persist aliases, blocklists, and trusted-device markers in `/qalcom/data/peripherals.meta`; no device control is exposed.

The 0.2.4 milestone adds local Infrastructure Controls. Operators can define named redstone input/output profiles in `/qalcom/data/infrastructure.meta` (or press N to add a starter output), inspect live state, require confirmation for output changes, issue pulses bounded by global and profile limits, and set enabled outputs to their configured safe state through a confirmed emergency action. Every write, cancellation, failure, pulse completion, and safe-state attempt is audited. Blocklisted or unavailable profiles fail closed; only local/base zones are controllable in this milestone; Safe Mode preserves read-only state inspection but blocks output writes and profile persistence. N creates a starter output; profile labels, sides, zones, and safe-state fields can be adjusted in the documented metadata record before saving.

The 0.2.5 milestone adds **Automation Jobs**. Jobs are persisted as validated records in `/qalcom/data/jobs.meta`, with bounded run history in `/qalcom/data/jobs.history`. A hidden kernel-launched service continues scheduling after the UI closes; the application provides creation, observation, editing, pause/disable, and emergency-stop controls. Jobs support manual, timer, and redstone-input triggers and can perform only structured infrastructure toggles or safe-state actions. Jobs enforce capability checks, cooldowns, bounded retries/history, pause/disable controls, and Safe Mode blocking; they never evaluate Lua strings or invoke arbitrary peripheral methods. Peripheral-attach and radar-contact triggers remain deferred.

Managed peripheral reads use an allowlist of known read-only methods and reject arbitrary method invocation. Absent or failing peripherals are reported as degraded device state and do not prevent Qalcom from booting.

Infrastructure profile records use `profile|id|label|kind|side|safe|confirm|zone|maxPulse|enabled|blocked` fields. Only local/base zones are controllable in 0.2.4; other zones remain inspectable but fail closed until a future server-aware zone adapter exists.

Run `lua tests/pure_test.lua` when a local Lua interpreter is available. This covers only CC:T-independent helpers; complete the in-game checklist in [TESTING.md](TESTING.md) as well.

The complete future roadmap is preserved in [ROADMAP.md](ROADMAP.md). See [TESTING.md](TESTING.md) for manual validation and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for milestone completion requirements.

## Design boundary

Qalcom replaces the default CraftOS user experience after the CC:T host and BIOS have loaded. It intentionally uses only standard CC:T Lua APIs, including `term`, `window`, `fs`, `peripheral`, and the event system. It is not a replacement for the Java-side CC:T firmware.

Safe Mode limits the launcher to recovery, logs, terminal, settings, the read-only Peripheral Manager, Infrastructure Controls, and Automation Jobs for troubleshooting, closes disallowed desktop apps when the setting takes effect, and blocks sensitive managed writes, redstone/infrastructure controls, job management/execution, label changes, and power actions. Read-only managed inspection remains available where the app is allowed. The current networking and remote automation layers are intentionally not enabled yet. The kernel forwards standard modem/rednet events to trusted applications, but this milestone does not expose a network control service. Future versions should add authenticated, allowlisted commands rather than arbitrary remote Lua execution.

Built-in applications are trusted and currently execute with the normal CC:T global APIs. Login credentials are stored locally in `/qalcom/data/accounts`; the included digest is a lightweight local deterrent, not cryptographic protection. Anyone with CraftOS recovery or server/file access can bypass it. Qalcom's process model provides lifecycle and UI isolation, not a security sandbox; third-party applications should not be installed until a capability-based service boundary is added.
