# Qalcom OS 0.2.0

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
/qalcom/apps/capabilities.lua
```

Reboot the computer. Qalcom starts through `/startup.lua`, shows the first-run account setup, and will enter a small recovery prompt if the kernel fails to load. When upgrading from 0.1.10, copy the updated `/qalcom/kernel/init.lua`, `/qalcom/lib/ui.lua`, `/qalcom/lib/ui/animation.lua`, `/qalcom/lib/config.lua`, `/qalcom/apps/settings.lua`, `/qalcom/lib/capabilities.lua`, `/qalcom/apps/capabilities.lua`, and `/qalcom/version.lua` files. Configuration schema migration runs automatically, including the Reduced motion preference; account data in `/qalcom/data/accounts` is preserved.

## Controls

- Qalcom requires a terminal at least 30 columns wide and 14 rows tall.
- Sign in at boot; the first boot creates a local administrator account.
- Click **Start** to open the application launcher, or use Up/Down and Enter while it is open.
- Click `-` in a window title bar to minimize it; click its taskbar button to restore it.
- Click a taskbar item to focus an application.
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
- Open **Capabilities** from Start to inspect built-in application manifests and the capability policy audit stream.
- Open **Recovery** from Start to clear notifications, reset the theme, toggle Safe Mode, restore Qalcom defaults, view diagnostics, or open the system log.
- In **Settings**, select Safe Mode, Log retention, or Reduced motion and press Enter to change them. Restore defaults to reset Qalcom settings without deleting accounts.
- In **System Log**, press F to cycle through all, failure, and login entries.
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
- **Account**: View the current session and sign out to the login screen.
- **Text Viewer**: View and edit local text, Lua, and log files.

## Version 0.2.0

This release introduces the first capability policy layer. Built-in applications now have trusted manifests, declared capability profiles, capability-aware context metadata, a read-only Capabilities inspector, and a bounded `/qalcom/logs/audit.log` stream for launches, logins, denials, and inspections. The policy is intentionally advisory in 0.2.0: trusted Lua still has normal CC:T globals and this is not a secure sandbox. Approval decisions and managed enforcement are deferred to 0.2.1 and later. The native Windows-like UI foundation from 0.1.10 remains active.

Run `lua tests/pure_test.lua` when a local Lua interpreter is available. This covers only CC:T-independent helpers; complete the in-game checklist in [TESTING.md](TESTING.md) as well.

The complete future roadmap is preserved in [ROADMAP.md](ROADMAP.md). See [TESTING.md](TESTING.md) for manual validation and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for milestone completion requirements.

## Design boundary

Qalcom replaces the default CraftOS user experience after the CC:T host and BIOS have loaded. It intentionally uses only standard CC:T Lua APIs, including `term`, `window`, `fs`, `peripheral`, and the event system. It is not a replacement for the Java-side CC:T firmware.

Safe Mode limits the launcher to recovery, logs, terminal, and settings tools for troubleshooting, and closes disallowed desktop apps when the setting takes effect. The current networking and remote automation layers are intentionally not enabled yet. The kernel forwards standard modem/rednet events to trusted applications, but this milestone does not expose a network control service. Future versions should add authenticated, allowlisted commands rather than arbitrary remote Lua execution.

Built-in applications are trusted and currently execute with the normal CC:T global APIs. Login credentials are stored locally in `/qalcom/data/accounts`; the included digest is a lightweight local deterrent, not cryptographic protection. Anyone with CraftOS recovery or server/file access can bypass it. Qalcom's process model provides lifecycle and UI isolation, not a security sandbox; third-party applications should not be installed until a capability-based service boundary is added.
