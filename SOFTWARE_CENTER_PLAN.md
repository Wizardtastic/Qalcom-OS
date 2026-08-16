# Qalcom Software Center — Design & Implementation Plan

**Target version:** `0.5.0` (Software Center milestone)
**Depends on:** existing Qalcom `0.4.7` kernel, capability/role layer, `Screen.app` UI shell, `crypto.lua`.

## What we're building

A Linux-software-manager-style app store for Qalcom OS. A developer packages a program (or an OS update) as **one file** and hosts it on Pastebin. They share a single Pastebin code. The recipient types one command into the Qalcom Terminal, and the **Software Center** window pops up showing the app's logo, name, publisher, description, and an **Install** button — the same shape as GNOME Software, KDE Discover, or Pop!\_Shop. Clicking Install writes the files, registers the app in the launcher, and (for larger installs) offers a reboot to finish.

Four decisions fixed for this version:

- **Package model:** manifest **plus embedded payload** — the paste is fully self-contained (metadata *and* the actual Lua source inline).
- **Entry point:** a command in the **Qalcom Terminal** app (`store <code>`), staying inside the desktop and its capability system.
- **Trust model:** **confirm + checksum** — show source, file list, size, requested capabilities, and a SHA-256 of the payload; require explicit confirmation before any write.
- **This document:** written plan only. No code yet.

## How it fits the existing architecture

Qalcom already has every primitive this needs, which keeps the build small:

- Apps are `function(ctx)` coroutines that render through `Screen.app(ctx.win, title, opts)` and loop on `ctx:pullEvent()` (see `calculator.lua`, `terminal.lua`). The store is just another such app.
- The kernel registers apps in static tables (`APP_PATHS`, `APP_META`, `APP_CATEGORIES`, `NORMAL_LAUNCHER_APPS`) and launches them via `context:launch(name, options) → spawn(name, options)`.
- Filesystem writes go through capability-gated `ctx:writeFile` / `ctx:makeDir` / `ctx:deletePath`, which enforce `fs.write` against the current role and Safe Mode.
- `install.lua` already demonstrates the fetch → clean → write → verify → reboot loop over `http.get`, with a progress bar and preserved user data. The store reuses that shape but inside a window and behind the trust gate.
- `crypto.lua` exposes `Crypto.sha256(msg)` and `Crypto.hex(raw)` for checksums. `textutils.serialize` / `unserialize` is the established structured-data format (`auth.lua`, the `*.meta` files).

## The Qalcom Package format (`.qpkg`)

A `.qpkg` is a single serialized Lua table (via `textutils.serialize`), hosted as a raw Pastebin paste. Payload strings hold Lua source directly — `textutils.serialize` escapes arbitrary strings safely, so no base64 is required for text (base64 stays an option for genuinely binary assets).

```lua
{
  qpkg = 1,                          -- schema version
  id = "com.example.notes",          -- reverse-DNS unique id
  name = "Notes",
  version = "1.2.0",                 -- semantic version, used for update detection
  publisher = "Example",
  category = "Tools",                -- maps to a launcher category
  kind = "app",                      -- "app" | "os-update" | "pack"
  summary = "A quick sticky-notes app.",
  description = "Longer, multi-line description shown on the detail page...",
  requires = { minOs = "0.4.7" },    -- refuse install on older Qalcom
  capabilities = { "fs.write" },     -- capabilities the INSTALLED app will request

  icon = "N",                        -- 1-2 char glyph fallback for taskbar/launcher tile
  logo = {                           -- optional pixel logo (see "Logos" below)
    w = 8, h = 8,
    pixels = { "77777777", "70000007", ... },  -- CC blit hex chars, one string per row
  },

  install = {
    root = "/",                      -- allowlisted base; all paths must resolve under it
    files = {                        -- declared target paths (for the confirm screen).
      { path = "qalcom/pkg/notes/main.lua" },   -- app kinds are quarantined under
      { path = "qalcom/pkg/notes/data.lua" },   -- /qalcom/pkg/<app>/ ; entry is main.lua
    },
    register = {                     -- how to wire the app into the desktop
      app = "notes",                 -- entry point is /qalcom/pkg/notes/main.lua
      meta = { title = "Notes", icon = "N", width = 40, height = 18 },
      category = "Tools",
      launcher = true,
    },
  },

  payload = {                        -- embedded file contents: target path -> source text
    ["qalcom/pkg/notes/main.lua"] = "....lua source....",
    ["qalcom/pkg/notes/data.lua"] = "....lua source....",
  },

  integrity = {
    algo = "sha256",
    payload = "<hex sha256 of canonical payload>",
  },
}
```

**Canonical checksum.** SHA-256 over a deterministic serialization of the payload: sort keys by path, concatenate `path .. "\0" .. content .. "\0"` for each, hash, and hex-encode with `Crypto.hex(Crypto.sha256(canonical))`. The store recomputes this on load and refuses to proceed on mismatch.

**Size reality.** Pastebin's free tier caps around 512 KB and serialized Lua adds overhead, so the embedded model comfortably fits single apps (a few files) but not a full ~35-file OS update. For `kind = "os-update"` the practical ceiling is real; a future `qpkg = 2` "multi-part" extension (manifest lists additional paste codes to stream) is the clean escape hatch and is flagged, not built, here.

## The Software Center app (`store.lua`)

Visual goal: read like a Linux software manager. Inside the `Screen.app` shell, the **detail page** is the primary view:

- **Hero band** — the pixel logo (drawn cell-by-cell with `UI.fill`, falling back to the `icon` glyph in a `UI.card`), then the app name in accent, and a muted subline `publisher • version • category`.
- **Primary action** — an accent **Install** button (`UI.button` variant `"accent"`). Label adapts to state: **Install** (not present), **Update** (installed, older version), **Open** / **Remove** (installed, same version).
- **Description** — wrapped body text in the content area.
- **Details rail** — labeled rows mirroring GNOME Software's "Details": Version, Download size, Publisher, Capabilities requested, Source (Pastebin code), Integrity (short SHA-256).
- **Optional Library tab** — a second view listing installed `.qpkg` packages with Open / Remove, using the `Screen.shell` segmented tabs.

**State machine:** `loading → idle → confirming → installing → done | failed`. The confirm and install screens follow `install.lua`'s proven pattern (`screenConfirm`, `screenInstall` progress bar) but render into the window body and write through `ctx:writeFile` / `ctx:makeDir`. `UI.progress` drives the bar.

**Launch contract:** the terminal opens it via `ctx:launch("store", { code = "<pastebin>" })`, or with no code to land on the Library/browse view. No kernel plumbing is required — `startTask` already merges the launch `options` onto the app context (`for key, value in pairs(task.options) do task.context[key] = value end`), so the store simply reads `ctx.code`.

## Terminal integration

Add to `terminal.lua`'s `run()` dispatch and help text:

- `store` → `ctx:launch("store")` (browse / library).
- `store <code>` (alias `get <code>`) → `ctx:launch("store", { code = code })`. The store performs the fetch, validation, and trust UI itself, so all network and confirmation logic lives in one place.

"Allow the terminal app to use those commands" resolves cleanly: the terminal only *launches* the store; the sensitive `fs.write` / fetch capabilities live on the **store's** manifest and are gated by role and Safe Mode. No new terminal capability is needed just to launch.

## Fetching from Pastebin

Reuse `install.lua`'s `http.get` helper. Raw URL: `https://pastebin.com/raw/<code>`. Handle the same failure classes: HTTP disabled, non-200, empty body, and Pastebin's throttle/HTML pages (detected because parsing won't yield a table with a `qpkg` field). One retry, then a clear error in the window. Optionally accept a full URL form (`store url https://...`) and GitHub-raw for flexibility. Note CC:Tweaked's HTTP allowlist must include `pastebin.com` (it does by default).

## Security and trust (confirm + checksum)

1. **Payload is data, never executed at browse time.** The store never `load()`s the payload; it only writes strings to disk. Installed apps run later at the same trust level as any Qalcom app — the README is explicit that built-in apps are trusted, not sandboxed — and the confirm screen says so plainly.
2. **Checksum verification.** Recompute the canonical SHA-256, display it, and compare to `integrity.payload`. Mismatch blocks the install with a tamper warning.
3. **Path allowlisting and quarantine.** App/pack packages may write *only* under `/qalcom/pkg/<app>/`; any path outside it, one that contains `..`, is absolute, or targets a protected tree (`/startup.lua`, `/qalcom/kernel`, `/qalcom/lib`, `/qalcom/apps`, `/qalcom/version.lua`, `/qalcom/data`, `/qalcom/logs`) is rejected. This means a downloaded package can never overwrite a trusted, kernel-loaded module or a built-in app — closing the privilege-escalation hole a security audit found. Only `kind == "os-update"` may touch system paths, and then behind an extra "system update" warning. User data directories are preserved exactly as `install.lua` preserves them.

> **Security note (audit-driven).** Two blockers were found and addressed. (a) *Writable core* — fixed by the `/qalcom/pkg/` quarantine and expanded protected roots above; app names are also checked against the built-in set, and the kernel refuses to override any existing app at merge time. (b) *No sandbox* — installed apps run with the same globals as built-in apps (Qalcom is explicitly "not a secure sandbox"), so the capability allow-list (`fs.read`, `fs.write`, `telemetry.read`, `peripheral.read` — enforced at validate time, again in `launcherEntries`, and a third time in `Capabilities.register`) is defence in depth, not containment. The mitigation shipped for v1 is an explicit, unmissable **trust-the-publisher warning** on the confirm screen: the checksum proves the download was not altered in transit, not that the author is benign. A real `_ENV`/`setfenv` sandbox that routes `peripheral`/`redstone`/`http`/`fs`/`os.reboot` through the capability layer, or a signed-publisher model, remains available as future hardening.
4. **Capability + role gate.** Install writes through `ctx:writeFile` / `ctx:makeDir`, which enforce `fs.write`. For Observer / Restricted guest the Install button is disabled with a "requires Administrator" note; in Safe Mode it's disabled with a Safe Mode note. Every install is audited via `ctx:audit("install", id .. "@" .. version)`.
5. **Confirm screen** (modeled on `install.lua`'s `screenConfirm`): source code, publisher, version, file count and total bytes, target paths, requested capabilities, checksum, and explicit Install / Cancel.
6. **Atomic-ish writes and rollback.** Write to temp paths then move (or clean-per-directory like `install.lua`); on any failure, abort with a "nothing was left half-installed" message. Record the installed package and its exact file list so Remove is precise.

## Installed-package registry

New serialized data file `/qalcom/data/packages.meta`, following the existing `*.meta` convention. Maps `id → { version, files = {...}, installedAt, source, category, register }`. This powers update detection (version compare), the Library list, and clean removal (delete exactly the recorded files, then unregister from the launcher).

## Registering installed apps into the desktop

The kernel builds its app registry from static tables at boot, so a newly installed third-party app has to be merged in. Two options:

- **(A) Registry-driven, reboot to finish (recommended for v1).** Install writes files and updates `packages.meta`; at boot the kernel reads `packages.meta` and merges third-party entries into `APP_PATHS` / `APP_META` / `APP_CATEGORIES` / the launcher list, and merges their manifests so `Capabilities.manifest` recognizes them. The app appears after a reboot — acceptable, and consistent with `install.lua`, which already reboots. The store offers a "Reboot now" prompt on success.
- **(B) Live registration (later enhancement).** Add kernel functions to register an app at runtime by mutating the in-memory tables and launcher list and accepting a dynamic manifest. More moving parts; deferred.

Either way, `capabilities.lua` needs a small change so `Capabilities.manifest(name)` can consult a runtime/registry manifest table in addition to the static `manifests`, otherwise installed apps can't declare capabilities.

## File-by-file change list

**New files**

- `qalcom/apps/store.lua` — the Software Center window: detail page, confirm, progress, done/fail, optional Library tab.
- `qalcom/lib/store.lua` — pure logic module: manifest parse + validate, canonical checksum, path allowlist, size calc, version compare, install/remove planning, `packages.meta` read/write. Kept separate so it's unit-testable in `tests/pure_test.lua`.
- `PACKAGING.md` — the `.qpkg` spec and a "how to publish to Pastebin" guide.

**Edited files**

- `qalcom/kernel/init.lua` — register `store` in `APP_PATHS` / `APP_META` / `APP_CATEGORIES` / `NORMAL_LAUNCHER_APPS`; at boot, merge `packages.meta` into the registry, launcher, and runtime manifests. (Launch options already reach `ctx` via `startTask`, so no change is needed there.)
- `qalcom/lib/capabilities.lua` — add the `store` manifest (`requested = { "fs.read", "fs.write", "content.fetch" }`); add a `content.fetch` capability name + description; let manifest lookup consult runtime/registry manifests; add `content.fetch` to the Safe-Mode-blocked set.
- `qalcom/lib/roles.lua` — grant `content.fetch` to `Administrator` (and optionally `Engineer` / `Automation service`).
- `qalcom/apps/terminal.lua` — add `store` / `get` commands and a help line.
- `qalcom/lib/managed.lua` — optional `Managed.fetch(ctx, url)` gated by `content.fetch` for auditable HTTP, plus a `Managed.deleteTree` helper for Remove.
- `install.lua` — add `qalcom/apps/store.lua` and `qalcom/lib/store.lua` to `CORE`; move `qalcom/lib/crypto.lua` from the `NETWORK` pack into `CORE` (it's dependency-free) so checksums work without the networking pack installed.
- `tests/pure_test.lua` — cases for manifest parse/validate, checksum match + tamper rejection, path-allowlist rejection, size calc, version compare, and `packages.meta` round-trip.
- `README.md` — document the Software Center app and packaging.
- `qalcom/version.lua` — bump to `0.5.0`.

## Milestones

1. **Spec + logic** (`lib/store.lua`): schema, parse/validate, checksum, allowlist, registry, version compare — plus pure tests. No UI.
2. **Store app UI**: detail page (logo / description / Install), confirm screen, progress, done/fail — styled like a Linux software center.
3. **Terminal + launch plumbing**: `store <code>` command, thread launch options, HTTP fetch with error handling.
4. **Install / remove + registry + boot merge**: capability and role gates, `packages.meta`, launcher integration, reboot-to-finish.
5. **Publisher tooling + docs**: a small `pack` helper that builds a `.qpkg` from a folder and computes the checksum, plus `PACKAGING.md` and README updates.

## Logos

Define a small blit-pixel logo format (CC's 16-color hex chars, e.g. 8×8 or 16×16, one string per row) so packages get real app-icon art, with the 1–2 char `icon` glyph as fallback. Keep logos small to respect the paste-size budget. This is what makes the store *look* like a software manager rather than a text list.

## Flagged trade-offs

- The embedded single-file model is ideal for apps but hits Pastebin's size ceiling for full-OS updates; the `qpkg = 2` multi-part extension is the intended path there.
- Reboot-to-finish (option A) is the pragmatic v1; live registration (option B) is a clean follow-up once the format is proven.
- A future `store install <code> --yes` (still capability-gated) would enable scripted / automated installs.
