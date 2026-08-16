# Packaging for the Qalcom Software Center (`.qpkg`)

This is the process for creating a **Qalcom Package** — a single `.qpkg` file you host on Pastebin so anyone can install your app with one command in the Qalcom Terminal. It covers the quick path (a folder + the `pack` tool), the full schema (for hand-authoring or for agents generating packages programmatically), and the rules the installer enforces.

A `.qpkg` is one self-contained file: a serialized Lua table holding your app's metadata, its logo, and the source of every file, plus a SHA-256 checksum. Nothing else is fetched at install time.

## The workflow at a glance

1. Put your app in a folder, with the entry point at `src/main.lua`.
2. Write a small `build.lua` descriptor next to it.
3. Run `pack build.lua` to produce `<app>.qpkg`.
4. `pastebin put <app>.qpkg` and share the returned code.
5. Recipients run `get <code>` in the Qalcom Terminal; the Software Center opens with your app's logo, description, and an Install button.

## Quick start

A complete working template lives in `examples/hello/`. Copy it and edit two things: the code in `src/main.lua` and the metadata in `build.lua`.

```
examples/hello/
  build.lua        -- descriptor (metadata + app name + source dir)
  src/
    main.lua       -- your app: returns function(ctx) ... end
```

Build it on a CC:Tweaked computer or in CraftOS-PC (the `pack` tool needs the `fs` and `textutils` APIs):

```
pack examples/hello/build.lua hello.qpkg
pastebin put hello.qpkg
```

`pack` validates the package exactly the way the installer will and refuses to write an invalid one, so if it packs, it installs.

## Writing the app

An installed app is an ordinary Qalcom app: a module that returns a `function(ctx)`. The entry file must be `main.lua`. After install your files live at `/qalcom/pkg/<app>/`, so `main.lua` becomes `/qalcom/pkg/<app>/main.lua`, and it is launched like any built-in app. The `ctx` object gives you the window, the event loop, notifications, and capability-gated filesystem helpers — see any built-in app (`qalcom/apps/calculator.lua` is the simplest) for the pattern:

```lua
local UI = dofile("/qalcom/lib/ui.lua")
local Screen = dofile("/qalcom/lib/ui/screen.lua")

return function(ctx)
    local function render()
        local shell = Screen.app(ctx.win, "My App", { ui = UI, footer = { "Esc = close" } })
        UI.text(ctx.win, shell.body.x, shell.body.y, "Hello", UI.colors.text, UI.colors.surface, shell.body.width)
    end
    render()
    while true do
        local event, value = ctx:pullEvent()
        if event == "key" and value == keys.escape then ctx:close()
        elseif event == "term_resize" or event == "qalcom_tick" then render() end
    end
end
```

Helper files are fine — put them under `src/` too (for example `src/lib/util.lua` → `/qalcom/pkg/<app>/lib/util.lua`) and `dofile("/qalcom/pkg/<app>/lib/util.lua")` from `main.lua`.

## The build descriptor (`build.lua`)

`build.lua` returns a table. Required fields are `id`, `name`, `version`, `app`, and `source`; the rest are optional but recommended.

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Reverse-DNS unique id, e.g. `com.yourname.notes`. |
| `name` | yes | Display name shown in the store and launcher. |
| `version` | yes | Dotted numeric version (`1.0.0`). Bump it to publish an update. |
| `app` | yes | Internal name and quarantine directory (`/qalcom/pkg/<app>/`). Letters, digits, underscore. Cannot be a built-in name. |
| `source` | yes | Folder (relative to `build.lua`) whose files are embedded. Must contain `main.lua` for `kind = "app"`. |
| `publisher` | no | Your name/handle, shown on the detail page. |
| `summary` | no | One-line description. |
| `description` | no | Longer description (newlines allowed). |
| `category` | no | Launcher category (e.g. `Tools`). |
| `icon` | no | 1–2 character glyph for the launcher/taskbar tile. |
| `logo` | no | Pixel logo table (see "Logos" below). |
| `window` | no | Window metadata: `{ title, icon, width, height }`. |
| `kind` | no | `"app"` (launchable, default) or `"pack"` (files only, no launcher). |
| `launcher` | no | `true` (default) to show a launcher tile. |
| `requires` | no | `{ minOs = "0.5.0" }` — refuse install on older Qalcom. |
| `capabilities` | no | What the installed app may use. **Only** `fs.read`, `fs.write`, `telemetry.read`, `peripheral.read` are permitted. |

## The `pack` tool

```
pack <build.lua> [output.qpkg]
```

It reads the descriptor, embeds every file under `source`, maps each to `/qalcom/pkg/<app>/<relative-path>`, computes the checksum, validates, and writes the `.qpkg`. If validation fails it prints the reason and writes nothing. Output defaults to `<app>.qpkg`.

## Publishing and installing

Publish with the built-in CraftOS Pastebin client:

```
pastebin put myapp.qpkg
```

Share the returned code (or the `pastebin.com/<code>` link). To install, a user opens the Qalcom Terminal and runs one of:

```
get <code>          -- fetch and open the Software Center on this package
store <code>        -- same
store               -- open the store's library / code entry
```

The Software Center shows the logo, name, `publisher · version · category`, description, requested capabilities, and the checksum, with an Install button. Installing needs an Administrator (or another `fs.write` role) and is blocked in Safe Mode. A brand-new app appears in the launcher after the reboot the store offers.

## Updating

Publish a new paste with a higher `version`. When a user opens it, the store detects the installed copy, shows **Update**, installs the new files, and removes any files the old version shipped that the new one dropped. Lower versions show **Downgrade**; equal versions show **Reinstall**.

## Manifest schema (for hand-authoring or agents)

`pack` is the easy path, but a `.qpkg` is just a `textutils.serialize`d table, so an agent can build one directly. The shape:

```lua
{
  qpkg = 1,                                  -- schema version (must be 1)
  id = "com.example.notes",
  name = "Notes",
  version = "1.0.0",
  publisher = "Example",
  category = "Tools",
  kind = "app",                              -- "app" | "pack" | "os-update"
  summary = "...",
  description = "...",
  requires = { minOs = "0.5.0" },
  capabilities = { "fs.write" },             -- allow-listed set only
  icon = "N",
  logo = { w = 8, h = 8, pixels = { "77777777", ... } },  -- optional; CC blit hex chars

  install = {
    root = "/",
    files = {                                -- one entry per payload file
      { path = "qalcom/pkg/notes/main.lua" },
      { path = "qalcom/pkg/notes/data.lua" },
    },
    register = {                             -- omit for kind = "pack"
      app = "notes",
      meta = { title = "Notes", icon = "N", width = 40, height = 18 },
      category = "Tools",
      launcher = true,
    },
  },

  payload = {                                -- target path -> file source (verbatim)
    ["qalcom/pkg/notes/main.lua"] = "....lua source....",
    ["qalcom/pkg/notes/data.lua"] = "....lua source....",
  },

  integrity = { algo = "sha256", payload = "<hex sha256>" },
}
```

The **checksum** is `Crypto.hex(Crypto.sha256(canonical))`, where `canonical` sorts payload paths and concatenates `path .. "\0" .. content .. "\0"` for each. `qalcom/lib/store.lua` does this for you: `Store.assemble(meta, payload)` builds the whole table (deriving `install.files` and computing `integrity`), and `Store.encode(manifest)` serializes it. Prefer those over rolling your own — they guarantee a package that the installer accepts.

## Rules the installer enforces

A package is rejected unless all of these hold:

- **Schema** is `1`; `id`, `name`, `version` are present; `id` matches `[%w%.%-_]+`.
- **Quarantine.** For `app`/`pack` kinds, every file path must be under `/qalcom/pkg/`. Absolute paths, `..` traversal, and anything targeting a protected tree (`/startup.lua`, `/qalcom/kernel`, `/qalcom/lib`, `/qalcom/apps`, `/qalcom/version.lua`, `/qalcom/data`, `/qalcom/logs`) are refused. This is why a package can never overwrite the OS or a built-in app.
- **App entry.** A launchable app's `register.app` must be a valid, non-reserved name, and `/qalcom/pkg/<app>/main.lua` must be one of the files.
- **Capabilities.** Every declared capability must be in the allow-list (`fs.read`, `fs.write`, `telemetry.read`, `peripheral.read`). Sensitive ones (cannon control, reboot/shutdown, account, network, redstone, `content.fetch`, …) are refused.
- **Payload integrity.** Every declared file has matching payload content and vice versa (no undeclared or missing files); a valid `sha256` checksum is present and matches.
- **Size.** ≤ 64 files, ≤ 256 KiB per file, ≤ ~500 KiB total; and the whole `.qpkg` must fit under Pastebin's ~512 KiB paste limit.

`os-update` packages may write system paths (they replace the OS itself) and are meant for Qalcom maintainers, not third-party apps; the quarantine and capability rules above are for the app/pack packages everyone else publishes.

## Trust and safety — read this

The checksum proves the download was **not altered in transit**. It does **not** vouch for the author. Qalcom is explicitly *not a secure sandbox*: an installed app runs with the same access as built-in apps, so the capability allow-list is defence in depth, not containment. Treat installing a `.qpkg` like running `pastebin run` — **only install from publishers you trust.** The confirm screen says as much before every install.

## Logos

A logo makes your package look like a real app in the store. Provide `logo = { w, h, pixels = { ... } }`, where `pixels` is a list of strings, one per row, each character a ComputerCraft blit hex digit (`0`–`9`, `a`–`f`) naming a palette color; unknown characters are skipped (transparent). Keep it small (8×8 or 16×16) to respect the paste-size budget. Without a logo, the store falls back to your 1–2 character `icon` glyph.

## Troubleshooting

| Message | Cause and fix |
| --- | --- |
| `installed files must live under /qalcom/pkg/` | An `app`/`pack` file targets a system path. Put everything under `source/`; the tool maps it into the quarantine for you. |
| `register app has no matching file: /qalcom/pkg/<app>/main.lua` | Your `source` folder has no `main.lua`. Add one. |
| `app name is reserved` / `app name '<x>' is reserved` | `app` collides with a built-in (terminal, settings, …). Pick another name. |
| `capability not allowed for installed apps: <cap>` | Remove it; only `fs.read`, `fs.write`, `telemetry.read`, `peripheral.read` are allowed. |
| `checksum mismatch` | The payload changed after the checksum was computed. Re-run `pack` (or `Store.assemble`) to recompute. |
| `not a Qalcom package` | The paste isn't a `.qpkg` (often a Pastebin error/HTML page or wrong code). Check the code. |
| `Needs Qalcom <x> or newer` | The target machine's Qalcom is older than your `requires.minOs`. Update it, or lower the requirement. |
| `HTTP is disabled on this computer` | Enable `http` in the CC:Tweaked config on the target machine. |
