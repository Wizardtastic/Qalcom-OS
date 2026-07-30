-- os/gfx.lua — drawing API for Qalcom OS, backed by **CC:Graphics** (CraftOS-PC
-- gfxmode port) on a ComputerCraft: Tweaked advanced computer.
--
-- Public API kept intentionally identical to the previous CC:DirectGPU
-- version so the apps don't have to change:
--   M.init({mode=2})              -> ok, msg (true if pixel surface enabled)
--   M.isDirectGPU()               -> alias -> M.isGpu() (true when graphics mode)
--   M.width() / M.height()        -> pixel dimensions
--   M.clear(r,g,b)
--   M.fillRect(x,y,w,h, col)      -- col: {r,g,b} | palette index | "transparent"
--   M.outlineRect(x,y,w,h, col, t)
--   M.fillRoundRect(x,y,w,h, r, col)
--   M.line(x1,y1,x2,y2, col)
--   M.pixel(x,y, col)
--   M.text(str, x, y, col, opts)  -- opts: {font, size, style}
--   M.textSize(str, opts) -> w, h
--   M.circle(cx, cy, r, col, filled)
--   M.gradient(x,y,w,h, c1, c2, dir)
--   M.shadow(x,y,w,h, offset, alpha)
--   M.startFrame() / M.endFrame() / M.flush()
--   M._stats()
--
-- Behavior:
--   * If term.setGraphicsMode is present (CC:Graphics installed), boot
--     into mode 2 (51×19 cells × 6×9 px = 306×171 px) by default, with
--     a 256-color palette.
--   * Colors from the OS theme (RGB triples {r,g,b}) are mapped to the
--     nearest palette entry by squared-Euclidean distance, with results
--     cached per unique RGB triple.
--   * Text is rendered with /os/font.lua (5x7 bitmap) pixel-by-pixel; this
--     is fast when wrapped in term.setFrozen(true)/setFrozen(false).
--   * If CC:Graphics is missing, we fall back to the standard term
--     51×19 character grid (caller decides which path the OS takes; the
--     desktop paints itself there too).

local M = {}

local term_native    -- stored handle to the unredirected computer term
local width, height  -- pixel canvas size (when in graphics mode) or cells
local isGpu          -- true when CC:Graphics is active
local frozen = false  -- tracks setFrozen state so caller doesn't have to

-- font module (loaded on first text() call, deferred to keep init crisp)
local font = nil

-- Palette mapping cache: key = string "r,g,b", value = 0..255 palette index
local rgbCache = {}

-- -------------------------------------------------------------------
-- Palette pre-bake (CraftOS-PC mode-2 256-color palette)
-- -------------------------------------------------------------------
local palette = {}  -- palette[i] = {r,g,b,kind}, kind: "std"|"cube"|"gray"

local STDCOLORS = {
    -- Roughly perceptual layout of the standard 16 CC colors
    -- (the mod remaps 0..15 internally; we pick any of these as target.)
    {240,240,240}, {255,170, 85}, {255, 85,255}, {170,170,255},
    {255,255, 85}, {170,255, 85}, {255,170,170}, {165,165,165},
    {255,255,255}, {170,255,255}, {255, 85,170}, { 85,170,255},
    {170, 85,  0}, { 85,255, 85}, {255, 85, 85}, {  0,  0,  0},
}
for i = 0, 15 do palette[#palette+1] = { STDCOLORS[i+1][1], STDCOLORS[i+1][2], STDCOLORS[i+1][3], "std" } end

-- RGB cube 16..231
local function cubeChannel(v5) -- v5 is 0..5, return level 0..255
    -- step size is 51 (255 / 5 = 51) for the first five stops, 255 for the last
    if v5 == 0 then return 0 end
    if v5 == 5 then return 255 end
    return v5 * 51
end
for r = 0, 5 do
    for g = 0, 5 do
        for b = 0, 5 do
            palette[#palette+1] = {
                cubeChannel(r), cubeChannel(g), cubeChannel(b), "cube"
            }
        end
    end
end

-- Grayscale 232..255 (24 stops, ~10.625 each)
for i = 232, 255 do
    local v = math.floor((i - 232) * (255 / 23) + 0.5)
    palette[#palette+1] = { v, v, v, "gray" }
end

-- -------------------------------------------------------------------
-- Init
-- -------------------------------------------------------------------
function M.init(opts)
    opts = opts or {}
    local mode = (opts.mode == 1) and 1 or 2

    -- Cache the unredirected computer term so we can paint there if the
    -- graphics surface fails for any reason.
    term_native = (type(term.native) == "function") and term.native() or term
    -- Already see if CC:Graphics is present (injects term.setGraphicsMode).
    if term and type(term.setGraphicsMode) == "function" then
        local ok = pcall(term.setGraphicsMode, mode)
        if ok then
            isGpu = true
            -- In graphics mode, term.getSize(mode) returns PIXEL dimensions.
            -- Passing no args always returns text-mode size (51x19), so we
            -- must pass the mode number to get the correct pixel surface.
            local w, h = term.getSize(mode)
            width  = w or (mode == 2 and 306 or 128)
            height = h or (mode == 2 and 171 or 128)
            -- Preload font so font access is non-blocking in app code
            font = require("os.font")
            -- Paint a neutral base color so users don't see the prior frame.
            M.clear(0,0,0)
            M.endFrame()
            return true, ("CC:Graphics mode %d (%dx%d px)"):format(mode, width, height)
        end
        isGpu = false
    end

    -- Fallback: standard text term.
    isGpu = false
    width, height = term.getSize()
    return false, ("Term fallback %dx%d cells"):format(width, height)
end

-- alias for compatibility with legacy callers
function M.isDirectGPU() return isGpu end
function M.isGpu() return isGpu end
function M.width() return width end
function M.height() return height end

-- -------------------------------------------------------------------
-- Color resolution (RGB triple -> palette index)
-- -------------------------------------------------------------------
local function resolveColor(col, fallback)
    if col == nil then col = fallback or {0,0,0} end
    if col == "transparent" then return nil end
    if type(col) == "number" then
        if col < 0 then col = 0 end
        if col > 255 then col = col % 256 end
        return col
    end
    if type(col) == "table" then
        local r = math.max(0, math.min(255, math.floor((col[1] or 0) + 0.5)))
        local g = math.max(0, math.min(255, math.floor((col[2] or 0) + 0.5)))
        local b = math.max(0, math.min(255, math.floor((col[3] or 0) + 0.5)))
        local key = r..","..g..","..b
        local cached = rgbCache[key]
        if cached then return cached end
        -- Find nearest palette entry by squared Euclidean distance.
        local bestI, bestD = 0, 1e18
        for i = 1, #palette do
            local p = palette[i]
            local dr = p[1] - r
            local dg = p[2] - g
            local db = p[3] - b
            local d = dr*dr + dg*dg + db*db
            if d < bestD then bestD, bestI = d, i - 1 end
        end
        rgbCache[key] = bestI
        return bestI
    end
    return 0
end
-- Public alias of the internal resolver so theme.lua / boot may resolve
-- a single {r,g,b} triple to a palette index at theme-load time.
local function resolveColorPub(col, fallback)
    return resolveColor(col, fallback)
end
M.resolveColor = resolveColorPub

-- -------------------------------------------------------------------
-- Frame control
-- -------------------------------------------------------------------
function M.startFrame()
    if isGpu and term and type(term.setFrozen) == "function" then
        pcall(term.setFrozen, true)
        frozen = true
    end
end

function M.endFrame()
    if isGpu and term and type(term.setFrozen) == "function" and frozen then
        pcall(term.setFrozen, false)
        frozen = false
    end
end

function M.flush()
    if isGpu and term and type(term.setFrozen) == "function" and frozen then
        pcall(term.setFrozen, false)
        frozen = false
        pcall(term.setFrozen, true)
    end
end

function M.invalidate() end -- no-op; framing is explicit via startFrame/endFrame

-- -------------------------------------------------------------------
-- Clear
-- -------------------------------------------------------------------
function M.clear(r, g, b)
    if r == nil then r, g, b = 16, 16, 24 end
    if isGpu then
        local idx = type(r) == "table"
            and resolveColor(r, {0,0,0})
            or  (type(r) == "number" and (g and resolveColor({r,g,b}, {0,0,0}) or r) or 0)
        if term and type(term.drawPixels) == "function" then
            pcall(term.drawPixels, 0, 0, idx, width, height)
        elseif term and type(term.setPixel) == "function" then
            for y = 0, height - 1 do
                for x = 0, width - 1 do
                    pcall(term.setPixel, x, y, idx)
                end
            end
        end
    else
        term.setBackgroundColor(type(r) == "table" and resolveColor(r, {0,0,0}) or (r or 0))
        term.clear()
    end
end

-- -------------------------------------------------------------------
-- Primitives
-- -------------------------------------------------------------------
function M.fillRect(x, y, w, h, col)
    if col == "transparent" or w <= 0 or h <= 0 then return end
    local idx = resolveColor(col, {0,0,0})
    if isGpu then
        if term and type(term.drawPixels) == "function" then
            pcall(term.drawPixels, x, y, idx, w, h)
        elseif term and type(term.setPixel) == "function" then
            for yy = y, y + h - 1 do
                for xx = x, x + w - 1 do
                    pcall(term.setPixel, xx, yy, idx)
                end
            end
        end
    else
        term.setBackgroundColor(idx)
        -- char coords are 1-indexed; offset by 1
        local cx, cy = math.floor(x/6)  + 1, math.floor(y/9) + 1
        local cw, ch = math.ceil(w/6),  math.ceil(h/9)
        for j = 0, ch - 1 do
            term.setCursorPos(cx, cy + j)
            term.write(string.rep(" ", cw))
        end
        term.setBackgroundColor(0)
    end
end

function M.outlineRect(x, y, w, h, col, t)
    t = t or 1
    if col == "transparent" then return end
    M.fillRect(x,         y,         w, t, col)
    M.fillRect(x,         y + h - t, w, t, col)
    M.fillRect(x,         y,         t, h, col)
    M.fillRect(x + w - t, y,         t, h, col)
end

-- Approximated by drawing filled bars and skipping small corner wedges.
function M.fillRoundRect(x, y, w, h, r, col)
    if col == "transparent" or r <= 0 then
        return M.fillRect(x, y, w, h, col)
    end
    M.fillRect(x + r, y,     w - 2*r, h,     col)
    M.fillRect(x,     y + r, w,       h-2*r, col)
    -- approximate rounded corners with pixel disks per quadrant
    local function quad(cx, cy)
        -- iterate bounding box of the corner disk
        for ox = -r, r do
            for oy = -r, r do
                if ox*ox + oy*oy <= r*r then
                    M.pixel(cx + ox, cy + oy, col)
                end
            end
        end
    end
    quad(x + r,         y + r)         -- top-left
    quad(x + w - r - 1, y + r)         -- top-right
    quad(x + r,         y + h - r - 1) -- bottom-left
    quad(x + w - r - 1, y + h - r - 1) -- bottom-right
end

function M.line(x1, y1, x2, y2, col)
    if col == "transparent" then return end
    local idx = resolveColor(col, {255,255,255})
    if isGpu then
        -- Bresenham — small line. Cheap API is to call term.drawLine if mod
        -- exposes it (uncommon on CC:Graphics port). Fall back to setPixel.
        local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
        local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
        local err = dx - dy
        local x, y = x1, y1
        while true do
            pcall(term.setPixel, x, y, idx)
            if x == x2 and y == y2 then break end
            local e2 = 2 * err
            if e2 > -dy then err = err - dy; x = x + sx end
            if e2 <  dx then err = err + dx; y = y + sy end
        end
    else
        local function pc(c) return c < 0 and math.ceil(c) or math.floor(c + 0.5) end
        term.setBackgroundColor(idx)
        local steps = math.max(math.abs(x2-x1), math.abs(y2-y1))
        if steps == 0 then
            term.setCursorPos(math.floor(x1/6)+1, math.floor(y1/9)+1)
            term.write(" ")
            return
        end
        for i = 0, steps do
            local t = i / steps
            local px = pc(x1 + (x2 - x1) * t)
            local py = pc(y1 + (y2 - y1) * t)
            term.setCursorPos(math.floor(px/6) + 1, math.floor(py/9) + 1)
            term.write(" ")
        end
        term.setBackgroundColor(0)
    end
end

function M.pixel(x, y, col)
    if col == "transparent" or col == nil then return end
    local idx = resolveColor(col, {255,255,255})
    if isGpu then
        pcall(term.setPixel, x, y, idx)
    else
        term.setCursorPos(math.floor(x/6)+1, math.floor(y/9)+1)
        term.setBackgroundColor(idx)
        term.write(" ")
        term.setBackgroundColor(0)
    end
end

-- -------------------------------------------------------------------
-- Text rendering via 5x7 bitmap
-- -------------------------------------------------------------------
local DEFAULT_SCALE = 2  -- (cs+1)=6 cols / glyph; at this default each char is 12 px wide and each row is 14 px tall

-- We batch *every* maximal "###" run of foreground pixels in each glyph row
-- into a single term.drawPixels call (CC:T doesn't support per-pixel alpha
-- in drawPixels, so true transparency must be preserved by run-length
-- encoding).  Compared to per-pixel setPixel:
--   * ~1700 setPixel calls for a 9-char title become ~30-40 drawPixels.
--   * At scale 2 each "on" pixel is a 2x2 block → the savings scale too
--     (factor of ~(cs+1)*scale per primitive).
-- If term.drawPixels isn't available we fall back to a tight inner
-- setPixel loop *per run* (still 10-20x fewer calls than full per-pixel).
function M.text(str, x, y, col, opts)
    if col == nil then col = {255,255,255} end
    if col == "transparent" then return end
    if type(str) ~= "string" or #str == 0 then return end
    if not font then font = require("os.font") end
    opts = opts or {}
    local scale = opts.size and font.scaleForSize(opts.size) or DEFAULT_SCALE
    if scale < 1 then scale = 1 end
    local idx = resolveColor(col, {255,255,255})

    pcall(function()
        local cs, rs = font.colCount, font.rowCount
        local stride = (cs + 1) * scale     -- horizontal advance per char (5px + 1px tracking)
        local drawPixels = (type(term) == "table") and term.drawPixels or nil
        local setPixel   = drawPixels or ((type(term) == "table") and term.setPixel or nil)
        if not setPixel then return end      -- nothing to paint with on this surface

        -- Emit one maximal run as a single drawPixels, or as a tight
        -- setPixel loop when term.drawPixels isn't exposed.  A run is a
        -- contiguous block of foreground bitmap columns within one glyph row.
        local function emitRun(gx0, runS, runE, gy0)
            local px0 = gx0 + (runS - 1) * scale
            local runW = (runE - runS + 1) * scale
            if drawPixels then
                drawPixels(px0, gy0, idx, runW, scale)
            else
                local yyEnd = gy0 + scale - 1
                for xx = px0, px0 + runW - 1 do
                    for yy = gy0, yyEnd do
                        setPixel(xx, yy, idx)
                    end
                end
            end
        end

        -- Top-level loop walks the string char by char; for each char we
        -- scan its rows left-to-right and locate maximal "###" runs.
        for i = 1, #str do
            local b = string.byte(str, i)
            local glyph
            if b == 9 or b == 10 or b == 13 then
                glyph = font.glyphs[10]  -- tab/CR/LF render as a space glyph
            else
                glyph = font.glyphs[b] or font.glyphs[32]
            end
            if glyph then
                local gx0 = x + (i - 1) * stride
                for gy = 1, rs do
                    local row = glyph[gy]
                    local gy0 = y + (gy - 1) * scale
                    local runS = nil  -- start column of the active run, or nil
                    for gx = 1, cs do
                        -- row is a string of "###.."; pixel-on if byte 35 ("#")
                        local on = string.byte(row, gx) == 35
                        if on then
                            if not runS then runS = gx end
                            -- last column reached: close any active run
                            if gx == cs and runS then
                                emitRun(gx0, runS, cs, gy0)
                                runS = nil
                            end
                        else
                            if runS then
                                emitRun(gx0, runS, gx - 1, gy0)
                                runS = nil
                            end
                        end
                    end
                end
            end
        end
    end)
end

function M.textSize(str, opts)
    opts = opts or {}
    if not font then font = require("os.font") end
    local scale = opts.size and font.scaleForSize(opts.size) or DEFAULT_SCALE
    local w = 0
    for _ in str:gmatch(".") do w = w + 1 end
    return w * (font.colCount + 1) * scale, font.rowCount * scale
end

-- -------------------------------------------------------------------
-- Common shapes
-- -------------------------------------------------------------------
function M.circle(cx, cy, radius, col, filled)
    if col == "transparent" then return end
    local idx = resolveColor(col, {255,255,255})
    if isGpu then
        -- Midpoint circle algorithm.
        -- The classic implementation plots 8 symmetric points per step and,
        -- when filled, draws horizontal scanlines between them.
        local setpx = term.setPixel
        local function drawHLine(x0, x1, yy) -- inclusive bounds
            if x0 > x1 then x0, x1 = x1, x0 end
            for xx = x0, x1 do setpx(cx + xx, cy + yy, idx) end
        end
        local x, y = radius, 0
        local err = 1 - radius
        local function putEdge(px, py)
            setpx(cx + px, cy + py, idx)
            setpx(cx - px, cy + py, idx)
            setpx(cx + px, cy - py, idx)
            setpx(cx - px, cy - py, idx)
            if y >= x then
                setpx(cx + y, cy + x, idx)
                setpx(cx - y, cy + x, idx)
                setpx(cx + y, cy - x, idx)
                setpx(cx - y, cy - x, idx)
            end
            if filled then
                -- Two rows are scanned per step: y=±y goes x∈[-x,+x];
                -- and (when y>=x) y=±x goes x∈[-y,+y].
                drawHLine(-x, x, py)
                drawHLine(-x, x, -py)
                if y >= x then
                    drawHLine(-y, y, x)
                    drawHLine(-y, y, -x)
                end
            end
        end
        repeat
            putEdge(x, y)
            y = y + 1
            err = err + (2 * y + 1)
            if 2 * (err + x - 1) > 0 then
                if err > 0 then
                    x = x - 1
                    err = err + (-2 * x + 1)
                end
            end
        until x < y
        if filled then
            -- Close the seam when x drops below y (last horizontal lines).
            drawHLine(-x - 1, x + 1, y - 1)
            drawHLine(-x - 1, x + 1, -(y - 1))
        end
    else
        if filled then M.fillRect(cx - radius, cy - radius, radius*2, radius*2, col) end
        M.outlineRect(cx - radius, cy - radius, radius*2, radius*2, col, 1)
    end
end

function M.gradient(x, y, w, h, c1, c2, dir)
    dir = dir or "v"
    if c1 == "transparent" or c2 == "transparent" then return end
    if not isGpu then
        return M.fillRect(x, y, w, h, c2)
    end
    if dir == "v" then
        for yy = 0, h - 1 do
            local t = h > 1 and (yy / (h - 1)) or 0
            local r = math.floor(c1[1] * (1-t) + c2[1] * t + 0.5)
            local g = math.floor(c1[2] * (1-t) + c2[2] * t + 0.5)
            local b = math.floor(c1[3] * (1-t) + c2[3] * t + 0.5)
            M.fillRect(x, y + yy, w, 1, {r, g, b})
        end
    else
        for xx = 0, w - 1 do
            local t = w > 1 and (xx / (w - 1)) or 0
            local r = math.floor(c1[1] * (1-t) + c2[1] * t + 0.5)
            local g = math.floor(c1[2] * (1-t) + c2[2] * t + 0.5)
            local b = math.floor(c1[3] * (1-t) + c2[3] * t + 0.5)
            M.fillRect(x + xx, y, 1, h, {r, g, b})
        end
    end
end

function M.shadow(x, y, w, h, offset, alpha)
    offset = offset or 3
    alpha  = alpha or 0.55
    local shadowCol = {0, 0, 0}
    for i = 0, offset - 1 do
        local k = ((1 - i / math.max(1, offset)) * alpha)
        local col = {
            math.floor(shadowCol[1] * k + 0.5),
            math.floor(shadowCol[2] * k + 0.5),
            math.floor(shadowCol[3] * k + 0.5),
        }
        M.fillRect(x + i,         y + h + i,     w, 1, col)
        M.fillRect(x + w + i,     y + i,         1, h, col)
    end
end

function M._stats()
    return {
        isGpu       = isGpu,
        isDirectGPU = isGpu, -- legacy alias
        width       = width,
        height      = height,
        mode        = isGpu and term.getGraphicsMode and term.getGraphicsMode() or 0,
        paletteCacheSize = (next(rgbCache) and 1) and #rgbCache or 0,
    }
end

return M
