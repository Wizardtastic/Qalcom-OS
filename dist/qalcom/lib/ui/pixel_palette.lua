local PixelPalette = {}
local function channels(hex)
hex = math.floor(tonumber(hex) or 0) % 0x1000000
return math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256
end
local function pack(r, g, b)
local function clamp(v) v = math.floor(v + 0.5); if v < 0 then return 0 elseif v > 255 then return 255 end return v end
return clamp(r) * 65536 + clamp(g) * 256 + clamp(b)
end
function PixelPalette.interp(a, b, t)
if t < 0 then t = 0 elseif t > 1 then t = 1 end
local ar, ag, ab = channels(a)
local br, bg, bb = channels(b)
return pack(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end
function PixelPalette.ramp(stops, steps)
steps = math.max(1, math.floor(tonumber(steps) or 1))
if type(stops) ~= "table" or #stops == 0 then return {} end
if #stops == 1 then
local out = {}
for i = 1, steps do out[i] = stops[1] end
return out
end
local out = {}
for i = 1, steps do
local pos = (i - 1) / math.max(1, steps - 1) * (#stops - 1)
local lo = math.floor(pos)
local frac = pos - lo
local a = stops[lo + 1]
local b = stops[math.min(#stops, lo + 2)]
out[i] = PixelPalette.interp(a, b, frac)
end
return out
end
PixelPalette.slots = {
wallpaperFrom = 16, wallpaperCount = 24,
accent = 40, accentDeep = 41, text = 42, textMuted = 43,
acrylic = 44, acrylicLight = 45,
card = 46, cardHeader = 47, cardBorder = 48,
shadowFrom = 49, shadowCount = 4,
tileFrom = 53, tileCount = 8,
white = 61, startPill = 62,
}
PixelPalette.wallpaperStops = { 0x0A1730, 0x102A5C, 0x1E63B4, 0x2C86E0, 0x1E63B4, 0x102A5C, 0x0A1730 }
PixelPalette.shadowStops = { 0x060C1C, 0x0A1226 }
PixelPalette.tiles = { 0xF7C948, 0x34C6A8, 0x4C8DFF, 0xFF6B6B, 0xB48EF2, 0x4CD07D, 0xFF9F40, 0x59C1FF }
function PixelPalette.plan()
local s = PixelPalette.slots
local list = {}
local function add(slot, hex) list[#list + 1] = { slot = slot, hex = hex } end
local wallpaper = {}
local wallRamp = PixelPalette.ramp(PixelPalette.wallpaperStops, s.wallpaperCount)
for i = 1, s.wallpaperCount do
local slot = s.wallpaperFrom + i - 1
add(slot, wallRamp[i]); wallpaper[i] = slot
end
add(s.accent, 0x4CC2FF); add(s.accentDeep, 0x0067C0)
add(s.text, 0xF2F5FA); add(s.textMuted, 0xA9B4C6)
add(s.acrylic, 0x232B3D); add(s.acrylicLight, 0x2E3850)
add(s.card, 0x2A2E3A); add(s.cardHeader, 0x333B4C); add(s.cardBorder, 0x3E4658)
local shadow = {}
local shadowRamp = PixelPalette.ramp(PixelPalette.shadowStops, s.shadowCount)
for i = 1, s.shadowCount do
local slot = s.shadowFrom + i - 1
add(slot, shadowRamp[i]); shadow[i] = slot
end
local tiles = {}
for i = 1, s.tileCount do
local slot = s.tileFrom + i - 1
add(slot, PixelPalette.tiles[i] or 0x808080); tiles[i] = slot
end
add(s.white, 0xFFFFFF); add(s.startPill, 0x4CC2FF)
return { list = list, wallpaper = wallpaper, shadow = shadow, tiles = tiles }
end
function PixelPalette.apply(plan)
plan = plan or PixelPalette.plan()
if type(term) == "table" and type(term.setPaletteColor) == "function" then
for _, entry in ipairs(plan.list) do
local r, g, b = channels(entry.hex)
pcall(term.setPaletteColor, entry.slot, r / 255, g / 255, b / 255)
end
end
return plan
end
function PixelPalette.verified(plan)
plan = plan or PixelPalette.plan()
if type(term) ~= "table" or type(term.getPaletteColor) ~= "function" then return false end
local function near(a, b) return math.abs(a - b) < 0.02 end
for _, entry in ipairs(plan.list) do
if entry.slot >= 16 then
local ok, r, g, b = pcall(term.getPaletteColor, entry.slot)
if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
local er, eg, eb = channels(entry.hex)
if not (near(r, er / 255) and near(g, eg / 255) and near(b, eb / 255)) then return false end
end
end
return true
end
return PixelPalette