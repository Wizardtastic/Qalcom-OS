--[[ Build descriptor for the "Hello" example package.
    Package it with:  pack examples/hello/build.lua hello.qpkg
    Every file under `source` is embedded and installed to
    /qalcom/pkg/<app>/<relative-path>. See PACKAGING.md for the full reference. ]]

return {
    -- Identity (required)
    id = "com.example.hello",     -- reverse-DNS, unique per package
    name = "Hello",               -- display name
    version = "1.0.0",            -- dotted numeric; bump to publish updates
    app = "hello",                -- internal name + quarantine dir (/qalcom/pkg/hello)
    source = "src",               -- folder (relative to this file) holding main.lua

    -- Presentation (optional but recommended)
    publisher = "Example",
    summary = "A minimal Qalcom package example.",
    description = "A tiny app that greets you.\nCopy this folder as a template for your own Software Center packages.",
    category = "Tools",
    icon = "Hi",                  -- 1-2 char launcher/taskbar glyph
    window = { title = "Hello", icon = "Hi", width = 40, height = 14 },

    -- Behaviour (optional)
    kind = "app",                 -- "app" (launchable) or "pack" (files only)
    launcher = true,              -- show a launcher tile
    requires = { minOs = "0.5.0" },
    capabilities = {},            -- only fs.read, fs.write, telemetry.read, peripheral.read are allowed
}
