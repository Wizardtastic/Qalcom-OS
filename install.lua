--[[ Qalcom OS installer ------------------------------------------------------
    Run on a ComputerCraft:Tweaked computer:

        wget https://raw.githubusercontent.com/Wizardtastic/Qalcom-OS/main/install.lua install
        install

    or via pastebin:

        pastebin get <code> install
        install

    Walks through a component picker (core is always installed; the networking
    and CBC "war" packs are optional), downloads the selected files, and reboots
    into the existing Qalcom account / login screen. User data under
    /qalcom/data and /qalcom/logs is preserved across reinstalls.
------------------------------------------------------------------------------]]

-- === Where to fetch from ====================================================
local REPO_USER   = "Wizardtastic"
local REPO_NAME   = "Qalcom-OS"
local REPO_BRANCH = "main"
-- "dist" installs the minified build; set to "" to install the full source.
local SOURCE_SUBDIR = "dist"

local BASE_URL = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(REPO_USER, REPO_NAME, REPO_BRANCH)
if SOURCE_SUBDIR ~= "" then BASE_URL = BASE_URL .. SOURCE_SUBDIR .. "/" end

-- === File manifest (paths are relative to the computer root) ================
local CORE = {
    "startup.lua",
    "qalcom/version.lua",
    "qalcom/kernel/init.lua",
    "qalcom/apps/account.lua", "qalcom/apps/calculator.lua", "qalcom/apps/capabilities.lua",
    "qalcom/apps/control.lua", "qalcom/apps/diagnostics.lua", "qalcom/apps/dialog.lua",
    "qalcom/apps/editor.lua", "qalcom/apps/explorer.lua", "qalcom/apps/fluent.lua",
    "qalcom/apps/logs.lua", "qalcom/apps/peripherals.lua", "qalcom/apps/recovery.lua",
    "qalcom/apps/settings.lua", "qalcom/apps/telemetry.lua", "qalcom/apps/terminal.lua",
    "qalcom/lib/auth.lua", "qalcom/lib/calculator.lua", "qalcom/lib/capabilities.lua",
    "qalcom/lib/config.lua", "qalcom/lib/managed.lua", "qalcom/lib/peripherals.lua",
    "qalcom/lib/pure.lua", "qalcom/lib/roles.lua", "qalcom/lib/system.lua",
    "qalcom/lib/telemetry.lua", "qalcom/lib/ui.lua",
    "qalcom/lib/ui/animation.lua", "qalcom/lib/ui/canvas.lua", "qalcom/lib/ui/display.lua",
    "qalcom/lib/ui/hit.lua", "qalcom/lib/ui/palette.lua", "qalcom/lib/ui/pixel_palette.lua",
    "qalcom/lib/ui/pixelfont.lua", "qalcom/lib/ui/screen.lua",
}
local NETWORK = {
    "qalcom/apps/network.lua", "qalcom/apps/network_service.lua",
    "qalcom/lib/network.lua", "qalcom/lib/protocol.lua",
    "qalcom/lib/nodes.lua", "qalcom/lib/crypto.lua",
}
local WAR = {
    "qalcom/apps/cannon.lua", "qalcom/lib/cannon.lua",
}

-- Program directories wiped before a fresh write so stale/omitted files do not
-- linger. Everything else under /qalcom (data, logs) is left untouched.
local PROGRAM_DIRS  = { "/qalcom/kernel", "/qalcom/lib", "/qalcom/apps" }
local PROGRAM_FILES = { "/qalcom/version.lua", "/startup.lua" }

-- === Terminal helpers =======================================================
local W, H = term.getSize()
local color = term.isColor()

local COL = {
    bg      = color and colors.black    or colors.black,
    bar     = color and colors.blue     or colors.white,
    barText = color and colors.white    or colors.black,
    title   = color and colors.cyan     or colors.white,
    text    = color and colors.white    or colors.white,
    dim     = color and colors.lightGray or colors.white,
    on      = color and colors.lime     or colors.white,
    off     = color and colors.gray     or colors.white,
    accent  = color and colors.yellow   or colors.white,
    ok      = color and colors.lime     or colors.white,
    err     = color and colors.red      or colors.white,
}

local function c(fg, bg)
    term.setTextColor(fg or COL.text)
    term.setBackgroundColor(bg or COL.bg)
end

local function clear()
    term.setBackgroundColor(COL.bg)
    term.clear()
    term.setCursorPos(1, 1)
end

local function at(x, y, text, fg, bg)
    c(fg, bg)
    term.setCursorPos(x, y)
    term.write(text)
end

local function center(y, text, fg, bg)
    local x = math.max(1, math.floor((W - #text) / 2) + 1)
    at(x, y, text, fg, bg)
end

local function header(subtitle)
    clear()
    term.setBackgroundColor(COL.bar)
    term.setTextColor(COL.barText)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write("Qalcom OS  Installer")
    if subtitle then
        local s = subtitle
        term.setCursorPos(math.max(2, W - #s), 1)
        term.write(s)
    end
    c(COL.text, COL.bg)
end

local function footer(text)
    at(2, H, text, COL.dim, COL.bg)
end

-- === Screens ================================================================

local function screenWelcome()
    header()
    center(3, "Qalcom OS", COL.title)
    center(4, "a Lua desktop for CC:Tweaked", COL.dim)
    local y = 6
    local lines = {
        "This will install Qalcom OS onto this computer.",
        "",
        "You can choose to leave out two optional packs:",
        "  - Network apps  (authenticated modem transport)",
        "  - War apps      (CBC Fire Control)",
        "",
        "Existing accounts and settings are preserved.",
    }
    for _, line in ipairs(lines) do
        local hl = (line:find("Network") or line:find("War")) and COL.accent or COL.text
        at(4, y, line, hl)
        y = y + 1
    end
    footer("enter  continue        q  quit")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter or key == keys.numPadEnter then return true end
        if key == keys.q then return false end
    end
end

-- Component picker (toggle screen). Returns installNetwork, installWar or nil if quit.
local function screenSelect()
    local wantNetwork, wantWar = true, true
    -- focusable rows: 1 = network, 2 = war, 3 = install
    local focus = 3
    local ROWS = 3

    local function draw()
        header()
        at(3, 3, "Choose components, then install:", COL.text)

        at(4, 5, "[#]", COL.dim)
        at(8, 5, "Core system", COL.text)
        if W >= 46 then at(W - 12, 5, "required", COL.dim) end

        local function toggleRow(y, on, label, note, focused)
            local box = on and "[x]" or "[ ]"
            at(4, y, box, on and COL.on or COL.off)
            at(8, y, label, focused and COL.accent or COL.text)
            if W >= 46 then at(W - 1 - #note, y, note, COL.dim) end
            at(2, y, focused and ">" or " ", COL.accent)
        end
        toggleRow(6, wantNetwork, "Network apps", "modem / rednet", focus == 1)
        toggleRow(7, wantWar, "War apps (CBC Fire Control)", "aim / fire", focus == 2)

        at(2, 9, focus == 3 and ">" or " ", COL.accent)
        at(4, 9, "Install", focus == 3 and COL.accent or COL.text)

        footer("up/down move   space toggle   enter select   q quit")
    end

    while true do
        draw()
        local _, key = os.pullEvent("key")
        if key == keys.up then
            focus = (focus - 2) % ROWS + 1
        elseif key == keys.down then
            focus = focus % ROWS + 1
        elseif key == keys.space then
            if focus == 1 then wantNetwork = not wantNetwork
            elseif focus == 2 then wantWar = not wantWar end
        elseif key == keys.enter or key == keys.numPadEnter then
            if focus == 1 then wantNetwork = not wantNetwork
            elseif focus == 2 then wantWar = not wantWar
            else return wantNetwork, wantWar end
        elseif key == keys.q then
            return nil
        end
    end
end

local function buildFileList(wantNetwork, wantWar)
    local files = {}
    for _, f in ipairs(CORE) do files[#files + 1] = f end
    if wantNetwork then for _, f in ipairs(NETWORK) do files[#files + 1] = f end end
    if wantWar then for _, f in ipairs(WAR) do files[#files + 1] = f end end
    return files
end

local function screenConfirm(wantNetwork, wantWar, count)
    header()
    at(3, 3, "Ready to install:", COL.text)
    at(4, 5, "Core system", COL.text)
    at(24, 5, "yes", COL.on)
    at(4, 6, "Network apps", COL.text)
    at(24, 6, wantNetwork and "yes" or "no", wantNetwork and COL.on or COL.off)
    at(4, 7, "War apps (CBC)", COL.text)
    at(24, 7, wantWar and "yes" or "no", wantWar and COL.on or COL.off)
    at(3, 9, count .. " files will be downloaded from GitHub.", COL.dim)
    at(3, 10, "Program files are replaced; your data is kept.", COL.dim)
    footer("enter  install now       q  back")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter or key == keys.numPadEnter then return true end
        if key == keys.q then return false end
    end
end

-- === Networking / filesystem ================================================

local function fetch(url)
    if not http then return nil, "HTTP API is disabled on this computer" end
    local handle, err = http.get(url)
    if not handle then return nil, tostring(err or "connection failed") end
    local code = handle.getResponseCode and handle.getResponseCode() or 200
    local data = handle.readAll()
    handle.close()
    if code and code ~= 200 then return nil, "HTTP " .. tostring(code) end
    if not data or #data == 0 then return nil, "empty response" end
    return data
end

local function writeFile(path, data)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and dir ~= "/" then fs.makeDir(dir) end
    local f, err = fs.open(path, "w")
    if not f then return false, tostring(err or "cannot open for writing") end
    f.write(data)
    f.close()
    return true
end

local function cleanProgram()
    for _, dir in ipairs(PROGRAM_DIRS) do
        if fs.exists(dir) then fs.delete(dir) end
    end
    for _, file in ipairs(PROGRAM_FILES) do
        if fs.exists(file) then fs.delete(file) end
    end
end

local function progressBar(y, done, total, label)
    local barW = W - 6
    local filled = math.floor(barW * done / total)
    at(3, y, "[", COL.dim)
    term.setCursorPos(4, y)
    term.setBackgroundColor(COL.bg)
    term.setTextColor(COL.on)
    term.write(string.rep("=", filled))
    term.setTextColor(COL.off)
    term.write(string.rep("-", barW - filled))
    at(4 + barW, y, "]", COL.dim)
    local pct = math.floor(100 * done / total)
    center(y + 1, ("%d%%   (%d / %d)"):format(pct, done, total), COL.text)
    -- clear + write current label line
    term.setCursorPos(1, y + 3)
    term.setBackgroundColor(COL.bg)
    term.clearLine()
    center(y + 3, label, COL.dim)
end

local function screenInstall(files)
    header()
    center(3, "Installing Qalcom OS", COL.title)
    cleanProgram()
    local total = #files
    for i, rel in ipairs(files) do
        progressBar(6, i - 1, total, rel)
        local url = BASE_URL .. rel
        local data, err = fetch(url)
        if not data then
            -- one retry, then abort
            data, err = fetch(url)
        end
        if not data then
            return false, ("Failed on %s\n%s"):format(rel, tostring(err))
        end
        local ok, werr = writeFile("/" .. rel, data)
        if not ok then
            return false, ("Could not write /%s\n%s"):format(rel, tostring(werr))
        end
        progressBar(6, i, total, rel)
    end
    return true
end

local function screenError(message)
    header()
    center(3, "Installation failed", COL.err)
    local y = 5
    for line in (tostring(message) .. "\n"):gmatch("(.-)\n") do
        at(3, y, line:sub(1, W - 4), COL.text)
        y = y + 1
    end
    at(3, y + 1, "Nothing was left half-running; fix the issue", COL.dim)
    at(3, y + 2, "and run the installer again.", COL.dim)
    footer("enter  exit")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter or key == keys.numPadEnter or key == keys.q then return end
    end
end

local function screenDone()
    header()
    center(3, "Qalcom OS installed", COL.ok)
    center(5, "Reboot to create your account and sign in.", COL.text)
    center(7, "The first boot walks you through creating", COL.dim)
    center(8, "the local administrator account.", COL.dim)
    footer("enter  reboot now       q  exit to shell")
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter or key == keys.numPadEnter then
            os.reboot()
            return
        elseif key == keys.q then
            clear()
            print("Qalcom OS is installed. Run 'reboot' when ready.")
            return
        end
    end
end

-- === Main ===================================================================

local function main()
    if not http then
        header()
        center(3, "HTTP is required", COL.err)
        center(5, "Enable the http API in the CC:Tweaked config", COL.text)
        center(6, "(http.enabled = true), then run the installer again.", COL.text)
        footer("enter  exit")
        os.pullEvent("key")
        clear()
        return
    end

    if not screenWelcome() then clear(); return end

    while true do
        local wantNetwork, wantWar = screenSelect()
        if wantNetwork == nil then clear(); return end

        local files = buildFileList(wantNetwork, wantWar)
        if screenConfirm(wantNetwork, wantWar, #files) then
            local ok, err = screenInstall(files)
            if ok then
                screenDone()
            else
                screenError(err)
            end
            return
        end
        -- otherwise loop back to the selector
    end
end

local ok, err = pcall(main)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
if not ok then
    term.setCursorPos(1, H)
    print("\nInstaller error: " .. tostring(err))
end
