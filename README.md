# Qalcom OS

Qalcom OS is a self-contained Lua desktop environment for [ComputerCraft:Tweaked](https://tweaked.cc/). It boots from CraftOS, provides a Windows-inspired multi-window desktop, and adds local accounts, role-aware operations, managed filesystem/peripheral access, telemetry adapters, optional authenticated networking, and guarded Create: Big Cannons control.

**Source version:** `0.4.7`  
**Runtime:** ComputerCraft:Tweaked / CraftOS  
**Minimum terminal size:** `30 x 14`

This repository is the source tree copied onto a CC:T computer. It does not use a package manager, build step, or external Lua dependency.

The visual system and staged resolution-independent UI overhaul are specified in [UI_DESIGN.md](UI_DESIGN.md). The primary design surface is a 204 x 76 terminal, while the supported compact floor remains 30 x 14.

## What is included

- A CraftOS bootloader with a safe recovery prompt.
- A coroutine-based desktop kernel with windows, focus, dragging, minimize/maximize/close, taskbar, launcher, notifications, resize handling, crash screens, and restart limits.
- A native UI toolkit that works with CC:T's normal 16-color terminal API and can optionally use CC:Graphics for the visual preview.
- First-boot account creation, login, account migration, roles, capability decisions, Safe Mode, auditing, and local recovery tools.
- Managed filesystem, redstone, computer-label, peripheral-inspection, modem, and power helpers.
- Read-only peripheral discovery and normalized telemetry for supported Aeronautics, Create: Propulsion, Create Radar, Create Aero Radar, and Create: Big Cannons evidence, with compact single-pane inspection layouts.
- An opt-in authenticated/encrypted modem transport with paired nodes, counters, replay protection, request allowlists, rate limits, and bounded audit/state files.
- A guarded CBC Fire Control app that only accepts verified cannon-mount telemetry, requires confirmation for aim/fire, uses geometric line-of-sight angles, and automatically clears fire pulses.

## Important security and safety notes

Qalcom's policy layer is an application boundary and local operational safeguard, **not a secure sandbox**. Built-in Lua applications are trusted and still have access to normal CC:T globals. Anyone with access to the computer, its filesystem, the server, or the CraftOS recovery shell can inspect or change Qalcom files.

- The account password digest is a lightweight local deterrent, not a modern password-hashing system.
- Network protection uses dependency-free SHA-256/HMAC/HKDF code and a custom authenticated stream envelope. It protects against altered, stale, misdirected, or replayed datagrams when configured correctly; it does not protect a compromised host, stolen pairing secret, modem jamming, or a malicious server.
- Network transport is disabled by default and requires explicit local configuration plus paired nodes.
- Telemetry is read-only. Unknown, stale, degraded, and unavailable data is kept explicit instead of being guessed.
- CBC Fire Control is a real-world-changing control surface. It is intentionally limited to verified mount types and allowlisted methods, but operators must validate the actual modpack, mount orientation, permissions, ammunition, and target before use. Its angles are geometric line-of-sight angles, not a ballistic solution.

## Installation

1. Copy `startup.lua` to `/startup.lua` on the target computer.
2. Copy the complete `qalcom/` directory to `/qalcom`, preserving the directory structure.
3. Reboot the computer.
4. On first boot, create the local administrator account. Later boots show the lock screen and login form.

For a CraftOS shell, the equivalent copy operations are conceptually:

```text
copy startup.lua /startup.lua
copy qalcom /qalcom
```

The exact transfer method can instead be a disk, paste tool, server deployment, or CraftOS-PC filesystem import. Do not omit `qalcom/kernel`, `qalcom/lib`, or `qalcom/apps`.

The bootloader checks for `/qalcom/kernel/init.lua`. If it is missing, it prints a recovery message rather than attempting to boot. If the kernel crashes, the bootloader restores the host palette when possible and offers:

- `reboot` — try Qalcom again;
- `shell` — return to the normal CraftOS shell.

## First boot and desktop use

- The first account created becomes `Administrator`.
- Later accounts default to `Observer`.
- Username input accepts 2–24 letters, numbers, `_`, or `-`.
- Passwords must be at least four characters.
- Press any key or click at the lock screen to reveal the login form.
- `Esc` from the login screen shuts down during first-time setup; on an existing installation it returns to the lock screen.
- The `Q` button on the taskbar opens the launcher. Type to search, use the arrow keys to select, `Enter` to launch, and `Esc` to close.
- Click a taskbar icon to focus a window; click the focused icon again to minimize it.
- Windows can be dragged by their title bar. The title-bar controls close, minimize, and maximize/restore.
- `Alt+Tab` switches visible windows and `Alt+F4` closes the focused window.
- Reboot and shutdown always go through a confirmation dialog and role/Safe Mode policy.

The desktop requires a terminal at least `30 x 14`. Individual applications have compact layouts, but some operations—especially CBC Fire Control—need more height or width to be useful.

## Built-in applications

| Application | Purpose |
| --- | --- |
| Fluent Desktop | Optional CC:Graphics/CraftOS-PC 256-color preview on an Advanced (color) computer. Falls back to a text explanation when graphics mode is unavailable, the terminal is not color-capable, or the extended palette is not accepted. |
| Terminal | Managed filesystem shell, identity/version information, logout, and confirmed power commands. |
| File Explorer | Browse, view, create folders, rename/delete selected items, copy/paste, open files with the Editor, and use the global right-click menu to create collision-safe folders, `.txt` files, and `.lua` files through managed filesystem helpers. |
| Text Viewer | View and edit text files; `Ctrl+S` saves when the role and Safe Mode policy allow it. |
| Calculator | Bounded arithmetic calculator with keyboard and mouse input. |
| Peripheral Manager | Inspect attached peripherals, safe method metadata, adapter status, aliases, trusted markers, and blocklist markers. |
| Operations Telemetry | Read-only normalized status for supported peripherals and radar contacts. |
| CBC Fire Control | Plan, confirm, aim, pulse-fire, and stop verified Create: Big Cannons mounts. |
| Network Operations / Network Manager | Configure the local modem transport, node trust state, channels, and recent authenticated request audit. |
| Control Center | Inspect running applications/services and restart failed applications within the restart limit. |
| Capabilities | Inspect built-in app manifests and role/Safe Mode decisions; explicitly states that this is not a sandbox. |
| Settings | Change theme, wallpaper, Safe Mode, log retention, Reduced motion, and computer label. |
| Account | View the active identity and, for an Administrator, manage account roles. |
| Recovery | Clear notifications, reset the theme, toggle Safe Mode, restore Qalcom defaults, and open diagnostics/logs. |
| System Log | Read bounded boot, login, failure, configuration, recovery, and operational events. |
| Diagnostics | Review recent boot stages, process failures, restart counts, and crash reasons. |
| Network Service | Hidden background service started after login. It is not a launcher application. |

## Roles and capabilities

The built-in roles are:

- `Administrator` — full local administrative access;
- `Commander` — strategic operations and emergency oversight;
- `Operations officer` — base operations and approved infrastructure response;
- `Artillery officer` — artillery telemetry and controlled CBC operations;
- `Engineer` — vehicle, propulsion, and infrastructure telemetry/control;
- `Logistics officer` — supply, storage, and transport telemetry;
- `Observer` — read-only status and incident visibility;
- `Automation service` — bounded service identity for structured local jobs;
- `Restricted guest` — no managed operational permissions.

An application must declare a capability in its built-in manifest, the current role must allow it, and Safe Mode must not block it. Sensitive capabilities such as writes, peripheral control, redstone control, modem operations, label changes, power actions, and cannon control are denied in Safe Mode. Denials are notified to the user and written to the audit log when storage permits.

The capability catalog is an explanation and decision surface. It does not prevent a trusted application from using raw CC:T globals.

## Configuration and persistent data

Qalcom settings are stored through the CraftOS `settings` API. The current settings include:

- `qalcom.theme`: `win11dark`, `win11light`, `blue`, `dark`, or `green`;
- `qalcom.safe_mode`: start with recovery-oriented tools and sensitive actions blocked;
- `qalcom.log_limit`: retained system log lines, clamped to 50–1000;
- `qalcom.reduced_motion`: disable UI animation;
- `qalcom.wallpaper`: `solid` (the desktop intentionally uses no background image or texture).

Qalcom-owned files are:

| Path | Contents |
| --- | --- |
| `/qalcom/data/accounts` | Serialized local account records, role data, salts, and password digests. |
| `/qalcom/data/peripherals.meta` | Peripheral aliases, blocklist markers, and operator trust markers. |
| `/qalcom/data/network.meta` | Opt-in network enablement, node ID, protocol, and modem channels. |
| `/qalcom/data/nodes.meta` | Paired node IDs, aliases, secrets, roles, states, and last-seen values. |
| `/qalcom/data/network.state` | Transmit counter and persisted receive replay windows. |
| `/qalcom/data/network.audit` | Bounded authenticated network request audit records. |
| `/qalcom/logs/system.log` | Boot, login, configuration, process, recovery, and general system events. |
| `/qalcom/logs/audit.log` | Capability, denial, approval, role-change, inspection, and operational audit events. |

Do not delete `/qalcom/data/accounts` unless an account reset is intentional. If the desktop is unavailable, the bootloader's `shell` option can be used to copy logs or restore known-good files before rebooting.

## Network operations

The modem transport is deliberately conservative:

1. Configure and save `/qalcom/data/network.meta` in Network Operations.
2. Pair nodes explicitly in `/qalcom/data/nodes.meta`; each node needs a secret of at least 16 characters.
3. Enable the transport, save, and let the hidden Network Service reload.
4. Validate the target's modem and protocol behavior in-game.

Secure envelopes bind protocol/version, source, destination, message kind, timestamp, counter, nonce, ciphertext, and authentication tag. The receiver checks node state, age/future skew, destination, counter windows, replay, payload bounds, request IDs, allowlists, and per-node rate limits. Current service handling is read-only: `system.status`, `telemetry.snapshot`, `radar.contacts`, and `assets.summary` are the implemented request set. Control request names exist in the policy module for future expansion but are not a general remote command channel.

## Peripheral telemetry and CBC Fire Control

Peripheral discovery is capability/evidence based rather than fixed-name based. The inspector bounds method lists and calls only allowlisted read methods. For CC:CBC, verified telemetry requires a `cannon_mount` or `compact_cannon_mount` device exposing a usable `getInfo()` result. Generic inspection and telemetry never call `fire`, `assemble`, computer-control, or aiming methods.

CBC Fire Control adds the separate controlled path:

- select one or more verified mounts;
- enter coordinates or choose a fresh, non-ambiguous radar contact;
- create a per-mount geometric line-of-sight plan;
- explicitly confirm AIM or FIRE;
- send only `setComputerControl`, `setTargetAngles`, and bounded `fire(true/false)` calls through `Managed.cannonControl`;
- clear the fire signal after the pulse, on Stop, detach, app close, or cleanup retries.

Test the actual CC:CBC API, mount coordinates/orientation, and safe-state behavior in the target modpack before relying on this feature.

## Repository layout

```text
startup.lua                 CraftOS bootloader and recovery prompt
qalcom/
  version.lua               Source version (`0.4.7`)
  kernel/init.lua           Kernel, desktop shell, process/event lifecycle
  apps/                     Built-in application coroutines
  lib/                      Runtime services and pure/helper modules
    ui.lua                  Native drawing primitives and shell chrome
    ui/                     Screen app-shell, animation, palette, hit-testing, graphics helpers
    auth.lua                Account storage, migration, login UI
    config.lua              Settings, themes, wallpaper, Safe Mode
    roles.lua               Role definitions and capability policy source
    capabilities.lua        App manifests, decisions, and audit output
    managed.lua              Capability-gated CC:T operations
    peripherals.lua         Peripheral inspection and adapter contracts
    telemetry.lua           Normalized read-only telemetry
    network.lua              Serialization, envelopes, replay, counters, bounds
    protocol.lua             Request validation, responses, network audit
    nodes.lua                Pairing and node state helpers
    crypto.lua               SHA-256/HMAC/HKDF and authenticated stream helpers
    cannon.lua               Safe target/angle planning and CBC selection
    calculator.lua           Pure calculator state machine
tests/pure_test.lua         Offline helper regression tests
TESTING.md                  Manual CC:T checklist and historical regression notes
UI_DESIGN.md                Visual tokens, responsive layout, and UI overhaul plan
AGENTS.md                   Maintenance notes for future coding agents
```

All runtime modules use absolute `/qalcom/...` paths and `dofile`; there is no Lua `require` package layout. Keep the copied-on-device paths aligned with this tree.

## Testing

The standalone suite covers pure helpers such as path and account validation, roles/policies, replay protection, cryptographic vectors and tamper rejection, peripheral normalization, CBC angle planning, calculator arithmetic, hit testing, animation, palette conversion, and window fitting.

Run it with a Lua 5.1-compatible interpreter:

```text
lua tests/pure_test.lua
```

This checkout currently has no `lua` executable, so the suite cannot be run here without adding a local interpreter. In-game validation remains necessary even when the pure suite passes because the desktop depends on CC:T globals, terminal behavior, palette APIs, timers, windows, modems, and optional peripherals.

For manual validation, use `TESTING.md` together with the actual source tree and target modpack. Some older checklist sections describe planned or historical systems that are not present in this snapshot; the implemented app list above is authoritative for `0.4.7`.

## Recovery checklist

If boot fails:

1. Use the bootloader prompt and choose `shell`.
2. Copy `/qalcom/logs/system.log` and `/qalcom/logs/audit.log` before editing files.
3. Check the reported kernel/app error and the most recent boot stage.
4. Restore the last known-good source if needed.
5. Reboot and test only the smallest relevant checklist section.
6. Use `Start → Recovery → Open diagnostics` or `Open system log` when the desktop is still usable.

If a fire signal or peripheral operation is ever uncertain, use the target's physical/modpack safe-state controls first; do not assume a Qalcom process cleanup succeeded when the peripheral is detached or unresponsive.
