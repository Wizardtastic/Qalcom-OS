# Qalcom OS Testing Guide

The current source version is 0.2.2. The 0.1.x, 0.2.0, and 0.2.1 checks below remain required regression checks; the managed-context and Safe Mode checks cover the current milestone. No local Lua runtime or CC:T instance is available in this checkout, so automated and in-game validation remain pending.

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
- [ ] Login, Settings, Recovery, Control Center, Diagnostics, Monitor, System Log, Explorer, Terminal, Account, and Editor share the refreshed visual language.
- [ ] Window shadows remain inside the terminal and do not corrupt adjacent windows.
- [ ] Notifications animate in without blocking input; Reduced motion disables the transition.
- [ ] The centered taskbar and floating Start menu open and close with mouse and keyboard.
- [ ] Taskbar buttons remain correctly hit-testable after centering.
- [ ] Start opens and closes with mouse and keyboard.
- [ ] Terminal `reboot` and `shutdown` open a confirmation dialog instead of powering off immediately.
- [ ] Cancelling the power dialog leaves the desktop running.
- [ ] Terminal, Explorer, Settings, Account, Recovery, System Log, Control Center, System Monitor, and Capabilities launch.
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
- [ ] Safe Mode limits Start to Recovery, System Log, Terminal, and Settings.
- [ ] Enabling Safe Mode closes disallowed running apps.
- [ ] Safe Mode can be disabled from Settings or Recovery.
- [ ] Log retention remains within the configured bounds.
- [ ] Compact Settings still exposes Safe Mode, log retention, Reduced motion, and restore defaults.
- [ ] Changing Reduced motion persists after reboot and does not affect account data.
- [ ] Settings and Recovery remain usable at the supported minimum size.

### Native UI foundation

- [ ] Shadows, cards, title bars, dialogs, and notifications remain readable at 30 x 14 and at a normal terminal size.
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

### Session and resize behavior

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
