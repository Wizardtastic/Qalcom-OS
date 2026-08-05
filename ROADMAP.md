# Qalcom OS Roadmap

Qalcom OS is a Windows-inspired ComputerCraft: Tweaked operating environment built entirely from standard CC:T Lua APIs. It is a replacement userland and desktop running above the CC:T host, not a replacement for the Java-side firmware.

## Release policy

- Increment `/qalcom/version.lua` after every major milestone.
- Keep user-facing version text sourced from that file.
- Keep all remote control allowlisted and authenticated.
- Never expose arbitrary remote Lua execution as a default feature.
- Preserve a recovery path to CraftOS.
- Validate every release on an actual CC:T computer because the project has no local CC:T runtime.

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
- Categorized Settings overview:
  - Personalization
  - Account
  - Display
  - Startup
  - Security
  - Storage
  - Peripherals
  - Network
  - Recovery
- Theme reset and safe troubleshooting workflow

## 0.2.0 — Security and permissions foundation

Priority: establish a meaningful capability model before third-party apps or remote control.

- Capability declarations: `fs.read`, `fs.write`, `peripheral.read`, `peripheral.control`, `network.send`, `network.receive`, `system.reboot`, `system.shutdown`
- Trusted, approved, and untrusted application classes
- Curated application environments
- Privilege prompts for sensitive actions
- Roles: Administrator, Operator, Observer, Automation service, Restricted guest
- Security audit log for login, account, permission, peripheral, network, and recovery actions
- Explicit documentation that CC:T Lua isolation is not an unbreakable sandbox

## 0.2.1 — Local peripherals and automation

- Peripheral manager
- Peripheral aliases and trust/block lists
- Safe method/status inspection
- Redstone control center
- Named inputs and outputs
- Timed pulses and emergency all-off action
- Local job scheduler with triggers, retry limits, timeouts, logs, and manual controls
- Structured automation actions instead of arbitrary Lua strings

## 0.3.0 — Authenticated network operations

- Dedicated network manager service
- Modem discovery and channel configuration
- Rednet identity, discovery, pairing, enrollment, and revocation
- Stored node records and capability assignments
- Authenticated allowlisted commands only
- Request IDs, expiry, nonces, validated arguments, and audit records
- Network management UI with node status, capabilities, alerts, quarantine, and logs

## 0.4.0 — Defense command center

- Perimeter status dashboard
- Turtle fleet management and patrol routes
- Inventory, logistics, power, and reactor monitoring
- Door, barrier, alarm, and emergency lockdown controls
- Node quarantine and incident timeline
- Operator acknowledgements and scheduled defensive actions
- Automation failure safe mode

All offensive-style functions remain limited to authorized operations inside the Minecraft world and installed mod ecosystem. Destructive actions require explicit policy and operator confirmation.

## Cross-release quality requirements

### Versioning

- Centralize the version in `/qalcom/version.lua`.
- Remove stale hard-coded versions from user-facing apps and docs.

### Testing

Build a lightweight CC:T test suite for path handling, account validation, settings persistence, configuration migration, window geometry, event routing, file operations, and recovery behavior.

### Documentation

Every release documents new files, installation changes, controls, commands, recovery instructions, security limitations, and migration notes.

### Performance

Monitor and constrain event queue size, application count, memory use, log growth, long filesystem operations, and network message rates.

## Explicit non-goals for now

- No arbitrary remote Lua execution
- No unrestricted `shell.run` or `os.run` over the network
- No unrestricted remote `peripheral.call`
- No third-party app store before capability work
- No complex multi-user desktop before the local foundation is stable
- No claim that the local login system is cryptographically secure
- No modification of the CC:T Java host or firmware in this project
