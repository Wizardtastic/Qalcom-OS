# Qalcom OS Testing Guide

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
- [ ] Terminal, Explorer, Settings, Account, Recovery, System Log, Control Center, and System Monitor launch.
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
