# Qalcom OS Testing Guide

The current source version is 0.4.4. The 0.1.x, 0.2.0, 0.2.1, 0.2.2, and 0.2.3 checks below remain required regression checks; the Infrastructure Controls and Automation Jobs checks cover the current milestones. No local Lua runtime or CC:T instance is available in this checkout, so automated and in-game validation remain pending.

The 0.2.6 service is intentionally conservative: only manual, timer, and redstone-edge triggers are implemented; peripheral-attach and radar-contact triggers are deferred. Runtime status is persisted in `/qalcom/data/jobs.status`; the hidden service uses bounded retry backoff and remains recoverable from Recovery or CraftOS. Version 0.4.4 adds opt-in authenticated encrypted datagrams, persisted replay/counter state, Network Operations, read-only Operations Telemetry, and Incident Response dry-runs. Encryption cannot prevent jamming or protect a compromised host.

## Offline pure-helper checks

The standalone test runner covers logic that does not require CC:T globals:

```text
lua tests/pure_test.lua
```

The current workspace may not include a Lua interpreter. In that case, run the same file with a local Lua 5.1-compatible interpreter or validate it on a CC:T computer through the recovery shell. The test runner must not be treated as a replacement for in-game testing.

Covered helper behavior:

- Absolute and normalized paths
- Username validation
- Account record shape validation
- Role normalization and role capability policy
- Safe Mode policy decisions for sensitive and read-only capabilities
- Log line retention
- Integer setting clamping
- Window geometry fitting
- Animation interpolation and cancellation
- HMAC-SHA256 encrypted envelope validation, expiry, destination binding, persistent counter replay rejection, request allowlists, rate limits, and bounded node/config records
- Incident record validation, acknowledgement, and dry-run playbook previews

## Manual CC:T checklist

Run these checks on a fresh copy and again over an existing 0.1.x installation.

### Boot and login

- [ ] `/startup.lua` reaches the Qalcom login screen.
- [ ] First boot creates an administrator account.
- [ ] Correct credentials enter the desktop.
- [ ] Incorrect credentials show an error and do not enter the desktop.
- [ ] Escape from login reaches the expected shutdown behavior.
- [ ] A terminal smaller than 30 x 14 displays the resize/recovery message.

### Desktop and applications

- [ ] The native UI foundation renders without an external dependency.
- [ ] The login screen shows a centered Qalcom OS wordmark in its yellow header with no window controls or offset grey shadow; the white body and credential controls remain usable in compact mode.
- [ ] Login, Settings, Recovery, Control Center, Diagnostics, Monitor, System Log, Explorer, Terminal, Account, and Editor share the refreshed visual language.
- [ ] Window shadows remain inside the terminal and do not corrupt adjacent windows.
- [ ] Notifications animate in without blocking input; Reduced motion disables the transition.
- [ ] The bottom-left green Q opens a Windows-style Start menu above the taskbar, with a search field and recent-app list.
- [ ] Start-menu typing, backspace, paste, Up/Down selection, Enter launch, Escape close, and mouse selection work without leaking input to the focused app.
- [ ] Taskbar applications render as centered icon buttons and mouse hover displays the full application name.
- [ ] Taskbar icon buttons remain correctly hit-testable after centering, including the bottom-left Q button.
- [ ] Start opens and closes with mouse and keyboard, remains anchored to the bottom-left, and stays above the taskbar/start button at 30×14 and normal sizes.
- [ ] Terminal `reboot` and `shutdown` open a confirmation dialog instead of powering off immediately.
- [ ] Cancelling the power dialog leaves the desktop running.
- [ ] Terminal, Explorer, Calculator, Settings, Account, Recovery, System Log, Control Center, System Monitor, and Capabilities launch.
- [ ] System Monitor does not launch automatically after login.
- [ ] Windows can be focused, dragged, minimized, restored, and closed.
- [ ] Alt+Tab and Alt+F4 behave as documented.
- [ ] An app failure leaves a visible recovery screen and a log entry.
- [ ] Recovery opens Diagnostics and shows recent boot stages, PIDs, crash reasons, and restart counts.
- [ ] Control Center can identify and restart a failed app.
- [ ] Repeated manual restarts eventually show a restart-limit state instead of looping indefinitely.

### Settings and Safe Mode

- [ ] Configuration migration creates/updates the Qalcom schema setting without deleting accounts.
- [ ] A legacy theme, Safe Mode, or log-limit setting is migrated instead of being replaced by the current default.
- [ ] Invalid theme, Safe Mode, or log-limit values fall back to safe defaults.
- [ ] Restore defaults from Settings resets Qalcom settings without deleting `/qalcom/data/accounts`.
- [ ] Restore defaults from Recovery behaves the same way.
- [ ] Configuration migrations and changes appear in `/qalcom/logs/system.log`.
- [ ] Theme changes persist after reboot.
- [ ] Theme reset returns to Ocean/blue.
- [ ] Safe Mode limits Start to Recovery, System Log, Terminal, Calculator, and Settings.
- [ ] Enabling Safe Mode closes disallowed running apps.
- [ ] Safe Mode can be disabled from Settings or Recovery.
- [ ] Log retention remains within the configured bounds.
- [ ] Compact Settings still exposes Safe Mode, log retention, Reduced motion, and restore defaults.
- [ ] Changing Reduced motion persists after reboot and does not affect account data.
- [ ] Settings and Recovery remain usable at the supported minimum size.

### Taskbar and window chrome polish

- [ ] The green Q launcher is flush to the bottom-left and never displays the old Start label.
- [ ] Taskbar icons are vertically centered, begin immediately after the green Q button, and do not hug the top edge at 30×14 and a normal terminal size.
- [ ] Taskbar app icons have no selected/hover overlay; the active app is marked only by a subtle light-blue underline.
- [ ] Clicking the active taskbar icon minimizes its window; clicking it again restores it, and clicking another icon focuses that app.
- [ ] Hover labels remain inside the terminal and do not cover the taskbar controls unexpectedly; if the runtime lacks `mouse_move`, the desktop still remains usable via click and keyboard.
- [ ] Window frames are flush, yellow title bars show left-side `x`, `-`, and `+` controls, those hit areas close/minimize/expand correctly, resize preserves valid restore geometry, and no frame/shadow protrudes into neighboring content.
- [ ] Window title text remains clipped cleanly on narrow windows.

### Native UI foundation

- [ ] Shadows, cards, title bars, dialogs, notifications, shared visible buttons, badges, meters, list rows, and section headers remain readable at 30 x 14 and at a normal terminal size.
- [ ] Shared app headers and footers do not overlap content after resize; monitor meters and status badges remain clipped inside their windows.
- [ ] Changing themes updates the semantic UI colors without restarting Qalcom.
- [ ] Reduced motion applies immediately and cancels active animations.
- [ ] Animation updates do not starve application events or cause repeated timer backlog.
- [ ] Opening several windows does not produce visible shadow overlap or redraw corruption.
- [ ] Resize and Safe Mode recovery still work while an animation is active.

### Logs and recovery

- [ ] System Log opens when entries exist and when it is empty.
- [ ] Repeated logging appends normally and remains bounded after pruning.
- [ ] Scrolling, refresh, and all/failure/login filters work.
- [ ] Recovery can clear notifications, reset the theme, toggle Safe Mode, and open System Log.
- [ ] Log retention prevents unbounded growth.
- [ ] `/qalcom/logs/system.log` records boot, login, failure, and recovery events.
- [ ] `/qalcom/logs/audit.log` records capability launches, denials, and inspections and remains bounded.

### Roles, approvals, and trusted manifests

- [ ] Every built-in Start application appears in Capabilities with a title and declared profile.
- [ ] A legacy first account with no role is migrated to Administrator and other legacy accounts to Observer without losing login data.
- [ ] A malformed explicit role does not escalate to Administrator and is normalized to Observer.
- [ ] Account, Settings, Control Center, and Capabilities show the active role.
- [ ] Observer cannot request reboot/shutdown; the denial is visible and audit-recorded.
- [ ] Administrator can request reboot/shutdown and must explicitly confirm in the dialog.
- [ ] Administrator can open Account → Manage account roles, change a user role, and see the audited confirmation including old and new roles.
- [ ] Attempting to demote the last Administrator is rejected and leaves the Administrator intact.
- [ ] Confirmed approval, cancellation, and denied requests appear in the audit log with actor, role, capability, target, and action.
- [ ] Capabilities shows role decisions without implying enforcement beyond managed Qalcom actions.
- [ ] The UI clearly states that the policy is not a secure CC:T sandbox.
- [ ] Missing or malformed audit storage does not prevent Qalcom from booting.

### 0.2.2 managed context and Safe Mode

- [ ] Terminal `ls`, `cd`, `cat`, `mkdir`, `touch`, `rm`, `cp`, and `mv` use managed checks and show useful failures when denied.
- [ ] Explorer refresh, folder creation, deletion, and paste use managed filesystem helpers.
- [ ] Text Viewer reads through the managed helper and Safe Mode denies Ctrl+S with a visible message.
- [ ] System Log reads through the managed helper and remains available in Safe Mode.
- [ ] Settings label changes use the managed system helper; Safe Mode denies label changes with a notification and audit entry.
- [ ] System Monitor lists peripherals through the managed peripheral helpers and handles detach/attach safely.
- [ ] Control Center free-space and peripheral reporting remain visible only when the role policy allows them.
- [ ] Safe Mode blocks managed filesystem writes, peripheral controls, redstone controls, label changes, reboot, and shutdown, while read-only inspection remains available.
- [ ] Every managed denial shows a notification/status message and creates a `denied` audit entry.
- [ ] The Capabilities inspector shows Safe Mode-sensitive capabilities as denied while preserving allowed read-only decisions.
- [ ] Trusted built-in Lua still has normal CC:T globals; managed helpers are an application boundary, not a secure sandbox.
- [ ] Settings and Recovery persistence are treated as trusted kernel/recovery service paths, not as third-party filesystem capability enforcement.

### 0.2.3 Peripheral Manager

- [ ] Peripheral Manager appears in Start and launches in Normal Mode.
- [ ] Safe Mode lists Peripheral Manager alongside Recovery, Logs, Terminal, and Settings; it permits read-only inspection while denying metadata writes.
- [ ] Attached peripherals display side/name, type, method count, and safe status without invoking arbitrary methods.
- [ ] Peripheral attach and detach events refresh the inventory without crashing the app or desktop.
- [ ] Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar detection is capability-based and does not require fixed peripheral names.
- [ ] Adapter rows show contract version, availability, and stale/failure state when an integration is absent or a read fails.
- [ ] Radar contacts are bounded, timestamped, confidence-aware, and labeled unverified/ambiguous rather than treated as hostile identity.
- [ ] A edits an alias, B toggles a staged blocklist marker, T toggles a staged trusted marker, and S saves `/qalcom/data/peripherals.meta`.
- [ ] Safe Mode permits inventory inspection but denies metadata writes with a visible status/audit entry.
- [ ] No Peripheral Manager action changes a peripheral, redstone output, network state, vehicle, artillery, or propulsion system.

### 0.2.4 Infrastructure Controls

- [ ] Infrastructure Controls appears in Start and remains available in Safe Mode for inspection.
- [ ] Automation Jobs appears in Start, remains inspectable in Safe Mode, and has no arbitrary Lua/script execution path.
- [ ] `/qalcom/data/infrastructure.meta` profiles parse defensively, cap profile count/size, and persist after N/S save; profile fields and local/base zone restrictions are understood.
- [ ] Named input profiles show live redstone input state and become visibly offline when the side is unavailable.
- [ ] Named output profiles show output state and never invoke arbitrary peripheral methods; non-local/base zones remain blocked for writes.
- [ ] Enter on an output requires confirmation when configured; cancellation leaves the output unchanged and is audited.
- [ ] Output changes are role/capability-gated, audited, and fail safely when the side disappears.
- [ ] P pulses only output profiles, requires confirmation, and rejects invalid, global-over-limit, or profile-over-limit durations.
- [ ] Pulse completion returns the output to its configured safe state and audits success/failure.
- [ ] E emergency safe-state requires confirmation, checks the emergency capability, applies every enabled output safe state, and reports partial failures.
- [ ] Blocklisted profiles cannot be controlled; safe-state and control failures remain visible.
- [ ] Safe Mode permits read-only state inspection but denies output writes and profile persistence.
- [ ] No Infrastructure Controls action issues vehicle, artillery, propulsion, peripheral, network, or arbitrary Lua commands.

### Calculator

- [ ] Calculator appears in Start and launches with the screenshot-inspired light-gray body, white display, and four-column keypad of distinct, visible gray keycaps.
- [ ] Shared UI buttons render with a contrasting keycap background and shared hit-testing resolves their local bounds correctly.
- [ ] Mouse clicks activate every keypad button without leaking into the desktop.
- [ ] Keyboard digits, decimal point, operators, Enter, Backspace, and Escape work as documented.
- [ ] Addition, subtraction, multiplication, division, sign, percent, clear, and division-by-zero handling behave safely.
- [ ] Calculator remains usable after a terminal resize and at the supported minimum size.

### 0.2.5 Automation Jobs

- [ ] `/qalcom/data/jobs.meta` parses defensively, rejects unsupported trigger/action values, caps input bytes/job count, and persists after S save.
- [ ] The hidden scheduler service continues timer/redstone jobs after the Automation Jobs window is closed and reloads definitions safely.
- [ ] N creates a structured starter job and the definition remains data-only.
- [ ] Manual jobs run only after capability, cooldown, target, and action validation.
- [ ] Timer jobs obey their interval and cooldown without starving the desktop.
- [ ] Redstone jobs respond only to validated side:on/off triggers and remain rate-limited.
- [ ] Space pauses/resumes a job; D disables/enables it; R refreshes saved definitions.
- [ ] E pauses all jobs immediately and writes an audit record.
- [ ] Run history is bounded and shows success, failure, skipped, or denied outcomes.
- [ ] Missing, blocked, disabled, or offline infrastructure targets fail safely and visibly.
- [ ] Safe Mode blocks job management/execution while preserving read-only job inspection.
- [ ] Jobs never execute arbitrary Lua strings, shell commands, unrestricted peripheral calls, or network commands.

#### 0.2.6 Automation observability and recovery

- [ ] Control Center shows active, retrying, failed, and total automation counts.
- [ ] Automation Jobs shows runtime state, attempt count, and the latest failure/recovery detail.
- [ ] Failed infrastructure targets become blocked without changing unrelated outputs.
- [ ] Retry attempts use bounded backoff and do not block desktop event handling.
- [ ] `/qalcom/data/jobs.status` remains bounded and survives a restart.
- [ ] I exports validated definitions to `/qalcom/data/jobs.export`.
- [ ] O imports only definitions accepted by `Jobs.parse`.
- [ ] Recovery pauses all persisted jobs and the scheduler reloads without deleting job definitions or history.
- [ ] Safe Mode prevents execution while preserving status inspection.
- [ ] CraftOS recovery can pause jobs by editing `/qalcom/data/jobs.meta` to set `paused=true` records or removing the file when a full reset is intentional.

## 0.4.4 Network, telemetry, and incident operations

- [ ] Network Operations appears in Start and Safe Mode and does not crash when no modem is present.
- [ ] Incident Response appears in Start and Safe Mode and does not crash with empty or malformed incident storage.
- [ ] Modem inventory reports side/name/type and refreshes after attach/detach; enabled transport opens configured channels and persists transmit/receive counters.
- [ ] `/qalcom/data/network.meta` parses defensively, clamps channels, and persists only through the configured manager.
- [ ] The default network state is disabled; enabling requires local configuration save and an explicit service reload.
- [ ] Encrypted envelopes reject altered ciphertext/tag/associated data, wrong destination, unknown nodes, stale timestamps, duplicate/out-of-order counters, oversized ciphertext, and unsupported suites.
- [ ] Rebooting with `/qalcom/data/network.state` preserves receive high-water/window state and rejects captured packets.
- [ ] Network Operations can block/quarantine/approve a node and review bounded audit entries.
- [ ] A modem jammer or interference is reported as unavailable/stale rather than treated as a cryptographic failure.
- [ ] Incident Response acknowledges an incident and previews alarm/lockdown/evacuation without executing a playbook automatically.
- [ ] `/qalcom/data/nodes.meta` rejects malformed/duplicate/over-limit node records.
- [ ] Authenticated envelopes reject protocol/version mismatch, missing fields, expiry, future timestamps, unknown nodes, bad authentication, and replay.
- [ ] Read request names are allowlisted; `shell.run`, arbitrary Lua, arbitrary peripheral calls, firing, movement, and propulsion requests are rejected.
- [ ] Operations Telemetry appears in Start and remains read-only in Safe Mode.
- [ ] Aeronautics, CBC, Create: Propulsion, Create Radar, and Create Aero Radar candidates are discovered by type/method evidence rather than fixed names.
- [ ] Telemetry distinguishes online, stale, degraded, unavailable, blocked, and unknown data.
- [ ] Radar contacts remain bounded, timestamped, uncertain, and never become hostile/firing decisions.
- [ ] If a bridge addon is absent, Qalcom boots and shows a clear degraded/unavailable state.
- [ ] Verify the actual modpack's CC:CBC/Create: Avionics/radar bridge method names in-game before enabling any future control adapter.
- [ ] Confirm only successful adapter-specific probes become `apiCompatible`; name/type guesses remain unknown/degraded.

## Session and resize behavior

- [ ] Closing an app releases its task/window and does not leave a ghost taskbar entry.
- [ ] Crashed and stopped tasks are removed cleanly after closure.

- [ ] Account logout returns to login.
- [ ] Apps from the previous session are closed after logout.
- [ ] Resizing above the minimum keeps windows inside the terminal.
- [ ] Resizing below the minimum shows the recovery/resize message.
- [ ] Restoring the terminal size redraws the desktop.

## Recovery procedure

If Qalcom fails during boot:

1. Use the bootloader recovery prompt.
2. Type `shell` to enter CraftOS.
3. Inspect `/qalcom/logs/system.log` and the reported error.
4. Copy the log before changing files.
5. Restore the previous known-good Qalcom files if necessary.
6. Reboot and retest the smallest relevant checklist section.

If the desktop is usable, open **Start → Recovery → Open system log** first. Do not delete `/qalcom/data/accounts` unless account reset is intentional.

## Fresh-install validation

A release is not complete until the following have been verified:

- The documented file list matches the files copied to the computer.
- The version shown by the terminal and README matches `/qalcom/version.lua`.
- A new account can be created.
- Existing account data remains readable.
- The manual checklist has been completed on the target CC:T version.
- Known failures and limitations are recorded in the release notes.
