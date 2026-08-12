# Qalcom OS Agent Notes

This file is a compact map of the repository for future maintenance work. It is intentionally implementation-oriented; `README.md` is the operator/user guide.

## Runtime model

- Target runtime is ComputerCraft:Tweaked / CraftOS, not desktop Lua. CC:T globals (`fs`, `term`, `window`, `settings`, `textutils`, `os`, `peripheral`, `redstone`, `colors`, `keys`, and optionally `bit32`) are expected.
- There is no package manager, build system, or dependency installation. Modules are loaded with `dofile`, normally through absolute device paths such as `/qalcom/lib/ui.lua`.
- `startup.lua` is installed as `/startup.lua`. It checks `/qalcom/kernel/init.lua`, calls it under `pcall`, restores the host palette on failure when possible, and offers `reboot` or `shell` recovery.
- Current source version is returned by `qalcom/version.lua`: `0.4.7`.
- The supported terminal floor is `30 x 14`. The kernel blocks boot or pauses after resize below that size.

## Boot and kernel flow

`qalcom/kernel/init.lua` owns the OS lifecycle:

1. Load UI, config, version, auth, system, capability, role, managed-operation, network, and palette helpers.
2. Load/migrate settings and snapshot the host palette.
3. Apply the configured semantic UI theme/palette.
4. Show the splash and authenticate through `Auth.login`.
5. Create a session, record user/role, audit login, start the hidden `network_service`, and start clock/UI timers.
6. Run the event loop, dispatching events to applications and services.
7. Handle logout, Safe Mode changes, resize, power confirmation, task cleanup, targeted redraws, and palette restoration.

The kernel uses a task record plus coroutine per app. Important task fields include `pid`, `name`, `window`, `context`, `session`, `state`, `failed`, `restartCount`, `watchdog`, `cleanups`, `minimized`, `hidden`, and optional restore geometry. Failed apps remain visible on a failure screen and can be restarted from Control Center up to `MAX_MANUAL_RESTARTS = 3`.

Do not move process/event ownership into an app. The kernel owns z-order, focus, modal behavior, taskbar state, window coordinates, event routing, session invalidation, and cleanup.

## Application contract

Each app file returns a function:

```lua
return function(ctx)
    -- render once, then consume events through ctx:pullEvent()
end
```

Use the context rather than raw global event flow when adding normal app behavior:

- `ctx:pullEvent()` — session-aware coroutine event wait;
- `ctx:close()` — request task removal;
- `ctx:launch(name, options)` — spawn another built-in app/modal;
- `ctx:notify`, `ctx:log`, `ctx:audit` — shell feedback and records;
- `ctx:hasCapability`, `ctx:policy`, `ctx:isSafeMode` — current policy;
- `ctx:registerCleanup(callback)` — cleanup for timers, fire signals, graphics mode, etc.;
- managed filesystem/peripheral/redstone/power methods — see below.

Apps should render after state changes and on `term_resize`/`qalcom_tick` when needed. Keep data bounds and event handlers local to the app. Modal dialogs are the `dialog` app with callback fields attached to its context.

## Capability and trust model

The policy decision is effectively:

```text
known app manifest + manifest declares capability + role allows capability + Safe Mode permits capability
```

`qalcom/lib/capabilities.lua` owns built-in manifests, capability descriptions, decisions, catalogs, and bounded audit writes. `qalcom/lib/roles.lua` owns role definitions. `qalcom/lib/managed.lua` is the normal enforcement surface for filesystem, peripheral reads, redstone, label, power, modem, metadata, and CBC controls.

This is not a sandbox. All built-in apps are marked trusted and can still access normal Lua/CC:T globals. Do not describe capability approval as isolation or security. Every new sensitive action should still have:

- a narrowly scoped managed helper;
- a capability declaration and role decision;
- Safe Mode behavior;
- denial notification and audit behavior;
- bounded arguments and failure handling;
- manual in-game validation.

`Managed.peripheralRead` only permits the read-only method allowlist. `Managed.cannonControl` is a separate, narrower contract and currently permits only:

- `setComputerControl(boolean)`;
- `setTargetAngles(finite yaw, finite pitch)` within `-360..360`;
- `fire(boolean)`.

Do not widen that surface casually. In particular, generic inspection/telemetry must not invoke `assemble`, `fire`, `setComputerControl`, `setTargetAngles`, `setTargetYaw`, or `setTargetPitch`.

## UI and redraw invariants

`qalcom/lib/ui.lua` is the native drawing layer. `qalcom/lib/ui/screen.lua` provides shared screen headers and shell layout. `qalcom/lib/ui/animation.lua`, `hit.lua`, `palette.lua`, `canvas.lua`, `display.lua`, `pixel_palette.lua`, and `pixelfont.lua` provide supporting UI/graphics primitives.

Important invariants:

- Prefer `UI.fill`, `UI.text`, `UI.button`, `UI.listRow`, `UI.input`, `UI.panel`, `UI.titleBar`, and related helpers over raw drawing.
- `UI.captionButtons(x, y, width)` is the single geometry source for title-bar hit testing and rendering. Do not duplicate its coordinates in the kernel.
- Window frames and shadows must remain inside the rectangle the kernel knows how to restore. Do not draw outside a task's frame without updating the region-restore model.
- The kernel distinguishes full repaint (`state.dirty`) from taskbar and notification region repaint. Moving/focusing/minimizing windows must use `moveWindow`, `restoreRegion`, `flushWindow`, and related helpers rather than clearing arbitrary screen areas.
- App mouse coordinates are window-relative (`x - task.x`, `y - task.y`). Shared button hit testing uses half-open rectangles through `UI.hitButton`/`ui/hit.lua`.
- Themes mutate the 16 CC color slots and `UI.colors`. Always allow palette restoration on shutdown, reboot, logout, graphics exit, and crash cleanup.
- Graphics preview code must register cleanup that exits graphics mode and reapplies the configured text palette. The 256-color preview also requires a color-capable terminal: `Canvas.enter` refuses known non-colour terminals (the mod's grayscale mode renders the scene flat gray), and `PixelPalette.verified` reads back the extended palette so a host that ignores writes above slot 15 falls back to the text explanation.

## Persistence map

Settings use the CraftOS `settings` API:

- `qalcom.schema`, `qalcom.theme`, `qalcom.safe_mode`, `qalcom.log_limit`, `qalcom.reduced_motion`, `qalcom.wallpaper` (currently normalized to the image-free `solid` surface).
- `Config.load()` performs migration and normalization; do not bypass it when reading configuration.
- `Config.resetDefaults()` preserves account data.

Qalcom files:

- `/qalcom/data/accounts` — serialized accounts and roles;
- `/qalcom/data/peripherals.meta` — aliases, `blocked`, `trusted` markers;
- `/qalcom/data/network.meta` — opt-in transport config;
- `/qalcom/data/nodes.meta` — paired node records;
- `/qalcom/data/network.state` — transmit and receive replay counters;
- `/qalcom/data/network.audit` — bounded protocol audit;
- `/qalcom/logs/system.log` — boot and system log;
- `/qalcom/logs/audit.log` — capability/operations audit.

Use the existing parser/serializer for each file. They clamp fields and have schema markers. Never introduce an unbounded `textutils.serialize` record into network or operator-controlled input without validation.

## Network model

`network.lua` handles bounded line formats, node/config normalization, secure envelope construction/opening, protocol validation, counters, replay windows, payload limits, request allowlists, and rate limits. `protocol.lua` tracks request IDs, responses, and audit text. `nodes.lua` handles pairing and state changes. `apps/network_service.lua` is a hidden kernel task that reloads config, opens configured modems, persists replay state before accepting requests, and currently serves only read-only status/telemetry/radar/assets request names.

The intended current path is:

```text
Network Operations -> network.meta/nodes.meta -> qalcom_network_reload
-> hidden Network Service -> modem_message -> validate/decrypt/replay-check
-> read-only telemetry/status response -> network.state/network.audit
```

The old checksum envelope helpers remain for compatibility in source, but the receiver rejects legacy envelopes and requires `hmac-sha256-stream-v1`. Do not call the custom crypto implementation production-grade AEAD; retain the explicit host/jamming limitations in documentation.

## Peripheral, telemetry, and cannon model

`peripherals.lua` discovers peripherals by type/method evidence, caps method/contact counts, reads only safe status methods, and reports adapter compatibility as confirmed/unknown/stale/unavailable. `telemetry.lua` turns devices into bounded read-only records and keeps missing values unknown. Radar identities are observations; ambiguous contacts are rejected by cannon targeting, while fresh unverified contacts with a position still require operator confirmation.

`cannon.lua` is pure planning logic: coordinate validation, line-of-sight yaw/pitch, per-mount plans, alignment checks, selection, and bounds. `apps/cannon.lua` owns the interactive safety workflow, modal confirmations, detach/cooldown handling, pulse timers, and cleanup retries. Do not call world-changing mount methods from `peripherals.lua` or `telemetry.lua`.

## Source map

- `kernel/init.lua`: desktop kernel, task manager, event router, launcher, taskbar, window lifecycle, recovery.
- `apps/*.lua`: user-facing coroutines and hidden network service.
- `lib/ui.lua`: text-mode UI primitives and shell chrome.
- `lib/ui/*`: UI support and optional graphics mode.
- `auth.lua`: account storage/migration/login.
- `config.lua`: settings, themes, wallpaper, Safe Mode.
- `roles.lua` / `capabilities.lua`: policy model/manifests/audit.
- `managed.lua`: app-facing gated CC:T operations.
- `peripherals.lua` / `telemetry.lua`: adapters and normalized telemetry.
- `network.lua` / `protocol.lua` / `nodes.lua` / `crypto.lua`: transport foundation.
- `cannon.lua`: pure CBC target planning.
- `pure.lua` / `calculator.lua`: dependency-light/testable helpers.
- `tests/pure_test.lua`: offline regression suite.

## Testing workflow

The repository does not currently contain a Lua executable or an automated CC:T harness. The intended pure test command is:

```text
lua tests/pure_test.lua
```

When changing pure modules, run that suite with a Lua 5.1-compatible interpreter if available. When changing kernel/UI/apps, manually test in CC:T or CraftOS-PC, including minimum terminal size, resize, logout, Safe Mode, crash/restart, cleanup, and palette restoration. When changing peripherals, network, or CBC code, use fake-helper tests where possible and then validate against the actual in-game modpack APIs.

Do not claim a test passed if it could not run because CC:T or Lua was unavailable.

## Known documentation/source boundary

`TESTING.md` contains a large historical/regression checklist. It mentions systems such as Infrastructure Controls, Automation Jobs, and Incident Response that are not represented by files in the current `qalcom/apps` tree. Treat the current source and `README.md` app table as authoritative before implementing or documenting those systems. Do not infer an implementation merely from a checklist item.

Likewise, verify any mod-specific method names in-game before adding an adapter. Compatibility guesses must remain `unknown` until an allowlisted read probe succeeds.

## Change checklist

Before finishing a change:

1. Keep `/qalcom` absolute paths and the app return-function contract intact.
2. Update the relevant manifest, role/Safe Mode policy, and audit behavior for sensitive actions.
3. Preserve bounds, schema parsing, and safe failure behavior.
4. Preserve kernel redraw/cleanup/session invariants.
5. Add or update pure tests for deterministic logic.
6. Run the pure suite if a Lua runtime exists; otherwise report that it was unavailable.
7. Manually validate CC:T behavior for runtime-dependent changes.
8. Update `README.md`, `TESTING.md`, or this file when behavior, paths, limits, or known limitations change.
