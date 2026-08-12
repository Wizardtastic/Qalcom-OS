local Display = {}

-- Runtime capability probe for the rendering track. Track A (Fluent text mode)
-- works everywhere; Track B (the 256-color CC:Graphics / CraftOS-PC compositor)
-- is only used when the graphics-mode API is actually present. Everything here
-- degrades silently to text mode so a plain CC:T computer is never broken.

local function hasFunction(name)
    return type(term) == "table" and type(term[name]) == "function"
end

function Display.supportsPalette()
    -- Palette remapping (Track A) needs only setPaletteColor. This is available
    -- on modern CC:T; older/stripped hosts fall back to the stock palette.
    return hasFunction("setPaletteColor")
end

function Display.supportsNativePalette()
    return hasFunction("nativePaletteColor")
end

function Display.supportsGraphics()
    -- 256-color graphics mode requires the CC:Graphics mod (or CraftOS-PC). We
    -- probe non-destructively: getGraphicsMode must succeed without switching.
    if not hasFunction("setGraphicsMode") or not hasFunction("getGraphicsMode") then
        return false
    end
    local ok = pcall(term.getGraphicsMode)
    return ok == true
end

function Display.mode()
    -- Coarse capability tier used to pick a rendering track.
    if Display.supportsGraphics() then return "graphics256" end
    if Display.supportsPalette() then return "text-fluent" end
    return "text"
end

function Display.textSize()
    if type(term) ~= "table" or type(term.getSize) ~= "function" then return nil end
    return term.getSize()
end

function Display.pixelSize()
    -- Pixel dimensions of graphics mode (6x wide, 9x tall the text size), read
    -- through the documented term.getSize(2) overload. nil when unsupported.
    if not Display.supportsGraphics() then return nil end
    local ok, w, h = pcall(term.getSize, 2)
    if ok and w and h then return w, h end
    return nil
end

return Display
