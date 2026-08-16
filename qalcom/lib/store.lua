--[[ Qalcom Software Center logic ----------------------------------------------
    Pure, side-effect-free helpers for the Software Center app. This module owns
    the Qalcom Package (`.qpkg`) contract: decoding, validation, payload
    checksums, install-path allow-listing, the installed-package registry
    (`/qalcom/data/packages.meta`), and install/remove planning.

    Everything here except `Store.decode` / `Store.encode` (which touch the CC:T
    `textutils` API) is plain Lua so it can be exercised by tests/pure_test.lua
    under a bare Lua 5.1 interpreter. Validation always operates on an
    already-decoded table, so the interesting logic stays testable.
------------------------------------------------------------------------------]]

local Store = {}

-- Highest `.qpkg` schema this build understands. Manifests may declare an equal
-- or lower version; newer ones are refused rather than guessed at.
Store.schemaVersion = 1

-- Bounds. Pastebin's free tier caps a paste near 512 KiB and serialized Lua
-- adds overhead, so the embedded single-file model is sized for apps, not full
-- multi-file OS images (those want the future multi-part format).
Store.maxFiles       = 64
Store.maxFileBytes   = 262144   -- 256 KiB per file
Store.maxPayloadBytes = 512000  -- ~500 KiB total decoded payload
Store.kinds = { app = true, ["os-update"] = true, pack = true }

-- Capabilities a downloaded, launchable app may request. Deliberately narrow:
-- even with the operator's consent at the confirm screen, an installed package
-- must never be able to fire cannons, reboot the machine, manage accounts,
-- reach the network transport, or exfiltrate over HTTP. Anything outside this
-- set fails validation. (content.fetch is intentionally excluded.)
Store.installableCapabilities = {
    ["fs.read"] = true,
    ["fs.write"] = true,
    ["telemetry.read"] = true,
    ["peripheral.read"] = true,
}

-- Third-party packages are quarantined here. Their files may not live anywhere
-- else (only an explicit os-update may touch system paths), so a package can
-- never overwrite a trusted, kernel-loaded module or a built-in app file. The
-- launchable entry point is always <packageRoot><app>/main.lua.
Store.packageRoot = "/qalcom/pkg/"

-- Built-in app names an installed package may not claim, for a friendly error
-- (the kernel additionally refuses to override any existing app at merge time).
Store.reservedApps = {
    terminal = true, explorer = true, settings = true, account = true, editor = true,
    dialog = true, control = true, logs = true, recovery = true, diagnostics = true,
    capabilities = true, peripherals = true, calculator = true, network = true,
    telemetry = true, network_service = true, cannon = true, fluent = true, store = true,
}

-- Files/trees the store refuses to touch unless the package is an explicit
-- OS update AND the operator confirms the extra warning. Covers the boot loader,
-- the kernel, every trusted library, the built-in apps, the version marker, and
-- user data/logs -- everything the kernel dofile()s at boot with full globals.
Store.protectedRoots = {
    "/startup.lua", "/qalcom/kernel", "/qalcom/lib", "/qalcom/apps",
    "/qalcom/version.lua", "/qalcom/data", "/qalcom/logs",
}

-- === Dependency loading =====================================================
-- Load sibling modules through candidate paths so this file works both on a
-- CC:T computer (absolute /qalcom paths) and from the repo root under the pure
-- test harness (relative paths). Mirrors capabilities.lua's loader.
local function loadModule(name)
    local candidates = {
        "qalcom/lib/" .. name,
        "../qalcom/lib/" .. name,
        "/qalcom/lib/" .. name,
    }
    for _, path in ipairs(candidates) do
        local ok, module = pcall(dofile, path)
        if ok and type(module) == "table" then return module end
    end
    return nil
end

local Pure = loadModule("pure.lua")
-- Crypto is optional at load time (it lives in the networking pack today; the
-- installer is expected to promote it into CORE). When it is missing the store
-- still works but cannot verify checksums, and says so.
local Crypto = loadModule("crypto.lua")
Store.cryptoAvailable = Crypto ~= nil

-- Minimal, dependency-free path normalizer used when Pure is somehow absent.
local function normalizePath(path)
    if Pure and Pure.normalizePath then return Pure.normalizePath(path) end
    local result = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        if part == ".." then
            if #result > 0 then table.remove(result) end
        elseif part ~= "." and part ~= "" then
            result[#result + 1] = part
        end
    end
    if #result == 0 then return "/" end
    return "/" .. table.concat(result, "/")
end

local function absolutePath(base, path)
    if Pure and Pure.absolutePath then return Pure.absolutePath(base, path) end
    path = tostring(path or "")
    if path:sub(1, 1) == "/" then return normalizePath(path) end
    return normalizePath(tostring(base or "/") .. "/" .. path)
end

-- === Small utilities ========================================================

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- === Checksums ==============================================================

-- Deterministic serialization of a payload map (path -> content). Sorting by
-- path makes the digest independent of table iteration order so publisher and
-- installer agree.
function Store.canonicalPayload(payload)
    if type(payload) ~= "table" then return "" end
    local parts = {}
    for _, path in ipairs(sortedKeys(payload)) do
        parts[#parts + 1] = path
        parts[#parts + 1] = "\0"
        parts[#parts + 1] = tostring(payload[path] or "")
        parts[#parts + 1] = "\0"
    end
    return table.concat(parts)
end

-- Hex SHA-256 of the canonical payload, or nil when crypto is unavailable.
function Store.checksum(payload)
    if not Crypto then return nil, "crypto unavailable" end
    return Crypto.hex(Crypto.sha256(Store.canonicalPayload(payload)))
end

-- === Version comparison =====================================================

local function versionParts(version)
    local parts = {}
    for chunk in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(chunk) or 0
    end
    return parts
end

-- Returns -1, 0, or 1 for a < b, a == b, a > b using dotted numeric segments.
function Store.compareVersions(a, b)
    local pa, pb = versionParts(a), versionParts(b)
    local count = math.max(#pa, #pb)
    for index = 1, count do
        local left = pa[index] or 0
        local right = pb[index] or 0
        if left < right then return -1 end
        if left > right then return 1 end
    end
    return 0
end

-- === Install-path safety ====================================================

function Store.isProtectedPath(absPath)
    local normalized = normalizePath(absPath)
    for _, root in ipairs(Store.protectedRoots) do
        local rootNormalized = normalizePath(root)
        if normalized == rootNormalized or normalized:sub(1, #rootNormalized + 1) == rootNormalized .. "/" then
            return true
        end
    end
    return false
end

-- Resolve a payload-relative path against the package root, refusing anything
-- that is absolute, escapes the root via "..", or is empty. Returns the
-- absolute path, or nil plus a reason.
function Store.resolveInstallPath(root, rel)
    if not isNonEmptyString(rel) then return nil, "empty file path" end
    if rel:sub(1, 1) == "/" then return nil, "absolute path not allowed: " .. rel end
    for segment in rel:gmatch("[^/]+") do
        if segment == ".." then return nil, "path escapes package root: " .. rel end
    end
    local base = normalizePath(root or "/")
    local abs = absolutePath(base, rel)
    local prefix = base == "/" and "/" or (base .. "/")
    if abs ~= base and abs:sub(1, #prefix) ~= prefix then
        return nil, "path escapes package root: " .. rel
    end
    return abs
end

-- === Manifest validation ====================================================

local function fail(reason)
    return { ok = false, reason = reason }
end

-- Validate an already-decoded manifest table. On success returns a descriptor
-- with resolved files (rel/abs/size/content), totals, checksum status, and the
-- passthrough metadata the UI and planner need.
function Store.validate(manifest, options)
    options = options or {}
    if type(manifest) ~= "table" then return fail("package is not a table") end

    local schema = tonumber(manifest.qpkg)
    if not schema then return fail("missing package schema version") end
    if schema > Store.schemaVersion then return fail("unsupported package schema " .. tostring(schema)) end

    if not isNonEmptyString(manifest.id) then return fail("missing package id") end
    if manifest.id:match("^[%w%.%-_]+$") == nil then return fail("invalid package id: " .. manifest.id) end
    if not isNonEmptyString(manifest.name) then return fail("missing package name") end
    if not isNonEmptyString(manifest.version) then return fail("missing package version") end

    local kind = manifest.kind or "app"
    if not Store.kinds[kind] then return fail("unknown package kind: " .. tostring(kind)) end

    local install = manifest.install
    if type(install) ~= "table" then return fail("missing install section") end
    if type(install.files) ~= "table" or #install.files == 0 then return fail("package declares no files") end

    local payload = manifest.payload
    if type(payload) ~= "table" then return fail("missing payload") end

    local root = install.root or "/"
    local allowProtected = kind == "os-update"

    -- Resolve every declared file and pair it with its payload content.
    local files = {}
    local declared = {}
    local totalBytes = 0
    for index, entry in ipairs(install.files) do
        if type(entry) ~= "table" or not isNonEmptyString(entry.path) then
            return fail("malformed file entry #" .. index)
        end
        local rel = entry.path
        if declared[rel] then return fail("duplicate file entry: " .. rel) end
        declared[rel] = true

        local abs, reason = Store.resolveInstallPath(root, rel)
        if not abs then return fail(reason) end
        if Store.isProtectedPath(abs) and not allowProtected then
            return fail("file targets a protected system path: " .. abs)
        end
        -- Everything but an explicit os-update is quarantined under packageRoot,
        -- so a package can never place a file where the kernel would trust it.
        if not allowProtected and abs:sub(1, #Store.packageRoot) ~= Store.packageRoot then
            return fail("installed files must live under " .. Store.packageRoot .. ": " .. abs)
        end

        local content = payload[rel]
        if type(content) ~= "string" then return fail("payload missing content for " .. rel) end
        local size = #content
        if size > Store.maxFileBytes then return fail("file exceeds size limit: " .. rel) end
        totalBytes = totalBytes + size

        files[#files + 1] = { rel = rel, path = abs, size = size, content = content }
    end

    -- Security: refuse any payload entry that was not declared in install.files
    -- so a package cannot smuggle in files the confirm screen never listed.
    for path in pairs(payload) do
        if not declared[path] then return fail("payload contains undeclared file: " .. tostring(path)) end
    end

    if #files > Store.maxFiles then return fail("package exceeds file-count limit") end
    if totalBytes > Store.maxPayloadBytes then return fail("package exceeds total size limit") end

    -- Integrity: a checksum is mandatory under the confirm+checksum trust model.
    local integrity = manifest.integrity
    if type(integrity) ~= "table" or not isNonEmptyString(integrity.payload) then
        return fail("missing integrity checksum")
    end
    if integrity.algo and integrity.algo ~= "sha256" then
        return fail("unsupported checksum algorithm: " .. tostring(integrity.algo))
    end

    local integrityChecked = false
    local warnings = {}
    if Crypto then
        local computed = Store.checksum(payload)
        if computed ~= integrity.payload then
            return fail("checksum mismatch")
        end
        integrityChecked = true
    elseif not options.skipChecksumWarning then
        warnings[#warnings + 1] = "checksum not verified (crypto unavailable)"
    end

    -- Every non-os-update package is held to the installable-capability
    -- allow-list, whether or not it registers a launchable app, so a "pack" can
    -- never request something a launchable app could not.
    if not allowProtected then
        for _, capability in ipairs(manifest.capabilities or {}) do
            if not Store.installableCapabilities[capability] then
                return fail("capability not allowed for installed apps: " .. tostring(capability))
            end
        end
    end

    -- A launchable app must name itself (not shadowing a built-in) and ship its
    -- quarantined entry file at <packageRoot><app>/main.lua.
    local register = install.register
    if register ~= nil then
        if type(register) ~= "table" or not isNonEmptyString(register.app) then
            return fail("register block missing app name")
        end
        if register.app:match("^[%w_]+$") == nil then
            return fail("invalid app name: " .. tostring(register.app))
        end
        if Store.reservedApps[register.app] then
            return fail("app name is reserved: " .. register.app)
        end
        local mainPath = Store.packageRoot .. register.app .. "/main.lua"
        local hasMain = false
        for _, file in ipairs(files) do
            if file.path == mainPath then hasMain = true break end
        end
        if not hasMain then return fail("register app has no matching file: " .. mainPath) end
    end

    return {
        ok = true,
        id = manifest.id,
        name = manifest.name,
        version = manifest.version,
        publisher = manifest.publisher or "Unknown",
        summary = manifest.summary,
        description = manifest.description,
        category = manifest.category or (install.register and install.register.category) or "Apps",
        kind = kind,
        icon = manifest.icon,
        logo = manifest.logo,
        requires = manifest.requires or {},
        capabilities = manifest.capabilities or {},
        register = install.register,
        root = root,
        files = files,
        fileCount = #files,
        totalBytes = totalBytes,
        checksum = integrity.payload,
        integrityChecked = integrityChecked,
        warnings = warnings,
    }
end

-- Compare a descriptor's minimum-OS requirement against the running version.
function Store.meetsRequirements(descriptor, currentVersion)
    local minOs = descriptor and descriptor.requires and descriptor.requires.minOs
    if not isNonEmptyString(minOs) then return true end
    return Store.compareVersions(currentVersion, minOs) >= 0
end

-- === Installed-package registry (/qalcom/data/packages.meta) =================
-- Line-based, textutils-free format so it round-trips under the pure test
-- harness, following network.lua's serializeState/parseState convention.

local function escape(value)
    return tostring(value or ""):gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("[\r\n]", " ")
end

local function unescape(value)
    return (tostring(value or ""):gsub("\\(.)", function(character)
        if character == "p" then return "|" end
        if character == "\\" then return "\\" end
        return character
    end))
end

local function splitFields(line)
    local fields = {}
    for field in (line .. "|"):gmatch("(.-)|") do
        fields[#fields + 1] = unescape(field)
    end
    return fields
end

function Store.newRegistry()
    return { schemaVersion = Store.schemaVersion, packages = {} }
end

function Store.parseRegistry(text)
    local registry = Store.newRegistry()
    local source = tostring(text or "")
    if source == "" then return registry end
    for line in (source .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = splitFields(line)
            local tag = fields[1]
            if tag == "schema" then
                registry.schemaVersion = tonumber(fields[2]) or registry.schemaVersion
            elseif tag == "pkg" and isNonEmptyString(fields[2]) then
                registry.packages[fields[2]] = {
                    id = fields[2],
                    version = fields[3] or "0",
                    installedAt = tonumber(fields[4]) or 0,
                    source = fields[5] or "",
                    category = fields[6] or "Apps",
                    kind = fields[7] or "app",
                    files = {},
                    capabilities = {},
                }
            elseif tag == "file" and isNonEmptyString(fields[2]) and isNonEmptyString(fields[3]) then
                local package = registry.packages[fields[2]]
                if package then package.files[#package.files + 1] = fields[3] end
            elseif tag == "reg" and isNonEmptyString(fields[2]) then
                local package = registry.packages[fields[2]]
                if package and isNonEmptyString(fields[3]) then
                    package.register = {
                        app = fields[3],
                        title = fields[4] ~= "" and fields[4] or nil,
                        icon = fields[5] ~= "" and fields[5] or nil,
                        width = tonumber(fields[6]),
                        height = tonumber(fields[7]),
                        category = fields[8] ~= "" and fields[8] or nil,
                        launcher = fields[9] ~= "0",
                    }
                end
            elseif tag == "cap" and isNonEmptyString(fields[2]) and isNonEmptyString(fields[3]) then
                local package = registry.packages[fields[2]]
                if package then
                    package.capabilities = package.capabilities or {}
                    package.capabilities[#package.capabilities + 1] = fields[3]
                end
            end
        end
    end
    if registry.schemaVersion ~= Store.schemaVersion then
        registry.error = "Unsupported package registry schema"
    end
    return registry
end

function Store.serializeRegistry(registry)
    registry = registry or Store.newRegistry()
    local lines = {
        "# Qalcom package registry schema " .. tostring(Store.schemaVersion),
        "schema|" .. tostring(Store.schemaVersion),
    }
    for _, id in ipairs(sortedKeys(registry.packages)) do
        local package = registry.packages[id]
        lines[#lines + 1] = table.concat({
            "pkg",
            escape(id),
            escape(package.version),
            tostring(math.floor(tonumber(package.installedAt) or 0)),
            escape(package.source),
            escape(package.category),
            escape(package.kind or "app"),
        }, "|")
        for _, path in ipairs(package.files or {}) do
            lines[#lines + 1] = "file|" .. escape(id) .. "|" .. escape(path)
        end
        local register = package.register
        if type(register) == "table" and isNonEmptyString(register.app) then
            lines[#lines + 1] = table.concat({
                "reg",
                escape(id),
                escape(register.app),
                escape(register.title or ""),
                escape(register.icon or ""),
                tostring(math.floor(tonumber(register.width) or 0)),
                tostring(math.floor(tonumber(register.height) or 0)),
                escape(register.category or ""),
                register.launcher == false and "0" or "1",
            }, "|")
        end
        for _, capability in ipairs(package.capabilities or {}) do
            lines[#lines + 1] = "cap|" .. escape(id) .. "|" .. escape(capability)
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- === Install / remove planning ==============================================

local ACTION_LABELS = {
    install = "Install",
    update = "Update",
    reinstall = "Reinstall",
    downgrade = "Downgrade",
    remove = "Remove",
    open = "Open",
}

function Store.actionLabel(action)
    return ACTION_LABELS[action] or "Install"
end

-- Given a validated descriptor and the current registry, decide the action and
-- the exact writes and stale deletions. Pure: callers perform the I/O.
function Store.planInstall(descriptor, registry)
    if not descriptor or not descriptor.ok then
        return { ok = false, reason = "package is not valid" }
    end
    registry = registry or Store.newRegistry()
    local previous = registry.packages and registry.packages[descriptor.id] or nil

    local action = "install"
    if previous then
        local comparison = Store.compareVersions(descriptor.version, previous.version)
        action = comparison > 0 and "update" or comparison == 0 and "reinstall" or "downgrade"
    end

    local writes = {}
    local newPaths = {}
    for _, file in ipairs(descriptor.files) do
        writes[#writes + 1] = { path = file.path, content = file.content }
        newPaths[file.path] = true
    end

    -- Files the previous version installed that this version no longer ships.
    local deletes = {}
    if previous then
        for _, path in ipairs(previous.files or {}) do
            if not newPaths[path] then deletes[#deletes + 1] = path end
        end
    end

    -- Reboot to finish when the desktop registry must pick up a new app or when
    -- system files changed.
    local reboot = descriptor.kind == "os-update" or descriptor.register ~= nil

    return {
        ok = true,
        action = action,
        id = descriptor.id,
        version = descriptor.version,
        previousVersion = previous and previous.version or nil,
        writes = writes,
        deletes = deletes,
        reboot = reboot,
    }
end

-- Produce the updated registry record for a completed install.
function Store.recordInstall(registry, descriptor, source, timestamp)
    registry = registry or Store.newRegistry()
    registry.packages = registry.packages or {}
    local paths = {}
    for _, file in ipairs(descriptor.files) do paths[#paths + 1] = file.path end
    local register = nil
    if type(descriptor.register) == "table" and isNonEmptyString(descriptor.register.app) then
        -- Accept metadata under register.meta (preferred) or directly on register.
        local reg = descriptor.register
        local meta = reg.meta or {}
        register = {
            app = reg.app,
            title = meta.title or reg.title,
            icon = meta.icon or reg.icon,
            width = meta.width or reg.width,
            height = meta.height or reg.height,
            category = reg.category,
            launcher = reg.launcher,
        }
    end
    local capabilities = {}
    for _, capability in ipairs(descriptor.capabilities or {}) do capabilities[#capabilities + 1] = capability end
    registry.packages[descriptor.id] = {
        id = descriptor.id,
        version = descriptor.version,
        installedAt = math.floor(tonumber(timestamp) or 0),
        source = source or "",
        category = descriptor.category,
        kind = descriptor.kind,
        files = paths,
        register = register,
        capabilities = capabilities,
    }
    return registry
end

-- Build the launcher/registry entries the kernel merges at boot for installed
-- apps. Only packages with a register block are launchable; capabilities are
-- filtered to the installable allow-list as a defence in depth. Pure: the
-- kernel does the actual table mutation and filesystem existence checks.
function Store.launcherEntries(registry)
    local entries = {}
    registry = registry or Store.newRegistry()
    for _, id in ipairs(sortedKeys(registry.packages or {})) do
        local package = registry.packages[id]
        local register = package.register
        if type(register) == "table" and isNonEmptyString(register.app)
            and register.app:match("^[%w_]+$") and not Store.reservedApps[register.app] then
            local capabilities = {}
            for _, capability in ipairs(package.capabilities or {}) do
                if Store.installableCapabilities[capability] then
                    capabilities[#capabilities + 1] = capability
                end
            end
            entries[#entries + 1] = {
                id = id,
                name = register.app,
                path = Store.packageRoot .. register.app .. "/main.lua",
                meta = {
                    title = register.title or register.app,
                    icon = register.icon or "?",
                    width = tonumber(register.width) or 40,
                    height = tonumber(register.height) or 18,
                },
                category = register.category or package.category or "Apps",
                launcher = register.launcher ~= false,
                capabilities = capabilities,
            }
        end
    end
    return entries
end

function Store.planRemove(id, registry)
    registry = registry or Store.newRegistry()
    local package = registry.packages and registry.packages[id] or nil
    if not package then return { ok = false, reason = "package not installed" } end
    local deletes = {}
    for _, path in ipairs(package.files or {}) do deletes[#deletes + 1] = path end
    return { ok = true, id = id, version = package.version, deletes = deletes }
end

function Store.removeRecord(registry, id)
    if registry and registry.packages then registry.packages[id] = nil end
    return registry
end

-- === Authoring ==============================================================

-- Assemble a complete manifest table from metadata plus a payload map
-- (targetPath -> content). Derives install.files from the payload, carries the
-- register block through, and computes the integrity checksum. Pure: the pack
-- tool feeds it files read from disk; callers should Store.validate the result
-- before publishing. `meta` fields: id, name, version, publisher, category,
-- kind, summary, description, requires, capabilities, icon, logo, root,
-- register.
function Store.assemble(meta, payload)
    meta = meta or {}
    payload = payload or {}
    local files = {}
    for _, path in ipairs(sortedKeys(payload)) do files[#files + 1] = { path = path } end
    local manifest = {
        qpkg = Store.schemaVersion,
        id = meta.id,
        name = meta.name,
        version = meta.version,
        publisher = meta.publisher,
        category = meta.category,
        kind = meta.kind or "app",
        summary = meta.summary,
        description = meta.description,
        requires = meta.requires,
        capabilities = meta.capabilities,
        icon = meta.icon,
        logo = meta.logo,
        install = {
            root = meta.root or "/",
            files = files,
            register = meta.register,
        },
        payload = payload,
    }
    manifest.integrity = { algo = "sha256", payload = Store.checksum(payload) }
    return manifest
end

-- === Runtime-only (textutils) encode/decode =================================
-- Kept thin and guarded so the pure logic above stays interpreter-agnostic.

-- Decode raw paste text into a manifest table. Guards against Pastebin throttle
-- / HTML error pages, which will not contain a `qpkg` field.
function Store.decode(text)
    if type(text) ~= "string" or text == "" then return nil, "no package data" end
    if not text:find("qpkg", 1, true) then return nil, "not a Qalcom package" end
    if type(textutils) ~= "table" or not textutils.unserialize then
        return nil, "textutils unavailable" end
    local ok, value = pcall(textutils.unserialize, text)
    if not ok or type(value) ~= "table" then return nil, "could not parse package" end
    return value
end

-- Serialize a manifest table for publishing (used by the pack tool). Fills in
-- the integrity checksum from the payload when possible.
function Store.encode(manifest)
    if type(manifest) ~= "table" then return nil, "manifest is not a table" end
    if type(textutils) ~= "table" or not textutils.serialize then
        return nil, "textutils unavailable" end
    manifest.qpkg = manifest.qpkg or Store.schemaVersion
    local checksum = Store.checksum(manifest.payload)
    if checksum then manifest.integrity = { algo = "sha256", payload = checksum } end
    return textutils.serialize(manifest)
end

return Store
