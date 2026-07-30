# Installing Qalcom OS

Qalcom OS turns an **advanced ComputerCraft: Tweaked computer** into a
fully-graphical desktop using the **CC:Graphics** mod. No external
monitor stack, no GPU peripheral, no `pastebin get` dance — drop the
files and boot.

## 1. Mod prerequisites

* **Minecraft 1.21.1 or later** (1.20.1 may work on older CC:Graphics
  versions — check the mod page).
* **ComputerCraft: Tweaked 1.117+ or later**.
* **[CC:Graphics](https://modrinth.com/mod/cc-graphics/install)** —
  compatible with Fabric, Quilt, NeoForge, or Forge depending on which
  build you grab from the mod's release page.

Drop the CC:Graphics jar into your `mods/` folder alongside
ComputerCraft: Tweaked.

## 2. Place a computer

* Place a **Computer** or **Advanced Computer** block. The OS paints
  its UI directly on this block's screen — no monitor stack needed.
* (Optional) Place a **Speaker** block one block away for sound
  feedback.

## 3. Copy the OS files

Two ways:

### Option A — manual paste

1. Right-click the computer → *Open* → drop into the in-game terminal.
2. In each line below, run `pastebin put <code>  <path>`. After each
   pastebin `get`, type:

   ```lua
   pastebin get <your_code>  startup       -- /startup
   pastebin get <your_code>  os/run.lua    -- /os/run.lua
   …
   ```

3. **Easier:** create the files on your local machine and copy the
   whole folder onto a disk, then place the disk in a Disk Drive
   attached to the computer. Inside the game:

   ```lua
   cp /disk/* /
   ```

### Option B — single installer (when bundled)

If the OS ships an `install.lua` program, simply:

```lua
install
```

…and the program will fetch every OS file from the bundled disk or
pastebin and lay them out correctly.

## 4. Boot

Right-click the computer → *Boot*. Qalcom OS runs its boot splash and
then presents the **login** screen. Default user is `admin`, password
`admin`. **Change it** via Settings → Accounts after first login.

## 5. Troubleshooting

### Boot failure — red screen

If the computer only shows a red *QALCOM OS — BOOT FAILURE* wall, the
OS crashed before splash. The full traceback is dumped to
`/os/data/boot_error.log`. Press any key to scroll the traceback,
then `q` to drop to the shell and read:

```lua
type /os/data/boot_error.log
type /os/data/boot.log
```

The boot log shows the phase-by-phase progress (`run.lua: enter`,
`gfx.init ->`, `boot shown`, …). The last successful line tells you
which phase crashed.

### Boot failure — CC:Graphics not found

* Confirm the CC:Graphics jar is in `mods/` and you restarted Minecraft.
* Confirm CC:Tweaked is **1.117+**. Earlier versions are missing
  `term.setFrozen` and `term.drawPixels` which CC:Graphics relies on.
* If you want a hard requirement (so the OS stops instead of falling
  back to the cramped 51×19 text mode), set `display.requireGraphics =
  true` in `os/config.lua`.

### Login screen renders but text is unreadable

The CC:Graphics mode 2 palette has a steeper gamma curve than CraftOS
text. Try setting `display.graphicsMode = 1` for the 16-color
"Windows 95" aesthetic — text becomes chunkier but more contrasty.

### Apps are crashing, you see the term warning on each startup

`/os/data/boot.log` will have a `safeLoad FAILED` line pointing at
the broken app. The most common cause is a typo when pasting through
pastebin — copy the file directly if you can.

## Updating

Pull a new copy of the project, then overwrite the `os/` folder on
the computer. Don't forget a fresh `startup` and `os/run.lua`.

## Uninstalling

Just rename or delete `/startup`. The OS-specific files stay on disk
but won't be invoked.

## Going further (optional)

* Make `boot.lua` paint a custom splash image by editing the bitmap it
  ships. CC:Graphics mode 2 is a 256×171-ish canvas so a simple 1-bit
  dithered picture works.
* Want a full-screen wallpaper, no taskbar? Set
  `appearance.taskbarPosition = "hidden"` in `os/config.lua` (you can
  add that branch in `os/taskbar.lua` yourself).
* Want network drives visible in the File Explorer? Attach a Disk
  Drive / networking cable and the OS will see them; File Explorer
  lists all `*.fs` roots automatically.
