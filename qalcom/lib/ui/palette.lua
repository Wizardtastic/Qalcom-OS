local Pure = dofile("/qalcom/lib/pure.lua")

local Palette = {}

-- Owns the RGB definitions for the 16 CC:T base color slots and applies them
-- with term.setPaletteColor so a single theme can re-skin the whole OS at once
-- (every app draws through these 16 indices). All calls degrade to no-ops when
-- the palette API is missing, so a plain host keeps the stock palette.

-- The 16 base slots, in a stable order for snapshot/restore iteration.
Palette.slots = {
    colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray,
    colors.lightGray, colors.cyan, colors.purple, colors.blue,
    colors.brown, colors.green, colors.red, colors.black,
}

local function supported()
    return type(term) == "table" and type(term.setPaletteColor) == "function"
end

Palette.supported = supported

function Palette.channels(hex)
    return Pure.colorChannels(hex)
end

function Palette.snapshot()
    -- Capture the current RGB of every base slot so the exact pre-Qalcom
    -- palette can be put back on exit. Returns nil when unsupported.
    if not supported() or type(term.getPaletteColor) ~= "function" then return nil end
    local snap = {}
    for _, slot in ipairs(Palette.slots) do
        local ok, r, g, b = pcall(term.getPaletteColor, slot)
        if ok and r then snap[slot] = { r, g, b } end
    end
    return snap
end

function Palette.resetDefaults()
    -- Return the base slots to CC:T's stock palette. Used when a theme declares
    -- no custom palette (the Classic themes) so they render as originally designed.
    if not supported() or type(term.nativePaletteColor) ~= "function" then return false end
    for _, slot in ipairs(Palette.slots) do
        local ok, r, g, b = pcall(term.nativePaletteColor, slot)
        if ok and r then pcall(term.setPaletteColor, slot, r, g, b) end
    end
    return true
end

function Palette.restore(snap)
    -- Put back a snapshot captured by Palette.snapshot(); fall back to CC:T
    -- defaults when no snapshot is available.
    if not supported() then return false end
    if type(snap) == "table" then
        for slot, rgb in pairs(snap) do
            pcall(term.setPaletteColor, slot, rgb[1], rgb[2], rgb[3])
        end
        return true
    end
    return Palette.resetDefaults()
end

function Palette.apply(palette)
    -- palette maps a CC color index -> 0xRRGGBB integer. Missing slots are left
    -- untouched, so a theme need only override the slots it cares about.
    if not supported() or type(palette) ~= "table" then return false end
    for slot, hex in pairs(palette) do
        local r, g, b = Pure.colorChannels(hex)
        pcall(term.setPaletteColor, slot, r, g, b)
    end
    return true
end

return Palette
