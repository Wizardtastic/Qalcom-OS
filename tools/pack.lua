--[[ Qalcom .qpkg packager -------------------------------------------------------
    Build a self-contained Qalcom package from a source folder, ready to publish
    on Pastebin. Runs on a CC:Tweaked computer or in CraftOS-PC (it needs the
    `fs` and `textutils` APIs).

        pack <build.lua> [output.qpkg]

    <build.lua> is a build descriptor (see PACKAGING.md) that returns a table of
    metadata plus the `app` name and `source` directory. Every file under the
    source directory is embedded and mapped to /qalcom/pkg/<app>/<relative-path>;
    an app's entry point must be <source>/main.lua.

    The tool validates the assembled package (schema, size bounds, path
    quarantine, capability allow-list, checksum) and refuses to write an invalid
    one, so a package that packs is a package that will install.
------------------------------------------------------------------------------]]

local function loadStore()
    local candidates = { "/qalcom/lib/store.lua", "qalcom/lib/store.lua", "../qalcom/lib/store.lua" }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    return nil
end

local function report(message)
    if printError then printError(message) else print(message) end
end

local function main(args)
    if type(fs) ~= "table" or type(textutils) ~= "table" then
        report("pack must run on CC:Tweaked / CraftOS-PC (needs fs + textutils).")
        return false
    end

    local Store = loadStore()
    if not Store then
        report("Cannot find qalcom/lib/store.lua. Install Qalcom or run from its tree.")
        return false
    end

    local buildArg = args[1]
    if not buildArg then
        print("Usage: pack <build.lua> [output.qpkg]")
        return false
    end

    local buildPath = (shell and shell.resolve and shell.resolve(buildArg)) or buildArg
    if not fs.exists(buildPath) then
        report("Build descriptor not found: " .. tostring(buildArg))
        return false
    end

    local ok, descriptor = pcall(dofile, buildPath)
    if not ok or type(descriptor) ~= "table" then
        report("Build descriptor did not return a table: " .. tostring(descriptor))
        return false
    end

    -- Required metadata.
    for _, field in ipairs({ "id", "name", "version", "app", "source" }) do
        if type(descriptor[field]) ~= "string" or descriptor[field] == "" then
            report("Build descriptor is missing '" .. field .. "'.")
            return false
        end
    end
    if descriptor.app:match("^[%w_]+$") == nil then
        report("app must be letters, digits, or underscores: " .. descriptor.app)
        return false
    end
    if Store.reservedApps[descriptor.app] then
        report("app name '" .. descriptor.app .. "' is reserved by a built-in.")
        return false
    end

    local kind = descriptor.kind or "app"
    local buildDir = fs.getDir(buildPath)
    local sourceDir = fs.combine(buildDir, descriptor.source)
    if not fs.exists(sourceDir) or not fs.isDir(sourceDir) then
        report("Source directory not found: " .. sourceDir)
        return false
    end
    if kind == "app" and not fs.exists(fs.combine(sourceDir, "main.lua")) then
        report("App packages need an entry file at " .. descriptor.source .. "/main.lua")
        return false
    end

    -- Embed every file under the source directory.
    local payload = {}
    local count = 0
    local function walk(directory, prefix)
        for _, name in ipairs(fs.list(directory)) do
            local full = fs.combine(directory, name)
            local rel = prefix == "" and name or (prefix .. "/" .. name)
            if fs.isDir(full) then
                walk(full, rel)
            else
                local handle = fs.open(full, "r")
                if not handle then report("Could not read " .. full); return false end
                local data = handle.readAll()
                handle.close()
                payload["qalcom/pkg/" .. descriptor.app .. "/" .. rel] = data or ""
                count = count + 1
            end
        end
        return true
    end
    if walk(sourceDir, "") == false then return false end
    if count == 0 then
        report("Source directory is empty: " .. sourceDir)
        return false
    end

    -- Register block for launchable apps.
    local register = nil
    if kind == "app" then
        register = {
            app = descriptor.app,
            meta = descriptor.window or { title = descriptor.name, icon = descriptor.icon },
            category = descriptor.category,
            launcher = descriptor.launcher ~= false,
        }
    end

    local manifest = Store.assemble({
        id = descriptor.id,
        name = descriptor.name,
        version = descriptor.version,
        publisher = descriptor.publisher,
        category = descriptor.category,
        kind = kind,
        summary = descriptor.summary,
        description = descriptor.description,
        requires = descriptor.requires,
        capabilities = descriptor.capabilities,
        icon = descriptor.icon,
        logo = descriptor.logo,
        register = register,
    }, payload)

    -- Validate exactly as the Software Center will before it installs.
    local result = Store.validate(manifest)
    if not result.ok then
        report("Package is invalid: " .. tostring(result.reason))
        return false
    end

    local serialized, encodeErr = Store.encode(manifest)
    if not serialized then
        report("Could not serialize package: " .. tostring(encodeErr))
        return false
    end

    local outPath = args[2] or (descriptor.app .. ".qpkg")
    outPath = (shell and shell.resolve and shell.resolve(outPath)) or outPath
    local out = fs.open(outPath, "w")
    if not out then report("Could not write " .. outPath); return false end
    out.write(serialized)
    out.close()

    print("Wrote " .. outPath)
    print(("%d file(s), %d bytes payload, %d bytes packaged")
        :format(result.fileCount, result.totalBytes, #serialized))
    if #serialized > 480000 then
        report("Warning: package is near Pastebin's ~512 KiB limit.")
    end
    print("")
    print("Publish:  pastebin put " .. fs.getName(outPath))
    print("Install:  in the Qalcom Terminal, run  get <code>")
    return true
end

local ok = main({ ... })
return ok
