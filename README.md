# Qalcom OS

A full graphical computer operating system written in Lua for
[ComputerCraft: Tweaked](https://tweaked.cc/), powered by
[CC:Graphics](https://modrinth.com/mod/cc-graphics) for **true RGB pixel
rendering** painted directly on the **advanced computer's own screen**.

This OS was inspired by **[LevelOS](https://github.com/LinearNoodle/LevelOS)**
and **[Ursa OS](https://github.com/Wertybility/UrsaOS)**, and is built
to feel like a modern Windows / macOS hybrid: a real login screen,
desktop, taskbar, file explorer, task manager, settings panel,
calculator, notepad, clock, paint, and start menu.

## What CC:Graphics lets Qalcom do

* **No external monitor stack required.** Place the files onto an
  advanced computer (or right-click *Boot*) and the OS paints its login,
  desktop, and apps straight onto the computer's own monitor.
* **256 colors at full ~306×171 px** (51×19 cells × 6 × 9 px per cell on
  mode 2 of CC:Graphics).
* **Real mouse hover** — `mouse_move`, `mouse_click`, `mouse_drag`,
  `mouse_up` all fire with pixel coordinates from the graphics surface.
* **Frame batching** via `term.setFrozen(true)` for clean frame-by-frame
  draw with no tearing.

![concept](docs/preview-placeholder.png)

## Features

* **Login screen** with photorealistic-feeling gradient, lock icon, user
  chip, password input, error feedback, and account creation on first
  boot.
* **Windowing system** with title bars, close / minimize / maximize
  controls, drag-to-move, drop shadows, and modal support.
* **Taskbar** along the bottom with a Start button, pinned apps, live
  running-apps strip, notification tray, and a live clock (HH:MM:SS +
  date).
* **Start menu** with search, categorised apps, user account, and
  power actions (Lock / Log out / Restart / Shut down).
* **Desktop** wallpaper (gradient / solid / pattern), desktop icons
  for File Explorer / Task Manager / Settings / About, and a
  right-click menu.
* **Apps**:
  * **File Explorer** — sidebar (Quick Access + This PC), address bar,
    back / up buttons, grid of files, double-click to open.
  * **Task Manager** — list of running windows, end-task, switch-to,
    a (fake) CPU bar, and live resolution / graphics-mode report.
  * **Notepad** — minimal plain-text editor with Save, dirty marker,
    and status bar.
  * **Clock** — large digital time, ISO date, and a sweeping analog
    dial.
  * **Calculator** — 4×5 keypad, arithmetic, ±, %, decimal.
  * **Paint** — left palette, brush / spray / erase tools, brush size,
    pixel canvas.
  * **Settings** — Display, Personalization (wallpaper style +
    swatches), Accounts, Sound (test tones), About.
  * **About** — hero logo, version, credits.
* **Notifications** — auto-dismissing toasts in the bottom-right with
  success / warning / error variants and audible feedback if a speaker
  is attached.
* **Security** — salted FNV-style hashed passwords in
  `/users/<name>.lua`; lockout after too many failed logins.
* **Sound** — speaker-peripheral-driven chimes, clicks, warnings,
  start-up jingle.

## Hardware requirements

* Minecraft 1.21.1 or later (1.20.1 with older Forge may also work; check
  CC:Graphics release notes).
* ComputerCraft: Tweaked 1.117 or later (earlier versions are missing
  some `term.drawPixels` / batching edge cases that CC:Graphics relies
  on).
* [CC:Graphics](https://modrinth.com/mod/cc-graphics) installed.
* An **advanced computer**. Pocket and normal computers also work but
  are too small for the desktop. The OS auto-adapts.

To run a pocket / normal computer, set `display.graphicsMode = 1` in
`os/config.lua` (16-color mode is faster but visually flatter).

## Installation

See [INSTALL.md](./INSTALL.md) for full step-by-step instructions.

Quick steps:

1. Install CC:Tweaked + CC:Graphics (Fabric / NeoForge on Minecraft
   1.21.1+).
2. Place the contents of this folder on an advanced computer
   (`startup`, `os/`).
3. Right-click the computer → *Boot*. Qalcom OS should boot to the
   login screen automatically.

The first time the OS boots it creates a default user named **`admin`**
with the password **`admin`** (change it after logging in!).

## File map

```
/startup                   autorun bootstrap (require wrapper + splash crash handler)
/os/run.lua                kernel entry point
/os/boot.lua               first splash + step status
/os/login.lua              login UI
/os/session.lua            main session loop after login
/os/theme.lua              color palette + design tokens
/os/config.lua             graphics mode, paths, theme config
/os/gfx.lua                drawing API for CC:Graphics (term.setPixel/drawPixels)
/os/font.lua               5x7 bitmap font (ASCII 32..126)
/os/input.lua              unified event pump
/os/text.lua               text measurement / wrapping
/os/fsutil.lua             filesystem helpers
/os/auth.lua               user accounts + hashed passwords
/os/sound.lua              PC speaker beeps / chime
/os/notifications.lua      toast stack
/os/programs.lua           app registry
/os/wm.lua                 window manager
/os/taskbar.lua            bottom taskbar
/os/startmenu.lua          popup start menu
/os/desktop.lua            wallpaper + desktop icons
/os/apps/explorer.lua      file explorer
/os/apps/taskmgr.lua       task manager
/os/apps/notepad.lua       text editor
/os/apps/clockapp.lua      clock
/os/apps/calculator.lua    calculator
/os/apps/paint.lua         paint
/os/apps/settings.lua      settings panel
/os/apps/about.lua         about Qalcom OS
/users/admin.lua           user account (created on first boot)
/home/admin/               user home directory (created on first login)
/os/data/                  misc OS state (boot.log, boot_error.log, etc.)
INSTALL.md                 install guide
README.md                  this file
LICENSE                    MIT License
```

## Tech reference

### Resolution

The OS targets CC:Graphics **mode 2** by default. On a vanilla advanced
computer this renders as approximately **306 × 171 pixels** = the
default term `getSize()` (51 × 19 cells) × 6 × 9 px-per-cell.

Configure it in `os/config.lua`:

```lua
M.display = {
    graphicsMode = 2,   -- 1 = 16-color, 2 = 256-color. Default = 2.
}
```

Set to `1` if you want to drop to 16-color mode for slightly faster
pixels and a flatter look (good for kiosk / pocket computers).

Color depth adaptation happens at runtime: every `{r,g,b}` is mapped to
the nearest palette entry via squared-Euclidean distance, with the
result cached per color so subsequent draws are constant-time.

### Mouse / keyboard

The graphics surface emits standard CC: `mouse_click`, `mouse_drag`,
`mouse_up`, and `mouse_move` events with pixel coordinates. `os/input.lua`
normalises them into a single event table the window manager consumes.

### Frame model

The window manager redraws only when state changes (drag, focus,
click, notification…) — no busy 30 Hz loop. When it does draw, the
kernel wraps the frame in `term.setFrozen(true)` … `term.setFrozen(false)`
so all pixels hit the screen in a single instant rather than flickering
in.

## Known limitations

* No real CPU / memory accounting — the Task Manager shows a
  placeholder bar; consider extending it for real usage.
* File Explorer does not recurse into subdirectories in its grid view
  (the path is clickable to navigate).
* Notifications don't currently fade in/out — they just appear and
  vanish.
* Text rendering uses a 5×7 bitmap font to avoid OCR-style font lookups
  in CC:T's font cache. At scale 2 (default) you get ~21-character-wide
  buttons and readable title bars; the desktop text is small but works.

## License

MIT — see [LICENSE](./LICENSE).
